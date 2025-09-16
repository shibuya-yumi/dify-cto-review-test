#!/bin/bash

# エラーハンドリングをインポート
source "$(dirname "$0")/error-handler.sh"

# 環境変数の検証
required_env_vars=(
  "WEBHOOK_SERVER_URL"
  "GITHUB_REPOSITORY"
  "PR_NUMBER"
  "PR_TITLE"
  "PR_SHA"
)

for var in "${required_env_vars[@]}"; do
  if [[ -z "${!var}" ]]; then
    handle_error 1 "必要な環境変数が設定されていません: $var" "環境変数検証"
  fi
done

# ペイロードの作成
payload=$(cat << JSON
{
  "action": "labeled",
  "label": {
    "name": "cto-review"
  },
  "pull_request": {
    "number": ${PR_NUMBER},
    "title": "${PR_TITLE}",
    "head": {
      "sha": "${PR_SHA}"
    }
  },
  "repository": {
    "full_name": "${GITHUB_REPOSITORY}"
  }
}
JSON
)

# Webhookサーバーを呼び出し
echo "[INFO] Webhookサーバーを呼び出し中..."
HTTP_STATUS=$(curl -w "%{http_code}" -s -o response.json \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$payload" \
  "${WEBHOOK_SERVER_URL}/webhook")

if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "[SUCCESS] Webhookサーバーの呼び出しに成功しました"
  cat response.json
  rm -f response.json
  exit 0
else
  echo "[ERROR] Webhookサーバーの呼び出しに失敗しました (HTTP $HTTP_STATUS)"
  if [[ -f response.json ]]; then
    cat response.json
    rm -f response.json
  fi
  exit 1
fi
