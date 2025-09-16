# VM手動セットアップ手順

踏み台サーバー経由でのWebhookサーバーセットアップ手順です。

## 🔧 フェーズ1: Node.jsアップデート

### **1-1. 現在の状況確認**
```bash
# 現在のNode.jsバージョン確認
node --version
npm --version
which node

# OS確認
cat /etc/redhat-release
```

### **1-2. 既存Node.jsの削除**
```bash
# 既存のNode.jsとnpmを削除
sudo yum remove -y nodejs npm

# 削除確認
which node
# 何も表示されなければOK
```

### **1-3. NodeSourceリポジトリの追加**
```bash
# Node.js 18.x リポジトリを追加
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
```

### **1-4. Node.js 18のインストール**
```bash
# Node.js 18をインストール
sudo yum install -y nodejs

# バージョン確認
node --version
npm --version
```

### **1-5. 開発ツールのインストール**
```bash
# ネイティブモジュールビルドに必要
sudo yum groupinstall -y "Development Tools"
sudo yum install -y gcc-c++ make python2
```

---

## 📁 フェーズ2: ディレクトリとファイル準備

### **2-1. 作業ディレクトリ作成**
```bash
# Webhookサーバー用ディレクトリ作成
sudo mkdir -p /opt/webhook-server
sudo chown $USER:$USER /opt/webhook-server
mkdir -p /opt/webhook-server/logs
cd /opt/webhook-server
```

### **2-2. 必要ファイルの作成**

#### **package.json**
```bash
cat > package.json << 'EOF'
{
  "name": "internal-webhook-server",
  "version": "1.0.0",
  "description": "Internal VM webhook server for Dify CTO Review Bot",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "test": "node test-server.js",
    "pm2:start": "pm2 start ecosystem.config.js",
    "pm2:stop": "pm2 stop ecosystem.config.js",
    "pm2:restart": "pm2 restart ecosystem.config.js",
    "pm2:delete": "pm2 delete ecosystem.config.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "winston": "^3.10.0",
    "node-fetch": "^2.7.0"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  },
  "engines": {
    "node": ">=16.0.0"
  },
  "keywords": [
    "webhook",
    "github",
    "dify",
    "ai",
    "code-review",
    "internal"
  ],
  "author": "shibuya-yumi",
  "license": "MIT"
}
EOF
```

#### **ecosystem.config.js**
```bash
cat > ecosystem.config.js << 'EOF'
// PM2 設定ファイル
module.exports = {
  apps: [{
    name: 'webhook-server',
    script: 'server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    env_production: {
      NODE_ENV: 'production',
      PORT: 443,
      USE_HTTPS: 'true'
    },
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true
  }]
};
EOF
```

#### **環境変数ファイル**
```bash
cat > .env << 'EOF'
# 社内VM用環境変数設定

# Dify API設定
DIFY_API_KEY=your_dify_api_key_here
DIFY_API_URL=https://api.iruka.dev/v1/chat-messages

# GitHub設定
GITHUB_TOKEN=your_github_token_here

# サーバー設定
PORT=3000
NODE_ENV=production

# HTTPS設定（本番環境）
USE_HTTPS=true
SSL_KEY_PATH=/etc/ssl/private/server.key
SSL_CERT_PATH=/etc/ssl/certs/server.crt

# ログ設定
LOG_LEVEL=info
EOF
```

---

## 🚀 フェーズ3: メインサーバーファイル作成

### **3-1. server.js作成（長いファイルなので分割）**

#### **Part 1: 基本設定とミドルウェア**
```bash
cat > server.js << 'EOF'
// 社内VM用のWebhookサーバー (Node.js + Express)
// GitHub Webhook → 社内VM → Dify API → GitHub PR Comment

const express = require('express');
const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

const app = express();

// ミドルウェア
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// ログ設定
const winston = require('winston');
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.File({ filename: 'webhook-error.log', level: 'error' }),
        new winston.transports.File({ filename: 'webhook.log' }),
        new winston.transports.Console({
            format: winston.format.combine(
                winston.format.colorize(),
                winston.format.simple()
            )
        })
    ]
});

// 環境変数の確認
const requiredEnvVars = ['DIFY_API_KEY', 'DIFY_API_URL', 'GITHUB_TOKEN'];
for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
        logger.error(`環境変数 ${envVar} が設定されていません`);
        process.exit(1);
    }
}

// ヘルスチェックエンドポイント
app.get('/health', (req, res) => {
    res.json({ 
        status: 'healthy', 
        timestamp: new Date().toISOString(),
        uptime: process.uptime()
    });
});
EOF
```

