# Configuration Guide

このガイドでは、kuro の詳細な設定方法を説明します。基本的な設定から高度なカスタマイズまで、幅広い設定項目をカバーします。

## 基本的な設定構造

kuro の設定は、Emacs Lisp を通じて行います。以下の3つのレイヤーで設定を管理できます：

1. **グローバル設定**: 全ての kuro セッションに適用
2. **バッファローカル設定**: 特定のバッファにのみ適用
3. **プロファイル設定**: 用途別のプリセット

## 設定ファイルの場所

設定は通常 `init.el` または専用の設定ファイルに記述します：

```
~/.emacs.d/
├── init.el              # メインの設定ファイル
└── kuro-config.el       # kuro 専用の設定ファイル
```

## 設定項目一覧

### コア設定

```elisp
;; デフォルトのシェル
(setq kuro-default-shell "/bin/zsh")

;; 動的モジュールのパス
(setq kuro-module-path
      (expand-file-name "rust-core/target/release/libkuro_core.so"
                        (projectile-project-root)))

;; スクロールバックのサイズ
(setq kuro-scrollback-size 10000)

;; 文字コード
(setq kuro-default-coding-system 'utf-8-unix)
```

### 表示設定

```elisp
;; カーソルの種類 (box, bar, underline)
(setq kuro-cursor-type 'box)

;; カーソルの点滅
(setq kuro-cursor-blink-mode t)

;; カーソルの色
(setq kuro-cursor-color "#5c6370")

;; 背景色と前景色
(setq kuro-background-color "#282c34")
(setq kuro-foreground-color "#abb2bf")

;; Bold/Italic の有効化
(setq kuro-enable-bold t)
(setq kuro-enable-italic t)
```

### 動作設定

```elisp
;; 自動スクロール
(setq kuro-auto-scroll t)

;; 自動スクロールのしきい値
(setq kuro-auto-scroll-threshold 1)

;; 更新間隔 (ミリ秒)
(setq kuro-update-interval 16)

;; 更新のスロットリング
(setq kuro-update-throttle 10)

;; 1回の更新で処理する最大行数
(setq kuro-max-update-lines 1000)

;; Dirty Line Tracking
(setq kuro-dirty-line-tracking t)
```

### パフォーマンス設定

```elisp
;; メモリプールサイズ
(setq kuro-cell-pool-size 10000)
(setq kuro-line-pool-size 1000)

;; GC 閾値
(setq kuro-gc-threshold (* 100 1024 1024))

;; 非同期レンダリング
(setq kuro-async-rendering nil)

;; バイトコンパイル
(setq kuro-enable-byte-compile t)
```

### 高度な設定

```elisp
;; 環境変数
(setq kuro-environment-variables
      '(("EDITOR" . "vim")
        ("PAGER" . "less")
        ("LANG" . "ja_JP.UTF-8")))

;; TERM 環境変数
(setq kuro-term-env "xterm-256color")

;; カラーパレット
(setq kuro-color-palette 'kuro)  ; 'kuro, 'standard, 'solarized

;; Alt キーを Meta として扱う
(setq kuro-alt-is-meta t)
```

## use-package を使用した設定

モダンな Emacs 設定では `use-package` を使用して設定を整理できます：

```elisp
(use-package kuro
  :load-path "~/.emacs.d/site-lisp/kuro"
  :init
  ;; 初期化フェーズで設定する項目
  (setq kuro-module-path
        (expand-file-name "rust-core/target/release/libkuro_core.so"
                          (projectile-project-root)))
  :config
  ;; コンフィギュレーションフェーズで設定する項目
  (setq kuro-default-shell "/bin/zsh")
  (setq kuro-scrollback-size 10000)
  (setq kuro-auto-scroll t)
  :hook
  ;; フックを設定
  (kuro-mode . kuro-setup)
  :bind
  ;; キーバインドを設定
  ("C-c t" . kuro)
  (:map kuro-mode-map
        ("C-c C-q" . kuro-quit)
        ("C-c C-l" . kuro-clear-scrollback)))
```

## プロファイル設定

用途別にプロファイルを定義して、簡単に切り替えることができます：

