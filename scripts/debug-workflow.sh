#!/bin/bash

# GitHub Actionsワークフローのデバッグ支援スクリプト
# 使用方法: ./debug-workflow.sh [PR番号]

# エラーハンドラーを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handler.sh"

# エラーハンドラーを初期化
init_error_handler

PR_NUMBER=${1:-"123"}

start_process "debug_workflow" "GitHub Actionsワークフローデバッグ"

log_info "=== GitHub Actions ワークフローデバッグ ==="
log_info "PR番号: $PR_NUMBER"

# 1. 環境変数のシミュレーション
log_info "--- ステップ1: GitHub Actions環境変数のシミュレーション ---"

# GitHub Actions環境変数を設定
export GITHUB_ACTIONS="true"
export GITHUB_WORKSPACE="$(pwd)"
export GITHUB_REPOSITORY="test-user/dify-cto-review-test"
export GITHUB_REPOSITORY_OWNER="test-user"
export GITHUB_EVENT_NAME="pull_request"
export GITHUB_EVENT_PATH="/tmp/github_event.json"

# PR情報を環境変数として設定
export PR_NUMBER="$PR_NUMBER"
export PR_TITLE="Test PR for CTO Review"
export PR_BRANCH="feature/test-outline"
export BASE_BRANCH="main"

log_info "GitHub Actions環境変数:"
show_stats "環境変数" \
    "GITHUB_ACTIONS: $GITHUB_ACTIONS" \
    "GITHUB_WORKSPACE: $GITHUB_WORKSPACE" \
    "GITHUB_REPOSITORY: $GITHUB_REPOSITORY" \
    "PR_NUMBER: $PR_NUMBER" \
    "PR_TITLE: $PR_TITLE"

# 2. GitHub Eventのシミュレーション
log_info "--- ステップ2: GitHub Eventのシミュレーション ---"

# GitHub Event JSONを作成
cat > "$GITHUB_EVENT_PATH" << EOF
{
  "action": "labeled",
  "number": $PR_NUMBER,
  "pull_request": {
    "number": $PR_NUMBER,
    "title": "$PR_TITLE",
    "head": {
      "ref": "$PR_BRANCH"
    },
    "base": {
      "ref": "$BASE_BRANCH"
    }
  },
  "label": {
    "name": "cto-review"
  }
}
EOF

log_success "GitHub Event JSONを作成しました: $GITHUB_EVENT_PATH"

# 3. ワークフローステップのシミュレーション
log_info "--- ステップ3: ワークフローステップのシミュレーション ---"

# ステップ1: 依存関係のインストール
log_info "🔧 依存関係のインストールをシミュレート中..."
if command -v jq > /dev/null 2>&1; then
    log_success "jq: 既にインストール済み"
else
    log_warn "jq: インストールが必要です"
    log_info "インストールコマンド: sudo apt-get install -y jq (Ubuntu/Debian)"
    log_info "インストールコマンド: brew install jq (macOS)"
fi

# ステップ2: 環境変数の検証
log_info "🔍 環境変数の検証をシミュレート中..."
if [ -f "./scripts/validate-env.sh" ]; then
    chmod +x ./scripts/validate-env.sh
    if ./scripts/validate-env.sh; then
        log_success "環境変数検証: 成功"
    else
        log_warn "環境変数検証: 警告あり"
    fi
else
    log_error "環境変数検証スクリプトが見つかりません"
fi

# ステップ3: PR情報の設定
log_info "📋 PR情報の設定をシミュレート中..."
log_info "PR番号: $PR_NUMBER"
log_info "PRタイトル: $PR_TITLE"
log_info "追加されたラベル: cto-review"

# ステップ4: outline.mdレビュー
log_info "📝 outline.mdレビューをシミュレート中..."

if [ ! -f "outline.md" ]; then
    log_error "outline.mdファイルが見つかりません"
    log_info "PRにoutline.mdファイルが含まれているか確認してください"
else
    log_success "outline.mdファイルが見つかりました"
    
    if [ -f "./scripts/review-outline.sh" ]; then
        chmod +x ./scripts/review-outline.sh
        
        # デバッグモードで実行
        export LOG_LEVEL=0  # DEBUGレベル
        
        log_info "outline.mdレビュースクリプトを実行中..."
        if ./scripts/review-outline.sh outline.md; then
            log_success "outline.mdレビュー: 成功"
        else
            log_error "outline.mdレビュー: 失敗"
        fi
    else
        log_error "outline.mdレビュースクリプトが見つかりません"
    fi
fi

# ステップ5: PRコメント投稿のシミュレーション
log_info "💬 PRコメント投稿をシミュレート中..."

