# AlmaLinux Ruby Webhook Server セットアップ

AlmaLinux 8.7でRubyを使用したWebhookサーバーの構築ガイドです。

## 🔍 **フェーズ1: Ruby環境の確認とセットアップ**

### **1-1. Ruby環境確認**
```bash
# Rubyバージョン確認
ruby --version
gem --version
bundler --version

# 必要に応じてbundlerインストール
gem install bundler
```

### **1-2. 必要なパッケージのインストール**
```bash
# 開発ツールとSSL関連
sudo dnf install -y ruby-devel gcc openssl-devel curl wget git

# 必要に応じてRuby本体をインストール
sudo dnf install -y ruby ruby-devel rubygems
```

### **1-3. ファイアウォール設定**
```bash
# firewalldの状態確認
sudo systemctl status firewalld

# Webhookポート（4567番）を開放
sudo firewall-cmd --permanent --add-port=4567/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload

# 確認
sudo firewall-cmd --list-ports
```

## 🏗️ **フェーズ2: Ruby Webhookサーバーの構築**

### **2-1. プロジェクトディレクトリの作成**
```bash
# 作業ディレクトリ作成
sudo mkdir -p /opt/ruby-webhook-server
sudo chown $USER:$USER /opt/ruby-webhook-server
cd /opt/ruby-webhook-server

# ログディレクトリ作成
mkdir -p logs
mkdir -p tmp
```

### **2-2. Gemfileの作成**
```bash
cat > Gemfile << 'EOF'
source 'https://rubygems.org'

gem 'sinatra', '~> 3.1'
gem 'puma', '~> 6.4'
gem 'httparty', '~> 0.21'
gem 'json', '~> 2.6'
gem 'dotenv', '~> 2.8'
gem 'logger', '~> 1.5'
gem 'base64', '~> 0.1'

group :development do
  gem 'rerun', '~> 0.14'
end
EOF
```

### **2-3. 依存関係のインストール**
```bash
# Bundlerでgemをインストール
bundle install

# インストール確認
bundle list
```

### **2-4. 環境変数ファイルの作成**
```bash
cat > .env << 'EOF'
# AlmaLinux Ruby Webhook Server 環境変数

# Dify API設定
DIFY_API_KEY=your_dify_api_key_here
DIFY_API_URL=https://api.iruka.dev/v1/chat-messages

# GitHub設定
GITHUB_TOKEN=your_github_token_here

# Sinatra設定
RACK_ENV=production
PORT=4567

# ログ設定
LOG_LEVEL=INFO
LOG_FILE=./logs/webhook.log
ERROR_LOG_FILE=./logs/error.log
EOF
```

