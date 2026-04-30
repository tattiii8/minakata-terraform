# --- 1. 静的コンテンツ公開用バケット (root) ---
resource "aws_s3_bucket" "root" {
  bucket = "${var.project_name}-root-${data.aws_caller_identity.aws.account_id}"
}

# ウェブサイトホスティング設定
resource "aws_s3_bucket_website_configuration" "root" {
  bucket = aws_s3_bucket.root.id
  index_document {
    suffix = "index.html"
  }
}

# パブリックアクセスブロックの解除
# ※ これを先に完了させないと、次のバケットポリシー適用で 403 エラーになります
resource "aws_s3_bucket_public_access_block" "root" {
  bucket = aws_s3_bucket.root.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# バケットポリシー (全ユーザーに読み取り許可)
resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.root.id

  # パブリックアクセスブロック解除後に実行することを明示
  depends_on = [aws_s3_bucket_public_access_block.root]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.root.arn}/*"
    }]
  })
}

# --- 2. 学習データ蓄積用のプライベートバケット (lexique) ---
resource "aws_s3_bucket" "lexique" {
  bucket = "${var.project_name}-lexique-${data.aws_caller_identity.aws.account_id}"
}

# パブリックアクセスはすべてブロック
resource "aws_s3_bucket_public_access_block" "lexique" {
  bucket = aws_s3_bucket.lexique.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- 1. S3 Bucket (PDF & Meilisearch Index) ---
resource "aws_s3_bucket" "corpus" {
  bucket = "${var.project_name}-corpus-storage"
}

# --- 3. 出力 ---
output "bucket_name" {
  value       = aws_s3_bucket.root.id
  description = "The name of the root S3 bucket"
}

output "lexique_bucket_name" {
  value       = aws_s3_bucket.lexique.id
  description = "The name of the lexique S3 bucket"
}