import base64
import json
import gzip
import datetime
import logging

# ロガーの設定
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    output = []
    success_count = 0
    dropped_count = 0
    failure_count = 0
    
    for record in event['records']:
        record_id = record['recordId']
        try:
            payload = base64.b64decode(record['data'])
            
            # CloudWatch Logsの圧縮を解除
            if payload.startswith(b'\x1f\x8b'):
                data = gzip.decompress(payload)
            else:
                data = payload
            
            log_data = json.loads(data)
            
            # 制御メッセージの処理
            if log_data.get('messageType') == 'CONTROL_MESSAGE':
                dropped_count += 1
                output.append({
                    'recordId': record_id,
                    'result': 'Dropped',
                    'data': record['data']
                })
                continue

            if 'logEvents' in log_data:
                processed_lines = []
                for log_event in log_data['logEvents']:
                    message_content = log_event.get('message', '')
                    
                    refined = {
                        "cwl_id": log_event.get("id"),
                        "cwl_timestamp": log_event.get("timestamp"),
                        "datetime_utc": datetime.datetime.fromtimestamp(
                            log_event.get("timestamp", 0) / 1000.0, 
                            datetime.timezone.utc
                        ).isoformat(timespec='milliseconds') if log_event.get("timestamp") else None
                    }

                    if message_content.startswith('{'):
                        try:
                            refined.update(json.loads(message_content))
                        except:
                            refined["message"] = message_content
                    else:
                        refined["message"] = message_content.strip()
                        refined["log_type"] = "platform" if any(x in message_content for x in ["START", "END", "REPORT"]) else "text"

                    processed_lines.append(json.dumps(refined, ensure_ascii=False))
                
                joined_data = "\n".join(processed_lines) + "\n"
                output_data = base64.b64encode(joined_data.encode('utf-8')).decode('utf-8')
                
                success_count += 1
                output.append({
                    'recordId': record_id,
                    'result': 'Ok',
                    'data': output_data
                })
            else:
                # logEventsがない場合も一応成功扱い（必要に応じて変更）
                success_count += 1
                output.append({'recordId': record_id, 'result': 'Ok', 'data': record['data']})
                
        except Exception as e:
            failure_count += 1
            # エラーの詳細（レコードIDと例外内容）をログに記録
            logger.error(f"Failed to process record. recordId: {record_id}, Error: {str(e)}")
            output.append({
                'recordId': record_id, 
                'result': 'ProcessingFailed', 
                'data': record['data']
            })
    
    # 処理全体のサマリーをログ出力
    logger.info(
        f"Processing complete. Total: {len(event['records'])}, "
        f"Success: {success_count}, Dropped: {dropped_count}, Failed: {failure_count}"
    )
            
    return {'records': output}