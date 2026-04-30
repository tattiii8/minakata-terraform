import os
import json
import time
import boto3
import httpx
from bs4 import BeautifulSoup  # requirements.txt に追加
import google.generativeai as genai
from aws_lambda_powertools import Logger

logger = Logger(service="Minakata-Worker")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.getenv("TABLE_NAME"))

# Webコンテンツを取得・クリーンアップする関数
async def fetch_web_content(url: str) -> str:
    async with httpx.AsyncClient(follow_redirects=True, timeout=15.0) as client:
        response = await client.get(url)
        response.raise_for_status()
        
        soup = BeautifulSoup(response.text, "html.parser")
        # スクリプト、スタイル、ナビゲーションなど不要な要素を削除
        for element in soup(["script", "style", "nav", "footer", "header"]):
            element.decompose()
            
        text = soup.get_text(separator=" ", strip=True)
        # Geminiに渡す文字数を制限（コンテキスト節約のため2500文字程度）
        return text[:2500]

def handler(event, context):
    # 非同期実行のためにループ内で async 関数を呼ぶ仕組みが必要な場合は、
    # asyncio.run() 等を使用しますが、ここでは簡単のため同期的な構造で示します。
    import asyncio
    return asyncio.run(async_handler(event, context))

async def async_handler(event, context):
    for record in event['Records']:
        body = json.loads(record['body'])
        job_id = body.get("job_id")
        webhook_url = body.get("webhook_url")
        
        # 調査対象URLがあるかチェック
        target_url = body.get("url")
        user_prompt = body.get("prompt")

        logger.info("Processing job", extra={"job_id": job_id, "url": target_url})

        try:
            # 1. コンテキストの準備
            if target_url:
                web_content = await fetch_web_content(target_url)
                final_prompt = (
                    f"重要なポイントを3点で要約してください。\n"
                    f"URL: {target_url}\n"
                    f"内容: {web_content}"
                )
            else:
                final_prompt = user_prompt

            # 2. Gemini実行
            genai.configure(api_key=os.getenv("GEMINI_API_KEY"))
            model = genai.GenerativeModel(os.getenv("GEMINI_MODEL_NAME", "gemini-1.5-flash"))
            response = model.generate_content(final_prompt)
            answer = response.text

            # 3. DynamoDB保存
            table.put_item(Item={
                "job_id": job_id,
                "prompt": target_url or user_prompt,
                "answer": answer,
                "status": "completed",
                "created_at": int(time.time()),
                "expires_at": int(time.time()) + (30 * 86400)
            })

            # 4. Webhook送信（自分自身のAPIへ報告）
            if webhook_url:
                async with httpx.AsyncClient() as client:
                    await client.post(webhook_url, json={
                        "job_id": job_id,
                        "status": "completed",
                        "answer": answer
                    }, timeout=10.0)
                logger.info("Webhook sent successfully", extra={"url": webhook_url})

        except Exception as e:
            logger.exception("Worker failure")
            if webhook_url:
                try:
                    async with httpx.AsyncClient() as client:
                        await client.post(webhook_url, json={"job_id": job_id, "status": "failed"})
                except: pass
            raise e