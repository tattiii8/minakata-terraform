# --- Base Stage (共通のPython環境) ---
FROM public.ecr.aws/lambda/python:3.12 as base
WORKDIR ${LAMBDA_TASK_ROOT}

# 1. まず依存関係定義だけをコピー（キャッシュが効きやすい）
COPY requirements.txt .
RUN pip install -r requirements.txt

# --- App Stage (API/Gemini/Lexique用: Meiliなし) ---
FROM base as app_final
# 2. ここで初めて全ソースコードをコピー（コード修正時はここから下が動く）
COPY . .
CMD ["main.handler"]

# --- Corpus Stage (Corpus Agent用: Meiliあり) ---
FROM base as corpus_final

# 1. バイナリのダウンロードと権限付与
# (あらかじめ実行権限を付けておけば、コード側での chmod 失敗を回避できる可能性があります)
RUN mkdir -p ${LAMBDA_TASK_ROOT}/bin && \
    curl -L https://github.com/meilisearch/meilisearch/releases/download/v1.6.2/meilisearch-linux-amd64 > ${LAMBDA_TASK_ROOT}/bin/meilisearch && \
    chmod 755 ${LAMBDA_TASK_ROOT}/bin/meilisearch

# 2. Meilisearchが書き込みを行うディレクトリを環境変数で強制的に /tmp に向ける
# これにより、引数で指定し忘れたログや一時ファイルも /tmp に行きます
ENV MEILI_DB_PATH=/tmp/data.ms
ENV MEILI_DUMP_DIR=/tmp/dumps
ENV MEILI_SNAPSHOT_DIR=/tmp/snapshots
ENV MEILI_HTTP_ADDR=127.0.0.1:7700
ENV MEILI_NO_ANALYTICS=true

# 3. 最後に全ソースコードをコピー
COPY . .

# 4. 実行時の作業ディレクトリを /tmp に設定（重要）
# Lambda実行時のデフォルトカレントディレクトリを書き込み可能領域にします
WORKDIR /tmp

CMD ["/var/task/agents/agent_corpus.handler"]