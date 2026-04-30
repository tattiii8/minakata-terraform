resource "aws_sqs_queue" "gemini_queue" {
  name                       = "${var.project_name}-gemini-queue"
  visibility_timeout_seconds = 300 # agentのタイムアウトより長く設定
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.gemini_queue.arn
  function_name = aws_lambda_function.gemini_agent.function_name
  batch_size       = 1
}

resource "aws_sqs_queue" "lexique_queue" {
  name                       = "${var.project_name}-lexique-queue"
  visibility_timeout_seconds = 900 # 最大15分（スクレイピングの長期戦に対応）
}

# lexique agent Lambdaのトリガー設定
resource "aws_lambda_event_source_mapping" "lexique_sqs_trigger" {
  event_source_arn = aws_sqs_queue.lexique_queue.arn
  function_name    = aws_lambda_function.lexique_agent.function_name # agentの名前
  batch_size       = 1
}

# --- 3. SQS: Corpus Queue ---
resource "aws_sqs_queue" "corpus_queue" {
  name                       = "${var.project_name}-corpus-queue"
  visibility_timeout_seconds = 900 # Agentの最大実行時間(15分)に合わせる
}

# --- 6. SQS Trigger for Corpus Agent ---
resource "aws_lambda_event_source_mapping" "corpus_worker_sqs" {
  event_source_arn = aws_sqs_queue.corpus_queue.arn
  function_name    = aws_lambda_function.corpus_agent.arn
  batch_size       = 1

  # フラグが false の間、SQSはLambdaをキックしなくなります
  enabled          = var.enable_corpus_agent

  # インデックス更新の競合を防ぐため、同時実行数を制限
  scaling_config {
    maximum_concurrency = 2 
  }
}

