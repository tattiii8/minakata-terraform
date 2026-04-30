provider "aws" {
  region = "ap-northeast-1"
}

# エラーを解消するために必要な「us-east-1」の設定
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_caller_identity" "aws" {}

