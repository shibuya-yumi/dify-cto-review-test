#!/bin/bash

# outline.mdファイルをCTOの視点でレビューするスクリプト
# 使用方法: ./review-outline.sh [outline.mdファイルパス]

# エラーハンドラーを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handler.sh"

# エラーハンドラーを初期化
init_error_handler

# デフォルトのファイルパス
OUTLINE_FILE=${1:-"outline.md"}

start_process "outline_review" "outline.md CTOレビュー"

# 必要な環境変数のチェック
check_env_var "DIFY_API_KEY" "Dify APIキー"
check_env_var "DIFY_API_URL" "Dify API URL"

# ファイル存在チェック
check_file_exists "$OUTLINE_FILE" "outline.mdファイル"

log_info "対象ファイル: $OUTLINE_FILE"
log_info "API URL: $DIFY_API_URL"
log_info "APIキー: ${DIFY_API_KEY:0:10}..." # セキュリティのため最初の10文字のみ表示

# outline.mdの内容を読み込み
log_info "outline.mdの内容を読み込み中..."
OUTLINE_CONTENT=$(cat "$OUTLINE_FILE")
CONTENT_SIZE=$(echo "$OUTLINE_CONTENT" | wc -c)
CONTENT_LINES=$(echo "$OUTLINE_CONTENT" | wc -l)

show_stats "ファイル統計" \
    "行数: $CONTENT_LINES" \
    "サイズ: $CONTENT_SIZE バイト"

# outline.mdが空の場合の処理
if [ -z "$OUTLINE_CONTENT" ] || [ "$CONTENT_SIZE" -lt 10 ]; then
    handle_error 1 "outline.mdファイルが空または非常に小さいです" "ファイル内容チェック"
fi

# JSONエスケープ関数
json_escape() {
    # 改行文字を適切にエスケープ
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/	/\\t/g' | tr '\n' ' ' | sed 's/ /\\n/g'
}

# エスケープされたコンテンツを準備
ESCAPED_CONTENT=$(json_escape "$OUTLINE_CONTENT")

# CTOレビュー用のプロンプトを構築
PROMPT="あなたは経験豊富なCTO（最高技術責任者）です。以下のプロジェクト概要書（outline.md）を技術的・戦略的な観点から詳細にレビューし、建設的で具体的なフィードバックを日本語で提供してください。

