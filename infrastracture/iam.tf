# --- 1. Lambda 共通の実行ロール本体 ---
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# --- 2. DynamoDB へのアクセス権限 ---
resource "aws_iam_role_policy" "dynamodb_access" {
  name = "${var.project_name}-dynamodb-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = [
          aws_dynamodb_table.gemini_jobs.arn,
          aws_dynamodb_table.lexique_jobs.arn,
          aws_dynamodb_table.corpus_jobs.arn,
          aws_dynamodb_table.lexique_master.arn, # 【重要】これを追加！
          "${aws_dynamodb_table.gemini_jobs.arn}/index/*",
          "${aws_dynamodb_table.lexique_jobs.arn}/index/*",
          "${aws_dynamodb_table.corpus_jobs.arn}/index/*",
          "${aws_dynamodb_table.lexique_master.arn}/index/*" # 【重要】Masterのインデックスも追加
        ]
      }
    ]
  })
}

# --- 3. SQS 送受信権限 ---
resource "aws_iam_role_policy" "sqs_access" {
  name = "${var.project_name}-sqs-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      Effect   = "Allow"
      Resource = [
        aws_sqs_queue.gemini_queue.arn,
        aws_sqs_queue.lexique_queue.arn,
        aws_sqs_queue.corpus_queue.arn
      ]
    }]
  })
}

# --- 6. S3 へのアクセス権限 ---
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.project_name}-s3-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.lexique.arn}/*",
          "${aws_s3_bucket.corpus.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.lexique.arn,
          aws_s3_bucket.corpus.arn
        ]
      }
    ]
  })
}

# --- 4 & 5. ログとX-Rayの設定 ---
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}