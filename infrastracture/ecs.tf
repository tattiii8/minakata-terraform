# ==========================================
# 1. ECS Cluster
# ==========================================
resource "aws_ecs_cluster" "minakata_daemon" {
  name = "minakata-daemon" # 修正: minakata-ecs -> minakata-daemon
}

# ==========================================
# 2. IAM Roles (名前は既存のままでも動作しますが、一貫性のため整理)
# ==========================================

# External Instances用 (shoin本体の登録用)
resource "aws_iam_role" "ecs_external_instance_role" {
  name = "minakata-daemon-external-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
    }]
  })
}

# ... (IAM Policy Attachment 類は既存の role 名を参照するように修正) ...
resource "aws_iam_role_policy_attachment" "ecs_external_instance_ssm" {
  role       = aws_iam_role.ecs_external_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecs_external_instance_ecs" {
  role       = aws_iam_role.ecs_external_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "minakata-daemon-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Role (Corpus Agent用)
resource "aws_iam_role" "ecs_task_role" {
  name = "minakata-corpus-agent-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "agent_aws_policy" {
  name = "minakata-corpus-agent-aws-policy"
  role = aws_iam_role.ecs_task_role.id
  # ... (Policy内容は変更なし) ...
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Effect = "Allow"
        Resource = "*" 
      },
      {
        Action = ["s3:GetObject", "s3:ListBucket", "s3:PutObject"]
        Effect = "Allow"
        Resource = ["arn:aws:s3:::${var.corpus_bucket_name}", "arn:aws:s3:::${var.corpus_bucket_name}/*"]
      },
      {
        Action = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"]
        Effect = "Allow"
        Resource = "arn:aws:dynamodb:ap-northeast-1:*:table/minakata-corpus"
      }
    ]
  })
}

# ==========================================
# 3. Task Definitions & Services
# ==========================================

# Meilisearch (修正: サービス名を minakata-meilisearch へ)
resource "aws_ecs_task_definition" "meilisearch" {
  family                   = "minakata-meilisearch"
  requires_compatibilities = ["EXTERNAL"]
  network_mode             = "bridge"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  cpu                      = "1024"
  memory                   = "12288"

  container_definitions = jsonencode([
    {
      name  = "meilisearch"
      image = "getmeili/meilisearch:latest"
      portMappings = [{ containerPort = 7700, hostPort = 7700, protocol = "tcp" }]
      environment = [
        { name = "MEILI_ENV", value = "production" },
        { name = "MEILI_NO_ANALYTICS", value = "true" },
        { name = "MEILI_MASTER_KEY", value = var.meili_master_key },
        { name = "MEILI_DB_PATH", value = "/meili_data/data.ms" }
      ]
      mountPoints = [{ sourceVolume = "meili_data", containerPath = "/meili_data", readOnly = false }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/minakata-meilisearch"
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "meilisearch"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])
  volume {
    name      = "meili_data"
    host_path = "/home/tatsuki/meili_data"
  }
}

resource "aws_ecs_service" "meilisearch" {
  name            = "minakata-meilisearch" # 修正: meilisearch-service -> minakata-meilisearch
  cluster         = aws_ecs_cluster.minakata_daemon.id
  task_definition = aws_ecs_task_definition.meilisearch.arn
  desired_count   = 1
  launch_type     = "EXTERNAL"
}

# Corpus Agent (修正: サービス名を minakata-corpus-agent へ)
resource "aws_ecs_task_definition" "corpus_agent" {
  family                   = "minakata-corpus-agent"
  requires_compatibilities = ["EXTERNAL"]
  network_mode             = "bridge"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  cpu                      = "128"
  memory                   = "256"

  container_definitions = jsonencode([
    {
      name  = "corpus-agent"
      image = "871950640338.dkr.ecr.ap-northeast-1.amazonaws.com/minakata-corpus:${var.image_tag_corpus}"
      
      entryPoint = ["python3"]
      command    = ["agents/agent_corpus.py"]
      workingDirectory = "/var/task"

      environment = [
        { name = "AWS_DEFAULT_REGION", value = "ap-northeast-1" },
        { name = "MEILI_HOST", value = "http://localhost:7700" },
        { name = "MEILI_MASTER_KEY", value = var.meili_master_key },
        { name = "SQS_QUEUE_URL", value = "https://sqs.ap-northeast-1.amazonaws.com/871950640338/minakata-corpus-queue" },
        { name = "CORPUS_JOB_TABLE", value = "minakata-corpus" },
        { name = "CORPUS_BUCKET_NAME", value = var.corpus_bucket_name },
        { name = "PYTHONPATH", value = "/var/task" },
        { name = "MEILI_TIMEOUT_MS", value = "30000" }, # 5秒から30秒へ大幅延長
        { name = "MEILI_STARTUP_WAIT_SEC", value = "10" } # 起動後の安定待ち時間を追加
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/minakata-corpus-agent"
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = "agent"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "corpus_agent" {
  name            = "minakata-corpus-agent"
  cluster         = aws_ecs_cluster.minakata_daemon.id
  task_definition = aws_ecs_task_definition.corpus_agent.arn
  desired_count   = 5
  launch_type     = "EXTERNAL"
}