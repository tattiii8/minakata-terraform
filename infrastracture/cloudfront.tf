# --- 0. マネージドポリシーのデータソース取得 ---
data "aws_cloudfront_cache_policy" "disabling" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

# --- 1. ログ保存用 S3 バケット (CloudFront標準ログ用) ---
resource "aws_s3_bucket" "cf_logs" {
  bucket = "${var.project_name}-cloudfront-logs"
}

resource "aws_s3_bucket_ownership_controls" "cf_logs" {
  bucket = aws_s3_bucket.cf_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "cf_logs_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.cf_logs]
  bucket     = aws_s3_bucket.cf_logs.id
  acl        = "private"
}

# --- 2. CloudFront Function (防御 + 署名・ヘッダー付与) ---
# WAFを使わず、低コストでスキャンをブロックします
resource "aws_cloudfront_function" "add_custom_header" {
  name    = "${var.project_name}-edge-function"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOT
    function handler(event) {
        var request = event.request;
        var uri = request.uri;
        var clientIP = event.viewer.ip;

        // --- 防御ロジック: 不審なスキャンの即時拒否 ---
        // .env, .git, .php などのドットファイルや、特定の拡張子を狙ったアクセスをブロック
        if (uri.includes('/.') || uri.endsWith('.env')) {
            console.log("Blocked Scan Attempt: URL=" + uri + " IP=" + clientIP);
            return {
                statusCode: 403,
                statusDescription: 'Forbidden',
                headers: {
                    'content-type': { value: 'text/plain' }
                },
                body: 'Access Denied: Unallowed path'
            };
        }

        // --- 署名・ヘッダー付与ロジック ---
        var secretKey = "${var.x_minakata_header_secret}";
        var timestamp = Math.floor(Date.now() / 1000);
    
        var signature = btoa(timestamp + "." + secretKey);
        
        request.headers['x-minakata-header']    = { value: 'true' };
        request.headers['x-minakata-signature'] = { value: signature };
        request.headers['x-minakata-timestamp'] = { value: timestamp.toString() };

        // 正常なリクエストのログ（CloudWatch Logsへ）
        console.log("Edge Auth Trace: URL=" + uri + " IP=" + clientIP + " TS=" + timestamp);
        
        return request;
    }
  EOT

  lifecycle {
    create_before_destroy = true
  }
}

# --- 3. CloudFront 用 ACM (us-east-1) ---
resource "aws_acm_certificate" "cloudfront_cert" {
  provider          = aws.us_east_1
  domain_name       = local.full_domain_name
  validation_method = "DNS"
  
  lifecycle { 
    create_before_destroy = true 
  }
}

# --- 4. CloudFront Distribution ---
resource "aws_cloudfront_distribution" "api_dist" {
  enabled         = true
  is_ipv6_enabled = true
  aliases         = [local.full_domain_name]

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.cf_logs.bucket_domain_name
    prefix          = "cloudfront/"
  }

  origin {
    domain_name = aws_apigatewayv2_domain_name.minakata.domain_name_configuration[0].target_domain_name
    origin_id   = "APIGatewayCustomDomain"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "APIGatewayCustomDomain"
    viewer_protocol_policy = "redirect-to-https"

    cache_policy_id          = data.aws_cloudfront_cache_policy.disabling.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    # エッジ関数を紐付け
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.add_custom_header.arn
    }
  }

  restrictions {
    # 海外からのスキャンが多すぎる場合は、ここを "whitelist" にして ["JP"] を指定してください
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cloudfront_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}