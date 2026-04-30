# --- 1. 受付API用 Lambda (main.py) ---
resource "aws_lambda_function" "fastapi_app" {
  function_name = "${var.project_name}-api"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api.repository_url}:${var.image_tag_api}"
  
  memory_size = 512
  timeout     = 29

  image_config {
    command = ["main.handler"] # ルート直下の main.py
  }

  environment {
    variables = {
      # APIがSQSに投げるために必要な変数
      LEXIQUE_QUEUE_URL     = aws_sqs_queue.lexique_queue.url
      GEMINI_QUEUE_URL      = aws_sqs_queue.gemini_queue.url
      CORPUS_QUEUE_URL    = aws_sqs_queue.corpus_queue.url
      # GETリクエストでS3のindex.jsonを読むために必要
      ROOT_BUCKET_NAME      = aws_s3_bucket.root.id
      LEXIQUE_BUCKET_NAME   = aws_s3_bucket.lexique.id
      LEXIQUE_MASTER_TABLE = aws_dynamodb_table.lexique_master.name #
      X_MINAKATA_KEY        = var.x_minakata_key
      X_MINAKATA_HEADER_SECRET = var.x_minakata_header_secret
    }
  }
}

# --- 2. Gemini agent (agents/agent_gemini.py) ---
resource "aws_lambda_function" "gemini_agent" {
  function_name = "${var.project_name}-gemini-agent"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api.repository_url}:${var.image_tag_api}"
  
  memory_size = 512
  timeout     = 300

  image_config {
    # ディレクトリ構成に合わせて修正
    command = ["agents.agent_gemini.handler"] 
  }

  environment {
    variables = {
      TABLE_NAME        = aws_dynamodb_table.gemini_jobs.name
      GEMINI_API_KEY    = var.gemini_api_key
      GEMINI_MODEL_NAME = var.gemini_model_name
    }
  }
}

# --- 3. Lexique agent (agents/agent_lexique.py) ---
resource "aws_lambda_function" "lexique_agent" {
  function_name = "${var.project_name}-lexique-agent"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api.repository_url}:${var.image_tag_api}"
  
  memory_size = 512
  timeout     = 900 

  image_config {
    # ディレクトリ構成に合わせて修正
    command = ["agents.agent_lexique.handler"] 
  }

  environment {
    variables = {
      # scraper側(agent_lexique)が書き込むためのテーブルとバケット
      LEXIQUE_TABLE = aws_dynamodb_table.lexique_jobs.name
      LEXIQUE_BUCKET   = aws_s3_bucket.lexique.id
      LEXIQUE_MASTER_TABLE = aws_dynamodb_table.lexique_master.name 
      
    }
  }
}

# --- 4. Corpus Agent (minakata-corpus-agent) ---
resource "aws_lambda_function" "corpus_agent" {
  function_name = "${var.project_name}-corpus-agent"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  
  # 専用リポジトリを参照！
  image_uri     = "${aws_ecr_repository.corpus.repository_url}:${var.image_tag_corpus}"
  
  memory_size = 1024
  timeout     = 900 

  ephemeral_storage {
    size = 1024 
  }

  reserved_concurrent_executions = var.enable_corpus_agent ? -1 : 0

  environment {
    variables = {
      CORPUS_JOB_TABLE    = aws_dynamodb_table.corpus_jobs.name
      CORPUS_BUCKET_NAME  = aws_s3_bucket.corpus.id
      MEILI_MASTER_KEY    = var.meili_master_key
    }
  }

  image_config {
    command = ["agents.agent_corpus.handler"]
  }
}

# --- 管理用 API Lambda ---
resource "aws_lambda_function" "management_api" {
  function_name = "${var.project_name}-management-api"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api.repository_url}:${var.image_tag_api}"
  
  memory_size = 256 # 管理用なので少なめでOK
  timeout     = 29

  image_config {
    # ここがポイント：management.py 内の handler を呼び出す
    command = ["management.handler"] 
  }

  environment {
    variables = {
      LEXIQUE_TABLE       = aws_dynamodb_table.lexique_jobs.name
      LEXIQUE_BUCKET_NAME = aws_s3_bucket.lexique.id
      # 必要に応じて管理用のパスワードなどを設定
      # ADMIN_API_KEY      = var.admin_api_key
    }
  }
}