```elisp
;; デフォルトプロファイル
(defvar kuro-default-profile
  '((shell . "/bin/zsh")
    (scrollback-size . 10000)
    (cursor-type . box)
    (background-color . "#282c34")
    (foreground-color . "#abb2bf")))

;; 開発用プロファイル
(defvar kuro-dev-profile
  '((shell . "/bin/bash")
    (scrollback-size . 50000)
    (cursor-type . bar)
    (background-color . "#1e1e1e")
    (foreground-color . "#d4d4d4")
    (env-vars . (("NODE_ENV" . "development")))))

;; ライトテーマプロファイル
(defvar kuro-light-profile
  '((shell . "/bin/zsh")
    (scrollback-size . 10000)
    (cursor-type . box)
    (background-color . "#ffffff")
    (foreground-color . "#000000")))

;; プロファイルを適用する関数
(defun kuro-apply-profile (profile-name)
  "Apply a kuro profile by name."
  (interactive
   (list (completing-read "Profile: "
                          '(default dev light)
                          nil t)))
  (let* ((profile-symbol (intern (format "kuro-%s-profile" profile-name)))
         (settings (symbol-value profile-symbol)))
    (dolist (setting settings)
      (setq (intern (format "kuro-%s" (car setting))) (cdr setting)))
    (message "Applied kuro profile: %s" profile-name)))

;; 使用例
(kuro-apply-profile 'dev)
```

## バッファローカル設定

特定のバッファにのみ設定を適用する場合：

```elisp
;; バッファローカル設定を追加する関数
(defun kuro-set-buffer-local (key value)
  "Set a buffer-local kuro setting."
  (set (make-local-variable (intern (format "kuro-%s" key))) value))

;; 使用例
(defun my-kuro-dev-setup ()
  "Setup kuro for development."
  (kuro-set-buffer-local "scrollback-size" 50000)
  (kuro-set-buffer-local "update-throttle" 50)
  (kuro-set-buffer-local "max-update-lines" 5000))

;; フックで適用
(add-hook 'kuro-mode-hook #'my-kuro-dev-setup)
```

## 条件付き設定

条件に応じて設定を変更する場合：

```elisp
;; システムに応じた設定
(cond
 ((string-equal system-type "darwin")
  ;; macOS 用の設定
  (setq kuro-default-shell "/bin/zsh")
  (setq kuro-module-path "/usr/local/lib/libkuro_core.dylib"))
 ((string-equal system-type "gnu/linux")
  ;; Linux 用の設定
  (setq kuro-default-shell "/bin/bash")
  (setq kuro-module-path "/usr/local/lib/libkuro_core.so")))

;; Emacs バージョンに応じた設定
(when (version<= "28.1" emacs-version)
  (setq kuro-use-new-features t))

;; ディスプレイ環境に応じた設定
(if (display-graphic-p)
    (setq kuro-cursor-type 'box)
  (setq kuro-cursor-type 'bar))
```

## 設定の検証

設定が正しく適用されているか確認する方法：

```elisp
;; 変数の値を確認
C-h v kuro-scrollback-size

;; 現在の設定をすべて表示
M-x kuro-show-config

;; 設定をファイルにエクスポート
M-x kuro-export-config
```

## 設定のデバッグ

設定が期待通りに動作しない場合のデバッグ方法：

```elisp
;; デバッグモードを有効化
(setq kuro-debug-mode t)

;; デバッグ情報を表示
M-x kuro-show-debug-info

;; ログを記録
(setq kuro-log-level 'debug)  ; 'debug, 'info, 'warn, 'error
(setq kuro-log-file "~/.emacs.d/kuro.log")

;; トレースを有効化
(setq kuro-trace t)
```

## 設定のバックアップと復元

```elisp
;; 設定をバックアップ
(defun kuro-backup-config ()
  "Backup current kuro configuration."
  (interactive)
  (let ((backup-file (format-time-string
                      "~/.emacs.d/kuro-config-backup-%Y%m%d-%H%M%S.el")))
    (with-temp-file backup-file
      (insert ";; Kuro configuration backup\n")
      (insert (format ";; Created: %s\n" (current-time-string)))
      (insert "\n")
      (pp `(use-package kuro
            :config
            ,@(cl-loop for var in (apropos-internal "^kuro-" 'boundp)
                       collect `(setq ,(intern var) ,(symbol-value var))))
           (current-buffer)))
    (message "Kuro configuration backed up to: %s" backup-file)))

;; 設定を復元
M-x kuro-restore-config
```

## ベストプラクティス

1. **設定の整理**: 関連する設定をグループ化
2. **ドキュメント**: 複雑な設定にはコメントを追加
3. **バージョン管理**: 設定ファイルを Git で管理
4. **段階的な変更**: 一度に複数の設定を変更せず、一つずつテスト
5. **プロファイルの活用**: 用途別にプロファイルを作成

## 次のステップ

設定が完了したら、次のステップに進みましょう：

- [Performance Tuning](./performance-tuning.md) — パフォーマンスの最適化
- [Installation](./install.md) — インストール手順

## 関連ドキュメント

- [Architecture](../explanation/architecture.md) — アーキテクチャの理解
- [Reference](../reference/) — 技術的なリファレンス
