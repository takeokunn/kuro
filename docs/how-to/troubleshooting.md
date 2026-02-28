# Troubleshooting Guide

このガイドでは、kuro の使用中に発生する可能性のある問題とその解決方法を説明します。

## 目次

1. [インストール関連の問題](#インストール関連の問題)
2. [表示関連の問題](#表示関連の問題)
3. [パフォーマンス関連の問題](#パフォーマンス関連の問題)
4. [入力/出力関連の問題](#入力出力関連の問題)
5. [クラッシュとエラー](#クラッシュとエラー)

## インストール関連の問題

### 動的モジュールがロードできない

**エラーメッセージ**:
```
Error: Cannot open shared object file: No such file or directory
```

**原因**: 動的ライブラリのパスが正しく設定されていない、またはライブラリが存在しません。

**解決策**:

1. ライブラリが存在するか確認:
```bash
# Linux
ls -l /usr/local/lib/libkuro_core.so

# macOS
ls -l /usr/local/lib/libkuro_core.dylib
```

2. `kuro-module-path` が正しいか確認:
```elisp
M-x describe-variable RET kuro-module-path
```

3. ライブラリパスを環境変数に追加:
```bash
# Linux
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# macOS
export DYLD_LIBRARY_PATH=/usr/local/lib:$DYLD_LIBRARY_PATH
```

### コンパイルエラー

**エラーメッセージ**:
```
error: linking with `cc` failed: exit code: 1
note: ld: library not found for -lssl
```

**原因**: OpenSSL 開発パッケージがインストールされていません。

**解決策**:

```bash
# Ubuntu/Debian
sudo apt install libssl-dev pkg-config

# Arch Linux
sudo pacman -S openssl

# macOS (Homebrew)
brew install openssl

# Fedora
sudo dnf install openssl-devel
```

### Emacs の動的モジュール機能が無効

**エラーメッセージ**:
```
Error: Emacs modules are not supported
```

**原因**: Emacs が動的モジュール機能なしでビルドされています。

**解決策**:

動的モジュール機能付きで Emacs を再ビルドします。

```bash
# ビルド前の確認
emacs --version  # 28.1 以降であることを確認

# ソースからビルドする場合
./configure --with-modules
make
sudo make install
```

## 表示関連の問題

### 画面が乱れる

**症状**: 文字が重なって表示される、画面が崩れる

**原因**: 画面の再描画が正しく行われていません。

**解決策**:

1. 画面を再描画:
```elisp
M-x kuro-redraw
```

2. ターミナルをリセット:
```bash
reset
```

3. Emacs の Redisplay 間隔を調整:
```elisp
(setq redisplay-dont-pause t)
```

### 色が正しく表示されない

**症状**: 色が表示されない、色がおかしい

**原因**: TERM 環境変数や Face の設定に問題があります。

**解決策**:

1. TERM 環境変数を確認:
```bash
echo $TERM
# 出力: xterm-256color であることを確認
```

2. TERM を正しく設定:
```elisp
(setq kuro-term-env "xterm-256color")
```

3. Face を確認:
```elisp
M-x list-faces-display RET kuro
```

### 日本語が文字化けする

**症状**: 日本語が正しく表示されない

**原因**: 文字コードの設定に問題があります。

**解決策**:

1. シェル側で文字コードを設定:
```bash
export LANG=ja_JP.UTF-8
export LC_ALL=ja_JP.UTF-8
```

2. Emacs 側で文字コードを設定:
```elisp
(setq kuro-default-coding-system 'utf-8-unix)
(prefer-coding-system 'utf-8-unix)
```

### カーソルの位置がおかしい

**症状**: カーソルが実際の位置と異なる場所に表示される

**原因**: カーソル位置の同期に問題があります。

**解決策**:

1. カーソルをリセット:
```bash
# シェル側で
reset

# または Emacs 側で
M-x kuro-reset-cursor
```

2. カーソルタイプを変更:
```elisp
(setq kuro-cursor-type 'bar)  ; 'box, 'bar, 'underline
```

## パフォーマンス関連の問題

### 高速な出力に追いつかない

**症状**: 大量の出力時に表示が遅れる、フリーズする

**原因**: 更新頻度が高すぎます。

**解決策**:

1. 更新のスロットリングを調整:
```elisp
(setq kuro-update-throttle 50)  ; ミリ秒単位
(setq kuro-max-update-lines 5000)  ; 一回の更新で処理する最大行数
```

2. 非同期レンダリングを有効化:
```elisp
(setq kuro-async-rendering t)
```

3. GC 閾値を調整:
```elisp
(setq gc-cons-threshold (* 100 1024 1024))  ; 100MB
```

### Emacs 全体が重くなる

**症状**: kuro 使用中に Emacs の操作が遅くなる

**原因**: GC や Redisplay の頻度が高すぎます。

**解決策**:

1. GC 閾値を調整:
```elisp
(add-hook 'kuro-mode-hook
          (lambda ()
            (setq gc-cons-threshold (* 100 1024 1024))))
```

2. Redisplay の最適化:
```elisp
(setq redisplay-dont-pause t)
(setq kuro-update-interval 16)  ; 約 60 FPS
```

3. バイトコンパイルを有効化:
```elisp
(setq kuro-enable-byte-compile t)
```

### メモリ使用量が過剰に増加

**症状**: メモリ使用量が時間経過とともに増加し続ける

**原因**: スクロールバックバッファやメモリリークの可能性があります。

**解決策**:

1. スクロールバックサイズを削減:
```elisp
(setq kuro-scrollback-size 5000)
```

2. 自動 GC を有効化:
```elisp
(setq kuro-auto-gc t)
(setq kuro-gc-interval 300)  ; 5分ごと
```

3. メモリプールサイズを調整:
```elisp
(setq kuro-cell-pool-size 5000)
(setq kuro-line-pool-size 500)
```

## 入力/出力関連の問題

### 入力が反映されない

**症状**: キー入力が反映されない

**原因**: キーバインドの衝突やモードの問題があります。

**解決策**:

1. キーボードクォートを解除:
```elisp
C-g
```

2. kuro モードが有効か確認:
```elisp
M-x describe-mode
```

3. キーバインドを確認:
```elisp
M-x describe-key RET C-c
```

### 特殊キーが動作しない

**症状**: 矢印キーや Function キーが動作しない

**原因**: エスケープシーケンスの処理に問題があります。

**解決策**:

1. シェル側でキーバインドを確認:
```bash
# Zsh の場合
bindkey | grep cursor

# Bash の場合
bind -p | grep cursor
```

2. TERM 環境変数を確認:
```bash
echo $TERM
```

3. 入力モードを確認:
```bash
# キーボードアプリケーションモードを確認
echo $TERM
```

### ペーストが正しく動作しない

**症状**: ペーストしたテキストが壊れる、余分な文字が挿入される

**原因**: ブラケットペーストモードの設定に問題があります。

**解決策**:

1. ブラケットペーストモードを有効化:
```bash
set enable-bracketed-paste on
```

2. kuro のペースト機能を使用:
```elisp
M-x kuro-paste
```

## クラッシュとエラー

### Emacs がクラッシュする

**症状**: kuro 使用中に Emacs がクラッシュする

**原因**: 動的モジュールや FFI の問題があります。

**解決策**:

1. デバッグモードを有効化:
```elisp
(setq kuro-debug-mode t)
```

2. クラッシュログを確認:
```bash
# macOS
tail -f ~/Library/Logs/DiagnosticReports/Emacs*.crash

# Linux
journalctl -xe
```

3. 最小限の設定で再現するか確認:
```bash
emacs -q -l minimal-kuro-config.el
```

### 動的モジュールのエラー

**エラーメッセージ**:
```
Symbol's value as variable is void: kuro-module
```

**原因**: モジュールが正しくロードされていません。

**解決策**:

1. モジュールのロードを確認:
```elisp
M-x kuro-load-module
```

2. モジュールパスを確認:
```elisp
M-x describe-variable RET kuro-module-path
```

3. モジュールを再ロード:
```elisp
M-x kuro-reload-module
```

## デバッグの手法

### デバッグモードの有効化

```elisp
;; デバッグモードを有効化
(setq kuro-debug-mode t)

;; ログレベルを設定
(setq kuro-log-level 'debug)  ; 'debug, 'info, 'warn, 'error

;; ログファイルを指定
(setq kuro-log-file "~/.emacs.d/kuro.log")
```

### パフォーマンス情報の取得

```elisp
;; パフォーマンス統計を表示
M-x kuro-show-performance-stats

;; プロファイリングを開始
M-x kuro-start-profiling

;; プロファイリングを停止して結果を表示
M-x kuro-stop-profiling
```

### トレースを有効化

```elisp
;; トレースを有効化
(setq kuro-trace t)

;; トレースログを表示
M-x kuro-show-trace
```

## バグ報告

問題が解決しない場合は、バグ報告をお願いします。バグ報告には以下の情報を含めてください：

1. Emacs のバージョン: `emacs --version`
2. Rust のバージョン: `rustc --version`
3. OS のバージョン
4. 再現手順
5. 期待される動作
6. 実際の動作
7. エラーメッセージ
8. デバッグログ (可能な場合)

## 関連ドキュメント

- [Installation](./install.md) — インストール手順
- [Configuration](./configure.md) — 設定方法
- [Performance Tuning](./performance-tuning.md) — パフォーマンスの最適化
