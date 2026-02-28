# kuro ドキュメント

Rust製コアエンジンによるEmacs用高速ターミナルエミュレータ

## ドキュメント構成

本ドキュメントは [Diataxis フレームワーク](https://diataxis.fr/) に基づいて構成されています。Diataxis は、ドキュメントを以下の4象限に分類することで、読者のニーズに応じた適切な情報提供を実現するフレームワークです。

| | 学習時 | 実務時 |
|---|---|---|
| **実践的** | Tutorials (チュートリアル) | How-to (ハウツーガイド) |
| **理論的** | Explanation (解説) | Reference (リファレンス) |

## カテゴリ

### [`explanation/`](explanation/) — 解説

**理解指向**: アーキテクチャ・設計判断・パフォーマンス戦略の解説。「なぜそうなっているのか」を理解したい読者向けのドキュメントです。

### [`reference/`](reference/) — リファレンス

**情報指向**: Rust コンポーネント仕様・Elisp レンダラー仕様・データフロー定義。正確な技術情報を参照したい読者向けのドキュメントです。

### [`tutorials/`](tutorials/) — チュートリアル

**学習指向**: 初めて kuro を使う方がステップバイステップで学ぶためのガイドです。

- [`Getting Started`](tutorials/getting-started.md) — インストールと初回起動
- [`Basic Usage and Key Bindings`](tutorials/basic-usage.md) — 基本的な使い方とキーバインド
- [`First Customization`](tutorials/first-customization.md) — 最初のカスタマイズ

### [`how-to/`](how-to/) — ハウツーガイド

**タスク指向**: 特定の目的を達成するための実践的な手順書です。

- [`Installation`](how-to/install.md) — 各プラットフォームでのインストール方法
- [`Configuration`](how-to/configure.md) — 詳細な設定方法
- [`Shell Integration`](how-to/shell-integration.md) — 各種シェルとの統合
- [`Performance Tuning`](how-to/performance-tuning.md) — パフォーマンスの最適化

## ドキュメント一覧

### 解説 (Explanation)

- [`explanation/architecture.md`](./explanation/architecture.md) — 全体アーキテクチャ
- [`explanation/design-decisions.md`](./explanation/design-decisions.md) — 設計判断とトレードオフ
- [`explanation/performance-strategy.md`](./explanation/performance-strategy.md) — パフォーマンス戦略
- [`explanation/ai-agent-compatibility.md`](./explanation/ai-agent-compatibility.md) — AI Agent 出力への対応戦略
- [`explanation/comparison.md`](./explanation/comparison.md) — 既存ターミナルエミュレータとの比較

### リファレンス (Reference)

- [`reference/rust-core/grid.md`](./reference/rust-core/grid.md) — 仮想スクリーン (Grid) 仕様
- [`reference/rust-core/parser.md`](./reference/rust-core/parser.md) — VTE パーサー仕様
- [`reference/rust-core/kitty-graphics.md`](./reference/rust-core/kitty-graphics.md) — Kitty Graphics Protocol 処理仕様
- [`reference/rust-core/ffi-interface.md`](./reference/rust-core/ffi-interface.md) — Emacs FFI インターフェース仕様
- [`reference/elisp/renderer.md`](./reference/elisp/renderer.md) — Elisp レンダラー仕様
- [`reference/elisp/module-bridge.md`](./reference/elisp/module-bridge.md) — モジュールブリッジ仕様
- [`reference/data-flow.md`](./reference/data-flow.md) — データフロー定義

### チュートリアル (Tutorials)

- [`tutorials/README.md`](./tutorials/README.md) — チュートリアル (実装後に追加予定)

### ハウツーガイド (How-to)

- [`how-to/README.md`](./how-to/README.md) — ハウツーガイド (実装後に追加予定)
