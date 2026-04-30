import time
import json
import os
import boto3
import requests
from bs4 import BeautifulSoup
import urllib.parse
import csv
import io
from aws_lambda_powertools import Logger

# service名をAPI側と合わせることで、Insightsで横断検索しやすくなります
logger = Logger(service="Minakata")
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# 環境変数
TABLE_NAME = os.environ.get('LEXIQUE_TABLE', '')         # ジョブ管理用
MASTER_TABLE_NAME = os.environ.get('LEXIQUE_MASTER_TABLE', '') # 検索マスター用
BUCKET_NAME = os.environ.get('LEXIQUE_BUCKET', '')
PREFIX = "histoire/"

def get_table():
    if not TABLE_NAME:
        raise ValueError("環境変数 'LEXIQUE_TABLE' が設定されていません。")
    return dynamodb.Table(TABLE_NAME)

def get_master_table():
    if not MASTER_TABLE_NAME:
        raise ValueError("環境変数 'LEXIQUE_MASTER_TABLE' が設定されていません。")
    return dynamodb.Table(MASTER_TABLE_NAME)

def update_index_json():
    """S3上の全CSVを読み込み、最新のindex.jsonを生成する"""
    try:
        response = s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix=PREFIX)
        if 'Contents' not in response:
            return

        latest_entries = {}
        for obj in response['Contents']:
            key = obj['Key']
            if not key.endswith(".csv"): continue
            
            filename = key.replace(PREFIX, "")
            lexique_name = filename.split("_")[0]

            if lexique_name not in latest_entries or obj['LastModified'] > latest_entries[lexique_name]['raw_date']:
                try:
                    file_obj = s3.get_object(Bucket=BUCKET_NAME, Key=key)
                    content = file_obj["Body"].read().decode("utf-8")
                    reader = csv.reader(io.StringIO(content), quotechar='"', skipinitialspace=True)
                    row = next(reader)

                    latest_entries[lexique_name] = {
                        "lexique": row[0] if len(row) > 0 else lexique_name,
                        "phonetic": row[1] if len(row) > 1 else "N/A",
                        "definition_fr": row[2] if len(row) > 2 else "N/A",
                        "meaning_jp": row[3] if len(row) > 3 else "N/A",
                        "file_key": key,
                        "updated_at": obj['LastModified'].isoformat(),
                        "raw_date": obj['LastModified']
                    }
                except Exception as parse_err:
                    logger.error(f"Failed to parse CSV {key}", extra={"error": str(parse_err)})
                    continue

        index_data = [ {k: v for k, v in entry.items() if k != 'raw_date'} for entry in latest_entries.values() ]
        index_data.sort(key=lambda x: x["updated_at"], reverse=True)

        s3.put_object(
            Bucket=BUCKET_NAME,
            Key="index.json",
            Body=json.dumps(index_data, ensure_ascii=False),
            ContentType="application/json"
        )
        logger.info("Successfully updated index.json", extra={"event_type": "index_updated"})
    except Exception as e:
        logger.error("Failed to update index.json", extra={"error": str(e)})

