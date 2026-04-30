# HTTP API本体
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-apigateway"
  protocol_type = "HTTP"
}

# --- 1. ロググループ設定 (CloudWatch) ---

resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${var.project_name}-access-logs"
  retention_in_days = 7
}

# --- 2. バックエンド (Lambda) 設定 ---

# メインAPI (FastAPI)
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.fastapi_app.invoke_arn
  payload_format_version = "2.0"
}

# 管理用API
resource "aws_apigatewayv2_integration" "management_lambda" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.management_api.invoke_arn
  payload_format_version = "2.0"
}

# ルート設定
resource "aws_apigatewayv2_route" "management_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /api/v1/management/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.management_lambda.id}"
}

resource "aws_apigatewayv2_route" "api_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /api/v1/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# --- 3. フロントエンド (S3 静的ホスティング) 設定 ---

resource "aws_apigatewayv2_integration" "s3_proxy" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "http://${aws_s3_bucket_website_configuration.root.website_endpoint}/{proxy}"
  integration_method = "GET"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_integration" "s3_index" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "http://${aws_s3_bucket_website_configuration.root.website_endpoint}/index.html"
  integration_method = "GET"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "s3_index_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.s3_index.id}"
}

resource "aws_apigatewayv2_route" "s3_static_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.s3_proxy.id}"
}

# --- 4. 権限設定 ---

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fastapi_app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "management_api_gw" {
  statement_id  = "AllowManagementExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.management_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# --- 5. デプロイ・ステージ設定 (ログ設定含む) ---

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      sourceIp       = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      minakata_traceid = "$context.requestId" # ここでトレースIDを紐付け
    })
  }
}

output "api_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}