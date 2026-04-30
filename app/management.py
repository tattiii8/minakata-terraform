import os
import boto3
import json
import uuid
import time
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum
from aws_lambda_powertools import Logger
from boto3.dynamodb.conditions import Key

# 1. ロガーの初期化 (サービス名をManagement専用に設定)
logger = Logger(service="Minakata-Management")

# 2. FastAPIの初期化 (root_pathを指定し、API Gatewayのステージングに対応)
app = FastAPI(
    title="Minakata Management API",
    root_path="/api/v1/management"
)

# 3. CORS設定
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# 4. 共通ログ & 追跡用ミドルウェア
# すべてのリクエストに trace_id を付与し、処理時間を計測します
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()
    aws_context = request.scope.get("aws.context")
    
    # AWS LambdaのRequest IDがあれば使用し、なければ新規生成
    trace_id = aws_context.aws_request_id if aws_context else str(uuid.uuid4())
    request.state.minakata_traceid = trace_id

    # メイン処理の実行
    response = await call_next(request)

    # 後処理: 処理時間の計算とレスポンスヘッダーへのID付与
    process_time_ms = round((time.time() - start_time) * 1000, 2)
    response.headers["X-Minakata-TraceID"] = trace_id

    # 構造化ログを出力 (Athena分析などで活用可能)
    logger.info(
        "Management API Request Summary",
        extra={
            "event_type": "management_transaction",
            "minakata_traceid": trace_id,
            "http_method": request.method,
            "http_path": request.url.path,
            "http_status": response.status_code,
            "latency_ms": process_time_ms,
            "client_ip": request.client.host if request.client else "unknown",
            "user_agent": request.headers.get("user-agent"),
        }
    )
    return response

# --- リソース初期化 ---
dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ.get("LEXIQUE_TABLE")

# 5. エンドポイント定義

@app.get("/lexique/jobs/{job_id}")
async def get_lexique_job_status(job_id: str):
    """
    [ジョブ単体取得]
    DynamoDBのプライマリーキー(job_id)を使用して、
    非同期処理(Lexique等)の現在のステータスや実行結果を返します。
    """
    try:
        table = dynamodb.Table(TABLE_NAME)
        response = table.get_item(Key={"job_id": job_id})
        item = response.get("Item")
        if not item:
            raise HTTPException(status_code=404, detail="Job ID not found")
        return item
    except Exception as e:
        logger.error(f"Get Job Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal Server Error")

@app.get("/lexique/trace/{trace_id}")
async def get_jobs_by_trace_id(trace_id: str):
    """
    [トレーシング検索]
    GSI(Global Secondary Index)を使用して、特定の trace_id に紐づく
    すべてのジョブ履歴を一覧取得します。
    一回のリクエストから派生した複数の処理を横断的に確認するのに使用します。
    """
    try:
        table = dynamodb.Table(TABLE_NAME)
        response = table.query(
            IndexName='MinakataTraceIndex',
            KeyConditionExpression=Key('minakata_traceid').eq(trace_id)
        )
        items = response.get("Items", [])
        return {"count": len(items), "items": items}
    except Exception as e:
        logger.error(f"GSI Query Error: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal Server Error")

# 6. Lambdaハンドラー
# Mangumを使用してFastAPIアプリをLambda環境に適応させます
@logger.inject_lambda_context(log_event=False)
def handler(event, context):
    asgi_handler = Mangum(app, lifespan="off")
    return asgi_handler(event, context)