#!/bin/bash

# Cloudflare/WAF バイパス用のDify API呼び出しスクリプト
# 使用方法: ./cloudflare-bypass.sh <ペイロードファイル> <レスポンスファイル>

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

echo "Cloudflare/WAF バイパス手法でDify APIを呼び出し中..."

# 複数のバイパス手法を試行
BYPASS_METHODS=(
    "method1_real_browser"
    "method2_mobile_agent"
    "method3_curl_impersonation"
    "method4_different_headers"
)

for method in "${BYPASS_METHODS[@]}"; do
    echo "バイパス手法を試行中: $method"
    
    case $method in
        "method1_real_browser")
            # 実際のブラウザを模倣
            HTTP_STATUS=$(curl -w "%{http_code}" -s -o "$RESPONSE_FILE" \
                -X POST \
                -H "Authorization: Bearer $DIFY_API_KEY" \
                -H "Content-Type: application/json" \
                -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
                -H "Accept: application/json, text/plain, */*" \
                -H "Accept-Language: ja,en-US;q=0.9,en;q=0.8" \
                -H "Accept-Encoding: gzip, deflate, br" \
                -H "DNT: 1" \
                -H "Connection: keep-alive" \
                -H "Upgrade-Insecure-Requests: 1" \
                -H "Sec-Fetch-Dest: empty" \
                -H "Sec-Fetch-Mode: cors" \
                -H "Sec-Fetch-Site: cross-site" \
                -H "Sec-CH-UA: \"Not_A Brand\";v=\"8\", \"Chromium\";v=\"120\", \"Google Chrome\";v=\"120\"" \
                -H "Sec-CH-UA-Mobile: ?0" \
                -H "Sec-CH-UA-Platform: \"macOS\"" \
                --compressed \
                -d @"$PAYLOAD_FILE" \
                "$DIFY_API_URL" 2>/dev/null || echo "000")
            ;;
        "method2_mobile_agent")
            # モバイルブラウザを模倣
            HTTP_STATUS=$(curl -w "%{http_code}" -s -o "$RESPONSE_FILE" \
                -X POST \
                -H "Authorization: Bearer $DIFY_API_KEY" \
                -H "Content-Type: application/json" \
                -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" \
                -H "Accept: application/json" \
                -H "Accept-Language: ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7" \
                -H "Accept-Encoding: gzip, deflate, br" \
                -d @"$PAYLOAD_FILE" \
                "$DIFY_API_URL" 2>/dev/null || echo "000")
            ;;
        "method3_curl_impersonation")
            # curl impersonation (Chrome模倣)
            HTTP_STATUS=$(curl -w "%{http_code}" -s -o "$RESPONSE_FILE" \
                --http2 \
                --tlsv1.2 \
                --ciphers ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:DHE+CHACHA20:!aNULL:!MD5:!DSS \
                -X POST \
                -H "Authorization: Bearer $DIFY_API_KEY" \
                -H "Content-Type: application/json" \
                -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
                -H "Accept: */*" \
                -H "Cache-Control: no-cache" \
                -H "Pragma: no-cache" \
                -d @"$PAYLOAD_FILE" \
                "$DIFY_API_URL" 2>/dev/null || echo "000")
            ;;
        "method4_different_headers")
            # 異なるヘッダー順序とフィールド
            HTTP_STATUS=$(curl -w "%{http_code}" -s -o "$RESPONSE_FILE" \
                -X POST \
                -H "Accept: application/json, text/javascript, */*; q=0.01" \
                -H "Accept-Language: ja,en;q=0.5" \
                -H "Accept-Encoding: gzip, deflate" \
                -H "Content-Type: application/json; charset=UTF-8" \
                -H "Authorization: Bearer $DIFY_API_KEY" \
                -H "X-Requested-With: XMLHttpRequest" \
                -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/119.0" \
                -H "Origin: https://dify.ai" \
                -H "Referer: https://dify.ai/" \
                --connect-timeout 30 \
                --max-time 120 \
                -d @"$PAYLOAD_FILE" \
                "$DIFY_API_URL" 2>/dev/null || echo "000")
            ;;
    esac
    
    echo "HTTPステータス: $HTTP_STATUS"
    
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "✅ バイパス成功: $method"
        exit 0
    else
        echo "❌ バイパス失敗: $method (HTTP $HTTP_STATUS)"
        
        # レスポンス内容を確認
        if [ -f "$RESPONSE_FILE" ]; then
            echo "レスポンス内容（最初の2行）:"
            head -2 "$RESPONSE_FILE" | sed 's/^/  /'
        fi
    fi
    
    # 次の手法まで少し待機
    sleep 2
done

echo "❌ すべてのバイパス手法が失敗しました"
exit 1
