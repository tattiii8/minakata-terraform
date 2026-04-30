# --- メインアプリ用 (API, Gemini, Lexique) ---
resource "aws_ecr_repository" "api" {
  name                 = "${var.project_name}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# --- Corpus Agent専用 (Meilisearchバイナリ入り) ---
resource "aws_ecr_repository" "corpus" {
  name                 = "${var.project_name}-corpus"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# 共通のライフサイクルポリシー（モジュール化せずに記述）
resource "aws_ecr_lifecycle_policy" "app_policy" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 3 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "corpus_policy" {
  repository = aws_ecr_repository.corpus.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 3 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 3
      }
      action = { type = "expire" }
    }]
  })
}