def handler(event, context):
    table = get_table()
    master_table = get_master_table()
    
    for record in event['Records']:
        # ループの最初にロガーの状態をクリア
        logger.structure_logs(append=False) 
        
        try:
            body = json.loads(record['body'])
            job_id = body.get('job_id')
            trace_id = body.get('minakata_traceid', 'unknown_worker')
            lexique = body.get('lexique') or body.get('keyword') or body.get('word')
            
            # trace_id をロガーに固定
            logger.append_keys(minakata_traceid=trace_id)

            if not job_id or not lexique:
                logger.error("Missing parameters in SQS body", extra={"body": body})
                continue

            # --- 修正ポイント: workerがSQSメッセージを拾ったことを記録 ---
            logger.info(
                f"Worker started processing: {lexique}", 
                extra={
                    "event_type": "worker_consumed", 
                    "job_id": job_id, 
                    "lexique": lexique
                }
            )
            
            table.put_item(Item={
                'job_id': job_id, 
                'minakata_traceid': trace_id, 
                'status': 'processing', 
                'lexique': lexique, 
                'started_at': int(time.time())
            })
            # --- 修正ポイント: Jobテーブルへの初期書き込み完了ログ ---
            logger.info("Status updated to processing", extra={"event_type": "db_updated", "table": "JobTable"})

            # 2. Wiktionaryからデータ取得
            results = {"FR": "N/A", "JA": "N/A", "PRON": "N/A"}
            encoded_word = urllib.parse.quote(lexique)
            headers = {"User-Agent": "MinakataLexiqueBot/1.0"}

            # FR
            try:
                fr_url = f"https://fr.wiktionary.org/wiki/{encoded_word}"
                fr_res = requests.get(fr_url, headers=headers, timeout=10)
                if fr_res.status_code == 200:
                    soup_fr = BeautifulSoup(fr_res.text, 'html.parser')
                    pron_tag = soup_fr.find("span", class_="pron")
                    if pron_tag: results['PRON'] = pron_tag.get_text()
                    fr_def = soup_fr.find("ol")
                    if fr_def and fr_def.find("li"): results['FR'] = fr_def.find("li").get_text().strip()
            except Exception as e:
                logger.warning(f"FR scraping failed: {str(e)}")

            # JA
            try:
                ja_url = f"https://ja.wiktionary.org/wiki/{encoded_word}"
                ja_res = requests.get(ja_url, headers=headers, timeout=10)
                if ja_res.status_code == 200:
                    soup_ja = BeautifulSoup(ja_res.text, 'html.parser')
                    ja_def = soup_ja.find("ol")
                    if ja_def and ja_def.find("li"): results['JA'] = ja_def.find("li").get_text().strip()
            except Exception as e:
                logger.warning(f"JA scraping failed: {str(e)}")

            # 3. S3へ保存
            s3_key = f"{PREFIX}{lexique}_{job_id}.csv"
            csv_buffer = io.StringIO()
            writer = csv.writer(csv_buffer)
            writer.writerow([lexique, results['PRON'], results['FR'], results['JA'], time.strftime('%Y-%m-%d %H:%M:%S')])
            
            s3.put_object(
                Bucket=BUCKET_NAME, 
                Key=s3_key, 
                Body=csv_buffer.getvalue(),
                ContentType="text/csv"
            )
            logger.info(f"Saved CSV to S3: {s3_key}", extra={"event_type": "worker_file_saved", "s3_key": s3_key})

            # 4. 目録（index.json）更新
            update_index_json()

            # 5. Job Table完了更新
            table.update_item(
                Key={'job_id': job_id},
                UpdateExpression="set #s = :s, finished_at = :f",
                ExpressionAttributeNames={'#s': 'status'},
                ExpressionAttributeValues={':s': 'completed', ':f': int(time.time())}
            )
            # --- 修正ポイント: Jobテーブル完了ログ ---
            logger.info("Job status updated to completed", extra={"event_type": "db_updated", "table": "JobTable"})

            # 6. Master Table永続化
            master_table.put_item(Item={
                'lexique': lexique.lower(),
                'phonetic': results['PRON'],
                'definition_fr': results['FR'],
                'meaning_jp': results['JA'],
                'file_key': s3_key,
                'updated_at': time.strftime('%Y-%m-%dT%H:%M:%SZ'),
                'minakata_traceid': trace_id,
                'job_id': job_id
            })
            # --- 修正ポイント: Masterテーブル更新ログ ---
            logger.info(f"Master record updated: {lexique}", extra={"event_type": "db_updated", "table": "MasterTable"})

        except Exception as e:
            logger.error("Error processing record", extra={"error": str(e)})
            continue

    return {"statusCode": 200}