# Installation Guide

このガイドでは、各プラットフォームで kuro をインストールする方法を説明します。

## 対応プラットフォーム

- ✅ Linux (Ubuntu, Debian, Arch Linux, Fedora)
- ✅ macOS
- 🔄 Windows (WSL2 経由で動作確認済み)

## 共通の前提条件

すべてのプラットフォームで以下が必要です：

- Emacs 29.1 以降 (動的モジュール機能が有効であること)
- Rust 1.84.0 以降
- C Compiler (clang または GCC)

## Linux へのインストール

### Ubuntu / Debian

```bash
# 依存パッケージのインストール
sudo apt update
sudo apt install -y \
  emacs \
  build-essential \
  curl \
  pkg-config \
  libssl-dev

# Rust のインストール
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# kuro のクローンとビルドとインストール
git clone https://github.com/takeokunn/kuro.git
cd kuro
make install
```

### Arch Linux

```bash
# 依存パッケージのインストール
sudo pacman -S emacs rust clang cmake

# kuro のクローンとビルドとインストール
git clone https://github.com/takeokunn/kuro.git
cd kuro
make install
```

### Fedora

```bash
# 依存パッケージのインストール
sudo dnf install -y emacs rust clang cmake openssl-devel

# kuro のクローンとビルドとインストール
git clone https://github.com/takeokunn/kuro.git
cd kuro
make install
```

## macOS へのインストール

### Homebrew を使用する場合

```bash
# 依存パッケージのインストール
brew install emacs rust cmake

# kuro のクローンとビルドとインストール
git clone https://github.com/takeokunn/kuro.git
cd kuro
make install
```

### Nix を使用する場合

```bash
# Nix 環境でビルド
nix-shell -p rustc cmake pkg-config openssl
cd kuro/rust-core
cargo build --release

# Emacs Lisp ファイルのインストール
mkdir -p ~/.emacs.d/site-lisp/kuro
cp emacs-lisp/*.el ~/.emacs.d/site-lisp/kuro/
```

## Windows (WSL2) へのインストール

WSL2 経由でのインストール手順：

```bash
# WSL2 で Ubuntu を使用する場合
wsl --install -d Ubuntu

# WSL2 内で依存パッケージのインストール
sudo apt update
sudo apt install -y \
  emacs \
  build-essential \
  curl \
  pkg-config \
  libssl-dev

# Rust のインストール
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# kuro のクローンとビルドとインストール
git clone https://github.com/takeokunn/kuro.git
cd kuro
make install
```

## MELPA からのインストール (Emacs Lisp のみ)

MELPA から Emacs Lisp ファイルのみをインストールできます。
その場合、Rust バイナリは別途 `make install` でインストールが必要です。

```elisp
;; MELPA を package-archives に追加済みの場合
(package-install 'kuro)

;; バイナリのインストール（別途必要）
;; git clone https://github.com/takeokunn/kuro.git && cd kuro && make install
```

## Emacs の設定

インストール後、Emacs の設定ファイルに以下を追加します：

### init.el に直接設定を記述する場合

```elisp
;; kuro の設定
(add-to-list 'load-path "~/.emacs.d/site-lisp/kuro")

(require 'kuro)

;; バイナリパスを明示的に指定する場合（省略可能 — make install 使用時は自動検出）
;; (setq kuro-module-binary-path "~/.local/share/kuro/libkuro_core.so")

;; kuro を有効化
(kuro-mode 1)
```

### use-package を使用する場合

```elisp
(use-package kuro
  :load-path "~/.emacs.d/site-lisp/kuro"
  :init
  ;; バイナリパスを明示的に指定する場合（make install 使用時は省略可能）
  ;; (setq kuro-module-binary-path "~/.local/share/kuro/libkuro_core.so")
  :config
  (setq kuro-shell "/bin/zsh")
  (setq kuro-scrollback-size 10000)
  :hook
  (kuro-mode . kuro-setup))
```

## 動作確認

インストールが成功したか確認します：

```elisp
M-x kuro
```

正常に動作していれば、新しいバッファが開き、ターミナルプロンプトが表示されます。

## アップデート

kuro を最新版に更新する方法：

```bash
cd kuro
git pull
make install
```

## アンインストール

kuro を完全に削除する場合：

```bash
# 動的ライブラリの削除
rm -f ~/.local/share/kuro/libkuro_core.*

# Emacs Lisp ファイルの削除
rm -rf ~/.emacs.d/site-lisp/kuro

# ソースコードの削除
rm -rf kuro
```

init.el から kuro 関連の設定も削除してください。

## トラブルシューティング

### 動的モジュールがロードできない

```
Error: Cannot open shared object file
```

**解決策**:

1. `kuro-module-binary-path` が正しいか確認
2. ライブラリが存在するか確認：
   ```bash
   ls -l /usr/local/lib/libkuro_core.*
   ```
3. `LD_LIBRARY_PATH` にライブラリパスを追加：
   ```bash
   export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
   ```

### Emacs の動的モジュール機能が無効

```
Error: Emacs modules are not supported
```

**解決策**: Emacs を動的モジュール機能付きで再ビルド

```bash
# Ubuntu/Debian
sudo apt remove emacs
sudo apt install -y build-essential autoconf make texinfo libgtk-3-dev libxpm-dev libjpeg-dev libgif-dev libtiff5-dev libgnutls28-dev libncurses5-dev
cd /tmp
wget https://ftp.gnu.org/gnu/emacs/emacs-28.2.tar.xz
tar -xf emacs-28.2.tar.xz
cd emacs-28.2
./configure --with-modules
make
sudo make install
```

### コンパイルエラー

```
error: linking with `cc` failed: exit code: 1
```

**解決策**:

```bash
# 開発パッケージをインストール
sudo apt install -y build-essential cmake

# OpenSSL 開発パッケージをインストール
sudo apt install -y libssl-dev pkg-config

# 再ビルド
cd rust-core
cargo clean
cargo build --release
```

## 次のステップ

インストールが完了したら、次のステップに進みましょう：

- [Getting Started](../tutorials/getting-started.md) — 最初のターミナルセッションの起動
- [Configuration](./configure.md) — 詳細な設定方法

## 関連ドキュメント

- [Architecture](../explanation/architecture.md) — アーキテクチャの理解
- [Performance Strategy](../explanation/performance-strategy.md) — パフォーマンス戦略
