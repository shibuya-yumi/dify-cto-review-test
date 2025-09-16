# Vercel Webhook 詳細解説

## 🎯 Vercel Webhookとは

**Vercel Webhook**は、GitHubのイベント（PRラベル付与）を外部サーバー（Vercel）で受け取り、処理する仕組みです。

## 📋 ステップバイステップの動作

### **ステップ1: GitHubでのイベント発生**
```
ユーザーがPRに「cto-review」ラベルを付与
    ↓
GitHubが設定されたWebhook URLに通知を送信
```

### **ステップ2: Vercelでの受信・処理**
```
Vercel Serverless Function が起動
    ↓
outline.mdファイルをGitHub APIから取得
    ↓
Dify APIでCTOレビューを生成
    ↓
生成されたレビューをGitHub APIでPRにコメント投稿
```

## 🏗️ アーキテクチャ比較

### **従来のGitHub Actions**
```
GitHub Repository
├── .github/workflows/
│   └── dify-cto-review.yml    # GitHub Actions設定
└── scripts/
    └── review-outline.sh      # 実行スクリプト

実行環境: GitHubのサーバー（IPブロックされる）
```

### **Vercel Webhook**
```
GitHub Repository
├── webhook-server/
│   ├── api/webhook.js         # Vercel Function
│   ├── package.json
│   └── vercel.json
└── GitHub Webhook設定
    └── Payload URL: https://your-app.vercel.app/api/webhook

実行環境: Vercelのサーバー（IPブロックされない）
```

## 🔄 具体的な処理フロー

### **1. Webhook受信**
```javascript
// GitHub からのWebhookを受信
const { action, label, pull_request } = req.body;

// cto-reviewラベルの場合のみ処理
if (action === 'labeled' && label.name === 'cto-review') {
    // 処理開始
}
```

### **2. ファイル取得**
```javascript
// GitHub APIでoutline.mdを取得
const response = await fetch(
    `https://api.github.com/repos/${repo}/contents/outline.md`,
    {
        headers: {
            'Authorization': `token ${GITHUB_TOKEN}`
        }
    }
);
```

### **3. Dify API呼び出し**
```javascript
// Dify APIでCTOレビューを生成
const difyResponse = await fetch(DIFY_API_URL, {
    method: 'POST',
    headers: {
        'Authorization': `Bearer ${DIFY_API_KEY}`,
        'Content-Type': 'application/json'
    },
    body: JSON.stringify({
        query: `CTOの視点でレビューしてください: ${content}`,
        response_mode: "streaming"
    })
});
```

### **4. コメント投稿**
```javascript
// 生成されたレビューをPRにコメント
await fetch(
    `https://api.github.com/repos/${repo}/issues/${pr_number}/comments`,
    {
        method: 'POST',
        headers: {
            'Authorization': `token ${GITHUB_TOKEN}`
        },
        body: JSON.stringify({
            body: `## 🎯 CTO Review\n\n${review}`
        })
    }
);
```

## 💡 メリット・デメリット

### **✅ メリット**
1. **IPブロック回避**: VercelのIPアドレスは通常ブロックされない
2. **24時間稼働**: サーバーレスで常時利用可能
3. **複数人対応**: 誰でも、どのリポジトリでも使える
4. **メンテナンス不要**: Vercelが自動管理
5. **無料**: 基本的に無料で利用可能
6. **スケーラブル**: 使用量に応じて自動スケール

### **⚠️ 注意点**
1. **外部依存**: Vercelのサービスに依存
2. **設定複雑**: 初回セットアップが少し複雑
3. **デバッグ**: ローカルでのデバッグが少し難しい

## 🚀 GitHub Actionsとの違い

| 項目 | GitHub Actions | Vercel Webhook |
|------|----------------|----------------|
| **実行場所** | GitHubのサーバー | Vercelのサーバー |
| **IPアドレス** | GitHub固有（ブロックされる） | Vercel（通常OK） |
| **設定場所** | リポジトリ内 | 外部サービス |
| **利用者** | リポジトリオーナーのみ | 誰でも |
| **稼働時間** | リポジトリ依存 | 24時間 |
| **コスト** | 無料 | 無料（制限内） |

## 🎯 なぜVercel Webhookが解決策になるのか

### **問題の根本原因**
- GitHub ActionsのIPアドレスがDifyのWAF（Web Application Firewall）でブロックされている

### **Vercel Webhookの解決方法**
- VercelのIPアドレスは通常ブロックされていない
- 異なるクラウドプロバイダー（Vercel）からのアクセス
- より一般的なHTTPトラフィックパターン

## 📞 次のステップ

1. **Vercelアカウント作成**
2. **webhook-serverディレクトリのデプロイ**
3. **環境変数設定**
4. **GitHubでWebhook設定**
5. **テスト実行**

これにより、GitHub Actionsの制限を回避して、安定したCTOレビューボットを実現できます。
