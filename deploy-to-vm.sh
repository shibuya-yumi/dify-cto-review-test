#!/bin/bash

# CentOS 7 VMへのWebhookサーバーデプロイスクリプト
# 使用方法: ./deploy-to-vm.sh [VM_HOST] [VM_USER]

set -e

VM_HOST=${1:-"d-tb-d035"}
VM_USER=${2:-"shibuya_yumi"}
REMOTE_DIR="/opt/webhook-server"

echo "🚀 CentOS 7 VMへのWebhookサーバーデプロイを開始します"
echo "対象VM: ${VM_USER}@${VM_HOST}"
echo "リモートディレクトリ: ${REMOTE_DIR}"

# 1. VMでのディレクトリ準備
echo "📁 リモートディレクトリを準備中..."
ssh ${VM_USER}@${VM_HOST} "
    sudo mkdir -p ${REMOTE_DIR}
    sudo chown ${VM_USER}:${VM_USER} ${REMOTE_DIR}
    mkdir -p ${REMOTE_DIR}/logs
"

# 2. 必要ファイルの転送
echo "📤 ファイルを転送中..."
scp -r internal-server/* ${VM_USER}@${VM_HOST}:${REMOTE_DIR}/

# 3. 環境変数ファイルの準備
echo "⚙️  環境変数ファイルを準備中..."
ssh ${VM_USER}@${VM_HOST} "
    cd ${REMOTE_DIR}
    if [ ! -f .env ]; then
        cp env.example .env
        echo '✅ .env ファイルを作成しました。編集が必要です:'
        echo '   - DIFY_API_KEY'
        echo '   - DIFY_API_URL'  
        echo '   - GITHUB_TOKEN'
    fi
"

# 4. Node.jsバージョン確認
echo "🔍 Node.jsバージョンを確認中..."
NODE_VERSION=$(ssh ${VM_USER}@${VM_HOST} "node --version 2>/dev/null || echo 'not_installed'")

if [[ "$NODE_VERSION" == "not_installed" ]] || [[ "$NODE_VERSION" < "v16" ]]; then
    echo "⚠️  Node.js ${NODE_VERSION} は古すぎます。アップデートが必要です。"
    echo "📋 Node.jsアップデート手順:"
    echo "   1. ssh ${VM_USER}@${VM_HOST}"
    echo "   2. sudo yum remove -y nodejs npm"
    echo "   3. curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -"
    echo "   4. sudo yum install -y nodejs"
    echo "   5. node --version  # v18.x.x を確認"
    echo ""
    echo "Node.jsアップデート後、再度このスクリプトを実行してください。"
    exit 1
else
    echo "✅ Node.js ${NODE_VERSION} が利用可能です"
fi

# 5. 依存関係のインストール
echo "📦 依存関係をインストール中..."
ssh ${VM_USER}@${VM_HOST} "
    cd ${REMOTE_DIR}
    npm install
    echo '✅ 依存関係のインストールが完了しました'
"

# 6. PM2のインストール（グローバル）
echo "🔧 PM2をインストール中..."
ssh ${VM_USER}@${VM_HOST} "
    if ! command -v pm2 &> /dev/null; then
        sudo npm install -g pm2
        echo '✅ PM2をインストールしました'
    else
        echo '✅ PM2は既にインストール済みです'
    fi
"

# 7. SSL証明書の確認
echo "🔒 SSL証明書を確認中..."
ssh ${VM_USER}@${VM_HOST} "
    if [ ! -f /etc/ssl/private/server.key ] || [ ! -f /etc/ssl/certs/server.crt ]; then
        echo '⚠️  SSL証明書が見つかりません。自己署名証明書を作成します...'
        sudo mkdir -p /etc/ssl/private /etc/ssl/certs
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/ssl/private/server.key \
            -out /etc/ssl/certs/server.crt \
            -subj '/C=JP/ST=Tokyo/L=Tokyo/O=Company/CN=${VM_HOST}'
        sudo chmod 600 /etc/ssl/private/server.key
        sudo chmod 644 /etc/ssl/certs/server.crt
        echo '✅ 自己署名証明書を作成しました'
    else
        echo '✅ SSL証明書が見つかりました'
    fi
"

# 8. ファイアウォール設定の確認
echo "🛡️  ファイアウォール設定を確認中..."
ssh ${VM_USER}@${VM_HOST} "
    if systemctl is-active --quiet firewalld; then
        echo 'firewalldが動作中です。ポート3000と443を開放します...'
        sudo firewall-cmd --permanent --add-port=3000/tcp
        sudo firewall-cmd --permanent --add-port=443/tcp
        sudo firewall-cmd --reload
        echo '✅ ファイアウォール設定を更新しました'
    elif systemctl is-active --quiet iptables; then
        echo 'iptablesが動作中です。手動でポート設定が必要です:'
        echo '  sudo iptables -A INPUT -p tcp --dport 3000 -j ACCEPT'
        echo '  sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT'
        echo '  sudo service iptables save'
    else
        echo '✅ ファイアウォールが無効です'
    fi
"

# 9. テスト起動
echo "🧪 テスト起動を実行中..."
ssh ${VM_USER}@${VM_HOST} "
    cd ${REMOTE_DIR}
    echo 'ヘルスチェックエンドポイントをテスト中...'
    timeout 10s npm start &
    SERVER_PID=\$!
    sleep 3
    
    if curl -s http://localhost:3000/health > /dev/null; then
        echo '✅ Webhookサーバーが正常に起動しました'
        kill \$SERVER_PID 2>/dev/null || true
    else
        echo '❌ サーバーの起動に問題があります'
        kill \$SERVER_PID 2>/dev/null || true
        exit 1
    fi
"

echo ""
echo "🎉 デプロイが完了しました！"
echo ""
echo "📋 次のステップ:"
echo "1. 環境変数を設定:"
echo "   ssh ${VM_USER}@${VM_HOST}"
echo "   cd ${REMOTE_DIR}"
echo "   nano .env"
echo ""
echo "2. 本番環境で起動:"
echo "   pm2 start ecosystem.config.js"
echo "   pm2 startup"
echo "   pm2 save"
echo ""
echo "3. GitHub Webhookを設定:"
echo "   URL: https://${VM_HOST}/webhook"
echo "   Content-Type: application/json"
echo "   Events: Pull requests"
echo ""
echo "4. 動作確認:"
echo "   curl https://${VM_HOST}/health"
echo ""
echo "🔧 トラブルシューティング:"
echo "   - ログ確認: pm2 logs webhook-server"
echo "   - 状態確認: pm2 status"
echo "   - 再起動: pm2 restart webhook-server"