### **2-5. メインアプリケーションファイルの作成**
```bash
cat > app.rb << 'EOF'
#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'sinatra'
require 'httparty'
require 'json'
require 'base64'
require 'logger'
require 'dotenv/load'
require 'securerandom'

# 設定
configure do
  set :port, ENV['PORT'] || 4567
  set :bind, '0.0.0.0'
  set :environment, ENV['RACK_ENV'] || 'production'
  
  # ログ設定
  log_file = ENV['LOG_FILE'] || './logs/webhook.log'
  error_log_file = ENV['ERROR_LOG_FILE'] || './logs/error.log'
  
  # ディレクトリが存在しない場合は作成
  FileUtils.mkdir_p(File.dirname(log_file))
  FileUtils.mkdir_p(File.dirname(error_log_file))
  
  # ログレベル設定
  log_level = case ENV['LOG_LEVEL']&.upcase
              when 'DEBUG' then Logger::DEBUG
              when 'INFO' then Logger::INFO
              when 'WARN' then Logger::WARN
              when 'ERROR' then Logger::ERROR
              else Logger::INFO
              end
  
  # アプリケーションログ
  @@app_logger = Logger.new(log_file, 'daily')
  @@app_logger.level = log_level
  @@app_logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
  end
  
  # エラーログ
  @@error_logger = Logger.new(error_log_file, 'daily')
  @@error_logger.level = Logger::ERROR
  @@error_logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
  end
  
  # 標準出力ログ
  @@stdout_logger = Logger.new(STDOUT)
  @@stdout_logger.level = log_level
  @@stdout_logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
  end
end

# 環境変数チェック
required_env_vars = ['DIFY_API_KEY', 'DIFY_API_URL', 'GITHUB_TOKEN']
required_env_vars.each do |var|
  unless ENV[var]
    puts "環境変数 #{var} が設定されていません"
    exit 1
  end
end

# ヘルパーメソッド
def log_info(message)
  @@app_logger.info(message)
  @@stdout_logger.info(message)
end

def log_error(message)
  @@app_logger.error(message)
  @@error_logger.error(message)
  @@stdout_logger.error(message)
end

def log_debug(message)
  @@app_logger.debug(message)
  @@stdout_logger.debug(message)
end

def generate_request_id
  "req_#{Time.now.to_i}_#{SecureRandom.hex(4)}"
end

# リクエストログ
before do
  @start_time = Time.now
  @request_id = generate_request_id
  
  log_info("Request: #{request.request_method} #{request.path} from #{request.ip} - Request ID: #{@request_id}")
end

after do
  duration = ((Time.now - @start_time) * 1000).round(2)
  log_info("Response: #{response.status} in #{duration}ms - Request ID: #{@request_id}")
end

# ヘルスチェックエンドポイント
get '/health' do
  content_type :json
  
  health_data = {
    status: 'healthy',
    timestamp: Time.now.iso8601,
    ruby_version: RUBY_VERSION,
    rack_env: ENV['RACK_ENV'],
    uptime: Time.now.to_i - @@start_time.to_i,
    request_id: @request_id
  }
  
  log_info("Health check: #{health_data} - Request ID: #{@request_id}")
  health_data.to_json
end

# メインWebhookエンドポイント
post '/webhook' do
  content_type :json
  
  log_info("Webhook processing started - Request ID: #{@request_id}")
  
  begin
    # JSONデータを取得
    request.body.rewind
    payload = JSON.parse(request.body.read)
    
    action = payload['action']
    label = payload['label'] || {}
    pull_request = payload['pull_request']
    
    # リクエスト内容をログ
    log_info("Webhook payload - Request ID: #{@request_id}, Action: #{action}, " \
             "Label: #{label['name']}, PR: #{pull_request&.dig('number')}")
    
    # cto-reviewラベルが付いた場合のみ処理
    if action == 'labeled' && label['name'] == 'cto-review'
      log_info("Processing CTO review for PR ##{pull_request['number']} - Request ID: #{@request_id}")
      
      # outline.mdを取得
      content = fetch_outline_content(pull_request, @request_id)
      log_info("Fetched outline.md (#{content.length} chars) - Request ID: #{@request_id}")
      
      # Dify APIでレビュー生成
      review = call_dify_api(content, @request_id)
      log_info("Generated CTO review (#{review.length} chars) - Request ID: #{@request_id}")
      
      # PRにコメント投稿
      post_pr_comment(pull_request, review, @request_id)
      log_info("Posted comment to PR - Request ID: #{@request_id}")
      
      duration = ((Time.now - @start_time) * 1000).round(2)
      log_info("Webhook processing completed in #{duration}ms - Request ID: #{@request_id}")
      
      {
        success: true,
        message: 'CTO review completed',
        request_id: @request_id,
        duration: "#{duration}ms"
      }.to_json
    else
      log_info("No action needed - Request ID: #{@request_id}")
      {
        message: 'No action needed',
        request_id: @request_id,
        action: action,
        label_name: label['name']
      }.to_json
    end
    
  rescue JSON::ParserError => e
    log_error("JSON parse error - Request ID: #{@request_id}, Error: #{e.message}")
    status 400
    { error: 'Invalid JSON', request_id: @request_id }.to_json
    
  rescue => e
    duration = ((Time.now - @start_time) * 1000).round(2)
    log_error("Webhook processing failed - Request ID: #{@request_id}, " \
              "Error: #{e.message}, Duration: #{duration}ms")
    log_error("Backtrace: #{e.backtrace.join("\n")}")
    
    status 500
    {
      error: e.message,
      request_id: @request_id,
      duration: "#{duration}ms"
    }.to_json
  end
end

# GitHub APIからoutline.mdを取得
def fetch_outline_content(pull_request, request_id)
  repo = pull_request['base']['repo']['full_name']
  sha = pull_request['head']['sha']
  url = "https://api.github.com/repos/#{repo}/contents/outline.md?ref=#{sha}"
  
  log_info("Fetching outline.md from GitHub - Request ID: #{request_id}")
  
  headers = {
    'Authorization' => "token #{ENV['GITHUB_TOKEN']}",
    'Accept' => 'application/vnd.github.v3+json',
    'User-Agent' => 'AlmaLinux-CTO-Review-Bot-Ruby/1.0'
  }
  
  response = HTTParty.get(url, headers: headers, timeout: 30)
  
  unless response.success?
    raise "GitHub API error: #{response.code} #{response.message} - #{response.body}"
  end
  
  data = response.parsed_response
  
  unless data['content']
    raise 'outline.md not found or empty'
  end
  
  # Base64デコード
  Base64.decode64(data['content'])
end

# Dify APIを呼び出してCTOレビューを生成
def call_dify_api(content, request_id)
  log_info("Calling Dify API - Request ID: #{request_id}")
  
  payload = {
    inputs: {},
    query: "以下のoutline.mdファイルをCTOの視点でレビューしてください。技術的な観点、ビジネス的な観点、リスク管理の観点から建設的なフィードバックを提供してください:\n\n#{content}",
    response_mode: 'streaming',
    user: 'almalinux-ruby-cto-bot'
  }
  
  headers = {
    'Authorization' => "Bearer #{ENV['DIFY_API_KEY']}",
    'Content-Type' => 'application/json',
    'User-Agent' => 'AlmaLinux-CTO-Review-Bot-Ruby/1.0'
  }
  
  # ストリーミングレスポンスを処理
  result = ''
  
  HTTParty.post(ENV['DIFY_API_URL'], 
    headers: headers,
    body: payload.to_json,
    timeout: 300,
    stream_body: true
  ) do |fragment|
    lines = fragment.split("\n")
    lines.each do |line|
      if line.start_with?('data: ')
        begin
          json_str = line[6..-1].strip
          next if json_str.empty? || json_str == '[DONE]'
          
          data = JSON.parse(json_str)
          result += data['answer'] if data['answer']
        rescue JSON::ParserError
          # JSON解析エラーは無視
          log_debug("JSON parse warning - Request ID: #{request_id}")
        end
      end
    end
  end
  
  if result.strip.empty?
    raise 'No valid response received from Dify API'
  end
  
  result.strip
end

# PRにコメントを投稿
def post_pr_comment(pull_request, review, request_id)
  repo = pull_request['base']['repo']['full_name']
  pr_number = pull_request['number']
  
  timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S JST')
  
  comment_body = <<~COMMENT
    ## 🎯 CTO Review for outline.md

    #{review}

    ---
    *このレビューはDify CTO Review Botによって自動生成されました*  
    *生成時刻: #{timestamp}*  
    *処理サーバー: AlmaLinux (Ruby)*  
    *Request ID: #{request_id}*
  COMMENT
  
  url = "https://api.github.com/repos/#{repo}/issues/#{pr_number}/comments"
  
  headers = {
    'Authorization' => "token #{ENV['GITHUB_TOKEN']}",
    'Content-Type' => 'application/json',
    'Accept' => 'application/vnd.github.v3+json',
    'User-Agent' => 'AlmaLinux-CTO-Review-Bot-Ruby/1.0'
  }
  
  payload = { body: comment_body }
  
  log_info("Posting comment to GitHub - Request ID: #{request_id}")
  
  response = HTTParty.post(url, 
    headers: headers, 
    body: payload.to_json, 
    timeout: 30
  )
  
  unless response.success?
    raise "GitHub API error: #{response.code} #{response.message} - #{response.body}"
  end
  
  response.parsed_response
end

# エラーハンドラー
not_found do
  content_type :json
  { error: 'Not found', request_id: @request_id }.to_json
end

error do
  content_type :json
  log_error("Internal server error: #{env['sinatra.error'].message}")
  { error: 'Internal server error', request_id: @request_id }.to_json
end

# アプリケーション起動時の処理
@@start_time = Time.now

if __FILE__ == $0
  log_info("Starting AlmaLinux Ruby Webhook Server on port #{settings.port}")
  log_info("Environment: #{settings.environment}")
  log_info("Ruby version: #{RUBY_VERSION}")
  
  run!
end
EOF
```

