# AlmaLinux Webhook Server セットアップガイド

AlmaLinux環境でWebhookサーバーを構築する完全ガイドです。

## 🔍 **事前確認**

### **AlmaLinux環境の確認**
```bash
# OS確認
cat /etc/redhat-release
# AlmaLinux release X.X (xxxx)

# ユーザー権限確認
whoami
sudo -l

# ネットワーク確認
curl -I https://api.github.com
curl -I https://api.iruka.dev
```

## 📦 **フェーズ1: 開発環境のセットアップ**

### **1-1. Node.js 18のインストール**
```bash
# NodeSourceリポジトリを追加
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -

# Node.js 18をインストール
sudo dnf install -y nodejs

# バージョン確認
node --version  # v18.x.x
npm --version   # 9.x.x
```

### **1-2. 必要なツールのインストール**
```bash
# 開発ツールとSSL関連
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y openssl openssl-devel curl wget unzip git

# PM2（プロセスマネージャー）
sudo npm install -g pm2
```

### **1-3. ファイアウォール設定**
```bash
# firewalldの状態確認
sudo systemctl status firewalld

# Webhookポート（3000番）を開放
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload

# 確認
sudo firewall-cmd --list-ports
```

## 🏗️ **フェーズ2: Webhookサーバーの構築**

### **2-1. プロジェクトディレクトリの作成**
```bash
# 作業ディレクトリ作成
sudo mkdir -p /opt/webhook-server
sudo chown $USER:$USER /opt/webhook-server
cd /opt/webhook-server

# ログディレクトリ作成
mkdir -p logs
```

### **2-2. package.jsonの作成**
```bash
cat > package.json << 'EOF'
{
  "name": "dify-cto-webhook-server",
  "version": "1.0.0",
  "description": "AlmaLinux Webhook Server for Dify CTO Review Bot",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js",
    "pm2:start": "pm2 start ecosystem.config.js",
    "pm2:stop": "pm2 stop ecosystem.config.js",
    "pm2:restart": "pm2 restart ecosystem.config.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "winston": "^3.10.0",
    "dotenv": "^16.3.1"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  },
  "engines": {
    "node": ">=18.0.0"
  },
  "keywords": ["webhook", "github", "dify", "ai", "almalinux"],
  "author": "shibuya-yumi",
  "license": "MIT"
}
EOF
```

### **2-3. 環境変数ファイルの作成**
```bash
cat > .env << 'EOF'
# AlmaLinux Webhook Server 環境変数

# Dify API設定
DIFY_API_KEY=your_dify_api_key_here
DIFY_API_URL=https://api.iruka.dev/v1/chat-messages

# GitHub設定
GITHUB_TOKEN=your_github_token_here

# サーバー設定
PORT=3000
NODE_ENV=production

# SSL設定（HTTPS用）
USE_HTTPS=false
SSL_KEY_PATH=/etc/ssl/private/server.key
SSL_CERT_PATH=/etc/ssl/certs/server.crt

# ログ設定
LOG_LEVEL=info
LOG_FILE=./logs/webhook.log
ERROR_LOG_FILE=./logs/error.log
EOF
```

