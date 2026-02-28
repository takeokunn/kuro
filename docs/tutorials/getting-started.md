# Getting Started with kuro

このチュートリアルでは、kuro を初めて使用する方向けに、環境構築から最初のターミナルセッションの起動までの手順をステップバイステップで解説します。

## 前提条件

kuro を使用するには以下の環境が必要です：

- **Emacs**: 28.1 以降 (動的モジュール機能が有効であること)
- **Rust**: 1.70.0 以降
- **Cargo**: Rust に含まれるパッケージマネージャ
- **C Compiler**: clang または GCC (動的モジュールのビルドに必要)

### 前提条件の確認

```bash
# Emacs のバージョン確認
emacs --version

# Rust のバージョン確認
rustc --version

# Cargo の確認
cargo --version

# 動的モジュール機能の確認 (Emacs 上で)
M-x xt-moka-load-module
```

「動的モジュール機能が有効であること」というメッセージが出ない場合は、Emacs を `--with-modules` オプション付きで再ビルドする必要があります。

## ステップ 1: ソースコードの取得

kuro のリポジトリをクローンします：

```bash
git clone https://github.com/takeokunn/kuro.git
cd kuro
```

## ステップ 2: Rust コアのビルド

Rust コアエンジンを動的ライブラリとしてビルドします：

```bash
cd rust-core
cargo build --release
```

ビルドが成功すると、`target/release/libkuro_core.so` (Linux) または `target/release/libkuro_core.dylib` (macOS) が生成されます。

## ステップ 3: Emacs Lisp モジュールの配置

Emacs Lisp ファイルを Emacs の load-path に配置します：

```bash
# オプション 1: システム全体にインストール
sudo cp emacs-lisp/*.el /usr/local/share/emacs/site-lisp/kuro/

# オプション 2: ユーザーディレクトリに配置
mkdir -p ~/.emacs.d/site-lisp/kuro
cp emacs-lisp/*.el ~/.emacs.d/site-lisp/kuro/
```

## ステップ 4: Emacs の設定

`init.el` に以下の設定を追加します：

```elisp
;; kuro の設定
(add-to-list 'load-path "~/.emacs.d/site-lisp/kuro")

(require 'kuro)

;; 動的モジュールのパスを指定
(setq kuro-module-path
      (expand-file-name "rust-core/target/release/libkuro_core.so"
                        (projectile-project-root)))

;; kuro を有効化
(kuro-mode 1)
```

## ステップ 5: 最初のターミナルセッション

設定を反映させるために Emacs を再起動するか、以下のコマンドを実行します：

```elisp
M-x eval-buffer
```

それでは、最初のターミナルセッションを起動してみましょう：

```elisp
M-x kuro
```

新しいバッファが開き、ターミナルプロンプトが表示されます。試しにコマンドを入力してみてください：

```bash
echo "Hello, kuro!"
ls -la
```

## ステップ 6: 動作確認

kuro が正しく動作していることを確認するために、いくつかの機能を試してみましょう：

### 基本的なコマンド実行

```bash
# カレンダーを表示 (エスケープシーケンスのテスト)
cal

# ファイルの一覧を色付きで表示
ls --color=auto

# テキストエディタを起動
vim
```

### カーソル移動のテスト

```bash
# カーソルキーで移動
# ← ↑ ↓ →

# 単語単位の移動
# Ctrl+← Ctrl+→
```

### 画面スクロールのテスト

```bash
# 長い出力を生成
yes | head -n 100

# スクロールバックバッファの確認
# Shift+PgUp / Shift+PgDown
```

## トラブルシューティング

### 動的モジュールがロードできない

```
Error: Cannot open shared object file
```

**解決策**: `kuro-module-path` が正しく設定されているか確認してください：

```elisp
M-x describe-variable kuro-module-path
```

### コンパイルエラーが発生する

```
Error: Failed to compile kuro-core
```

**解決策**: Rust のバージョンを確認し、必要に応じて更新してください：

```bash
rustup update stable
```

### 文字化けが発生する

**解決策**: Emacs の coding system を確認してください：

```elisp
M-x describe-coding-system
```

UTF-8 が設定されていることを確認します。

## 次のステップ

これで kuro の基本設定は完了です。次は以下のチュートリアルに進むことをお勧めします：

- [基本的な使い方とキーバインド](./basic-usage.md) — 日常的なターミナル操作方法
- [最初のカスタマイズ](./first-customization.md) — 設定ファイルの編集方法

## まとめ

このチュートリアルでは、以下の内容を学びました：

1. ✅ kuro のビルドとインストール
2. ✅ Emacs の設定
3. ✅ 最初のターミナルセッションの起動
4. ✅ 基本的な動作確認

おめでとうございます！これで kuro を使用する準備が整いました。