#### **Part 2: メインWebhookエンドポイント**
```bash
cat >> server.js << 'EOF'

// メインのWebhookエンドポイント
app.post('/webhook', async (req, res) => {
    const startTime = Date.now();
    const requestId = generateRequestId();
    
    logger.info('Webhook received', { 
        requestId,
        headers: {
            'user-agent': req.get('user-agent'),
            'x-github-event': req.get('x-github-event'),
            'x-github-delivery': req.get('x-github-delivery')
        }
    });

    try {
        const { action, label, pull_request } = req.body;
        
        // cto-reviewラベルが付いた場合のみ処理
        if (action === 'labeled' && label && label.name === 'cto-review') {
            logger.info('Processing CTO review', { 
                requestId,
                pr_number: pull_request.number,
                repo: pull_request.base.repo.full_name
            });
            
            // outline.mdを取得
            const outlineContent = await fetchOutlineContent(pull_request, requestId);
            logger.info('Fetched outline.md', { 
                requestId,
                contentLength: outlineContent.length 
            });
            
            // Dify APIでCTOレビューを生成
            const ctoReview = await callDifyAPI(outlineContent, requestId);
            logger.info('Generated CTO review', { 
                requestId,
                reviewLength: ctoReview.length 
            });
            
            // PRにコメント投稿
            await postPRComment(pull_request, ctoReview, requestId);
            logger.info('Posted comment to PR', { requestId });
            
            const duration = Date.now() - startTime;
            logger.info('Webhook processing completed', { 
                requestId,
                duration: `${duration}ms`
            });
            
            res.json({ 
                success: true, 
                message: 'CTO review completed',
                requestId,
                duration: `${duration}ms`
            });
        } else {
            logger.info('No action needed', { 
                requestId,
                action,
                labelName: label?.name 
            });
            res.json({ message: 'No action needed', requestId });
        }
    } catch (error) {
        const duration = Date.now() - startTime;
        logger.error('Webhook processing failed', { 
            requestId,
            error: error.message,
            stack: error.stack,
            duration: `${duration}ms`
        });
        
        res.status(500).json({ 
            error: error.message,
            requestId,
            duration: `${duration}ms`
        });
    }
});
EOF
```

#### **Part 3: ヘルパー関数**
```bash
cat >> server.js << 'EOF'

// outline.mdファイルを取得
async function fetchOutlineContent(pullRequest, requestId) {
    const url = `https://api.github.com/repos/${pullRequest.base.repo.full_name}/contents/outline.md?ref=${pullRequest.head.sha}`;
    
    logger.info('Fetching outline.md from GitHub', { requestId, url });
    
    const response = await fetch(url, {
        headers: {
            'Authorization': `token ${process.env.GITHUB_TOKEN}`,
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'Internal-CTO-Review-Bot/1.0'
        }
    });
    
    if (!response.ok) {
        throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
    }
    
    const data = await response.json();
    
    if (!data.content) {
        throw new Error('outline.md not found or empty');
    }
    
    return Buffer.from(data.content, 'base64').toString('utf-8');
}

// Dify APIを呼び出し
async function callDifyAPI(content, requestId) {
    logger.info('Calling Dify API', { requestId });
    
    const payload = {
        inputs: {},
        query: `以下のoutline.mdファイルをCTOの視点でレビューしてください。技術的な観点、ビジネス的な観点、リスク管理の観点から建設的なフィードバックを提供してください:\n\n${content}`,
        response_mode: "streaming",
        user: "internal-cto-bot"
    };
    
    const response = await fetch(process.env.DIFY_API_URL, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${process.env.DIFY_API_KEY}`,
            'Content-Type': 'application/json',
            'User-Agent': 'Internal-CTO-Review-Bot/1.0'
        },
        body: JSON.stringify(payload)
    });

    if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Dify API error: ${response.status} ${response.statusText} - ${errorText}`);
    }

    // ストリーミングレスポンスを処理
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let result = '';
    
    try {
        while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            
            const chunk = decoder.decode(value, { stream: true });
            const lines = chunk.split('\n');
            
            for (const line of lines) {
                if (line.startsWith('data: ')) {
                    try {
                        const jsonStr = line.slice(6).trim();
                        if (jsonStr && jsonStr !== '[DONE]') {
                            const data = JSON.parse(jsonStr);
                            if (data.answer) {
                                result += data.answer;
                            }
                        }
                    } catch (e) {
                        // JSON解析エラーは無視（部分的なデータの可能性）
                        logger.warn('JSON parse warning', { requestId, error: e.message });
                    }
                }
            }
        }
    } finally {
        reader.releaseLock();
    }
    
    if (!result.trim()) {
        throw new Error('No valid response received from Dify API');
    }
    
    return result.trim();
}
EOF
```

#### **Part 4: サーバー起動部分**
```bash
cat >> server.js << 'EOF'

// PRにコメントを投稿
async function postPRComment(pullRequest, review, requestId) {
    const timestamp = new Date().toLocaleString('ja-JP', { 
        timeZone: 'Asia/Tokyo',
        year: 'numeric',
        month: '2-digit', 
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit'
    });
    
    const commentBody = `## 🎯 CTO Review for outline.md

${review}

---
*このレビューはDify CTO Review Botによって自動生成されました*  
*生成時刻: ${timestamp} (JST)*  
*処理サーバー: 社内VM*  
*Request ID: ${requestId}*`;

    const url = `https://api.github.com/repos/${pullRequest.base.repo.full_name}/issues/${pullRequest.number}/comments`;
    
    logger.info('Posting comment to GitHub', { requestId, url });
    
    const response = await fetch(url, {
        method: 'POST',
        headers: {
            'Authorization': `token ${process.env.GITHUB_TOKEN}`,
            'Content-Type': 'application/json',
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'Internal-CTO-Review-Bot/1.0'
        },
        body: JSON.stringify({ body: commentBody })
    });
    
    if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`GitHub API error: ${response.status} ${response.statusText} - ${errorText}`);
    }
    
    return await response.json();
}

