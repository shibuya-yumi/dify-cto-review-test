# Self-hosted Runner セットアップガイド

GitHub ActionsのIPアドレス制限を回避するため、Self-hosted Runnerを使用する方法です。

## 🎯 Self-hosted Runnerとは

- 自分のサーバーやローカルマシンでGitHub Actionsを実行
- GitHub.comのIPアドレス制限を回避
- より柔軟な環境設定が可能

## 🛠️ セットアップ手順

### **1. Runnerの登録**

1. GitHubリポジトリの **Settings** → **Actions** → **Runners** に移動
2. **New self-hosted runner** をクリック
3. OS（macOS/Linux/Windows）を選択
4. 表示されるコマンドを実行

```bash
# 例: macOS/Linux の場合
mkdir actions-runner && cd actions-runner
curl -o actions-runner-osx-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-osx-x64-2.311.0.tar.gz
tar xzf ./actions-runner-osx-x64-2.311.0.tar.gz

# 設定
./config.sh --url https://github.com/[USERNAME]/[REPO] --token [TOKEN]

# 実行
./run.sh
```

### **2. 必要な依存関係のインストール**

```bash
# macOS
brew install jq curl

# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y jq curl

# CentOS/RHEL
sudo yum install -y jq curl
```

### **3. 環境変数の設定**

Self-hosted Runnerでも同じSecrets（環境変数）が使用できます：

- `DIFY_API_KEY`
- `DIFY_API_URL`
- `GITHUB_TOKEN`

### **4. ワークフローファイルの使用**

`.github/workflows/dify-cto-review-selfhosted.yml` を使用：

```yaml
runs-on: self-hosted  # これが重要
```

## 🚀 実行方法

1. Self-hosted Runnerを起動
```bash
cd actions-runner
./run.sh
```

2. PRに `cto-review` ラベルを付与

3. Self-hosted Runner上でワークフローが実行される

## 🔧 トラブルシューティング

### **Runner が認識されない**
```bash
# Runnerの状態確認
./config.sh --check

# 再登録
./config.sh --url https://github.com/[USERNAME]/[REPO] --token [NEW_TOKEN]
```

### **権限エラー**
```bash
# スクリプトに実行権限を付与
chmod +x scripts/*.sh
```

### **依存関係エラー**
```bash
# 必要なツールの確認
which jq curl git

# 不足している場合はインストール
```

## 💡 メリット・デメリット

### **メリット**
- ✅ IPアドレス制限を完全に回避
- ✅ ローカル環境での実行（デバッグが容易）
- ✅ カスタム環境の構築が可能

### **デメリット**
- ❌ 常時起動が必要
- ❌ セキュリティ管理が必要
- ❌ メンテナンスコスト

## 🔄 代替案

Self-hosted Runnerが難しい場合：

1. **GitHub Codespaces** の利用
2. **外部Webhook** サーバーの構築
3. **VPN経由** でのアクセス

## 📞 サポート

Self-hosted Runnerの詳細は[GitHub公式ドキュメント](https://docs.github.com/en/actions/hosting-your-own-runners)を参照してください。
