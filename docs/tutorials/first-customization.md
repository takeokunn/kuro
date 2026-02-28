# First Customization

このチュートリアルでは、kuro を自分好みにカスタマイズする方法を学びます。設定ファイルの編集から、テーマの変更、キーバインドのカスタマイズまでをステップバイステップで解説します。

## 基本的な設定

### 設定ファイルの場所

kuro の設定は `init.el` または `use-package` を使用して管理します。ここでは `use-package` を使用したモダンな設定方法を紹介します。

### 最小限の設定

まずは、最小限の設定から始めましょう：

```elisp
(use-package kuro
  :load-path "~/.emacs.d/site-lisp/kuro"
  :init
  (setq kuro-module-path
        (expand-file-name "rust-core/target/release/libkuro_core.so"
                          (projectile-project-root)))
  :config
  (setq kuro-default-shell "/bin/zsh")  ; デフォルトのシェルを指定
  (setq kuro-scrollback-size 10000)     ; スクロールバックのサイズ
  :hook
  (kuro-mode . kuro-setup))
```

## 表示のカスタマイズ

### Face の設定

kuro は Emacs の Face システムを使用して表示を制御します。独自の Face を定義することで、ターミナルの見た目をカスタマイズできます。

```elisp
;; 基本的な Face の設定
(defface kuro-default-face
  '((t :inherit default))
  "Default face for kuro terminal."
  :group 'kuro)

(defface kuro-bold-face
  '((t :weight bold :inherit kuro-default-face))
  "Bold face for kuro terminal."
  :group 'kuro)

(defface kuro-italic-face
  '((t :slant italic :inherit kuro-default-face))
  "Italic face for kuro terminal."
  :group 'kuro)

;; カラーパレットの設定
(defface kuro-color-black
  '((t :foreground "black"))
  "Black color for kuro terminal."
  :group 'kuro)

(defface kuro-color-red
  '((t :foreground "red"))
  "Red color for kuro terminal."
  :group 'kuro)

;; その他の色も同様に定義...
```

### テーマの適用

既存のカラーテーマを使用する場合：

```elisp
;; doom-themes を使用する例
(use-package doom-themes
  :config
  (load-theme 'doom-one t))

;; kuro 用に Face を調整
(custom-set-faces
  '(kuro-default-face ((t (:background "#282c34" :foreground "#abb2bf"))))
  '(kuro-bold-face ((t (:weight bold :foreground "#61afef"))))
  '(kuro-color-red ((t (:foreground "#e06c75")))))
```

## 動作のカスタマイズ

### スクロールの設定

```elisp
;; スクロールバックのサイズ
(setq kuro-scrollback-size 10000)

;; スクロール速度
(setq kuro-scroll-speed 1)

;; 自動スクロールの有効/無効
(setq kuro-auto-scroll t)
```

### カーソルの設定

```elisp
;; カーソルの種類 (box, bar, underline)
(setq kuro-cursor-type 'box)

;; カーソルの点滅
(setq kuro-cursor-blink-mode t)

;; カーソルの色
(setq kuro-cursor-color "#5c6370")
```

### 文字コードの設定

```elisp
;; デフォルトの文字コード
(setq kuro-default-coding-system 'utf-8-unix)

;; 自動認識する文字コードの優先順位
(prefer-coding-system 'utf-8-unix)
(prefer-coding-system 'utf-8)
(prefer-coding-system 'euc-japan-unix)
```

## キーバインドのカスタマイズ

### グローバルキーバインド

```elisp
;; kuro を素早く起動
(global-set-key (kbd "C-c t") 'kuro)

;; クイックアクセス用のプレフィックスキー
(global-set-key (kbd "C-c k") 'kuro-command-map)
```

### kuro モード内のキーバインド

```elisp
;; kuro モードのキーマップをカスタマイズ
(defun my-kuro-setup ()
  (local-set-key (kbd "C-c C-q") 'kuro-quit)
  (local-set-key (kbd "C-c C-l") 'kuro-clear-scrollback)
  (local-set-key (kbd "C-c C-r") 'kuro-redraw)
  (local-set-key (kbd "M-p") 'kuro-previous-command)
  (local-set-key (kbd "M-n") 'kuro-next-command))

(add-hook 'kuro-mode-hook 'my-kuro-setup)
```

## 高度なカスタマイズ

### 複数のターミナルプロファイル

異なる用途に応じて設定を切り替える：

