# トラブルシューティングガイド

## 🚨 HTTP 403エラーの解決方法

### 1. GitHub Actions権限設定

#### リポジトリ設定の確認
1. GitHubリポジトリページに移動
2. **Settings** → **Actions** → **General**
3. **Workflow permissions**セクションで以下を確認：
   - ✅ **Read and write permissions** を選択
   - ✅ **Allow GitHub Actions to create and approve pull requests** にチェック

#### 現在のワークフロー権限
```yaml
permissions:
  contents: read          # リポジトリ内容の読み取り
  pull-requests: write    # PRへのコメント投稿
  issues: write          # Issueへのコメント投稿
```

### 2. Dify API 403エラーの対策

#### 原因の可能性
- GitHub ActionsのIPアドレスがDifyのWAFでブロックされている
- APIキーの権限不足
- レート制限に達している

#### 対策
1. **APIキーの確認**
   ```bash
   # ローカルでテスト
   ./scripts/test-dify-connection.sh
   ```

2. **GitHub Secretsの再設定**
   - `DIFY_API_KEY`を削除して再作成
   - `DIFY_API_URL`を確認

3. **Difyダッシュボードでの確認**
   - アプリケーションが正常に動作しているか
   - APIキーが有効か
   - 使用量制限に達していないか

### 3. 一時的な回避策

現在のワークフローでは、環境変数検証時のAPI接続テストをスキップするように設定済み：

```yaml
env:
  SKIP_API_TEST: "true"  # API接続テストをスキップ
```

これにより、実際のレビュー処理は正常に動作する可能性があります。

### 4. 段階的なテスト

#### ステップ1: 基本的な権限テスト
```yaml
# 最小限のテスト用ワークフロー
- name: Test basic permissions
  run: |
    echo "Repository: $GITHUB_REPOSITORY"
    echo "Actor: $GITHUB_ACTOR"
    echo "Token permissions test..."
```

#### ステップ2: Dify APIテスト
```bash
# ローカルでのテスト
export DIFY_API_KEY="your_key"
export DIFY_API_URL="your_url"
./scripts/review-outline.sh outline.md
```

#### ステップ3: 完全なワークフロー
- 上記が成功したら、完全なワークフローを実行

### 5. デバッグ情報の収集

#### GitHub Actionsでのデバッグ
```yaml
- name: Debug environment
  run: |
    echo "GitHub Context:"
    echo "  Repository: $GITHUB_REPOSITORY"
    echo "  Actor: $GITHUB_ACTOR"
    echo "  Event: $GITHUB_EVENT_NAME"
    echo "  Ref: $GITHUB_REF"
    
    echo "Environment Variables:"
    env | grep -E "(GITHUB_|DIFY_)" | sort
```

#### ネットワーク接続テスト
```yaml
- name: Test network connectivity
  run: |
    echo "Testing DNS resolution..."
    nslookup api.dify.ai || true
    
    echo "Testing HTTP connectivity..."
    curl -I https://api.dify.ai || true
```

### 6. 代替案

#### Option A: GitHub Codespaces/Self-hosted runner
- GitHub ActionsのIPアドレス制限を回避
- より柔軟なネットワーク設定

#### Option B: Webhook経由
- DifyからのWebhookを受信
- GitHub Actionsではなく、外部サーバーでの処理

#### Option C: プロキシ経由
- 信頼できるIPアドレスからのアクセス

### 7. 成功時の期待ログ

```
環境変数を検証中...
=== 環境変数検証開始 ===
--- 必須環境変数のチェック ---
✅ DIFY_API_KEY: app-2vdY4M...
✅ DIFY_API_URL: ***
✅ GITHUB_TOKEN: ghs_KltkaG...
--- API接続テスト ---
⚠️  API接続テストをスキップします（SKIP_API_TEST=true）
--- 検証結果 ---
✅ 環境変数の検証が完了しました
```

### 8. 次のステップ

1. **リポジトリ権限設定を確認**
2. **修正をプッシュ**
3. **ワークフローを再実行**
4. **実際のレビュー処理が動作するか確認**

問題が解決しない場合は、ローカルテストの結果と合わせて詳細を確認してください。