## レビュー対象のoutline.md:
\`\`\`markdown
${ESCAPED_CONTENT}
\`\`\`

## CTOとしてのレビュー観点:

### 1. 技術戦略・アーキテクチャ
- 技術選択の妥当性と将来性
- アーキテクチャの拡張性とメンテナンス性
- 技術的リスクの評価

### 2. プロジェクト管理・実装計画
- 実装フェーズの現実性と優先順位
- リソース配分の妥当性
- スケジュールの実現可能性

### 3. ビジネス価値・ROI
- 期待される効果の妥当性
- コスト対効果の分析
- ビジネスインパクトの評価

### 4. リスク管理・品質保証
- 潜在的なリスクの特定
- 品質保証戦略
- 運用・保守の考慮

### 5. 組織・チーム体制
- 必要なスキルセットと人材
- チーム体制の提案
- 知識共有・ドキュメント化

## 求めるフィードバック:
- 具体的な改善提案
- 追加すべき検討事項
- 技術的な代替案
- 実装上の注意点
- 成功のための重要ポイント

CTOとしての豊富な経験を活かし、このプロジェクトを成功に導くための戦略的で実践的なアドバイスをお願いします。"

# APIリクエストのJSONペイロードを作成（成功パターンに合わせて簡素化）
PAYLOAD=$(cat << EOF
{
  "inputs": {},
  "query": "$(json_escape "$PROMPT")",
  "response_mode": "streaming",
  "user": "github-actions-cto-bot"
}
EOF
)

# 一時ファイルにペイロードを保存
PAYLOAD_FILE="outline_review_payload.json"
RESPONSE_FILE="outline_review_response.json"

# 一時ファイルのクリーンアップ設定
setup_cleanup_trap "$PAYLOAD_FILE" "$RESPONSE_FILE"

echo "$PAYLOAD" > "$PAYLOAD_FILE"
log_info "ペイロードサイズ: $(echo "$PAYLOAD" | wc -c) バイト"

# Dify APIを呼び出し（リトライ機能付き）
log_info "Dify APIを呼び出し中..."

# リトライ機能付きスクリプトを使用
if [ -f "./scripts/retry-dify-api.sh" ]; then
    chmod +x ./scripts/retry-dify-api.sh
    
    log_info "リトライ機能付きでDify APIを呼び出します"
    if ./scripts/retry-dify-api.sh "$PAYLOAD_FILE" "$RESPONSE_FILE"; then
        log_success "Dify API呼び出し成功"
        HTTP_STATUS="200"
    else
        log_warn "リトライ機能付きDify API呼び出しが失敗しました。プロキシ経由を試行します"
        
        # プロキシ経由での試行
        if [ -f "./scripts/proxy-dify-api.sh" ]; then
            chmod +x ./scripts/proxy-dify-api.sh
            log_info "プロキシ経由でDify APIを呼び出します"
            
            if ./scripts/proxy-dify-api.sh "$PAYLOAD_FILE" "$RESPONSE_FILE"; then
                log_success "プロキシ経由でのDify API呼び出し成功"
                HTTP_STATUS="200"
            else
                log_error "プロキシ経由でのDify API呼び出しも失敗しました"
                HTTP_STATUS="403"
            fi
        else
            log_error "プロキシスクリプトが見つかりません"
            HTTP_STATUS="403"
        fi
    fi
else
    log_warn "リトライスクリプトが見つかりません。通常の呼び出しを実行します"
    
    # 成功パターンに合わせてシンプルなcurlコマンドを使用
    HTTP_STATUS=$(curl -w "%{http_code}" -s -o "$RESPONSE_FILE" \
      -X POST \
      -H "Authorization: Bearer $DIFY_API_KEY" \
      -H "Content-Type: application/json" \
      -d @"$PAYLOAD_FILE" \
      "$DIFY_API_URL")
    
    log_info "HTTPステータス: $HTTP_STATUS"
fi

# レスポンスの確認
if [ "$HTTP_STATUS" != "200" ]; then
    handle_error 1 "予期しないHTTPステータス: $HTTP_STATUS (期待値: 200)" "Dify API呼び出し"
fi

log_success "API呼び出し成功"

# レスポンスからCTOレビューコメントを抽出
log_info "レスポンスを解析中..."

# ストリーミングレスポンスの場合、JSON妥当性チェックはスキップ
log_debug "ストリーミングレスポンス形式のため、JSON妥当性チェックをスキップします"

# ストリーミングレスポンスからCTOレビューを抽出
log_info "ストリーミングレスポンスを解析中..."

# ストリーミングレスポンスパーサーを使用
if [ -f "./scripts/parse-streaming-response.sh" ]; then
    chmod +x ./scripts/parse-streaming-response.sh
    CTO_REVIEW=$(./scripts/parse-streaming-response.sh "$RESPONSE_FILE")
else
    log_warn "ストリーミングレスポンスパーサーが見つかりません。手動で解析します。"
    
    # 手動でストリーミングレスポンスを解析
    CTO_REVIEW=""
    while IFS= read -r line; do
        if [[ $line == data:* ]]; then
            json_data="${line#data: }"
            if [ -n "$json_data" ] && [ "$json_data" != " " ]; then
                if echo "$json_data" | jq . > /dev/null 2>&1; then
                    event=$(echo "$json_data" | jq -r '.event // ""')
                    if [ "$event" = "agent_message" ]; then
                        answer=$(echo "$json_data" | jq -r '.answer // ""')
                        if [ -n "$answer" ] && [ "$answer" != "null" ]; then
                            CTO_REVIEW="${CTO_REVIEW}${answer}"
                        fi
                    fi
                fi
            fi
        fi
    done < "$RESPONSE_FILE"
fi

if [ -z "$CTO_REVIEW" ] || [ "$CTO_REVIEW" = "null" ]; then
    log_warn "Difyからの有効なレスポンスが取得できませんでした"
    log_info "ストリーミングレスポンスの最初の10行:"
    head -10 "$RESPONSE_FILE" | sed 's/^/  /'
    
    CTO_REVIEW="CTOレビューの取得に失敗しました。ストリーミングレスポンスを確認してください。"
fi

# CTOレビューコメントをファイルに保存
OUTPUT_FILE="cto_outline_review.txt"
echo "$CTO_REVIEW" > "$OUTPUT_FILE"

log_success "CTOレビューコメントを $OUTPUT_FILE に保存しました"

# レビューコメントの統計
REVIEW_LINES=$(echo "$CTO_REVIEW" | wc -l)
REVIEW_SIZE=$(echo "$CTO_REVIEW" | wc -c)

show_stats "CTOレビューコメント統計" \
    "行数: $REVIEW_LINES" \
    "サイズ: $REVIEW_SIZE バイト"

log_info "=== CTOレビューコメント（プレビュー） ==="
echo "$CTO_REVIEW" | head -10
if [ "$REVIEW_LINES" -gt 10 ]; then
    log_info "... (残り $((REVIEW_LINES - 10)) 行)"
fi

# GitHub Actions用の環境変数設定
if [ -n "${GITHUB_ENV:-}" ]; then
    # 改行文字を適切にエスケープしてGitHub環境変数に設定
    echo "CTO_OUTLINE_REVIEW<<EOF" >> $GITHUB_ENV
    echo "$CTO_REVIEW" >> $GITHUB_ENV
    echo "EOF" >> $GITHUB_ENV
    log_success "GitHub Actions環境変数を設定しました"
fi

end_process "outline_review" "outline.md CTOレビュー"
