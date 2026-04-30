#!/bin/bash

# エラーが発生したら即終了
set -e

# 設定
PROJECT_ROOT=$(pwd)
FRONTEND_DIR="$PROJECT_ROOT/frontend"
# フォルダ名が infrastracture (aが入っている) のままであればこれでOK
INFRA_DIR="infrastracture" 

echo "🚀 [Agent: Frontend] デプロイプロセスを開始します..."

# 1. Terraformからバケット名を取得 (Docker使用)
# ※現在のディレクトリが PROJECT_ROOT であることを前提にマウントパスを調整
echo "🔍 ステップ 0: S3バケット名を照会中..."
S3_BUCKET_NAME=$(docker run --rm -v "$PROJECT_ROOT":/workspace -w /workspace hashicorp/terraform:latest -chdir=$INFRA_DIR output -raw bucket_name)

if [ -z "$S3_BUCKET_NAME" ]; then
  echo "❌ エラー: バケット名が取得できませんでした。"
  exit 1
fi

# 2. フロントエンドのビルド
echo "📦 ステップ 1: Reactプロジェクトのビルド中..."
cd "$FRONTEND_DIR"

if [ ! -d "node_modules" ]; then
  echo "📥 npm packages をインストール中..."
  npm install
fi

npm run build

# 3. S3への同期
echo "☁️ ステップ 2: S3バケット ($S3_BUCKET_NAME) へ同期中..."
# 【重要】--acl public-read を削除しました
aws s3 sync dist/ s3://"$S3_BUCKET_NAME"/ --delete

# 4. 完了報告
echo "✨ [Agent: Frontend] デプロイが正常に完了しました！"
# リージョンも自動取得してURLを表示
AWS_REGION=$(aws configure get region)
echo "🔗 URL: http://$S3_BUCKET_NAME.s3-website-$AWS_REGION.amazonaws.com/"