import os
import uuid
import json
import boto3
import re
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel
from aws_lambda_powertools import Logger

# 1. ロガー設定
logger = Logger(service="Minakata", child=True)

# 2. ルーターの定義
router = APIRouter(tags=["lexique"], prefix="")

sqs = boto3.client('sqs')
s3_client = boto3.client("s3")
dynamodb = boto3.resource('dynamodb')

# 環境変数
LEXIQUE_QUEUE_URL = os.environ.get("LEXIQUE_QUEUE_URL")
S3_BUCKET = os.environ.get("LEXIQUE_BUCKET_NAME")
LEXIQUE_MASTER_TABLE = os.environ.get("LEXIQUE_MASTER_TABLE")
INDEX_FILE = "index.json"

class LexiqueRequest(BaseModel):
    lexique: str

# --- 内部ロジック ---

def _structure_definition_fr(raw_text: str):
    if not raw_text or raw_text == "N/A":
        return []

    lines = [line.strip() for line in raw_text.split('\n') if line.strip()]
    structured_data = []
    current_definition = None

    for line in lines:
        is_example = bool(re.search(r'—\s*\(', line)) or line.startswith('—')

        if is_example:
            if current_definition:
                current_definition["examples"].append(line)
            else:
                structured_data.append({"text": "Exemples:", "examples": [line]})
        else:
            current_definition = {"text": line, "examples": []}
            structured_data.append(current_definition)
            
    return structured_data

async def _load_lexique_index():
    """S3からlexiqueインデックス（一覧用）を一括取得"""
    try:
        if not S3_BUCKET:
            raise ValueError("LEXIQUE_BUCKET_NAME is not set")
        response = s3_client.get_object(Bucket=S3_BUCKET, Key=INDEX_FILE)
        return json.loads(response["Body"].read().decode("utf-8"))
    except Exception as e:
        logger.error(f"Index Load Error: {str(e)}")
        return []

# --- エンドポイント ---

@router.post("/lexique") 
async def request_lexique_update(request: Request, data: LexiqueRequest):
    """[収集依頼] SQSへ調査ジョブを投入"""
    # ミドルウェアで付与された trace_id を取得
    trace_id = getattr(request.state, "minakata_traceid", "unknown")
    
    if not LEXIQUE_QUEUE_URL:
        logger.error("SQS Queue URL missing", extra={"minakata_traceid": trace_id})
        raise HTTPException(status_code=500, detail="Queue not configured")

    job_id = str(uuid.uuid4())
    
    try:
        # SQSへのメッセージ送信
        sqs.send_message(
            QueueUrl=LEXIQUE_QUEUE_URL,
            MessageBody=json.dumps({
                "job_id": job_id,
                "minakata_traceid": trace_id,
                "lexique": data.lexique
            })
        )
        
        # --- 修正ポイント: 構造化ログの出力 (event_type を指定) ---
        logger.info(
            f"Enqueued to SQS: {data.lexique}", 
            extra={
                "event_type": "sqs_produced", # 分散トレーシングの起点タグ
                "minakata_traceid": trace_id,
                "job_id": job_id,
                "lexique": data.lexique,
                "queue_url": LEXIQUE_QUEUE_URL
            }
        )

    except Exception as e:
        logger.error(f"SQS Error: {e}", extra={"minakata_traceid": trace_id})
        raise HTTPException(status_code=500, detail="Failed to dispatch job")

    return {"job_id": job_id, "status": "processing", "minakata_traceid": trace_id}

@router.get("/lexique")
async def list_lexique_items(request: Request):
    """[一覧取得] 蓄積された全lexiqueを返却"""
    trace_id = getattr(request.state, "minakata_traceid", "unknown")
    all_data = await _load_lexique_index()
    
    logger.info("Listed items", extra={"minakata_traceid": trace_id, "count": len(all_data)})
    return all_data

@router.get("/lexique/{lexique_item}")
async def get_lexique_detail(request: Request, lexique_item: str):
    """[詳細取得] DynamoDB Master Table から取得し、構造化して返却"""
    trace_id = getattr(request.state, "minakata_traceid", "unknown")
    
    if not LEXIQUE_MASTER_TABLE:
        logger.error("LEXIQUE_MASTER_TABLE env var is missing")
        raise HTTPException(status_code=500, detail="Database not configured")

    try:
        table = dynamodb.Table(LEXIQUE_MASTER_TABLE)
        response = table.get_item(
            Key={'lexique': lexique_item.lower()}
        )
        
        detail = response.get('Item')
        
        if not detail:
            logger.warning(f"Not found in MasterTable: {lexique_item}", extra={"minakata_traceid": trace_id})
            raise HTTPException(status_code=404, detail="Item not found")
        
        raw_def = detail.get("definition_fr", "")
        detail["definitions_structured"] = _structure_definition_fr(raw_def)
        
        logger.info("Detail viewed", extra={"minakata_traceid": trace_id, "lexique_word": lexique_item})
        return detail

    except Exception as e:
        logger.error(f"DynamoDB GetItem Error: {str(e)}", extra={"minakata_traceid": trace_id})
        raise HTTPException(status_code=500, detail="Internal Server Error")