REVIEW_FILE="cto_outline_review.txt"
if [ -f "$REVIEW_FILE" ]; then
    log_success "CTOレビューファイルが見つかりました: $REVIEW_FILE"
    
    CTO_REVIEW=$(cat "$REVIEW_FILE")
    
    # コメント内容を準備（Markdown形式）
    COMMENT_BODY="## 🎯 CTO Review for outline.md

$CTO_REVIEW

---
*このレビューはDify CTO Review Botによって自動生成されました*
*生成時刻: $(date '+%Y-%m-%d %H:%M:%S UTC')*"
    
    # コメント内容をファイルに保存（デバッグ用）
    echo "$COMMENT_BODY" > "debug_comment_body.md"
    log_success "コメント内容をdebug_comment_body.mdに保存しました"
    
    # コメント統計
    COMMENT_LINES=$(echo "$COMMENT_BODY" | wc -l)
    COMMENT_SIZE=$(echo "$COMMENT_BODY" | wc -c)
    
    show_stats "コメント統計" \
        "行数: $COMMENT_LINES" \
        "サイズ: $COMMENT_SIZE バイト"
    
    log_info "コメントプレビュー（最初の10行）:"
    echo "$COMMENT_BODY" | head -10 | sed 's/^/  /'
    
    # GitHub API呼び出しのシミュレーション（実際には呼び出さない）
    log_info "GitHub API呼び出しをシミュレート中..."
    log_info "URL: https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments"
    log_info "Method: POST"
    log_info "Headers: Authorization: token [GITHUB_TOKEN]"
    log_success "GitHub API呼び出し: シミュレーション完了"
    
else
    log_error "CTOレビューファイルが見つかりません: $REVIEW_FILE"
fi

# 4. ログファイルの生成
log_info "--- ステップ4: ログファイルの生成 ---"

LOG_FILE="debug_workflow_$(date '+%Y%m%d_%H%M%S').log"
{
    echo "=== GitHub Actions ワークフローデバッグログ ==="
    echo "実行日時: $(date)"
    echo "PR番号: $PR_NUMBER"
    echo "リポジトリ: $GITHUB_REPOSITORY"
    echo ""
    echo "=== 環境変数 ==="
    env | grep -E "(GITHUB_|PR_|DIFY_)" | sort
    echo ""
    echo "=== ファイル一覧 ==="
    find . -name "*.sh" -o -name "*.md" -o -name "*.txt" -o -name "*.json" | sort
    echo ""
    echo "=== 生成されたファイル ==="
    for file in "cto_outline_review.txt" "debug_comment_body.md" "outline_review_response.json"; do
        if [ -f "$file" ]; then
            echo "✅ $file ($(wc -c < "$file") バイト)"
        else
            echo "❌ $file (見つかりません)"
        fi
    done
} > "$LOG_FILE"

log_success "デバッグログを生成しました: $LOG_FILE"

# 5. トラブルシューティングガイド
log_info "--- ステップ5: トラブルシューティングガイド ---"

log_info "🔧 よくある問題と解決方法:"
log_info ""
log_info "1. 環境変数が設定されていない"
log_info "   → GitHub Secretsで DIFY_API_KEY, DIFY_API_URL を設定"
log_info ""
log_info "2. outline.mdファイルが見つからない"
log_info "   → PRにoutline.mdファイルが含まれているか確認"
log_info ""
log_info "3. Dify API呼び出しが失敗する"
log_info "   → APIキーとエンドポイントURLを確認"
log_info "   → Difyサービスの動作状況を確認"
log_info ""
log_info "4. GitHub API呼び出しが失敗する"
log_info "   → GITHUB_TOKENの権限を確認"
log_info "   → リポジトリの権限設定を確認"
log_info ""
log_info "5. ワークフローがトリガーされない"
log_info "   → PRに'cto-review'ラベルが追加されているか確認"
log_info "   → ワークフローファイルの構文を確認"

# 6. 次のステップ
log_info "--- ステップ6: 次のステップ ---"

log_info "📋 実際のGitHub Actionsでテストする手順:"
log_info "1. このリポジトリをGitHubにプッシュ"
log_info "2. GitHub Secretsを設定:"
log_info "   - Settings → Secrets and variables → Actions"
log_info "   - DIFY_API_KEY と DIFY_API_URL を追加"
log_info "3. テスト用PRを作成:"
log_info "   - outline.mdファイルを含むブランチを作成"
log_info "   - PRを作成"
log_info "4. 'cto-review'ラベルを追加"
log_info "5. Actions タブでワークフローの実行を確認"

# クリーンアップ
cleanup_temp_files "$GITHUB_EVENT_PATH"

end_process "debug_workflow" "GitHub Actionsワークフローデバッグ"

log_success "🎉 ワークフローデバッグが完了しました！"
log_info "生成されたファイル:"
log_info "  - $LOG_FILE (デバッグログ)"
log_info "  - debug_comment_body.md (コメント内容)"
