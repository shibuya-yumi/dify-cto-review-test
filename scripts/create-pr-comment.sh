#!/bin/bash

# PRコメント作成スクリプト
# 使用方法: ./create-pr-comment.sh <CTOレビューファイル> <出力ファイル>

set -e

REVIEW_FILE=$1
OUTPUT_FILE=${2:-"/tmp/final_comment.md"}

if [ ! -f "$REVIEW_FILE" ]; then
    echo "エラー: CTOレビューファイルが見つかりません: $REVIEW_FILE"
    exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')

# コメント内容を作成
{
    echo "## 🎯 CTO Review for outline.md"
    echo ""
    cat "$REVIEW_FILE"
    echo ""
    echo "---"
    echo "*このレビューはDify CTO Review Botによって自動生成されました*"
    echo "*生成時刻: $TIMESTAMP*"
} > "$OUTPUT_FILE"

echo "PRコメントを作成しました: $OUTPUT_FILE"
