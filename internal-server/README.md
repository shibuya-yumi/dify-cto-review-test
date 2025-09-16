# 社内VM用 Webhook Server

外部サービスに依存せず、社内のVMやサーバーでWebhookサーバーを運用する方法です。

## 🏗️ アーキテクチャ

```
GitHub Repository (Webhook)
    ↓ HTTPS
社内VM/サーバー (Node.js + Express)
    ↓ API呼び出し
Dify API
    ↓ レスポンス
社内VM/サーバー
    ↓ GitHub API
GitHub PR (コメント投稿)
```

## 🚀 セットアップ手順

### **1. 環境準備**

```bash
# Node.js のインストール (Ubuntu/CentOS)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# または
sudo yum install -y nodejs npm
```

### **2. プロジェクトセットアップ**

```bash
cd internal-server
npm install

# 環境変数設定
cp env.example .env
nano .env  # 必要な値を設定
```

### **3. SSL証明書の準備**

#### **Let's Encrypt を使用**
```bash
sudo apt install certbot
sudo certbot certonly --standalone -d your-vm.company.com

# 証明書のパス
SSL_KEY_PATH=/etc/letsencrypt/live/your-vm.company.com/privkey.pem
SSL_CERT_PATH=/etc/letsencrypt/live/your-vm.company.com/fullchain.pem
```

#### **社内CA証明書を使用**
```bash
# 社内で発行された証明書を配置
SSL_KEY_PATH=/etc/ssl/private/server.key
SSL_CERT_PATH=/etc/ssl/certs/server.crt
```

### **4. ファイアウォール設定**

```bash
# ポート443を開放
sudo ufw allow 443/tcp

# 特定のIPからのみ許可（推奨）
sudo ufw allow from 192.30.252.0/22 to any port 443  # GitHub Webhook IPs
sudo ufw allow from 185.199.108.0/22 to any port 443
```

### **5. サーバー起動**

#### **開発環境（HTTP）**
```bash
npm run dev
# http://localhost:3000 で起動
```

#### **本番環境（HTTPS + PM2）**
```bash
# PM2 インストール
npm install -g pm2

# 本番環境で起動
npm run pm2:start

# 自動起動設定
pm2 startup
pm2 save
```

## 🔧 GitHub Webhook 設定

### **1. リポジトリ設定**
1. GitHub リポジトリの **Settings** → **Webhooks**
2. **Add webhook** をクリック
3. 以下を設定：
   - **Payload URL**: `https://your-vm.company.com/webhook`
   - **Content type**: `application/json`
   - **Secret**: (オプション、セキュリティ強化のため推奨)
   - **Events**: `Pull requests` を選択
   - **Active**: チェック

### **2. 動作確認**
```bash
# ヘルスチェック
curl https://your-vm.company.com/health

# ログ確認
pm2 logs webhook-server
tail -f webhook.log
```

## 📊 監視・ログ

### **ログファイル**
- `webhook.log` - 全般的なログ
- `webhook-error.log` - エラーログ
- `logs/` - PM2のログ

### **監視コマンド**
```bash
# PM2 監視
pm2 monit

# ログリアルタイム表示
pm2 logs --lines 100

# サーバー状態確認
pm2 status
```

## 🔒 セキュリティ

### **推奨設定**
1. **Webhook Secret** の設定
2. **IP制限** (GitHubのWebhook IPのみ許可)
3. **SSL/TLS** の使用
4. **ログ監視** の実装
5. **定期的な証明書更新**

### **IP制限例**
```bash
# GitHub Webhook IP ranges
192.30.252.0/22
185.199.108.0/22
140.82.112.0/20
143.55.64.0/20
```

## 💰 コスト・リソース

### **必要リソース**
- **CPU**: 1-2 cores
- **RAM**: 1-2 GB
- **Storage**: 10 GB
- **Network**: 外部HTTPS通信可能

### **推定コスト**
- **既存VM利用**: 追加コストなし
- **新規VM**: $5-20/月 (クラウドプロバイダーによる)
- **SSL証明書**: 無料 (Let's Encrypt) または社内CA

## 🎯 メリット・デメリット

### **✅ メリット**
- 外部サービス依存なし
- 完全な制御とカスタマイズ
- 社内セキュリティポリシー準拠
- 無制限の実行回数
- ログ・監視の完全制御

### **⚠️ 注意点**
- サーバー管理が必要
- SSL証明書の管理
- 監視・アラートの設定
- 障害対応

## 🚀 本番運用

### **冗長化**
```bash
# ロードバランサー + 複数インスタンス
nginx + 複数のNode.jsプロセス
```

### **監視**
```bash
# Prometheus + Grafana
# Zabbix
# 社内監視システム
```

### **バックアップ**
```bash
# 設定ファイル
# ログファイル
# SSL証明書
```

## 📞 トラブルシューティング

### **よくある問題**
1. **SSL証明書エラー** → 証明書の有効期限・パス確認
2. **ポート接続エラー** → ファイアウォール設定確認
3. **GitHub API 401** → GITHUB_TOKEN の確認
4. **Dify API 403** → DIFY_API_KEY の確認

### **ログ確認**
```bash
# エラーログ
tail -f webhook-error.log

# 全体ログ
tail -f webhook.log

# PM2ログ
pm2 logs webhook-server
```

これで社内VMを使った完全に独立したWebhookサーバーが構築できます！
