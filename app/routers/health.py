import os
import boto3
from fastapi import APIRouter, Header, HTTPException, Request
from aws_lambda_powertools import Logger
from datetime import datetime
from botocore.exceptions import ClientError

# main.pyと同じサービス名で子ロガーを作成
logger = Logger(service="Minakata", child=True)
router = APIRouter(tags=["system"])

# S3設定
S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME", "Minakata-word-list-871950640338")
s3 = boto3.client("s3")

# 環境変数の取得（起動時に厳格にチェック）
try:
    EXPECTED_KEY = os.environ["X_MINAKATA_KEY"]
except KeyError:
    logger.critical("環境変数 'X_MINAKATA_KEY' が設定されていません。")
    EXPECTED_KEY = None

@router.get("/health")
async def health_check(request: Request, x_minakata_key: str = Header(None)):
    # 1. ミドルウェアから trace_id を取得
    trace_id = getattr(request.state, "minakata_traceid", "unknown")

    # 2. 環境変数の存在確認
    if EXPECTED_KEY is None:
        logger.error("API Key configuration missing on server side.", extra={"minakata_traceid": trace_id})
        raise HTTPException(status_code=500, detail="Server configuration error")

    # 3. カスタムヘッダの検証
    if x_minakata_key != EXPECTED_KEY:
        logger.warning(
            f"Unauthorized health check attempt.", 
            extra={
                "minakata_traceid": trace_id,
                "provided_key_snippet": x_minakata_key[:4] + "..." if x_minakata_key else None
            }
        )
        raise HTTPException(
            status_code=403, 
            detail="Access denied: Invalid X-MINAKATA-KEY"
        )

    # 4. 疎通確認ロジック
    health_status = {
        "status": "healthy",
        "service": "Minakata",
        "minakata_traceid": trace_id, # レスポンスにも含める
        "timestamp": datetime.now().isoformat(),
        "details": {}
    }

    try:
        s3.head_bucket(Bucket=S3_BUCKET_NAME)
        health_status["details"]["storage"] = {
            "status": "accessible",
            "bucket": S3_BUCKET_NAME
        }
        logger.info("Health check passed", extra={"minakata_traceid": trace_id})
    except ClientError as e:
        logger.error(f"S3 health check failed: {e}", extra={"minakata_traceid": trace_id})
        health_status["status"] = "unhealthy"
        health_status["details"]["storage"] = {"status": "error", "message": str(e)}

    return health_status