import os
import uuid
import json
import boto3
from fastapi import APIRouter, HTTPException, Request
from aws_lambda_powertools import Logger

logger = Logger(child=True)
router = APIRouter(prefix="/corpus", tags=["corpus"])

sqs = boto3.client('sqs')
QUEUE_URL = os.getenv("CORPUS_QUEUE_URL")

async def send_to_worker(action: str, params: dict, trace_id: str):
    """共通のジョブ発行ロジック"""
    job_id = str(uuid.uuid4())
    try:
        message_body = {
            "job_id": job_id,
            "minakata_traceid": trace_id,
            "action": action,
            **params
        }
        sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(message_body))
        return job_id
    except Exception as e:
        logger.error(f"Failed to queue {action}: {e}")
        raise HTTPException(status_code=500, detail="Failed to queue job")

@router.post("/index")
async def trigger_index(request: Request):
    """インデックス作成ジョブの受付"""
    trace_id = getattr(request.state, "minakata_traceid", "unknown")
    job_id = await send_to_worker("index_all_pdfs", {}, trace_id)
    return {"job_id": job_id, "status": "queued"}

@router.get("/search")
async def trigger_search(q: str, request: Request):
    """検索ジョブの受付 (非同期)"""
    trace_id = getattr(request.state, "minakata_traceid", "unknown")
    job_id = await send_to_worker("search_query", {"query": q}, trace_id)
    # クライアントはこの job_id を使って DynamoDB の結果を取得する
    return {"job_id": job_id, "status": "queued"}