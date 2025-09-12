# Dify CTO Review Bot セットアップガイド

このドキュメントでは、Dify CTO Review BotをGitHub Actionsで動作させるために必要な環境変数の設定方法を説明します。

## 必要な環境変数

### 1. DIFY_API_KEY
- **説明**: DifyのAPIキー
- **取得方法**: Difyのダッシュボードから取得
- **設定場所**: GitHub Secrets
- **必須**: はい

### 2. DIFY_API_URL
- **説明**: DifyのAPIエンドポイントURL
- **形式**: `https://api.dify.ai/v1/chat-messages`（例）
- **設定場所**: GitHub Secrets
- **必須**: はい

### 3. GITHUB_TOKEN
- **説明**: GitHub APIアクセス用トークン
- **取得方法**: GitHub Actionsで自動提供される
- **設定場所**: 自動設定（手動設定不要）
- **必須**: はい（自動）

## GitHub Secretsの設定手順

### ステップ1: GitHubリポジトリの設定画面にアクセス

1. GitHubリポジトリのページを開く
2. 「Settings」タブをクリック
3. 左サイドバーの「Secrets and variables」→「Actions」をクリック

### ステップ2: 環境変数を追加

#### DIFY_API_KEYの設定
1. 「New repository secret」をクリック
2. Name: `DIFY_API_KEY`
3. Secret: Difyから取得したAPIキーを入力
4. 「Add secret」をクリック

#### DIFY_API_URLの設定
1. 「New repository secret」をクリック
2. Name: `DIFY_API_URL`
3. Secret: DifyのAPIエンドポイントURLを入力
   ```
   例: https://api.dify.ai/v1/chat-messages
   ```
4. 「Add secret」をクリック

## Dify APIの設定確認

### APIキーの取得方法
1. Difyにログイン
2. 対象のアプリケーションを選択
3. 「API Access」または「API管理」セクションに移動
4. APIキーをコピー

### APIエンドポイントの確認方法
1. Difyのアプリケーション設定で「API Reference」を確認
2. Chat APIのエンドポイントURLをコピー
3. 通常は以下の形式：
   ```
   https://api.dify.ai/v1/chat-messages
   ```

## 動作確認用のcurlコマンド

設定が正しいかどうか、以下のcurlコマンドで確認できます：

```bash
curl -X POST 'YOUR_DIFY_API_URL' \
  -H 'Authorization: Bearer YOUR_DIFY_API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "inputs": {},
    "query": "テスト用のメッセージです",
    "response_mode": "blocking",
    "conversation_id": "",
    "user": "test-user"
  }'
```

## トラブルシューティング

### よくあるエラーと解決方法

#### 1. 401 Unauthorized
- **原因**: APIキーが無効または期限切れ
- **解決方法**: DifyでAPIキーを再生成し、GitHub Secretsを更新

#### 2. 404 Not Found
- **原因**: APIエンドポイントURLが間違っている
- **解決方法**: DifyのAPI Referenceで正しいURLを確認

#### 3. 403 Forbidden
- **原因**: APIキーに必要な権限がない
- **解決方法**: Difyでアプリケーションの権限設定を確認

#### 4. Rate Limit Exceeded
- **原因**: API呼び出し回数制限に達した
- **解決方法**: しばらく待ってから再試行、または料金プランを確認

## セキュリティのベストプラクティス

### 1. APIキーの管理
- APIキーは絶対にコードに直接記述しない
- GitHub Secretsを使用して安全に管理
- 定期的にAPIキーをローテーション

### 2. 権限の最小化
- 必要最小限の権限のみを付与
- 不要になったAPIキーは無効化

### 3. ログの管理
- APIキーがログに出力されないよう注意
- スクリプトではAPIキーの一部のみを表示

## ワークフローの実行確認

### 1. PRラベルの設定
ワークフローをトリガーするには、PRに以下のラベルを追加：
- `cto-review`（またはワークフローで設定したラベル名）

### 2. ログの確認
GitHub Actionsの実行ログで以下を確認：
- PR情報の取得成功
- Dify API呼び出し成功
- CTOレビューコメントの生成
- PRへのコメント投稿成功

### 3. エラー時の対処
ワークフローが失敗した場合：
1. GitHub Actionsのログを確認
2. 環境変数の設定を再確認
3. Dify APIの動作状況を確認
4. 必要に応じてスクリプトをデバッグ

## 参考リンク

- [GitHub Secrets の設定方法](https://docs.github.com/ja/actions/security-guides/encrypted-secrets)
- [Dify API ドキュメント](https://docs.dify.ai/)
- [GitHub Actions ワークフロー構文](https://docs.github.com/ja/actions/using-workflows/workflow-syntax-for-github-actions)
