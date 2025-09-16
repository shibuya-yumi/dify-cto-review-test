# Dify CTO Review Webhook Server

他の人も使えるようにするためのWebhookサーバーです。

## 🏗️ アーキテクチャ

```
GitHub PR (cto-reviewラベル)
    ↓ Webhook
Vercel Serverless Function
    ↓ API呼び出し
Dify API
    ↓ CTOレビュー生成
Vercel Serverless Function
    ↓ コメント投稿
GitHub PR
```

## 🚀 デプロイ手順

### 1. Vercelアカウント作成
- [Vercel](https://vercel.com)でアカウント作成
- GitHubアカウントと連携

### 2. プロジェクトデプロイ
```bash
# Vercel CLIインストール
npm i -g vercel

# webhook-serverディレクトリに移動
cd webhook-server

# デプロイ
vercel --prod
```

### 3. 環境変数設定
```bash
# Vercelで環境変数を設定
vercel env add DIFY_API_KEY
vercel env add DIFY_API_URL
vercel env add GITHUB_TOKEN
```

### 4. GitHubでWebhook設定
1. リポジトリの **Settings** → **Webhooks**
2. **Add webhook** をクリック
3. **Payload URL**: `https://your-app.vercel.app/api/webhook`
4. **Content type**: `application/json`
5. **Secret**: (オプション)
6. **Events**: `Pull requests` を選択
7. **Active**: チェック

## 🔧 使用方法

1. PRを作成
2. `cto-review` ラベルを付与
3. 自動的にCTOレビューコメントが投稿される

## 💰 コスト

- **Vercel**: 無料枠で十分（月100回実行まで）
- **追加コスト**: なし

## 🎯 メリット

- ✅ **24時間稼働**: サーバーレスで常時利用可能
- ✅ **複数人対応**: 誰でも使える
- ✅ **メンテナンス不要**: Vercelが管理
- ✅ **スケーラブル**: 使用量に応じて自動スケール
- ✅ **無料**: 基本的に無料で利用可能

## 🔍 ログ確認

```bash
# Vercelでログ確認
vercel logs
```

## 🛠️ ローカル開発

```bash
cd webhook-server
npm install
vercel dev
```

## 📞 サポート

問題が発生した場合は、Vercelのログを確認してください。