### **2-6. Puma設定ファイルの作成**
```bash
cat > config/puma.rb << 'EOF'
#!/usr/bin/env puma

# Puma設定ファイル

# ディレクトリ作成
directory '/opt/ruby-webhook-server'

# 環境設定
environment ENV.fetch('RACK_ENV', 'production')

# バインド設定
bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 4567)}"

# ワーカー設定
workers ENV.fetch('WEB_CONCURRENCY', 2)
threads_count = ENV.fetch('RAILS_MAX_THREADS', 5)
threads threads_count, threads_count

# プリロード
preload_app!

# PIDファイル
pidfile './tmp/puma.pid'

# 状態ファイル
state_path './tmp/puma.state'

# ログ設定
stdout_redirect './logs/puma-stdout.log', './logs/puma-stderr.log', true

# デーモン設定（systemdで管理する場合はfalse）
daemonize false

# タイムアウト設定
worker_timeout 60

# ワーカー起動時の処理
on_worker_boot do
  # データベース接続等があればここで設定
end

# 再起動時の処理
on_restart do
  puts 'Puma is restarting...'
end
EOF
```

### **2-7. Rackupファイルの作成**
```bash
cat > config.ru << 'EOF'
require_relative 'app'
run Sinatra::Application
EOF
```

## 🔧 **フェーズ3: systemdサービス設定**

