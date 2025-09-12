#!/bin/bash

# 環境変数の検証スクリプト
# GitHub Actionsワークフローで使用する環境変数が正しく設定されているかチェック

# エラーハンドラーを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handler.sh"

# エラーハンドラーを初期化
init_error_handler

echo "=== 環境変数検証開始 ==="

# 必須環境変数のリスト
REQUIRED_VARS=(
    "DIFY_API_KEY"
    "DIFY_API_URL"
    "GITHUB_TOKEN"
)

# オプション環境変数のリスト
OPTIONAL_VARS=(
    "GITHUB_REPOSITORY"
    "GITHUB_REPOSITORY_OWNER"
    "MAX_DIFF_LINES"
    "DEBUG_MODE"
)

# エラーカウンタ
ERROR_COUNT=0

echo "--- 必須環境変数のチェック ---"

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ エラー: $var が設定されていません"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    else
        # セキュリティのため、値の一部のみ表示
        case $var in
            *KEY*|*TOKEN*)
                echo "✅ $var: ${!var:0:10}..." 
                ;;
            *)
                echo "✅ $var: ${!var}"
                ;;
        esac
    fi
done

echo ""
echo "--- オプション環境変数のチェック ---"

for var in "${OPTIONAL_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "⚠️  警告: $var が設定されていません（オプション）"
    else
        echo "✅ $var: ${!var}"
    fi
done

echo ""
echo "--- Dify API接続テスト ---"

if [ -n "$DIFY_API_KEY" ] && [ -n "$DIFY_API_URL" ]; then
    echo "Dify APIへの接続をテスト中..."
    
    # テスト用のシンプルなリクエスト
    TEST_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/dify_test_response.json \
        -X POST \
        -H "Authorization: Bearer $DIFY_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "inputs": {},
            "query": "接続テスト",
            "response_mode": "blocking",
            "conversation_id": "",
            "user": "validation-test"
        }' \
        "$DIFY_API_URL" 2>/dev/null || echo "000")
    
    if [ "$TEST_RESPONSE" = "200" ]; then
        echo "✅ Dify API接続成功"
        
        # レスポンスの内容を確認
        if jq . /tmp/dify_test_response.json > /dev/null 2>&1; then
            echo "✅ 有効なJSONレスポンスを受信"
            
            # answerフィールドの存在確認
            if jq -e '.answer' /tmp/dify_test_response.json > /dev/null 2>&1; then
                echo "✅ 期待されるレスポンス形式を確認"
            else
                echo "⚠️  警告: レスポンスに'answer'フィールドがありません"
                echo "レスポンス構造:"
                jq keys /tmp/dify_test_response.json 2>/dev/null || echo "JSONパースエラー"
            fi
        else
            echo "❌ 無効なJSONレスポンス"
            ERROR_COUNT=$((ERROR_COUNT + 1))
        fi
    else
        echo "❌ Dify API接続失敗 (HTTP $TEST_RESPONSE)"
        echo "レスポンス内容:"
        cat /tmp/dify_test_response.json 2>/dev/null || echo "レスポンスファイルが見つかりません"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    
    # 一時ファイルのクリーンアップ
    rm -f /tmp/dify_test_response.json
else
    echo "⚠️  Dify API設定が不完全のため、接続テストをスキップ"
fi

echo ""
echo "--- GitHub API接続テスト ---"

if [ -n "$GITHUB_TOKEN" ]; then
    echo "GitHub APIへの接続をテスト中..."
    
    # GitHub APIでユーザー情報を取得（認証テスト）
    GITHUB_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/github_test_response.json \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user" 2>/dev/null || echo "000")
    
    if [ "$GITHUB_RESPONSE" = "200" ]; then
        echo "✅ GitHub API接続成功"
        
        # ユーザー名を表示
        if jq . /tmp/github_test_response.json > /dev/null 2>&1; then
            USERNAME=$(jq -r '.login // "不明"' /tmp/github_test_response.json)
            echo "✅ 認証ユーザー: $USERNAME"
        fi
    else
        echo "❌ GitHub API接続失敗 (HTTP $GITHUB_RESPONSE)"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
    
    # 一時ファイルのクリーンアップ
    rm -f /tmp/github_test_response.json
else
    echo "⚠️  GitHub Token が設定されていないため、接続テストをスキップ"
fi

echo ""
echo "--- 検証結果 ---"

if [ $ERROR_COUNT -eq 0 ]; then
    echo "✅ すべての検証が成功しました！"
    echo "Dify CTO Review Botを実行する準備ができています。"
    exit 0
else
    echo "❌ $ERROR_COUNT 個のエラーが見つかりました。"
    echo "上記のエラーを修正してから再度実行してください。"
    exit 1
fi
