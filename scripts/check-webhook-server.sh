#!/bin/bash

# エラーハンドリングをインポート
source "$(dirname "$0")/error-handler.sh"

# 環境変数の検証
if [[ -z "${WEBHOOK_SERVER_URL}" ]]; then
  handle_error 1 "必要な環境変数が設定されていません: WEBHOOK_SERVER_URL" "環境変数検証"
fi

# URLからwebhookパスを除去（もし含まれている場合）
BASE_URL=$(echo "${WEBHOOK_SERVER_URL}" | sed 's/\/webhook$//')

echo "::group::Webhookサーバーの疎通確認"
echo "[INFO] Webhookサーバーの疎通確認を開始します..."
echo "[INFO] 対象URL: ${BASE_URL}/health"

# 最大試行回数
MAX_RETRIES=3
RETRY_INTERVAL=5

for ((i=1; i<=MAX_RETRIES; i++)); do
  echo "[INFO] 試行 $i/$MAX_RETRIES"
  
  HTTP_STATUS=$(curl -w "%{http_code}" -s -o response.txt \
    --connect-timeout 10 \
    --max-time 10 \
    "${BASE_URL}/health")
  
  CURL_EXIT_CODE=$?
  
  if [[ $CURL_EXIT_CODE -ne 0 ]]; then
    echo "[WARNING] 接続エラーが発生しました (curl exit code: $CURL_EXIT_CODE)"
    if [[ $i -eq $MAX_RETRIES ]]; then
      echo "[ERROR] 最大試行回数に達しました"
      echo "::endgroup::"
      handle_error 1 "Webhookサーバーへの接続に失敗しました" "疎通確認"
    fi
    echo "[INFO] ${RETRY_INTERVAL}秒後にリトライします..."
    sleep $RETRY_INTERVAL
    continue
  fi

  if [[ "$HTTP_STATUS" == "200" ]]; then
    echo "[INFO] レスポンス内容:"
    cat response.txt
    echo "[SUCCESS] Webhookサーバーの疎通確認に成功しました"
    rm -f response.txt
    echo "::endgroup::"
    exit 0
  else
    echo "[WARNING] 予期しないHTTPステータスコード: $HTTP_STATUS"
    if [[ -f response.txt ]]; then
      echo "[INFO] レスポンス内容:"
      cat response.txt
      rm -f response.txt
    fi
    
    if [[ $i -eq $MAX_RETRIES ]]; then
      echo "[ERROR] 最大試行回数に達しました"
      echo "::endgroup::"
      handle_error 1 "Webhookサーバーからエラーレスポンスを受信しました (HTTP $HTTP_STATUS)" "疎通確認"
    fi
    
    echo "[INFO] ${RETRY_INTERVAL}秒後にリトライします..."
    sleep $RETRY_INTERVAL
  fi
done
