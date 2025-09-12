#!/bin/bash

# Dify API接続テスト専用スクリプト
# 使用方法: ./test-dify-connection.sh

# エラーハンドラーを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handler.sh"

# エラーハンドラーを初期化
init_error_handler

start_process "dify_connection_test" "Dify API接続テスト"

# 環境変数を読み込み
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
    log_success ".envファイルから環境変数を読み込みました"
fi

# 必要な環境変数のチェック
check_env_var "DIFY_API_KEY" "Dify APIキー"
check_env_var "DIFY_API_URL" "Dify API URL"

log_info "API URL: $DIFY_API_URL"
log_info "APIキー: ${DIFY_API_KEY:0:10}..."

# 複数のレスポンスモードをテスト
RESPONSE_MODES=("blocking" "streaming")

for mode in "${RESPONSE_MODES[@]}"; do
    log_info "--- $mode モードのテスト ---"
    
    # テスト用のシンプルなリクエスト
    TEST_PAYLOAD=$(cat << EOF
{
  "inputs": {},
  "query": "こんにちは、接続テストです。",
  "response_mode": "$mode",
  "conversation_id": "",
  "user": "connection-test"
}
EOF
)
    
    # 一時ファイル
    PAYLOAD_FILE="test_${mode}_payload.json"
    RESPONSE_FILE="test_${mode}_response.json"
    
    echo "$TEST_PAYLOAD" > "$PAYLOAD_FILE"
    
    log_info "$mode モードでDify APIを呼び出し中..."
    
    HTTP_STATUS=$(curl -w "%{http_code}" -s -o "$RESPONSE_FILE" \
        -X POST \
        -H "Authorization: Bearer $DIFY_API_KEY" \
        -H "Content-Type: application/json" \
        -d @"$PAYLOAD_FILE" \
        "$DIFY_API_URL" 2>/dev/null || echo "000")
    
    log_info "HTTPステータス: $HTTP_STATUS"
    
    if [ "$HTTP_STATUS" = "200" ]; then
        log_success "$mode モード: 接続成功"
        
        # レスポンスの確認
        if jq . "$RESPONSE_FILE" > /dev/null 2>&1; then
            log_success "有効なJSONレスポンスを受信"
            
            # レスポンス構造の表示
            log_info "レスポンス構造:"
            jq keys "$RESPONSE_FILE" | sed 's/^/  /'
            
            # answerフィールドの確認
            if jq -e '.answer' "$RESPONSE_FILE" > /dev/null 2>&1; then
                ANSWER=$(jq -r '.answer' "$RESPONSE_FILE")
                log_success "answerフィールドが見つかりました"
                log_info "レスポンス内容: ${ANSWER:0:100}..."
                
                # このモードが使用可能
                echo "WORKING_MODE=$mode" > "dify_config.txt"
                log_success "$mode モードが使用可能です"
                break
            else
                log_warn "answerフィールドが見つかりません"
            fi
        else
            log_error "無効なJSONレスポンス"
            cat "$RESPONSE_FILE"
        fi
    else
        log_error "$mode モード: 接続失敗 (HTTP $HTTP_STATUS)"
        log_info "エラー内容:"
        cat "$RESPONSE_FILE" | sed 's/^/  /'
    fi
    
    # 一時ファイルのクリーンアップ
    rm -f "$PAYLOAD_FILE" "$RESPONSE_FILE"
    
    echo ""
done

# 結果の確認
if [ -f "dify_config.txt" ]; then
    WORKING_MODE=$(grep "WORKING_MODE=" dify_config.txt | cut -d'=' -f2)
    log_success "使用可能なモード: $WORKING_MODE"
    log_info "このモードでreview-outline.shを更新してください"
else
    log_error "利用可能なレスポンスモードが見つかりませんでした"
    log_info "Difyの設定を確認してください:"
    log_info "1. APIキーが正しいか確認"
    log_info "2. アプリケーションの種類を確認"
    log_info "3. APIエンドポイントURLを確認"
fi

end_process "dify_connection_test" "Dify API接続テスト"
