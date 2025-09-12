#!/bin/bash

# Dify API呼び出しリトライ機能付きスクリプト
# 使用方法: ./retry-dify-api.sh <ペイロードファイル> <レスポンスファイル>

set -e

PAYLOAD_FILE=$1
RESPONSE_FILE=$2
MAX_RETRIES=${MAX_RETRIES:-3}
RETRY_DELAY=${RETRY_DELAY:-5}

if [ ! -f "$PAYLOAD_FILE" ]; then
    echo "エラー: ペイロードファイルが見つかりません: $PAYLOAD_FILE"
    exit 1
fi

# 必要な環境変数のチェック
if [ -z "$DIFY_API_KEY" ] || [ -z "$DIFY_API_URL" ]; then
    echo "エラー: DIFY_API_KEY または DIFY_API_URL が設定されていません"
    exit 1
fi

echo "Dify API呼び出し（リトライ機能付き）"
echo "最大試行回数: $MAX_RETRIES"
echo "リトライ間隔: ${RETRY_DELAY}秒"

for attempt in $(seq 1 $MAX_RETRIES); do
    echo "試行 $attempt/$MAX_RETRIES..."
    
    # 異なるUser-Agentを使用
    case $attempt in
        1) USER_AGENT="Mozilla/5.0 (compatible; DifyCTOReviewBot/1.0)" ;;
        2) USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" ;;
        3) USER_AGENT="curl/7.68.0" ;;
    esac
    
    # 成功パターンに合わせて、まずシンプルなリクエストを試行
    if [ $attempt -eq 1 ]; then
        # 1回目：成功パターンと同じシンプルなリクエスト
        HTTP_STATUS=$(curl -w "%{http_code}" -s -o "$RESPONSE_FILE" \
            -X POST \
            -H "Authorization: Bearer $DIFY_API_KEY" \
            -H "Content-Type: application/json" \
            -d @"$PAYLOAD_FILE" \
            "$DIFY_API_URL" 2>/dev/null || echo "000")
    else
        # 2回目以降：追加ヘッダー付きで試行
        HTTP_STATUS=$(curl -w "%{http_code}" -s -o "$RESPONSE_FILE" \
            -X POST \
            -H "Authorization: Bearer $DIFY_API_KEY" \
            -H "Content-Type: application/json" \
            -H "User-Agent: $USER_AGENT" \
            --connect-timeout 30 \
            --max-time 300 \
            -d @"$PAYLOAD_FILE" \
            "$DIFY_API_URL" 2>/dev/null || echo "000")
    fi
    
    echo "HTTPステータス: $HTTP_STATUS"
    
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "✅ API呼び出し成功（試行 $attempt/$MAX_RETRIES）"
        exit 0
    elif [ "$HTTP_STATUS" = "403" ]; then
        echo "❌ HTTP 403 Forbidden（試行 $attempt/$MAX_RETRIES）"
        
        # レスポンス内容を確認
        if [ -f "$RESPONSE_FILE" ]; then
            echo "レスポンス内容（最初の3行）:"
            head -3 "$RESPONSE_FILE" | sed 's/^/  /'
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo "⏳ ${RETRY_DELAY}秒後にリトライします..."
            sleep $RETRY_DELAY
            # 次回のリトライ間隔を増加
            RETRY_DELAY=$((RETRY_DELAY * 2))
        fi
    else
        echo "❌ 予期しないHTTPステータス: $HTTP_STATUS"
        if [ -f "$RESPONSE_FILE" ]; then
            echo "レスポンス内容:"
            cat "$RESPONSE_FILE"
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo "⏳ ${RETRY_DELAY}秒後にリトライします..."
            sleep $RETRY_DELAY
        fi
    fi
done

echo "❌ すべての試行が失敗しました"
exit 1
