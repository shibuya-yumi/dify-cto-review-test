# 社内VM経由でのDify CTO Review Bot セットアップ

外部サービスに依存せず、社内のVMやサーバーを使用してWebhookサーバーを構築する方法です。

## 🏗️ アーキテクチャ

```
GitHub Repository
    ↓ Webhook (HTTPS)
社内VM/サーバー (Node.js/Python/Go等)
    ↓ API呼び出し
Dify API
    ↓ レスポンス
社内VM/サーバー
    ↓ GitHub API
GitHub PR (コメント投稿)
```

## 🚀 実装オプション

### **オプション1: Node.js + Express**

#### **必要な環境**
- Node.js 18+
- 外部からアクセス可能なIP/ドメイン
- SSL証明書（Let's Encryptなど）

#### **実装例**
```javascript
// server.js
const express = require('express');
const https = require('https');
const fs = require('fs');

const app = express();
app.use(express.json());

// Webhookエンドポイント
app.post('/webhook', async (req, res) => {
    try {
        const { action, label, pull_request } = req.body;
        
        if (action === 'labeled' && label?.name === 'cto-review') {
            console.log(`Processing CTO review for PR #${pull_request.number}`);
            
            // outline.mdを取得
            const content = await fetchOutlineContent(pull_request);
            
            // Dify APIでレビュー生成
            const review = await callDifyAPI(content);
            
            // PRにコメント投稿
            await postPRComment(pull_request, review);
            
            res.json({ success: true, message: 'CTO review completed' });
        } else {
            res.json({ message: 'No action needed' });
        }
    } catch (error) {
        console.error('Error:', error);
        res.status(500).json({ error: error.message });
    }
});

// HTTPS サーバー起動
const options = {
    key: fs.readFileSync('/path/to/private-key.pem'),
    cert: fs.readFileSync('/path/to/certificate.pem')
};

https.createServer(options, app).listen(443, () => {
    console.log('Webhook server running on https://your-vm.company.com:443');
});
```

### **オプション2: Python + Flask**

#### **実装例**
```python
# app.py
from flask import Flask, request, jsonify
import requests
import json
import base64

app = Flask(__name__)

@app.route('/webhook', methods=['POST'])
def webhook():
    try:
        data = request.json
        action = data.get('action')
        label = data.get('label', {})
        pull_request = data.get('pull_request')
        
        if action == 'labeled' and label.get('name') == 'cto-review':
            print(f"Processing CTO review for PR #{pull_request['number']}")
            
            # outline.mdを取得
            content = fetch_outline_content(pull_request)
            
            # Dify APIでレビュー生成
            review = call_dify_api(content)
            
            # PRにコメント投稿
            post_pr_comment(pull_request, review)
            
            return jsonify({'success': True, 'message': 'CTO review completed'})
        else:
            return jsonify({'message': 'No action needed'})
            
    except Exception as e:
        print(f"Error: {e}")
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    # HTTPS で起動
    app.run(host='0.0.0.0', port=443, ssl_context='adhoc')
```

### **オプション3: Go + Gin**

#### **実装例**
```go
// main.go
package main

import (
    "github.com/gin-gonic/gin"
    "net/http"
    "log"
)

type WebhookPayload struct {
    Action      string      `json:"action"`
    Label       Label       `json:"label"`
    PullRequest PullRequest `json:"pull_request"`
}

func webhookHandler(c *gin.Context) {
    var payload WebhookPayload
    if err := c.ShouldBindJSON(&payload); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    
    if payload.Action == "labeled" && payload.Label.Name == "cto-review" {
        log.Printf("Processing CTO review for PR #%d", payload.PullRequest.Number)
        
        // outline.mdを取得
        content, err := fetchOutlineContent(payload.PullRequest)
        if err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
            return
        }
        
        // Dify APIでレビュー生成
        review, err := callDifyAPI(content)
        if err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
            return
        }
        
        // PRにコメント投稿
        err = postPRComment(payload.PullRequest, review)
        if err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
            return
        }
        
        c.JSON(http.StatusOK, gin.H{"success": true, "message": "CTO review completed"})
    } else {
        c.JSON(http.StatusOK, gin.H{"message": "No action needed"})
    }
}

