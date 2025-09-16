// Vercel用のWebhookサーバー
// GitHub PR → このサーバー → Dify API → GitHub PR Comment

export default async function handler(req, res) {
  // CORS対応
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  console.log('Webhook received:', {
    headers: req.headers,
    body: req.body
  });

  try {
    const { action, label, pull_request } = req.body;
    
    // cto-reviewラベルが付いた場合のみ処理
    if (action === 'labeled' && label && label.name === 'cto-review') {
      console.log('Processing CTO review for PR:', pull_request.number);
      
      // outline.mdを取得
      const outlineContent = await fetchOutlineContent(pull_request);
      console.log('Fetched outline.md content, length:', outlineContent.length);
      
      // Dify APIを呼び出し
      const ctoReview = await callDifyAPI(outlineContent);
      console.log('Generated CTO review, length:', ctoReview.length);
      
      // PRにコメント投稿
      await postPRComment(pull_request, ctoReview);
      console.log('Posted comment to PR');
      
      res.status(200).json({ 
        success: true, 
        message: 'CTO review completed',
        pr_number: pull_request.number
      });
    } else {
      console.log('No action needed for this webhook');
      res.status(200).json({ message: 'No action needed' });
    }
  } catch (error) {
    console.error('Webhook error:', error);
    res.status(500).json({ 
      error: error.message,
      stack: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
}

async function fetchOutlineContent(pullRequest) {
  const url = `https://api.github.com/repos/${pullRequest.base.repo.full_name}/contents/outline.md?ref=${pullRequest.head.sha}`;
  
  console.log('Fetching outline.md from:', url);
  
  const response = await fetch(url, {
    headers: {
      'Authorization': `token ${process.env.GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'Dify-CTO-Review-Bot/1.0'
    }
  });
  
  if (!response.ok) {
    throw new Error(`Failed to fetch outline.md: ${response.status} ${response.statusText}`);
  }
  
  const data = await response.json();
  
  if (!data.content) {
    throw new Error('outline.md not found or empty');
  }
  
  return Buffer.from(data.content, 'base64').toString('utf-8');
}

async function callDifyAPI(content) {
  console.log('Calling Dify API...');
  
  const payload = {
    inputs: {},
    query: `以下のoutline.mdファイルをCTOの視点でレビューしてください。技術的な観点、ビジネス的な観点、リスク管理の観点から建設的なフィードバックを提供してください:\n\n${content}`,
    response_mode: "streaming",
    user: "webhook-cto-bot"
  };
  
  const response = await fetch(process.env.DIFY_API_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.DIFY_API_KEY}`,
      'Content-Type': 'application/json',
      'User-Agent': 'Dify-CTO-Review-Bot/1.0'
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
            console.warn('JSON parse error:', e.message);
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

async function postPRComment(pullRequest, review) {
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
*Webhook Server: Vercel*`;

  const url = `https://api.github.com/repos/${pullRequest.base.repo.full_name}/issues/${pullRequest.number}/comments`;
  
  console.log('Posting comment to:', url);
  
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `token ${process.env.GITHUB_TOKEN}`,
      'Content-Type': 'application/json',
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'Dify-CTO-Review-Bot/1.0'
    },
    body: JSON.stringify({ body: commentBody })
  });
  
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Failed to post comment: ${response.status} ${response.statusText} - ${errorText}`);
  }
  
  return await response.json();
}
