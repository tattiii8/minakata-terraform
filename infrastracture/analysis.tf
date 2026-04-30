# ----------------------------------------------------------------
# 0. Data Sources
# ----------------------------------------------------------------
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ----------------------------------------------------------------
# 1. S3 Bucket
# ----------------------------------------------------------------
resource "aws_s3_bucket" "log_storage" {
  bucket = "minakata-app-log-${data.aws_caller_identity.current.account_id}"
}

# ----------------------------------------------------------------
# 2. Firehose Transformer Lambda (Container Image)
# ----------------------------------------------------------------
resource "aws_iam_role" "firehose_lambda_role" {
  name = "minakata-firehose-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "firehose_lambda_basic" {
  role       = aws_iam_role.firehose_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "firehose_transformer" {
  function_name = "${var.project_name}-firehose"
  role          = aws_iam_role.firehose_lambda_role.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api.repository_url}:${var.image_tag_api}"
  
  memory_size = 512 # 余裕を持って設定
  timeout     = 60

  image_config {
  # ファイルパスをドットで繋いだ形式
  command = ["transformer.firehose_transformer.handler"] 
}
}

# ----------------------------------------------------------------
# 3. Firehose Delivery Stream
# ----------------------------------------------------------------
resource "aws_iam_role" "firehose_role" {
  name = "minakata-firehose-log-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "firehose_policy" {
  name = "minakata-firehose-policy"
  role = aws_iam_role.firehose_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
        Effect = "Allow"
        Resource = [aws_s3_bucket.log_storage.arn, "${aws_s3_bucket.log_storage.arn}/*"]
      },
      {
        Action = ["lambda:InvokeFunction", "lambda:GetFunctionConfiguration"]
        Effect = "Allow"
        Resource = [aws_lambda_function.firehose_transformer.arn, "${aws_lambda_function.firehose_transformer.arn}:*"]
      },
      {
        Action = ["logs:PutLogEvents"]
        Effect = "Allow"
        Resource = ["${aws_cloudwatch_log_group.firehose_error_log.arn}:*"]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "log_stream" {
  name        = "minakata-log-delivery"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.log_storage.arn

    prefix              = "logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"

    buffering_size     = 5
    buffering_interval = 60 
    compression_format = "UNCOMPRESSED" # コスト削減のために必須

    processing_configuration {
      enabled = true
      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.firehose_transformer.arn}:$LATEST"
        }
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_error_log.name
      log_stream_name = "S3Delivery"
    }
  }
}

resource "aws_cloudwatch_log_group" "firehose_error_log" {
  name              = "/aws/kinesisfirehose/minakata-log-delivery"
  retention_in_days = 7
}

# ----------------------------------------------------------------
# 4. CloudWatch Logs -> Firehose Subscription
# ----------------------------------------------------------------
resource "aws_iam_role" "cwl_to_firehose_role" {
  name = "minakata-cwl-to-firehose-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "logs.${data.aws_region.current.name}.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "cwl_to_firehose_policy" {
  name = "minakata-cwl-to-firehose-policy"
  role = aws_iam_role.cwl_to_firehose_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      Effect   = "Allow"
      Resource = aws_kinesis_firehose_delivery_stream.log_stream.arn
    }]
  })
}

resource "aws_cloudwatch_log_subscription_filter" "minakata_api_log_filter" {
  name            = "minakata_api_to_firehose"
  log_group_name  = "/aws/lambda/${var.project_name}-api" # 既存のLogGroup名を指定
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.log_stream.arn
  role_arn        = aws_iam_role.cwl_to_firehose_role.arn
}

# ----------------------------------------------------------------
# 5. Glue/Athena (Enhanced Schema) - FIXED VERSION
# ----------------------------------------------------------------
resource "aws_glue_catalog_table" "minakata_logs" {
  name          = "minakata_logs_raw"
  database_name = "default"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"     = "json"
    "projection.enabled" = "true"
    
    # yearをenumに変更（数値のカンマ問題を回避）
    "projection.year.type"   = "enum"
    "projection.year.values" = "2026,2027,2028"
    
    "projection.month.type"   = "integer"
    "projection.month.range"  = "1,12"
    "projection.month.digits" = "2"
    
    "projection.day.type"   = "integer"
    "projection.day.range"  = "1,31"
    "projection.day.digits" = "2"

    # 【修正ポイント】
    # storage_descriptor の location からの相対パスを指定します。
    # Hive形式（year=...）であることを明示します。
    "storage.location.template" = "s3://${aws_s3_bucket.log_storage.bucket}/logs/year=$${year}/month=$${month}/day=$${day}/"
  }

  storage_descriptor {
    # 探索のベースディレクトリ
    location      = "s3://${aws_s3_bucket.log_storage.bucket}/logs/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = { "ignore.malformed.json" = "true" }
    }

    # フラット化した全カラムを定義
    columns {
       name = "datetime_utc"    
       type = "string" 
       }
    columns { 
      name = "level"           
      type = "string" 
      }
    columns { 
      name = "service"         
      type = "string" 
      }
    columns { 
      name = "http_method"     
      type = "string" 
      }
    columns { 
      name = "http_path"       
      type = "string" 
      }
    columns { 
      name = "http_status"     
      type = "int"    
      }
    columns { 
      name = "latency_ms"      
      type = "double" 
      }
    columns { 
      name = "minakata_traceid" 
      type = "string" 
      }
    columns { 
      name = "message"         
      type = "string" 
      }
    columns { 
      name = "log_type"        
      type = "string" 
      }
    columns { 
      name = "cwl_timestamp"   
      type = "bigint" 
      }
    columns { 
      name = "request_body" 
      type = "string" 
      } # 追加
    columns { 
      name = "location"
      type = "string" 
      }     # 追加
  }

  partition_keys { 
    name = "year"
    type = "string" 
    }
  partition_keys { 
    name = "month" 
    type = "string" 
    }
  partition_keys { 
    name = "day"   
    type = "string" 
    }
}