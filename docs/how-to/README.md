# ハウツーガイド

**タスク指向**: 特定の問題を解決するための実践的なレシピです。

Diataxis フレームワークにおけるハウツーガイドは、特定の目的を達成するための具体的な手順を提供します。チュートリアルとは異なり、読者がすでに基本的な知識を持っていることを前提とし、「これをやりたい」という明確なゴールに対して最短経路で解決策を示します。

## ハウツーガイド一覧

### インストールと設定

- **[Installation Guide](./install.md)** — 各プラットフォームでのインストール方法
  - Linux (Ubuntu, Debian, Arch, Fedora)
  - macOS (Homebrew, Nix)
  - Windows (WSL2)
  - トラブルシューティング

- **[Configuration Guide](./configure.md)** — 詳細な設定方法
  - 基本的な設定構造
  - 設定項目一覧
  - use-package を使用した設定
  - プロファイル設定
  - バッファローカル設定
  - 設定の検証とデバッグ

- **[Shell Integration Guide](./shell-integration.md)** — 各種シェルとの統合
  - Zsh との統合
  - Bash との統合
  - Fish との統合
  - Nu (Nushell) との統合
  - 共通の統合機能

### パフォーマンスと最適化

- **[Performance Tuning Guide](./performance-tuning.md)** — パフォーマンスの最適化

### トラブルシューティング

- **[Troubleshooting Guide](./troubleshooting.md)** — 一般的な問題と解決方法
  - インストール関連の問題
  - 表示関連の問題
  - パフォーマンス関連の問題
  - 入力/出力関連の問題
  - クラッシュとエラー
  - デバッグの手法
  - 基本的なパフォーマンス設定
  - Dirty Line Tracking の最適化
  - メモリ管理
  - 使用環境別の最適化
  - Rust コア側の最適化
  - ベンチマークの取得

### 開発者向けガイド (実装後に追加予定)

- **新しいエスケープシーケンスハンドラの追加方法** — Rust コア側に新規エスケープシーケンスの処理を実装する手順
- **Kitty Graphics 対応アプリのテスト方法** — Kitty Graphics プロトコルを使用するアプリケーションの動作確認手順
- **カスタム Face テーマの作成方法** — Elisp レンダラーの Face 定義をカスタマイズしてオリジナルテーマを作成する手順
- **トラブルシューティング: 表示が崩れた場合の対処法** — レンダリングの不具合を診断し修正するための実践的な手順

## ガイドの使い方

ハウツーガイドは、特定の課題を解決するために参照することを想定しています。例えば：

- 「kuro を macOS にインストールしたい」→ [Installation Guide](./install.md)
- 「AI エージェントからの大量出力をスムーズに処理したい」→ [Performance Tuning Guide](./performance-tuning.md)
- 「Zsh のプロンプトをカスタマイズしたい」→ [Shell Integration Guide](./shell-integration.md)

## 前提条件

ハウツーガイドを読む前に、以下のチュートリアルを完了していることをお勧めします：

1. [Getting Started](../tutorials/getting-started.md) — インストールと初回起動
2. [Basic Usage and Key Bindings](../tutorials/basic-usage.md) — 基本的な使い方

## 貢献

新しいハウツーガイドの追加や既存のガイドの改善は歓迎です。貢献方法の詳細については、リポジトリの CONTRIBUTING.md (実装後に追加予定) を参照してください。
