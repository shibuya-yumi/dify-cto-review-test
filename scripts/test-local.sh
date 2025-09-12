#!/bin/bash

# ローカル環境でのテスト実行スクリプト
# 使用方法: ./test-local.sh

# エラーハンドラーを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handler.sh"

# エラーハンドラーを初期化
init_error_handler

start_process "local_test" "ローカルテスト実行"

# テスト設定
TEST_OUTLINE_FILE="outline.md"
ENV_FILE=".env"

log_info "=== Dify CTO Review Bot ローカルテスト ==="

# 1. 環境設定の確認
log_info "--- ステップ1: 環境設定の確認 ---"

# .envファイルの存在確認
if [ -f "$ENV_FILE" ]; then
    log_info ".envファイルが見つかりました。環境変数を読み込みます..."
    set -a  # 自動エクスポートを有効化
    source "$ENV_FILE"
    set +a  # 自動エクスポートを無効化
    log_success ".envファイルから環境変数を読み込みました"
else
    log_warn ".envファイルが見つかりません"
    log_info "env.exampleを参考に.envファイルを作成してください"
    
    # 環境変数が直接設定されているかチェック
    if [ -z "$DIFY_API_KEY" ] || [ -z "$DIFY_API_URL" ]; then
        log_error "必要な環境変数が設定されていません"
        log_info "以下の環境変数を設定してください:"
        log_info "  - DIFY_API_KEY"
        log_info "  - DIFY_API_URL"
        log_info ""
        log_info "設定方法:"
        log_info "1. env.exampleをコピーして.envファイルを作成"
        log_info "2. 実際の値を設定"
        log_info "3. 再度このスクリプトを実行"
        exit 1
    fi
fi

# 2. 環境変数の検証
log_info "--- ステップ2: 環境変数の検証 ---"

if [ -f "./scripts/validate-env.sh" ]; then
    log_info "環境変数検証スクリプトを実行中..."
    chmod +x ./scripts/validate-env.sh
    
    # 検証スクリプトを実行（失敗を許可）
    if ./scripts/validate-env.sh; then
        log_success "環境変数の検証が完了しました"
    else
        log_warn "環境変数の検証で問題が発見されました"
        log_info "上記の警告を確認して、必要に応じて修正してください"
    fi
else
    log_warn "環境変数検証スクリプトが見つかりません"
fi

# 3. outline.mdファイルの確認
log_info "--- ステップ3: outline.mdファイルの確認 ---"

check_file_exists "$TEST_OUTLINE_FILE" "outline.mdファイル"

# ファイル内容の確認
CONTENT_LINES=$(wc -l < "$TEST_OUTLINE_FILE")
CONTENT_SIZE=$(wc -c < "$TEST_OUTLINE_FILE")

show_stats "outline.mdファイル情報" \
    "行数: $CONTENT_LINES" \
    "サイズ: $CONTENT_SIZE バイト"

# ファイル内容のプレビュー
log_info "outline.md内容プレビュー（最初の10行）:"
head -10 "$TEST_OUTLINE_FILE" | sed 's/^/  /'

# 4. 依存関係の確認
log_info "--- ステップ4: 依存関係の確認 ---"

# 必要なコマンドの確認
REQUIRED_COMMANDS=("curl" "jq" "git")

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if command -v "$cmd" > /dev/null 2>&1; then
        VERSION=$(command -v "$cmd" && $cmd --version 2>/dev/null | head -1 || echo "バージョン不明")
        log_success "$cmd: 利用可能 ($VERSION)"
    else
        log_error "$cmd: 見つかりません"
        handle_error 1 "必要なコマンド '$cmd' がインストールされていません" "依存関係チェック"
    fi
done

# 5. Dify API接続テスト
log_info "--- ステップ5: Dify API接続テスト ---"

