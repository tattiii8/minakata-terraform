# 1. ACM証明書のリクエスト
resource "aws_acm_certificate" "minakata" {
  domain_name       = local.full_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}


#ここからは最初のデプロイ時にはコメントアウト
#DNS検証が完了したら再度apply


# 2. API Gateway カスタムドメイン名
resource "aws_apigatewayv2_domain_name" "minakata" {
  domain_name = local.full_domain_name

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.minakata.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

# 3. APIとドメインの紐付け
resource "aws_apigatewayv2_api_mapping" "minakata" {
  # 提供されたリソース名「http_api」と「default」に合わせて修正
  api_id      = aws_apigatewayv2_api.http_api.id
  domain_name = aws_apigatewayv2_domain_name.minakata.id
  stage       = aws_apigatewayv2_stage.default.id
}

output "apigateway_target_domain" {
  description = "Cloudflareに登録する接続先（Target）"
  value       = aws_apigatewayv2_domain_name.minakata.domain_name_configuration[0].target_domain_name
}


#ここまでは最初のデプロイ時にはコメントアウト
#DNS検証が完了したら再度apply
#CloudflareにCNAMEでホスト名とAPI Gatewayのエンドポイントを追加する


# --- Cloudflare設定用の出力 ---
output "dns_validation_record" {
  description = "Cloudflareに登録する検証用CNAMEレコード"
  value = [
    for d in aws_acm_certificate.minakata.domain_validation_options : {
      name   = d.resource_record_name
      type   = d.resource_record_type
      value  = d.resource_record_value
    }
  ]
}

output "dns_validation_record_cloudfront" {
  description = "CloudFront用(ACM us-east-1)の検証レコード"
  value = [
    for d in aws_acm_certificate.cloudfront_cert.domain_validation_options : {
      name  = d.resource_record_name
      type  = d.resource_record_type
      value = d.resource_record_value
    }
  ]
}

