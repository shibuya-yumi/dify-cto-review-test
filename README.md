# Dify CTO Review Bot

DifyのCTOレビューbotのテスト用リポジトリ

GitHub Pull RequestにおけるCTOレビューをAIで自動化し、`outline.md`ファイルに対して戦略的で実践的なフィードバックを提供します。

## 🎯 機能

- **PRラベル検知**: `cto-review`ラベルが追加された時に自動実行
- **outline.md分析**: プロジェクト概要書を包括的に分析
- **CTOの視点**: 技術戦略、ビジネス価値、リスク管理の観点からレビュー
- **自動コメント**: PRに美しいMarkdown形式でレビューコメントを投稿

## 🚀 セットアップ

### 1. 環境変数の設定

GitHub Secretsで以下の環境変数を設定してください：

```
DIFY_API_KEY=your_dify_api_key_here
DIFY_API_URL=https://api.dify.ai/v1/chat-messages
```

詳細な設定方法は [docs/SETUP.md](docs/SETUP.md) を参照してください。

### 2. 使用方法

1. PRに`outline.md`ファイルを含める
2. PRに`cto-review`ラベルを追加
3. GitHub Actionsが自動実行される
4. CTOレビューコメントがPRに投稿される

## 🧪 テスト

### ローカルテスト

```bash
# 環境変数を設定（.envファイルを作成）
cp env.example .env
# .envファイルを編集して実際の値を設定

# ローカルテストを実行
./scripts/test-local.sh
```

### GitHub Actionsデバッグ

```bash
# ワークフローのデバッグ
./scripts/debug-workflow.sh [PR番号]
```

## 📁 プロジェクト構造

```
dify-cto-review-test/
├── .github/workflows/
│   └── dify-cto-review.yml     # GitHub Actionsワークフロー
├── scripts/
│   ├── review-outline.sh       # outline.mdレビュースクリプト
│   ├── validate-env.sh         # 環境変数検証スクリプト
│   ├── error-handler.sh        # エラーハンドリングユーティリティ
│   ├── test-local.sh          # ローカルテストスクリプト
│   └── debug-workflow.sh      # ワークフローデバッグスクリプト
├── docs/
│   └── SETUP.md               # セットアップガイド
├── outline.md                 # プロジェクト概要書（サンプル）
├── env.example               # 環境変数設定例
└── README.md                 # このファイル
```

## 🎨 CTOレビューの観点

このbotは以下の観点からレビューを行います：

### 1. 技術戦略・アーキテクチャ
- 技術選択の妥当性と将来性
- アーキテクチャの拡張性とメンテナンス性
- 技術的リスクの評価

### 2. プロジェクト管理・実装計画
- 実装フェーズの現実性と優先順位
- リソース配分の妥当性
- スケジュールの実現可能性

### 3. ビジネス価値・ROI
- 期待される効果の妥当性
- コスト対効果の分析
- ビジネスインパクトの評価

### 4. リスク管理・品質保証
- 潜在的なリスクの特定
- 品質保証戦略
- 運用・保守の考慮

### 5. 組織・チーム体制
- 必要なスキルセットと人材
- チーム体制の提案
- 知識共有・ドキュメント化

## 🔧 トラブルシューティング

### よくある問題

#### 1. ワークフローが実行されない
- PRに`cto-review`ラベルが追加されているか確認
- ワークフローファイルの構文エラーがないか確認

#### 2. 環境変数エラー
- GitHub Secretsで`DIFY_API_KEY`と`DIFY_API_URL`が設定されているか確認
- APIキーが有効で権限があるか確認

#### 3. outline.mdファイルが見つからない
- PRにoutline.mdファイルが含まれているか確認
- ファイル名が正確か確認（大文字小文字を含む）

#### 4. Dify API呼び出しエラー
- APIエンドポイントURLが正しいか確認
- Difyサービスの動作状況を確認
- APIキーの有効期限を確認

### デバッグ方法

1. **ローカルテスト**を実行して基本的な動作を確認
2. **GitHub Actionsログ**を確認してエラーの詳細を把握
3. **環境変数検証スクリプト**で設定を確認

## 📚 ドキュメント

- [セットアップガイド](docs/SETUP.md) - 詳細な設定手順
- [env.example](env.example) - 環境変数設定例

## 🤝 コントリビューション

1. このリポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add some amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. Pull Requestを作成

## 📄 ライセンス

このプロジェクトはMITライセンスの下で公開されています。

## 🙋‍♂️ サポート

問題や質問がある場合は、GitHubのIssuesを作成してください。

---

**Dify CTO Review Bot** - AIを活用したプロジェクトレビューの自動化