### **3-1. systemdサービスファイルの作成**
```bash
sudo tee /etc/systemd/system/ruby-webhook-server.service << 'EOF'
[Unit]
Description=Ruby Webhook Server for Dify CTO Review
After=network.target

[Service]
Type=simple
User=shibuya_yumi
Group=shibuya_yumi
WorkingDirectory=/opt/ruby-webhook-server
Environment=RACK_ENV=production
ExecStart=/usr/local/bin/bundle exec puma -C config/puma.rb
ExecReload=/bin/kill -s USR1 $MAINPID
Restart=always
RestartSec=5

# ログ設定
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ruby-webhook-server

[Install]
WantedBy=multi-user.target
EOF
```

### **3-2. サービスの有効化**
```bash
# systemdを再読み込み
sudo systemctl daemon-reload

# サービスを有効化
sudo systemctl enable ruby-webhook-server

# サービス状態確認
sudo systemctl status ruby-webhook-server
```

## 🧪 **フェーズ4: テストと起動**

### **4-1. 環境変数の設定**
```bash
# .envファイルを編集
nano .env

# 以下の値を実際の値に変更：
# DIFY_API_KEY=your_actual_dify_api_key
# DIFY_API_URL=https://api.iruka.dev/v1/chat-messages
# GITHUB_TOKEN=your_actual_github_token
```

### **4-2. 開発モードでテスト**
```bash
# 開発モードで起動
bundle exec ruby app.rb

# 別のターミナルでテスト
curl http://localhost:4567/health
```

### **4-3. Pumaでテスト**
```bash
# Pumaで起動
bundle exec puma -C config/puma.rb

# テスト
curl http://localhost:4567/health
```

### **4-4. systemdサービスで本番起動**
```bash
# サービスを開始
sudo systemctl start ruby-webhook-server

# 状態確認
sudo systemctl status ruby-webhook-server

# ログ確認
sudo journalctl -u ruby-webhook-server -f
tail -f logs/webhook.log
```

## 🌐 **フェーズ5: GitHub Webhook設定**

### **5-1. 外部アクセスの確認**
```bash
# サーバーのIPアドレス確認
ip addr show

# 外部からのアクセステスト
curl http://YOUR_ALMALINUX_IP:4567/health
```

### **5-2. GitHubでWebhook設定**
1. GitHubリポジトリの **Settings** → **Webhooks**
2. **Add webhook** をクリック
3. 設定：
   - **Payload URL**: `http://YOUR_ALMALINUX_IP:4567/webhook`
   - **Content type**: `application/json`
   - **Events**: `Pull requests` を選択
   - **Active**: チェック

## 📊 **監視とメンテナンス**

### **6-1. ログ監視**
```bash
# リアルタイムログ
tail -f logs/webhook.log
tail -f logs/error.log

# systemdログ
sudo journalctl -u ruby-webhook-server -f

# Pumaログ
tail -f logs/puma-stdout.log
tail -f logs/puma-stderr.log
```

### **6-2. サービス管理**
```bash
# サービス再起動
sudo systemctl restart ruby-webhook-server

# サービス停止
sudo systemctl stop ruby-webhook-server

# サービス状態確認
sudo systemctl status ruby-webhook-server

# Pumaの優雅な再起動
sudo systemctl reload ruby-webhook-server
```

### **6-3. パフォーマンス調整**
```ruby
# config/puma.rbで調整
workers ENV.fetch('WEB_CONCURRENCY', 4)  # ワーカー数を増加
threads 1, 16  # スレッド数を調整
```

## 💎 **Ruby版の特徴**

### **メリット**
- ✅ **馴染みのある言語**: Rubyでの開発経験を活用
- ✅ **Sinatra**: 軽量で高性能なWebフレームワーク
- ✅ **Puma**: 高性能なWebサーバー
- ✅ **HTTParty**: 使いやすいHTTPクライアント
- ✅ **豊富なGem**: Rubyエコシステムを活用

### **運用面**
- ✅ **systemdサービス**: 自動起動とプロセス管理
- ✅ **詳細なログ**: アプリケーション、エラー、アクセスログ
- ✅ **優雅な再起動**: USR1シグナルでの無停止再起動
- ✅ **設定の外部化**: .envファイルでの環境変数管理

これでRuby版のWebhookサーバーが構築できます！

まずはRuby環境の確認から始めましょう：

```bash
ruby --version
gem --version
bundler --version
```

この結果を教えてください！
