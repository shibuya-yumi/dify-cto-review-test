#!/bin/bash

# 外部プロキシサービス経由でのDify API呼び出し
# 使用方法: ./external-proxy.sh <ペイロードファイル> <レスポンスファイル>

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

echo "外部プロキシサービス経由でDify APIを呼び出し中..."

# 複数の外部プロキシサービスを試行
PROXY_SERVICES=(
    "https://api.allorigins.win/raw?url="
    "https://cors-anywhere.herokuapp.com/"
    "https://thingproxy.freeboard.io/fetch/"
    "https://yacdn.org/proxy/"
)

# ペイロードをBase64エンコード（一部のプロキシで必要）
PAYLOAD_BASE64=$(base64 -w 0 "$PAYLOAD_FILE" 2>/dev/null || base64 "$PAYLOAD_FILE")

for proxy in "${PROXY_SERVICES[@]}"; do
    echo "プロキシサービスを試行中: $proxy"
    
    # プロキシ経由でのURL構築
    ENCODED_URL=$(echo "$DIFY_API_URL" | sed 's/:/%3A/g; s/\//%2F/g')
    PROXY_URL="${proxy}${ENCODED_URL}"
    
    # 方法1: 直接プロキシ経由
    HTTP_STATUS=$(curl -w "%{http_code}" -s -o "$RESPONSE_FILE" \
        -X POST \
        -H "Authorization: Bearer $DIFY_API_KEY" \
        -H "Content-Type: application/json" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        -H "X-Requested-With: XMLHttpRequest" \
        --connect-timeout 30 \
        --max-time 120 \
        -d @"$PAYLOAD_FILE" \
        "$PROXY_URL" 2>/dev/null || echo "000")
    
    echo "HTTPステータス: $HTTP_STATUS"
    
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "✅ 外部プロキシ経由でのAPI呼び出し成功: $proxy"
        exit 0
    else
        echo "❌ 外部プロキシ経由での呼び出し失敗: $proxy (HTTP $HTTP_STATUS)"
        
        # レスポンス内容を確認
        if [ -f "$RESPONSE_FILE" ]; then
            echo "レスポンス内容（最初の2行）:"
            head -2 "$RESPONSE_FILE" | sed 's/^/  /'
        fi
    fi
    
    # 方法2: JSONP風のリクエスト（一部のプロキシ用）
    if [[ "$proxy" == *"allorigins"* ]]; then
        echo "AllOrigins用のJSONPリクエストを試行中..."
        
        JSONP_URL="https://api.allorigins.win/get?url=${ENCODED_URL}&callback=handleResponse"
        
        HTTP_STATUS=$(curl -w "%{http_code}" -s -o "$RESPONSE_FILE" \
            -X GET \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
            "$JSONP_URL" 2>/dev/null || echo "000")
        
        if [ "$HTTP_STATUS" = "200" ]; then
            echo "✅ JSONP経由でのAPI呼び出し成功"
            exit 0
        fi
    fi
    
    # 次のプロキシまで少し待機
    sleep 3
done

echo "❌ すべての外部プロキシサービスでの試行が失敗しました"
exit 1