func main() {
    r := gin.Default()
    r.POST("/webhook", webhookHandler)
    
    // HTTPS で起動
    log.Fatal(r.RunTLS(":443", "/path/to/cert.pem", "/path/to/key.pem"))
}
```

## 🔧 セットアップ手順

### **1. VM/サーバーの準備**
```bash
# Ubuntu/CentOS での例
sudo apt update
sudo apt install -y nodejs npm nginx certbot

# または Docker を使用
docker run -d -p 443:443 -v /path/to/certs:/certs your-webhook-app
```

### **2. SSL証明書の取得**
```bash
# Let's Encrypt を使用
sudo certbot certonly --standalone -d your-vm.company.com

# または社内CA証明書を使用
```

### **3. ファイアウォール設定**
```bash
# ポート443を開放
sudo ufw allow 443/tcp

# 必要に応じて特定のIPからのみ許可
sudo ufw allow from github-webhook-ips to any port 443
```

### **4. 環境変数設定**
```bash
# .env ファイル
DIFY_API_KEY=your_dify_api_key
DIFY_API_URL=https://api.iruka.dev/v1/chat-messages
GITHUB_TOKEN=your_github_token
PORT=443
```

### **5. プロセス管理**
```bash
# PM2 を使用 (Node.js)
npm install -g pm2
pm2 start server.js --name webhook-server
pm2 startup
pm2 save

# または systemd を使用
sudo systemctl enable webhook-server
sudo systemctl start webhook-server
```

## 🌐 ネットワーク要件

### **必要な通信**
1. **GitHub → 社内VM**: Webhook受信 (HTTPS 443)
2. **社内VM → Dify API**: API呼び出し (HTTPS 443)
3. **社内VM → GitHub API**: コメント投稿 (HTTPS 443)

### **ファイアウォール設定**
```bash
# インバウンド
443/tcp from github-webhook-ips  # GitHubからのWebhook

# アウトバウンド  
443/tcp to api.iruka.dev         # Dify API
443/tcp to api.github.com        # GitHub API
```

## 💰 コスト比較

| 項目 | 社内VM | Vercel | GitHub Actions |
|------|--------|--------|----------------|
| **サーバーコスト** | 既存VM利用 | 無料〜$20/月 | 無料 |
| **SSL証明書** | 無料(Let's Encrypt) | 無料 | - |
| **メンテナンス** | 社内で管理 | Vercelが管理 | GitHubが管理 |
| **制御レベル** | 完全制御 | 限定的 | 限定的 |
| **セキュリティ** | 社内ポリシー準拠 | 外部依存 | 外部依存 |

## 🎯 推奨構成

### **小規模（個人・小チーム）**
- **Node.js + Express** + PM2
- Let's Encrypt SSL
- 既存のVMを活用

### **中規模（部署レベル）**
- **Docker + Kubernetes**
- 社内CA証明書
- ロードバランサー + 冗長化

### **大規模（企業レベル）**
- **マイクロサービス化**
- 社内クラウド（OpenStack等）
- 監視・ログ・アラート完備

## 🔍 監視・ログ

### **ログ設定**
```javascript
// 構造化ログ
const winston = require('winston');

const logger = winston.createLogger({
    level: 'info',
    format: winston.format.json(),
    transports: [
        new winston.transports.File({ filename: 'webhook.log' }),
        new winston.transports.Console()
    ]
});

// 使用例
logger.info('Webhook received', { 
    pr_number: pull_request.number,
    action: action,
    timestamp: new Date().toISOString()
});
```

### **監視設定**
```bash
# Prometheus + Grafana
# Zabbix
# Nagios
# 社内監視システム
```

## 🚀 次のステップ

どの実装方法を選択されますか？

1. **Node.js + Express** (最も簡単)
2. **Python + Flask** (Pythonが得意な場合)
3. **Go + Gin** (高性能が必要な場合)
4. **Docker化** (コンテナ環境の場合)

選択された方法に応じて、詳細な実装をサポートします！
