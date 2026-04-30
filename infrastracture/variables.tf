# ==========================================
# 1. Project & Core Tags
# ==========================================
variable "project_name" {
  type    = string
  default = "minakata"
}

variable "image_tag_api" {
  description = "Tag for minakata-app repository (API/Gemini)"
  type        = string
  default     = "latest"
}

variable "image_tag_corpus" {
  description = "Tag for minakata-corpus repository (Agent)"
  type        = string
  default     = "latest"
}

# ==========================================
# 2. Domain Settings
# ==========================================
variable "subdomain_name" {
  type    = string
  default = "minakata"
}

variable "root_domain_name" {
  type    = string
  default = "lesure.net"
}

locals {
  full_domain_name = "${var.subdomain_name}.${var.root_domain_name}"
}

# ==========================================
# 3. API Keys & Secrets (Sensitive)
# ==========================================
variable "x_minakata_key" {
  type      = string
  sensitive = true
}

variable "x_minakata_header_secret" {
  type      = string
  sensitive = true
}

variable "gemini_api_key" {
  type      = string
  sensitive = true
}

variable "line_channel_access_token" {
  type      = string
  sensitive = true
}

variable "meili_master_key" {
  description = "Master Key for Meilisearch"
  type        = string
  sensitive   = true
}

# ==========================================
# 4. App Configurations
# ==========================================
variable "gemini_model_name" {
  type    = string
  default = "gemini-2.5-flash"
}

variable "internal_webhook_url" {
  description = "Webhook URL for job completion notifications"
  type        = string
}

variable "enable_corpus_agent" {
  type    = bool
  default = false
}

variable "corpus_bucket_name" {
  description = "S3 Bucket name for PDF and index storage"
  type        = string
}