# Performance Tuning Guide

このガイドでは、kuro のパフォーマンスを最適化するための設定と手法を説明します。kuro は高速に設計されていますが、使用環境や用途に応じてさらにパフォーマンスを向上させることができます。

## 基本的なパフォーマンス設定

### スクロールバックのサイズ

スクロールバックバッファのサイズを適切に設定することで、メモリ使用量とパフォーマンスのバランスを調整できます。

```elisp
;; デフォルト設定 (推奨)
(setq kuro-scrollback-size 10000)

;; 大量の出力を扱う場合 (AI エージェントなど)
(setq kuro-scrollback-size 100000)

;; メモリを節約する場合
(setq kuro-scrollback-size 1000)
```

**トレードオフ**:
- 大きな値: 過去の出力を遡れるが、メモリ使用量が増加
- 小さな値: メモリ効率が良いが、履歴が制限される

### 更新頻度の調整

画面更新の頻度を調整して、CPU 使用率と表示品質のバランスを取ります。

```elisp
;; デフォルトの更新間隔 (ミリ秒)
(setq kuro-update-interval 16)  ; 約 60 FPS

/* 高速な出力時のスロットリング */
(setq kuro-update-throttle 10)  ; 10ms 間隔で更新

/* 1回の更新で処理する最大行数 */
(setq kuro-max-update-lines 1000)
```

**使用例**:

```elisp
;; AI エージェントからの高速出力用
(setq kuro-update-throttle 50)     ; 更新頻度を下げる
(setq kuro-max-update-lines 5000) ; まとめて処理

;; 対話的な操作用
(setq kuro-update-throttle 5)      ; 頻繁に更新
(setq kuro-max-update-lines 100)   ; 少しずつ処理
```

## Dirty Line Tracking の最適化

kuro は Dirty Line Tracking を使用して、変更された行のみを更新します。この挙動を微調整できます。

```elisp
;; Dirty Line Tracking の有効化 (デフォルト: 有効)
(setq kuro-dirty-line-tracking t)

;; 変更検知の感度
(setq kuro-dirty-threshold 1)  ; 1文字以上の変更を検知

;; バッチ更新のサイズ
(setq kuro-batch-update-size 50)  ; 50行単位でバッチ更新
```

## メモリ管理

### メモリプールの設定

頻繁に使用するデータ構造のメモリプールサイズを調整します。

```elisp
;; グリッドセルのメモリプールサイズ
(setq kuro-cell-pool-size 10000)

;; ラインバッファのプールサイズ
(setq kuro-line-pool-size 1000)
```

### ガベージコレクションの最適化

Emacs の GC 頻度を調整して、ターミナルのパフォーマンスに影響を与えないようにします。

```elisp
;; GC 閾値を大きくする (メモリ余裕がある場合)
(setq gc-cons-threshold (* 100 1024 1024))  ; 100MB

;; kuro 実行中のみ GC 閾値を変更する場合
(add-hook 'kuro-mode-hook
          (lambda ()
            (setq gc-cons-threshold (* 100 1024 1024))))
(add-hook 'kuro-quit-hook
          (lambda ()
            (setq gc-cons-threshold (* 16 1024 1024))))
```

## 使用環境別の最適化

### AI エージェント用の設定

AI エージェントからの大量出力をスムーズに処理するための設定です。

```elisp
(use-package kuro
  :config
  ;; 大容量のスクロールバック
  (setq kuro-scrollback-size 100000)

  ;; 更新のスロットリング
  (setq kuro-update-throttle 50)
  (setq kuro-max-update-lines 5000)

  ;; バッファの自動保存を無効化 (パフォーマンス向上)
  (setq kuro-auto-save-buffer nil)

  ;; 非同期レンダリングの有効化
  (setq kuro-async-rendering t))
```

### 開発環境用の設定

日常的な開発作業用のバランスの取れた設定です。

