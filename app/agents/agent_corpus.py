import os
import time
import json
import fitz
import hashlib
import tarfile
import subprocess
import shutil
import boto3
from meilisearch import Client
from aws_lambda_powertools import Logger
from botocore.exceptions import ClientError

# ログ設定
logger = Logger(service="Minakata")
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

# 環境変数
TABLE_NAME = os.getenv('CORPUS_JOB_TABLE')
BUCKET = os.getenv('CORPUS_BUCKET_NAME')
MASTER_KEY = os.getenv('MEILI_MASTER_KEY', 'masterKey123')
SQS_QUEUE_URL = os.getenv('SQS_QUEUE_URL')

# パス設定
MEILI_BIN_ORIGIN = "/var/task/bin/meilisearch"
MEILI_BIN_TMP = "/tmp/meilisearch"
DB_PATH = "/tmp/data.ms"
DUMP_DIR = "/tmp/dumps"
SNAPSHOT_DIR = "/tmp/snapshots"
S3_PDF_PREFIX = "pdfs/"
LOCAL_PDF_DIR = "/tmp/pdfs"

def setup_local_meili():
    """Meilisearchを/tmp領域でセットアップして起動する"""
    os.makedirs(DUMP_DIR, exist_ok=True)
    os.makedirs(SNAPSHOT_DIR, exist_ok=True)
    
    if not os.path.exists(MEILI_BIN_TMP):
        logger.info(f"Copying binary to {MEILI_BIN_TMP}")
        shutil.copy2(MEILI_BIN_ORIGIN, MEILI_BIN_TMP)
    os.chmod(MEILI_BIN_TMP, 0o755)

    if os.path.exists(DB_PATH):
        logger.info(f"Cleaning up old DB path: {DB_PATH}")
        shutil.rmtree(DB_PATH)

    try:
        logger.info("Downloading Meilisearch index from S3...")
        s3.download_file(BUCKET, "index.tar.gz", "/tmp/index.tar.gz")
        with tarfile.open("/tmp/index.tar.gz", "r:gz") as tar:
            tar.extractall(path="/tmp")
        logger.info("Index extracted successfully")
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code in ["404", "403"]:
            logger.warning("No index found in S3, starting fresh")
        else:
            raise e
    except Exception as e:
        logger.error(f"Unexpected error during index restore: {e}")

    os.makedirs(DB_PATH, exist_ok=True)

    logger.info("Starting Meilisearch binary...")
    proc = subprocess.Popen([
        MEILI_BIN_TMP, 
        "--db-path", DB_PATH, 
        "--master-key", MASTER_KEY,
        "--http-addr", "127.0.0.1:7700",
        "--dump-dir", DUMP_DIR,
        "--snapshot-dir", SNAPSHOT_DIR,
        "--no-analytics"
    ], 
    stdout=subprocess.PIPE, 
    stderr=subprocess.STDOUT, 
    text=True,
    cwd="/tmp"
    )
    
    client = Client("http://127.0.0.1:7700", MASTER_KEY)
    for i in range(15):
        if proc.poll() is not None:
            stdout, _ = proc.communicate()
            raise Exception(f"Meilisearch process died: {stdout}")
        try:
            if client.health().get('status') == 'available':
                return proc, client
        except:
            time.sleep(1)
            
    proc.terminate()
    raise Exception("Meilisearch healthcheck timeout")

def save_index_to_s3():
    """DBをアーカイブしてS3へ保存"""
    if not os.path.exists(DB_PATH):
        return
    
    archive_path = "/tmp/index.tar.gz"
    if os.path.exists(archive_path):
        os.remove(archive_path)

    with tarfile.open(archive_path, "w:gz") as tar:
        tar.add(DB_PATH, arcname="data.ms")
    
    s3.upload_file(archive_path, BUCKET, "index.tar.gz")
    logger.info("Index upload complete")

