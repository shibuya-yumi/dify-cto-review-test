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