if [ -n "$DIFY_API_KEY" ] && [ -n "$DIFY_API_URL" ]; then
    log_info "Dify APIへの接続をテスト中..."
    
    # テスト用のシンプルなリクエスト
    TEST_PAYLOAD='{"inputs": {}, "query": "接続テスト", "response_mode": "blocking", "conversation_id": "", "user": "test-user"}'
    
    HTTP_STATUS=$(curl -w "%{http_code}" -s -o /tmp/dify_test_response.json \
        -X POST \
        -H "Authorization: Bearer $DIFY_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$TEST_PAYLOAD" \
        "$DIFY_API_URL" 2>/dev/null || echo "000")
    
    if [ "$HTTP_STATUS" = "200" ]; then
        log_success "Dify API接続成功 (HTTP $HTTP_STATUS)"
        
        # レスポンスの確認
        if jq . /tmp/dify_test_response.json > /dev/null 2>&1; then
            log_success "有効なJSONレスポンスを受信"
            
            # answerフィールドの存在確認
            if jq -e '.answer' /tmp/dify_test_response.json > /dev/null 2>&1; then
                ANSWER=$(jq -r '.answer' /tmp/dify_test_response.json)
                log_success "期待されるレスポンス形式を確認"
                log_info "テストレスポンス: ${ANSWER:0:100}..."
            else
                log_warn "レスポンスに'answer'フィールドがありません"
                log_info "利用可能なフィールド: $(jq -r 'keys | join(", ")' /tmp/dify_test_response.json)"
            fi
        else
            log_error "無効なJSONレスポンス"
        fi
    else
        log_error "Dify API接続失敗 (HTTP $HTTP_STATUS)"
        log_info "レスポンス内容:"
        cat /tmp/dify_test_response.json 2>/dev/null || echo "レスポンスファイルが見つかりません"
    fi
    
    # 一時ファイルのクリーンアップ
    rm -f /tmp/dify_test_response.json
else
    log_warn "Dify API設定が不完全のため、接続テストをスキップ"
fi

# 6. outline.mdレビューのテスト実行
log_info "--- ステップ6: outline.mdレビューのテスト実行 ---"

if [ -f "./scripts/review-outline.sh" ]; then
    log_info "outline.mdレビュースクリプトをテスト実行中..."
    
    # デバッグモードで実行
    export LOG_LEVEL=0  # DEBUGレベル
    
    chmod +x ./scripts/review-outline.sh
    
    if ./scripts/review-outline.sh "$TEST_OUTLINE_FILE"; then
        log_success "outline.mdレビューのテスト実行が完了しました"
        
        # 生成されたファイルの確認
        REVIEW_FILE="cto_outline_review.txt"
        if [ -f "$REVIEW_FILE" ]; then
            REVIEW_LINES=$(wc -l < "$REVIEW_FILE")
            REVIEW_SIZE=$(wc -c < "$REVIEW_FILE")
            
            show_stats "生成されたCTOレビュー" \
                "行数: $REVIEW_LINES" \
                "サイズ: $REVIEW_SIZE バイト"
            
            log_info "CTOレビュー内容プレビュー（最初の5行）:"
            head -5 "$REVIEW_FILE" | sed 's/^/  /'
            
            if [ "$REVIEW_LINES" -gt 5 ]; then
                log_info "  ... (残り $((REVIEW_LINES - 5)) 行)"
            fi
        else
            log_warn "CTOレビューファイルが生成されませんでした"
        fi
    else
        log_error "outline.mdレビューのテスト実行に失敗しました"
    fi
else
    log_error "outline.mdレビュースクリプトが見つかりません"
fi

# 7. テスト結果のサマリー
log_info "--- ステップ7: テスト結果サマリー ---"

# 生成されたファイルの一覧
log_info "生成されたファイル:"
for file in "cto_outline_review.txt" "outline_review_response.json"; do
    if [ -f "$file" ]; then
        SIZE=$(wc -c < "$file")
        log_success "  ✅ $file ($SIZE バイト)"
    else
        log_warn "  ❌ $file (見つかりません)"
    fi
done

# 8. GitHub Actions シミュレーション
log_info "--- ステップ8: GitHub Actions シミュレーション ---"

log_info "GitHub Actionsでの実行をシミュレート中..."

# 環境変数の設定（GitHub Actions風）
export GITHUB_ACTIONS="true"
export GITHUB_REPOSITORY="test-user/test-repo"
export PR_NUMBER="123"

log_info "シミュレーション環境変数:"
log_info "  GITHUB_ACTIONS: $GITHUB_ACTIONS"
log_info "  GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
log_info "  PR_NUMBER: $PR_NUMBER"

# GitHub Actions注釈のテスト
echo "::notice title=テスト完了::ローカルテストが正常に完了しました"

# 9. 次のステップの案内
log_info "--- ステップ9: 次のステップ ---"

log_success "=== ローカルテスト完了 ==="
log_info ""
log_info "次のステップ:"
log_info "1. GitHubリポジトリにコードをプッシュ"
log_info "2. GitHub Secretsで環境変数を設定:"
log_info "   - DIFY_API_KEY"
log_info "   - DIFY_API_URL"
log_info "3. PRを作成してoutline.mdファイルを含める"
log_info "4. PRに'cto-review'ラベルを追加"
log_info "5. GitHub Actionsの実行を確認"
log_info ""
log_info "トラブルシューティング:"
log_info "- GitHub Actionsのログを確認"
log_info "- 環境変数の設定を再確認"
log_info "- Dify APIの動作状況を確認"

end_process "local_test" "ローカルテスト実行"

log_success "🎉 すべてのテストが完了しました！"