def handler(event, context):
    """メインロジック (Lambdaイベント形式)"""
    table = dynamodb.Table(TABLE_NAME)
    
    for record in event['Records']:
        body = json.loads(record['body'])
        job_id = body.get('job_id')
        action = body.get('action')
        message_id = record.get('messageId')
        
        logger.append_keys(job_id=job_id, action=action)
        table.put_item(Item={
            'job_id': job_id, 
            'status': 'processing', 
            'started_at': int(time.time()),
            'sqs_message_id': message_id
        })
        
        process = None
        try:
            process, client = setup_local_meili()
            index = client.index('corpus')
            result_data = {}

            if action == "index_all_pdfs":
                os.makedirs(LOCAL_PDF_DIR, exist_ok=True)
                response = s3.list_objects_v2(Bucket=BUCKET, Prefix=S3_PDF_PREFIX)
                pdf_contents = response.get('Contents', [])
                
                pages_indexed = 0
                last_task_uid = None

                for obj in pdf_contents:
                    key = obj['Key']
                    if not key.endswith('.pdf'): continue
                    
                    filename = os.path.basename(key)
                    local_path = os.path.join(LOCAL_PDF_DIR, filename)
                    logger.info(f"Downloading PDF: {filename}")
                    s3.download_file(BUCKET, key, local_path)
                    
                    doc = fitz.open(local_path)
                    documents = []
                    for page_num, page in enumerate(doc):
                        text = page.get_text().strip()
                        if text:
                            doc_id = hashlib.md5(f"{key}_{page_num}".encode()).hexdigest()
                            documents.append({
                                "id": doc_id, "filename": filename, 
                                "page": page_num + 1, "content": text
                            })
                    
                    if documents:
                        task = index.add_documents(documents)
                        last_task_uid = task.task_uid
                        pages_indexed += len(documents)
                    
                    doc.close()
                    os.remove(local_path)

                if last_task_uid:
                    logger.info(f"Waiting for Meilisearch task {last_task_uid} to complete...")
                    client.wait_for_task(last_task_uid, timeout_in_ms=600000)

                logger.info("Task completed. Proceeding to save index.")
                process.terminate()
                process.wait(timeout=10)
                process = None 
                
                save_index_to_s3()
                result_data = {"status": "success", "total_pages": pages_indexed}

            elif action == "search_query":
                query = body.get('query')
                # ヒット内容を含め、キーワード強調を有効にする
                search_params = body.get('search_params', {
                    'limit': 20,
                    'attributesToHighlight': ['content'],
                    'highlightPreTag': '<mark>',
                    'highlightPostTag': '</mark>'
                })
                
                logger.info("Executing search query", extra={"query": query})
                start_perf = time.perf_counter()
                search_res = index.search(query, search_params)
                end_perf = time.perf_counter()

                result_data = {
                    "results_count": len(search_res['hits']),
                    "hits": search_res['hits'], 
                    "query": query,
                    "time_ms": (end_perf - start_perf) * 1000
                }

            table.update_item(
                Key={'job_id': job_id},
                UpdateExpression="set #s = :s, finished_at = :f, result_data = :d",
                ExpressionAttributeNames={'#s': 'status'},
                ExpressionAttributeValues={
                    ':s': 'completed', 
                    ':f': int(time.time()),
                    ':d': json.dumps(result_data, ensure_ascii=False)
                }
            )

        except Exception as e:
            logger.exception("Fatal error during worker processing")
            table.update_item(
                Key={'job_id': job_id},
                UpdateExpression="set #s = :s, #err = :e",
                ExpressionAttributeNames={'#s': 'status', '#err': 'error'},
                ExpressionAttributeValues={':s': 'failed', ':e': str(e)}
            )
        finally:
            if process:
                try:
                    process.terminate()
                    process.wait(timeout=2)
                except:
                    process.kill()
            logger.remove_keys(["job_id", "action"])

    return {"statusCode": 200}

def run_as_agent():
    """ECS/Anywhere環境での常駐ループ"""
    sqs = boto3.client('sqs')
    logger.info(f"Starting Minakata Corpus Agent loop. Queue: {SQS_QUEUE_URL}")
    
    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=SQS_QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=20,
                AttributeNames=['All']
            )
            
            if 'Messages' in response:
                for msg in response['Messages']:
                    fake_event = {
                        'Records': [{
                            'body': msg['Body'],
                            'messageId': msg['MessageId'],
                            'attributes': msg.get('Attributes', {})
                        }]
                    }
                    logger.info(f"Processing message: {msg['MessageId']}")
                    handler(fake_event, None)
                    sqs.delete_message(QueueUrl=SQS_QUEUE_URL, ReceiptHandle=msg['ReceiptHandle'])
        except Exception as e:
            logger.error(f"Error in agent loop: {e}")
            time.sleep(5)

if __name__ == "__main__":
    run_as_agent()