```elisp
;; デフォルトプロファイル
(setq kuro-default-profile
      '((shell . "/bin/zsh")
        (scrollback-size . 10000)
        (cursor-type . box)))

;; 開発用プロファイル
(setq kuro-dev-profile
      '((shell . "/bin/bash")
        (scrollback-size . 50000)
        (cursor-type . bar)
        (env-vars . (("NODE_ENV" . "development")))))

;; プロファイルを適用する関数
(defun kuro-apply-profile (profile)
  (interactive "SProfile name: ")
  (let ((settings (symbol-value (intern (format "kuro-%s-profile" profile)))))
    (dolist (setting settings)
      (setq (intern (format "kuro-%s" (car setting))) (cdr setting)))))

;; 使用例
(kuro-apply-profile 'dev)
```

### フックの活用

特定のイベント時に処理を実行：

```elisp
;; ターミナル起動時のフック
(add-hook 'kuro-mode-hook
          (lambda ()
            ;; 自動的に特定のコマンドを実行
            (when (string-match-p "dev" (buffer-name))
              (kuro-send-string "npm run dev\n"))))

;; ターミナル終了時のフック
(add-hook 'kuro-quit-hook
          (lambda ()
            (message "Kuro terminal quit")))
```

### 環境変数の設定

```elisp
;; ターミナル内で使用する環境変数
(setq kuro-environment-variables
      '(("EDITOR" . "vim")
        ("PAGER" . "less")
        ("LANG" . "ja_JP.UTF-8")))
```

## 実践的なカスタマイズ例

### 開発環境用の設定

```elisp
(use-package kuro
  :load-path "~/.emacs.d/site-lisp/kuro"
  :init
  (setq kuro-module-path
        (expand-file-name "rust-core/target/release/libkuro_core.so"
                          (projectile-project-root)))
  :config
  ;; 開発用の設定
  (setq kuro-default-shell "/bin/zsh")
  (setq kuro-scrollback-size 50000)
  (setq kuro-auto-scroll t)
  :hook
  (kuro-mode . (lambda ()
                 ;; プロジェクトルートへ移動
                 (when (projectile-project-p)
                   (kuro-send-string (format "cd %s\n" (projectile-project-root)))))))

;; プロジェクトごとのターミナル
(defun my-kuro-project-terminal ()
  "Open a kuro terminal in the project root."
  (interactive)
  (let ((default-directory (projectile-project-root)))
    (kuro (concat "kuro-" (projectile-project-name)))))

(global-set-key (kbd "C-c p t") 'my-kuro-project-terminal)
```

### AI エージェント用の設定

```elisp
;; AI エージェントからの大量出力に対応
(use-package kuro
  :config
  (setq kuro-scrollback-size 100000)
  (setq kuro-update-throttle 10)  ; ミリ秒単位の更新間隔
  (setq kuro-max-update-lines 1000))  ; 一回の更新で処理する最大行数
```

## 設定の検証

### 設定の確認

設定が正しく適用されているか確認します：

```elisp
;; 現在の設定値を確認
M-x describe-variable RET kuro-scrollback-size

;; Face の確認
M-x list-faces-display RET kuro
```

### トラブルシューティング

設定が反映されない場合：

1. Emacs を再起動
2. `M-x eval-buffer` で設定ファイルを再評価
3. `*Messages*` バッファでエラーを確認

## 次のステップ

カスタマイズをマスターしたら、次は特定のタスクを達成するためのハウツーガイドに進みましょう：

- [インストール方法](../how-to/install.md) — 各プラットフォームでのインストール手順
- [パフォーマンスチューニング](../how-to/performance-tuning.md) — 最適化の手法

## 練習問題

以下のカスタマイズを試してみましょう：

1. ✅ 好きなカラーテーマを適用
2. ✅ カーソルの種類と色を変更
3. ✅ 独自のキーバインドを定義
4. ✅ プロジェクト用のターミナル起動関数を作成

## まとめ

このチュートリアルでは、以下の内容を学びました：

1. ✅ 基本的な設定方法
2. ✅ Face とテーマのカスタマイズ
3. ✅ 動作設定の調整
4. ✅ キーバインドのカスタマイズ
5. ✅ 高度なカスタマイズ例

これで kuro を自分好みにカスタマイズできるようになりました。次は、より具体的なタスクを達成するためのハウツーガイドに進みましょう！
