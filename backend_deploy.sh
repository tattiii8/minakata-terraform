#!/bin/bash
set -e

# --- 設定 ---
PROJECT_NAME="minakata"
ACCOUNT_ID="871950640338"
REGION="ap-northeast-1"
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
ECR_APP="${ECR_BASE}/${PROJECT_NAME}-api"
ECR_CORPUS="${ECR_BASE}/${PROJECT_NAME}-corpus"

echo "--- 1. ECR Login ---"
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_BASE

# タグの生成
IMAGE_TAG_API=$(find app -type f -not -path '*/.*' | xargs sha1sum | sha1sum | cut -c1-8)
IMAGE_TAG_CORPUS="corpus-${IMAGE_TAG_API}"

echo "--- 2. Build & Push: App Image ---"
docker build --platform linux/amd64 --provenance=false \
  --target app_final \
  -t "${PROJECT_NAME}-api:latest" ./app

docker tag "${PROJECT_NAME}-api:latest" "${ECR_APP}:${IMAGE_TAG_API}"
docker push "${ECR_APP}:${IMAGE_TAG_API}"

echo "--- 3. Build & Push: Corpus Image ---"
docker build --platform linux/amd64 --provenance=false \
  --target corpus_final \
  -t "${PROJECT_NAME}-corpus:latest" ./app

docker tag "${PROJECT_NAME}-corpus:latest" "${ECR_CORPUS}:${IMAGE_TAG_CORPUS}"
docker push "${ECR_CORPUS}:${IMAGE_TAG_CORPUS}"

echo "--- 4. Terraform Apply ---"
# -w オプションを /workspace/infrastracture に修正
TERRAFORM_RUN="docker run --rm \
  -v $(pwd):/workspace \
  -w /workspace/infrastracture \
  -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  -e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN \
  -e AWS_DEFAULT_REGION=$REGION \
  hashicorp/terraform:latest"

$TERRAFORM_RUN init

# 変数を渡して適用
$TERRAFORM_RUN apply \
  -var="image_tag_api=${IMAGE_TAG_API}" \
  -var="image_tag_corpus=${IMAGE_TAG_CORPUS}" \
  -auto-approve

echo "--- Deployment Finished ---"
echo "Corpus Tag: ${IMAGE_TAG_CORPUS}"