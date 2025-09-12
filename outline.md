# プロジェクト概要書

## 1. プロジェクト名
Dify CTO Review Bot

## 2. 目的
GitHub Pull RequestにおけるコードレビューをAIで自動化し、CTOの視点から建設的なフィードバックを提供する。

## 3. 主な機能
- PRラベル検知による自動トリガー
- GitHub APIを使用したPR情報取得
- Dify APIを活用したAIレビュー
- 自動コメント投稿

## 4. 技術スタック
- GitHub Actions
- Bash スクリプト
- Dify API
- GitHub API

## 5. アーキテクチャ
```
GitHub PR (ラベル追加) 
  ↓
GitHub Actions ワークフロー
  ↓
PR情報・差分取得
  ↓
Dify API (CTOレビュー生成)
  ↓
PRコメント投稿
```

## 6. 実装フェーズ
1. 基本ワークフロー構築
2. API統合
3. エラーハンドリング
4. テスト・デバッグ

## 7. 期待される効果
- レビュー品質の向上
- レビュー時間の短縮
- 一貫したレビュー基準の適用
