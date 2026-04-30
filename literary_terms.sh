#!/bin/bash

BASE_URL="https://minakata.lesure.net/api/v1"

# --- 人文学・批評理論の重要単語 ---
# 意味の深みを出すため、あえて抽象度の高い単語を選択
WORDS=(
  "intertextualité" "discours" "narratologie" "esthétique" "rhétorique"
  "subjectivité" "transgression" "phénoménologie" "déconstruction" "paradigme"
  "sémiotique" "épistémologie" "altérité" "mimésis" "modernité"
  "structure" "allégorie" "métaphore" "herméneutique" "diégèse"
)

echo "===================================================="
echo "  Minakata API: 文学・批評用語 一括投入"
echo "===================================================="

TRACE_IDS=()

for WORD in "${WORDS[@]}"; do
    # 文学用語は綴りが複雑なため、確実にJSONエンコードしてPOST
    RESPONSE=$(curl -s -X POST "${BASE_URL}/lexique" \
      -H "Content-Type: application/json" \
      -d "{\"lexique\":\"${WORD}\"}")
    
    TID=$(echo "$RESPONSE" | jq -r '.minakata_traceid // empty')
    
    if [ -n "$TID" ] && [ "$TID" != "null" ]; then
        echo "[Queued] $WORD (TraceID: $TID)"
        TRACE_IDS+=("$TID")
    else
        echo "[Error]  $WORD の投入に失敗しました。"
    fi
    sleep 0.8 # Lambdaの同時実行数を考慮し少し長めに待機
done

echo ""
echo "--- ステータス監視中... ---"

while true; do
    COMPLETED=0
    for TID in "${TRACE_IDS[@]}"; do
        STATUS=$(curl -s "${BASE_URL}/management/lexique/trace/${TID}" | jq -r '.items[0].status // "pending"')
        [[ "$STATUS" == "completed" ]] && ((COMPLETED++))
    done

    printf "\r進捗: [%d/%d]" "$COMPLETED" "${#WORDS[@]}"
    
    if [ "$COMPLETED" -eq "${#WORDS[@]}" ]; then
        echo -e "\n✅ 文学用語の全登録が完了しました。"
        break
    fi
    sleep 5
done

echo "===================================================="