// リクエストIDを生成
function generateRequestId() {
    return `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

// エラーハンドリング
process.on('uncaughtException', (error) => {
    logger.error('Uncaught Exception', { error: error.message, stack: error.stack });
    process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
    logger.error('Unhandled Rejection', { reason, promise });
});

// グレースフルシャットダウン
process.on('SIGTERM', () => {
    logger.info('SIGTERM received, shutting down gracefully');
    process.exit(0);
});

process.on('SIGINT', () => {
    logger.info('SIGINT received, shutting down gracefully');
    process.exit(0);
});

// サーバー起動
const PORT = process.env.PORT || 3000;
const USE_HTTPS = process.env.USE_HTTPS === 'true';

if (USE_HTTPS) {
    // HTTPS サーバー
    const sslOptions = {
        key: fs.readFileSync(process.env.SSL_KEY_PATH || '/etc/ssl/private/server.key'),
        cert: fs.readFileSync(process.env.SSL_CERT_PATH || '/etc/ssl/certs/server.crt')
    };
    
    https.createServer(sslOptions, app).listen(PORT, () => {
        logger.info(`HTTPS Webhook server running on port ${PORT}`);
        logger.info('Environment:', {
            NODE_ENV: process.env.NODE_ENV,
            DIFY_API_URL: process.env.DIFY_API_URL,
            USE_HTTPS: USE_HTTPS
        });
    });
} else {
    // HTTP サーバー（開発用）
    http.createServer(app).listen(PORT, () => {
        logger.info(`HTTP Webhook server running on port ${PORT}`);
        logger.info('Environment:', {
            NODE_ENV: process.env.NODE_ENV,
            DIFY_API_URL: process.env.DIFY_API_URL,
            USE_HTTPS: USE_HTTPS
        });
    });
}

// fetch polyfill for Node.js < 18
if (!global.fetch) {
    global.fetch = require('node-fetch');
}
EOF
```

---

## 📦 フェーズ4: 依存関係とセキュリティ設定

### **4-1. 依存関係のインストール**
```bash
# npmパッケージをインストール
npm install

# インストール確認
npm list
```

### **4-2. PM2のインストール**
```bash
# PM2をグローバルインストール
sudo npm install -g pm2

# インストール確認
pm2 --version
```

### **4-3. SSL証明書の作成**
```bash
# SSL証明書ディレクトリ作成
sudo mkdir -p /etc/ssl/private /etc/ssl/certs

# 自己署名証明書を生成
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/server.key \
  -out /etc/ssl/certs/server.crt \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Company/CN=d-tb-d035"

# 権限設定
sudo chmod 600 /etc/ssl/private/server.key
sudo chmod 644 /etc/ssl/certs/server.crt

# 確認
ls -la /etc/ssl/private/server.key
ls -la /etc/ssl/certs/server.crt
```

### **4-4. ファイアウォール設定**
```bash
# firewalldの状態確認
systemctl status firewalld

# ポート開放（firewalldが動作している場合）
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload

# 設定確認
sudo firewall-cmd --list-ports
```

---

## ⚙️ フェーズ5: 環境変数設定と起動

### **5-1. 環境変数の編集**
```bash
# .envファイルを編集
nano .env

# 以下の値を実際の値に変更してください：
# DIFY_API_KEY=your_actual_dify_api_key
# GITHUB_TOKEN=your_actual_github_token
```

### **5-2. テスト起動**
```bash
# HTTPモードでテスト起動
USE_HTTPS=false PORT=3000 npm start

# 別のターミナルでヘルスチェック
curl http://localhost:3000/health

# Ctrl+C で停止
```

### **5-3. 本番起動（PM2）**
```bash
# PM2で起動
pm2 start ecosystem.config.js

# 自動起動設定
pm2 startup
# 表示されるコマンドをコピーして実行

# 設定保存
pm2 save

# 状態確認
pm2 status
pm2 logs webhook-server
```

---

## 🧪 フェーズ6: 動作確認

### **6-1. ローカルテスト**
```bash
# ヘルスチェック
curl https://localhost/health

# または
curl http://localhost:3000/health
```

### **6-2. ログ確認**
```bash
# PM2ログ
pm2 logs webhook-server

# アプリケーションログ
tail -f /opt/webhook-server/webhook.log
```

---

## 📋 完了チェックリスト

- [ ] Node.js v18.x がインストール済み
- [ ] 全ファイルが作成済み
- [ ] 依存関係がインストール済み
- [ ] SSL証明書が作成済み
- [ ] ファイアウォール設定完了
- [ ] 環境変数が設定済み
- [ ] PM2で起動済み
- [ ] ヘルスチェックが成功

すべて完了したら、GitHubでWebhook設定を行います！
