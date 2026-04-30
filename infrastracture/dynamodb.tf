

resource "aws_dynamodb_table" "gemini_jobs" {
  name         = "${var.project_name}-gemini" # varを使用
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"

  attribute {
    name = "job_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}


# --- 2. DynamoDB: Corpus Jobs ---
resource "aws_dynamodb_table" "corpus_jobs" {
  name         = "${var.project_name}-corpus"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"

  attribute {
    name = "job_id"
    type = "S"
  }

  attribute {
    name = "minakata_traceid"
    type = "S"
  }

  global_secondary_index {
    name            = "MinakataTraceIndex"
    hash_key        = "minakata_traceid"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "lexique_jobs" {
  name         = "${var.project_name}-lexique"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"

  # --- 追加: TraceID検索用の属性定義 ---
  attribute {
    name = "minakata_traceid"
    type = "S"
  }

  # --- 追加: GSIの設定 ---
  global_secondary_index {
    name               = "MinakataTraceIndex"
    hash_key           = "minakata_traceid"
    projection_type    = "ALL" # 全てのカラムをインデックスに含める
  }

  attribute {
    name = "job_id"
    type = "S"
  }

  # 1週間後などに自動削除したい場合は有効化
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}


# 新設：永続的な検索用マスターテーブル
resource "aws_dynamodb_table" "lexique_master" {
  name         = "${var.project_name}-lexique-master"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "lexique" # 単語名がキーなので検索が爆速かつ安価

  attribute {
    name = "lexique"
    type = "S"
  }

  # 作成日時などでソートしたい場合は、GSIを追加
  attribute {
    name = "updated_at"
    type = "S"
  }

  global_secondary_index {
    name               = "RecentUpdateIndex"
    hash_key           = "updated_at"
    projection_type    = "ALL"
  }
}