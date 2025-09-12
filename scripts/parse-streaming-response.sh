#!/bin/bash

# Difyストリーミングレスポンスパーサー
# 使用方法: ./parse-streaming-response.sh <レスポンスファイル>

RESPONSE_FILE=$1

if [ ! -f "$RESPONSE_FILE" ]; then
    echo "エラー: レスポンスファイルが見つかりません: $RESPONSE_FILE"
    exit 1
fi

# ストリーミングレスポンスからanswerを抽出
FULL_ANSWER=""

# data: で始まる行を処理
while IFS= read -r line; do
    # data: で始まる行のみ処理
    if [[ $line == data:* ]]; then
        # data: プレフィックスを削除
        json_data="${line#data: }"
        
        # 空行をスキップ
        if [ -z "$json_data" ] || [ "$json_data" = " " ]; then
            continue
        fi
        
        # JSONとして解析
        if echo "$json_data" | jq . > /dev/null 2>&1; then
            # agent_messageイベントからanswerを抽出
            event=$(echo "$json_data" | jq -r '.event // ""')
            if [ "$event" = "agent_message" ]; then
                answer=$(echo "$json_data" | jq -r '.answer // ""')
                if [ -n "$answer" ] && [ "$answer" != "null" ]; then
                    FULL_ANSWER="${FULL_ANSWER}${answer}"
                fi
            fi
        fi
    fi
done < "$RESPONSE_FILE"

# 結果を出力
echo "$FULL_ANSWER"
