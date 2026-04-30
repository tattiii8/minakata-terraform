import os
import json
import uuid
import boto3
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from aws_lambda_powertools import Logger
from typing import Optional

logger = Logger(child=True)
sqs = boto3.client("sqs")

# 環境変数
QUEUE_URL = os.getenv("SQS_QUEUE_URL")
DEFAULT_WEBHOOK_URL = os.getenv("INTERNAL_WEBHOOK_URL")
LINE_CHANNEL_ACCESS_TOKEN = os.getenv("LINE_CHANNEL_ACCESS_TOKEN") # Messaging API用

class ChatRequest(BaseModel):
    prompt: str
    webhook_url: Optional[str] = None

class WebhookPayload(BaseModel):
    job_id: str
    status: str
    answer: Optional[str] = None
    error: Optional[str] = None

router = APIRouter(prefix="/gemini", tags=["AI"])

# LINE Messaging API: Broadcast送信関数
async def send_line_broadcast(text: str):
    if not LINE_CHANNEL_ACCESS_TOKEN:
        logger.warning("LINE_CHANNEL_ACCESS_TOKEN is not set")
        return

    url = "https://api.line.me/v2/bot/message/broadcast"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {LINE_CHANNEL_ACCESS_TOKEN}"
    }
    payload = {
        "messages": [
            {
                "type": "text",
                "text": text
            }
        ]
    }

    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(url, headers=headers, json=payload)
            logger.info("LINE Broadcast sent", extra={"status": response.status_code})
        except Exception as e:
            logger.error("Failed to send LINE Broadcast", extra={"error": str(e)})

@router.post("/prompt")
async def ask_gemini_async(request: ChatRequest):
    job_id = str(uuid.uuid4())
    target_webhook = request.webhook_url or DEFAULT_WEBHOOK_URL
    
    try:
        payload = {
            "job_id": job_id, 
            "prompt": request.prompt,
            "webhook_url": target_webhook
        }
        sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(payload))
        logger.info("Sherlock accepted job", extra={"job_id": job_id})
        return {"status": "accepted", "job_id": job_id}
    except Exception as e:
        logger.exception("SQS error")
        raise HTTPException(status_code=500, detail=str(e))
    

@router.post("/webhook")
async def receive_gemini_webhook(payload: WebhookPayload):
    logger.info("Sherlock received webhook", extra={"job_id": payload.job_id})

    if payload.status == "completed":
        # Broadcastで送信
        msg = f"Sherlock\n\n{payload.answer}"
        await send_line_broadcast(msg)
    
    elif payload.status == "failed":
        await send_line_broadcast(f"Sherlock\nエラーが発生しました。\nJob ID: {payload.job_id[:8]}")

    return {"message": "Notification processed"}