### **2-4. メインサーバーファイルの作成**
```bash
cat > server.js << 'EOF'
// AlmaLinux用 Webhook Server
require('dotenv').config();

const express = require('express');
const winston = require('winston');
const https = require('https');
const http = require('http');
const fs = require('fs');

const app = express();

// ログ設定
const logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json()
    ),
    transports: [
        new winston.transports.File({ 
            filename: process.env.ERROR_LOG_FILE || './logs/error.log', 
            level: 'error' 
        }),
        new winston.transports.File({ 
            filename: process.env.LOG_FILE || './logs/webhook.log' 
        }),
        new winston.transports.Console({
            format: winston.format.combine(
                winston.format.colorize(),
                winston.format.simple()
            )
        })
    ]
});

// ミドルウェア
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// リクエストログ
app.use((req, res, next) => {
    logger.info('Request received', {
        method: req.method,
        url: req.url,
        ip: req.ip,
        userAgent: req.get('User-Agent')
    });
    next();
});

// 環境変数チェック
const requiredEnvVars = ['DIFY_API_KEY', 'DIFY_API_URL', 'GITHUB_TOKEN'];
for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
        logger.error(`環境変数 ${envVar} が設定されていません`);
        process.exit(1);
    }
}

// ヘルスチェックエンドポイント
app.get('/health', (req, res) => {
    const healthData = {
        status: 'healthy',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        memory: process.memoryUsage(),
        environment: process.env.NODE_ENV,
        version: process.version
    };
    
    logger.info('Health check requested', healthData);
    res.json(healthData);
});

// メインWebhookエンドポイント
app.post('/webhook', async (req, res) => {
    const startTime = Date.now();
    const requestId = generateRequestId();
    
    logger.info('Webhook processing started', { requestId });

    try {
        const { action, label, pull_request } = req.body;
        
        // リクエスト内容をログ
        logger.info('Webhook payload received', {
            requestId,
            action,
            labelName: label?.name,
            prNumber: pull_request?.number,
            repo: pull_request?.base?.repo?.full_name
        });
        
        // cto-reviewラベルが付いた場合のみ処理
        if (action === 'labeled' && label && label.name === 'cto-review') {
            logger.info('Processing CTO review', { requestId });
            
            // outline.mdを取得
            const outlineContent = await fetchOutlineContent(pull_request, requestId);
            logger.info('outline.md fetched', { 
                requestId, 
                contentLength: outlineContent.length 
            });
            
            // Dify APIでレビュー生成
            const ctoReview = await callDifyAPI(outlineContent, requestId);
            logger.info('CTO review generated', { 
                requestId, 
                reviewLength: ctoReview.length 
            });
            
            // PRにコメント投稿
            await postPRComment(pull_request, ctoReview, requestId);
            logger.info('Comment posted to PR', { requestId });
            
            const duration = Date.now() - startTime;
            logger.info('Webhook processing completed', { requestId, duration });
            
            res.json({
                success: true,
                message: 'CTO review completed',
                requestId,
                duration: `${duration}ms`
            });
        } else {
            logger.info('No action needed', { requestId, action, labelName: label?.name });
            res.json({ 
                message: 'No action needed', 
                requestId,
                action,
                labelName: label?.name 
            });
        }
    } catch (error) {
        const duration = Date.now() - startTime;
        logger.error('Webhook processing failed', {
            requestId,
            error: error.message,
            stack: error.stack,
            duration
        });
        
        res.status(500).json({
            error: error.message,
            requestId,
            duration: `${duration}ms`
        });
    }
});

// outline.mdファイルを取得
async function fetchOutlineContent(pullRequest, requestId) {
    const url = `https://api.github.com/repos/${pullRequest.base.repo.full_name}/contents/outline.md?ref=${pullRequest.head.sha}`;
    
    logger.info('Fetching outline.md', { requestId, url });
    
    const response = await fetch(url, {
        headers: {
            'Authorization': `token ${process.env.GITHUB_TOKEN}`,
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'AlmaLinux-CTO-Review-Bot/1.0'
        }
    });
    
    if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`GitHub API error: ${response.status} ${response.statusText} - ${errorText}`);
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
        user: "almalinux-cto-bot"
    };
    
    const response = await fetch(process.env.DIFY_API_URL, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${process.env.DIFY_API_KEY}`,
            'Content-Type': 'application/json',
            'User-Agent': 'AlmaLinux-CTO-Review-Bot/1.0'
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
*処理サーバー: AlmaLinux*  
*Request ID: ${requestId}*`;

    const url = `https://api.github.com/repos/${pullRequest.base.repo.full_name}/issues/${pullRequest.number}/comments`;
    
    logger.info('Posting comment to GitHub', { requestId });
    
    const response = await fetch(url, {
        method: 'POST',
        headers: {
            'Authorization': `token ${process.env.GITHUB_TOKEN}`,
            'Content-Type': 'application/json',
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'AlmaLinux-CTO-Review-Bot/1.0'
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

process.on('SIGTERM', () => {
    logger.info('SIGTERM received, shutting down gracefully');
    process.exit(0);
});

process.on('SIGINT', () => {
    logger.info('SIGINT received, shutting down gracefully');
    process.exit(0);
});

// fetch polyfill for Node.js < 18
if (!global.fetch) {
    const fetch = require('node-fetch');
    global.fetch = fetch;
}

// サーバー起動
const PORT = process.env.PORT || 3000;
const USE_HTTPS = process.env.USE_HTTPS === 'true';

if (USE_HTTPS && fs.existsSync(process.env.SSL_KEY_PATH) && fs.existsSync(process.env.SSL_CERT_PATH)) {
    const sslOptions = {
        key: fs.readFileSync(process.env.SSL_KEY_PATH),
        cert: fs.readFileSync(process.env.SSL_CERT_PATH)
    };
    
    https.createServer(sslOptions, app).listen(PORT, '0.0.0.0', () => {
        logger.info(`HTTPS Webhook server running on port ${PORT}`);
    });
} else {
    http.createServer(app).listen(PORT, '0.0.0.0', () => {
        logger.info(`HTTP Webhook server running on port ${PORT}`);
    });
}
EOF
```

### **2-5. PM2設定ファイルの作成**
```bash
cat > ecosystem.config.js << 'EOF'
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
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    error_file: './logs/pm2-error.log',
    out_file: './logs/pm2-out.log',
    log_file: './logs/pm2-combined.log',
    time: true
  }]
};
EOF
```

## 🔧 **フェーズ3: セットアップと起動**

### **3-1. 依存関係のインストール**
```bash
# npmパッケージをインストール
npm install

# node-fetchを追加（Node.js 18未満の場合）
npm install node-fetch@2.7.0
```

### **3-2. 環境変数の設定**
```bash
# .envファイルを編集
nano .env

# 以下の値を実際の値に変更：
# DIFY_API_KEY=your_actual_dify_api_key
# DIFY_API_URL=https://api.iruka.dev/v1/chat-messages
# GITHUB_TOKEN=your_actual_github_token
```

### **3-3. テスト起動**
```bash
# 開発モードで起動
npm start

# 別のターミナルでヘルスチェック
curl http://localhost:3000/health
```

### **3-4. PM2での本番起動**
```bash
# PM2で起動
pm2 start ecosystem.config.js

# 自動起動設定
pm2 startup
# 表示されるコマンドを実行

# 設定保存
pm2 save

# 状態確認
pm2 status
pm2 logs webhook-server
```

## 🌐 **フェーズ4: GitHub Webhook設定**

### **4-1. 外部アクセスの確認**
```bash
# サーバーのIPアドレス確認
ip addr show

# 外部からのアクセステスト（別のマシンから）
curl http://YOUR_ALMALINUX_IP:3000/health
```

### **4-2. GitHubでWebhook設定**
1. GitHubリポジトリの **Settings** → **Webhooks**
2. **Add webhook** をクリック
3. 設定：
   - **Payload URL**: `http://YOUR_ALMALINUX_IP:3000/webhook`
   - **Content type**: `application/json`
   - **Events**: `Pull requests` を選択
   - **Active**: チェック

## 🧪 **フェーズ5: 動作テスト**

### **5-1. ログ監視**
```bash
# リアルタイムログ監視
pm2 logs webhook-server --lines 50

# または
tail -f logs/webhook.log
```

### **5-2. テスト実行**
1. テスト用PRを作成
2. `outline.md` ファイルを含める
3. `cto-review` ラベルを付与
4. ログでWebhook受信を確認
5. PRにコメントが投稿されることを確認

## 🛡️ **セキュリティとメンテナンス**

### **SSL証明書の設定（推奨）**
```bash
# Let's Encryptで証明書取得
sudo dnf install -y certbot
sudo certbot certonly --standalone -d your-domain.com

# .envでHTTPS有効化
USE_HTTPS=true
SSL_KEY_PATH=/etc/letsencrypt/live/your-domain.com/privkey.pem
SSL_CERT_PATH=/etc/letsencrypt/live/your-domain.com/fullchain.pem
```

### **ログローテーション**
```bash
# logrotateの設定
sudo tee /etc/logrotate.d/webhook-server << EOF
/opt/webhook-server/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    notifempty
    create 644 $USER $USER
    postrotate
        pm2 reload webhook-server
    endscript
}
EOF
```

## 📊 **監視とアラート**

### **基本監視**
```bash
# PM2監視
pm2 monit

# システムリソース監視
htop
df -h
```

これで完全なAlmaLinux Webhook Serverが構築できます！

どの段階から始めますか？まずは基本的な環境確認から始めましょうか？
