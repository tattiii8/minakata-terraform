#!/bin/bash

# 設定
BASE_URL="https://minakata.lesure.net/api/v1"
# 挿入したい単語のリスト
WORDS=("aimer" "manger" "finir" "aller" "voir" "vouloir" "pouvoir" "savoir" "devoir" "venir" 
       "prendre" "croire" "tenir" "parler" "donner" "mettre" "dire" "passer" "regarder" "aimer")

for LEXIQUE_WORD in "${WORDS[@]}"; do
    echo "========================================"
    echo "Processing: ${LEXIQUE_WORD}"
    echo "========================================"

    # 1. POST Request 送信
    RESPONSE=$(curl -s -X POST "${BASE_URL}/lexique" \
      -H "Content-Type: application/json" \
      -d "{\"lexique\":\"${LEXIQUE_WORD}\"}")

    TRACE_ID=$(echo $RESPONSE | jq -r '.minakata_traceid')

    if [ "$TRACE_ID" == "null" ] || [ -z "$TRACE_ID" ]; then
        echo "Error: [${LEXIQUE_WORD}] traceid が取得できませんでした。"
        continue # 次の単語へスキップ
    fi

    echo "Trace ID: $TRACE_ID"

    # 2. ステータス確認 (ポーリング)
    while true; do
        STATUS_RES=$(curl -s "${BASE_URL}/management/lexique/trace/${TRACE_ID}")
        CURRENT_STATUS=$(echo $STATUS_RES | jq -r '.items[0].status')
        
        echo "単語: ${LEXIQUE_WORD} | ステータス: [$CURRENT_STATUS]"

        if [ "$CURRENT_STATUS" == "completed" ]; then
            echo "✅ 完了: ${LEXIQUE_WORD}"
            break
        elif [ "$CURRENT_STATUS" == "error" ]; then
            echo "❌ エラー発生: ${LEXIQUE_WORD}"
            break
        fi

        sleep 1 # サーバーに負荷をかけないよう1秒待機
    done
done

echo "--- 全ての処理が終了しました ---"