#!/bin/bash

# エラーハンドリングとログ出力のユーティリティスクリプト
# 他のスクリプトから source ./scripts/error-handler.sh で読み込んで使用

# ログレベルの定義
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_FATAL=4

# 現在のログレベル（環境変数で制御可能）
CURRENT_LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# カラーコードの定義
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# ログ出力関数
log_debug() {
    if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_DEBUG ]; then
        echo -e "${PURPLE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    fi
}

log_info() {
    if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_INFO ]; then
        echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
    fi
}

log_warn() {
    if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_WARN ]; then
        echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    fi
}

log_error() {
    if [ $CURRENT_LOG_LEVEL -le $LOG_LEVEL_ERROR ]; then
        echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
    fi
}

log_fatal() {
    echo -e "${RED}[FATAL]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# エラーハンドリング関数
handle_error() {
    local exit_code=$1
    local error_message=$2
    local context=${3:-"不明な処理"}
    
    log_error "処理中にエラーが発生しました"
    log_error "コンテキスト: $context"
    log_error "エラーメッセージ: $error_message"
    log_error "終了コード: $exit_code"
    
    # GitHub Actionsの場合、エラー注釈を追加
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        echo "::error title=処理エラー::$context で失敗: $error_message"
    fi
    
    exit $exit_code
}

# ファイル存在チェック関数
check_file_exists() {
    local file_path=$1
    local description=${2:-"ファイル"}
    
    log_debug "$description の存在確認: $file_path"
    
    if [ ! -f "$file_path" ]; then
        handle_error 1 "$description が見つかりません: $file_path" "ファイル存在チェック"
    fi
    
    log_debug "$description が見つかりました: $file_path"
}

# 環境変数チェック関数
check_env_var() {
    local var_name=$1
    local description=${2:-$var_name}
    
    log_debug "環境変数確認: $var_name"
    
    if [ -z "${!var_name}" ]; then
        handle_error 1 "$description 環境変数が設定されていません" "環境変数チェック"
    fi
    
    log_debug "$description 環境変数が設定されています"
}

# コマンド実行関数（エラーハンドリング付き）
execute_command() {
    local command=$1
    local description=${2:-"コマンド実行"}
    local allow_failure=${3:-false}
    
    log_info "$description を実行中..."
    log_debug "実行コマンド: $command"
    
    # コマンドを実行し、出力とエラーをキャプチャ
    local output
    local exit_code
    
    output=$(eval "$command" 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_success "$description が完了しました"
        log_debug "出力: $output"
        echo "$output"
        return 0
    else
        log_error "$description が失敗しました (終了コード: $exit_code)"
        log_error "出力: $output"
        
        if [ "$allow_failure" = "false" ]; then
            handle_error $exit_code "$output" "$description"
        else
            log_warn "$description の失敗を許可します"
            return $exit_code
        fi
    fi
}

# HTTP レスポンスチェック関数
check_http_response() {
    local http_status=$1
    local expected_status=${2:-200}
    local context=${3:-"HTTP リクエスト"}
    
    log_debug "HTTPステータス確認: $http_status (期待値: $expected_status)"
    
    if [ "$http_status" != "$expected_status" ]; then
        handle_error 1 "予期しないHTTPステータス: $http_status (期待値: $expected_status)" "$context"
    fi
    
    log_debug "HTTPステータスが正常です: $http_status"
}

# JSON 妥当性チェック関数
check_json_validity() {
    local json_file=$1
    local description=${2:-"JSONファイル"}
    
    log_debug "$description のJSON妥当性確認: $json_file"
    
    if ! jq . "$json_file" > /dev/null 2>&1; then
        handle_error 1 "$description が無効なJSON形式です" "JSON妥当性チェック"
    fi
    
    log_debug "$description のJSON形式が正常です"
}

# プロセス開始ログ
start_process() {
    local process_name=$1
    local process_description=${2:-$process_name}
    
    log_info "=== $process_description 開始 ==="
    
    # GitHub Actionsの場合、グループ開始
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        echo "::group::$process_description"
    fi
}

# プロセス終了ログ
end_process() {
    local process_name=$1
    local process_description=${2:-$process_name}
    
    log_success "=== $process_description 完了 ==="
    
    # GitHub Actionsの場合、グループ終了
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        echo "::endgroup::"
    fi
}

# 進捗表示関数
show_progress() {
    local current=$1
    local total=$2
    local description=${3:-"処理"}
    
    local percentage=$((current * 100 / total))
    log_info "$description 進捗: $current/$total ($percentage%)"
    
    # GitHub Actionsの場合、進捗注釈を追加
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        echo "::notice title=進捗::$description $current/$total ($percentage%)"
    fi
}

# 統計情報表示関数
show_stats() {
    local title=$1
    shift
    local stats=("$@")
    
    log_info "=== $title ==="
    for stat in "${stats[@]}"; do
        log_info "  $stat"
    done
}

# 一時ファイルクリーンアップ関数
cleanup_temp_files() {
    local temp_files=("$@")
    
    if [ ${#temp_files[@]} -eq 0 ]; then
        return 0
    fi
    
    log_info "一時ファイルをクリーンアップ中..."
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_debug "削除: $file"
        fi
    done
    
    log_success "一時ファイルのクリーンアップが完了しました"
}

# トラップ設定（スクリプト終了時の自動クリーンアップ）
setup_cleanup_trap() {
    local temp_files=("$@")
    
    trap "cleanup_temp_files ${temp_files[*]}" EXIT INT TERM
    log_debug "クリーンアップトラップを設定しました"
}

# 初期化関数
init_error_handler() {
    # エラー時即座に終了
    set -e
    
    # 未定義変数使用時にエラー
    set -u
    
    # パイプラインでエラーが発生した場合に終了
    set -o pipefail
    
    log_debug "エラーハンドラーを初期化しました"
}
