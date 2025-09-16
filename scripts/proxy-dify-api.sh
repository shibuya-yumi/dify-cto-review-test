#!/bin/bash

# プロキシ経由でのDify API呼び出しスクリプト
# 使用方法: ./proxy-dify-api.sh <ペイロードファイル> <レスポンスファイル>

set -e

PAYLOAD_FILE=$1
RESPONSE_FILE=$2

if [ ! -f "$PAYLOAD_FILE" ]; then
    echo "エラー: ペイロードファイルが見つかりません: $PAYLOAD_FILE"
    exit 1
fi

# 必要な環境変数のチェック
if [ -z "$DIFY_API_KEY" ] || [ -z "$DIFY_API_URL" ]; then
    echo "エラー: DIFY_API_KEY または DIFY_API_URL が設定されていません"
    exit 1
fi

echo "プロキシ経由でDify APIを呼び出し中..."

# 複数のプロキシサービスを試行
PROXY_SERVICES=(
    "https://cors-anywhere.herokuapp.com/"
    "https://api.allorigins.win/raw?url="
    "https://thingproxy.freeboard.io/fetch/"
)

for proxy in "${PROXY_SERVICES[@]}"; do
    echo "プロキシを試行中: $proxy"
    
    # プロキシ経由でのURL構築
    PROXY_URL="${proxy}${DIFY_API_URL}"
    
    HTTP_STATUS=$(curl -w "%{http_code}" -s -o "$RESPONSE_FILE" \
        -X POST \
        -H "Authorization: Bearer $DIFY_API_KEY" \
        -H "Content-Type: application/json" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        -H "Accept: application/json" \
        -H "Origin: https://github.com" \
        -H "Referer: https://github.com/" \
        --connect-timeout 30 \
        --max-time 300 \
        -d @"$PAYLOAD_FILE" \
        "$PROXY_URL" 2>/dev/null || echo "000")
    
    echo "HTTPステータス: $HTTP_STATUS"
    
    if [ "$HTTP_STATUS" = "200" ]; then
        # レスポンス内容を確認して実際に成功かどうかチェック
        if [ -f "$RESPONSE_FILE" ]; then
            RESPONSE_CONTENT=$(head -5 "$RESPONSE_FILE")
            echo "レスポンス内容（最初の5行）:"
            echo "$RESPONSE_CONTENT" | sed 's/^/  /'
            
            # 403エラーページかどうかチェック
            if echo "$RESPONSE_CONTENT" | grep -q "403 Forbidden\|403</title>\|Forbidden"; then
                echo "❌ プロキシ経由でも実際は403エラー: $proxy"
            elif echo "$RESPONSE_CONTENT" | grep -q "data:\|event:\|{"; then
                echo "✅ プロキシ経由でのAPI呼び出し成功: $proxy"
                exit 0
            else
                echo "⚠️  プロキシ経由での応答が不明: $proxy"
                echo "レスポンス全体（最初の10行）:"
                head -10 "$RESPONSE_FILE" | sed 's/^/    /'
            fi
        else
            echo "✅ プロキシ経由でのAPI呼び出し成功: $proxy"
            exit 0
        fi
    else
        echo "❌ プロキシ経由での呼び出し失敗: $proxy (HTTP $HTTP_STATUS)"
        
        # レスポンス内容を確認
        if [ -f "$RESPONSE_FILE" ]; then
            echo "レスポンス内容（最初の2行）:"
            head -2 "$RESPONSE_FILE" | sed 's/^/  /'
        fi
    fi
done

echo "❌ すべてのプロキシでの試行が失敗しました"
exit 1
