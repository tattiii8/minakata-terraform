#!/bin/bash

# --- 設定 ---
BASE_URL="https://minakata.lesure.net/api/v1"
# 動作確認用の20単語（フランス語の基本単語）
WORDS=("aimer" "manger" "finir" "aller" "voir" "vouloir" "pouvoir" "savoir" "devoir" "venir" 
       "prendre" "croire" "tenir" "parler" "donner" "mettre" "dire" "passer" "regarder" "comprendre")

echo "===================================================="
echo "  Minakata API: 動作確認 & 一括投入スクリプト"
echo "===================================================="

# 1. 一括投入フェーズ
TRACE_IDS=()
echo "--- 1. ジョブ投入開始 (20単語) ---"
for WORD in "${WORDS[@]}"; do
    # POSTリクエスト
    RESPONSE=$(curl -s -X POST "${BASE_URL}/lexique" \
      -H "Content-Type: application/json" \
      -d "{\"lexique\":\"${WORD}\"}")
    
    # 修正: jqのパースエラーを防ぎつつTraceIDを取得
    TID=$(echo "$RESPONSE" | jq -r '.minakata_traceid // empty')
    
    if [ -n "$TID" ] && [ "$TID" != "null" ]; then
        echo "[Queued] Word: $WORD | TraceID: $TID"
        TRACE_IDS+=("$TID")
    else
        echo "[Error]  Word: $WORD | Response: $RESPONSE"
    fi
    sleep 0.5
done

echo ""
echo "--- 2. ステータス監視 (全ての完了を待機) ---"
# 全てのTIDを順次チェックするロジックに変更
while true; do
    PENDING_COUNT=0
    COMPLETED_COUNT=0
    ERROR_COUNT=0

    for TID in "${TRACE_IDS[@]}"; do
        STATUS_RES=$(curl -s "${BASE_URL}/management/lexique/trace/${TID}")
        # items[0] が存在しない場合に備えて default 指定
        CURRENT_STATUS=$(echo "$STATUS_RES" | jq -r '.items[0].status // "pending"')

        if [ "$CURRENT_STATUS" == "completed" ]; then
            ((COMPLETED_COUNT++))
        elif [ "$CURRENT_STATUS" == "error" ]; then
            ((ERROR_COUNT++))
        else
            ((PENDING_COUNT++))
        fi
    done

    printf "\r進捗: [完了: %d, 実行中: %d, エラー: %d]" "$COMPLETED_COUNT" "$PENDING_COUNT" "$ERROR_COUNT"

    if [ "$PENDING_COUNT" -eq 0 ]; then
        echo -e "\n✅ 全てのキュー処理が終了しました。"
        break
    fi
    sleep 5
done

echo ""
echo "--- 3. 検索DB (DynamoDB Master Table) 疎通確認 ---"
# ランダムに1語（例: 5番目の単語 "voir"）
TEST_WORD=${WORDS[4]} 
echo "ターゲット単語: $TEST_WORD"

# 修正: URLエンコードが必要な場合に備え、パスを引用
DETAIL_RES=$(curl -s "${BASE_URL}/lexique/${TEST_WORD}")
# 取得データの検証（jqの -e フラグで存在チェック）
if echo "$DETAIL_RES" | jq -e ".lexique == \"$TEST_WORD\"" > /dev/null; then
    echo "✅ DynamoDB Master Table からのデータ取得に成功！"
    echo "$DETAIL_RES" | jq '{lexique: .lexique, meaning_jp: .meaning_jp, updated_at: .updated_at}'
else
    echo "❌ DynamoDB からデータを取得できませんでした。HTTP Status かテーブルを確認してください。"
fi

echo ""
echo "--- 4. 目録 (S3 index.json) 整合性確認 ---"
# 修正: 配列の長さを取得
INDEX_DATA=$(curl -s "${BASE_URL}/lexique")
INDEX_COUNT=$(echo "$INDEX_DATA" | jq '. | length')
echo "現在の index.json 掲載件数: $INDEX_COUNT 件"

# 20件以上（既存データを含むため）存在するか確認
if [ "$INDEX_COUNT" -ge 20 ]; then
    echo "✅ S3 index.json への反映も正常です。"
else
    echo "⚠️ 件数が足りません。S3イベント通知 または Lambda(Flaubert/Kristeva) のログを確認してください。"
fi

echo ""
echo "===================================================="
echo "  テスト終了"
echo "===================================================="