```elisp
(use-package kuro
  :config
  ;; 標準的なスクロールバックサイズ
  (setq kuro-scrollback-size 10000)

  ;; スムーズな更新
  (setq kuro-update-throttle 16)
  (setq kuro-max-update-lines 1000)

  ;; 自動スクロールの有効化
  (setq kuro-auto-scroll t))
```

### 低スペックマシン用の設定

メモリや CPU が限られている環境向けの設定です。

```elisp
(use-package kuro
  :config
  ;; 小さなスクロールバック
  (setq kuro-scrollback-size 1000)

  ;; 少し遅めの更新
  (setq kuro-update-throttle 100)
  (setq kuro-max-update-lines 500)

  ;; メモリプールの縮小
  (setq kuro-cell-pool-size 5000)
  (setq kuro-line-pool-size 500))
```

## Rust コア側の最適化

### リリースビルドの最適化

Rust コアをビルドする際、最適化レベルを調整できます。

```bash
# 標準的なリリースビルド
cargo build --release

# 最適化レベルの指定 (Cargo.toml)
[profile.release]
opt-level = 3        # 最適化レベル (0-3、s、z)
lto = true           # Link-Time Optimization
codegen-units = 1    # コード生成単語の削減
```

### プロファイリング

ボトルネックを特定するためにプロファイリングを行います。

```bash
# CPU プロファイリング
cargo install flamegraph
cargo flamegraph --bin kuro-core

# メモリプロファイリング
cargo install cargo-valgrind
cargo valgrind
```

## ベンチマークの取得

パフォーマンス改善の効果を測定するためにベンチマークを取得します。

```bash
# ベンチマークの実行
cd rust-core
cargo bench

# 結果の比較
cargo bench -- --save-baseline main
cargo bench -- --baseline main
```

## トラブルシューティング

### 表示が遅れる場合

**症状**: 高速な出力時に表示が追いつかない

**解決策**:

```elisp
;; 更新頻度を下げる
(setq kuro-update-throttle 50)

;; まとめて処理する行数を増やす
(setq kuro-max-update-lines 5000)

;; 非同期レンダリングを有効化
(setq kuro-async-rendering t)
```

### Emacs が重くなる場合

**症状**: kuro 使用中に Emacs 全体が重くなる

**解決策**:

```elisp
;; GC 閾値を調整
(setq gc-cons-threshold (* 100 1024 1024))

;; Redisplay 間隔を調整
(setq redisplay-dont-pause t)

;; バイトコンパイルを有効化
(setq kuro-enable-byte-compile t)
```

### メモリ使用量が多い場合

**症状**: メモリ使用量が過剰に増加

**解決策**:

```elisp
;; スクロールバックサイズを削減
(setq kuro-scrollback-size 5000)

;; メモリプールサイズを調整
(setq kuro-cell-pool-size 5000)
(setq kuro-line-pool-size 500)

;; 定期的なメモリ解放を有効化
(setq kuro-auto-gc t)
(setq kuro-gc-interval 300)  ; 5分ごと
```

## パフォーマンス監視

パフォーマンスを監視するためのツールと設定：

```elisp
;; パフォーマンス情報の表示
(setq kuro-show-performance-info t)

;; パフォーマンス統計の取得
M-x kuro-show-performance-stats

;; プロファイリングの開始
M-x kuro-start-profiling

;; プロファイリングの停止と結果表示
M-x kuro-stop-profiling
```

## ベストプラクティス

1. **環境に応じた設定**: 使用環境に合わせて適切な設定を選択
2. **ベンチマークの取得**: 変更前後でパフォーマンスを比較
3. **ボトルネックの特定**: プロファイリングを使用して問題箇所を特定
4. **段階的な調整**: 一度に複数の設定を変更せず、一つずつ調整

## 関連ドキュメント

- [Performance Strategy](../explanation/performance-strategy.md) — パフォーマンス戦略の詳細
- [Architecture](../explanation/architecture.md) — アーキテクチャの理解
- [AI Agent Compatibility](../explanation/ai-agent-compatibility.md) — AI エージェント対応について
