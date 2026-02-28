# Shell Integration Guide

このガイドでは、kuro を各種シェルと統合する方法を説明します。シェルの統合により、プロンプトのカスタマイズ、自動補完、およびその他のシェル機能を kuro で活用できます。

## 対応シェル

- ✅ Zsh
- ✅ Bash
- ✅ Fish
- ✅ Nu (Nushell)

## Zsh との統合

### 基本的な設定

Zsh を使用する場合の基本設定：

```elisp
;; init.el での設定
(setq kuro-default-shell "/bin/zsh")
```

### プロンプトのカスタマイズ

Zsh のプロンプトをカスタマイズして、kuro で美しく表示：

```zsh
# ~/.zshrc

# 基本的なプロンプト設定
PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '

# 右プロンプトに時間を表示
RPROMPT='%F{yellow}%T%f'

# Git 情報を表示 (vcs_info を使用)
autoload -Uz vcs_info
zstyle ':vcs_info:*' formats '%b'
zstyle ':vcs_info:*' actionformats '%b|%a'
RPROMPT='$vcs_info_msg_0_'

# プロンプトを更新
precmd() { vcs_info }
```

### シンタックスハイライト

Zsh シンタックスハイライトを有効化：

```zsh
# zsh-syntax-highlighting のインストール (macOS)
brew install zsh-syntax-highlighting

# ~/.zshrc で有効化
source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# または Linux (Arch Linux)
sudo pacman -S zsh-syntax-highlighting
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
```

### 自動補完

Zsh の補完機能を強化：

```zsh
# 補完機能を有効化
autoload -Uz compinit
compinit

# 補完のスタイル
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors ''

# 補完のキャッシュ
zstyle ':completion:*' use-cache yes
```

### ディレクトリスタック

```zsh
# ディレクトリスタックの設定
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS

# cd で pushd を使用
alias cd='pushd'

# ディレクトリスタックを表示
alias dirs='dirs -v'
```

## Bash との統合

### 基本的な設定

```elisp
;; init.el での設定
(setq kuro-default-shell "/bin/bash")
```

### プロンプトのカスタマイズ

Bash のプロンプトをカスタマイズ：

```bash
# ~/.bashrc

# 基本的なプロンプト
PS1='\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]\$ '

# Git ブランチを表示
parse_git_branch() {
  git branch 2>/dev/null | sed -n -e 's/^\* \(.*\)/(\1)/p'
}
PS1='\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]$(parse_git_branch)\$ '

# 履歴の設定
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoredups:erasedups
shopt -s histappend

# 履歴の即時反映
PROMPT_COMMAND="${PROMPT_CMD:+$PROMPT_COMMAND$'\n'}history -a; history -c; history -r"
```

### シンタックスハイライト

```bash
# bash-syntax-highlighting のインストール (Ubuntu/Debian)
sudo apt install bash-completion

# または GitHub から
git clone https://github.com/scop/bash-completion
cd bash-completion
sudo make install

# ~/.bashrc で有効化
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
```

## Fish との統合

### 基本的な設定

```elisp
;; init.el での設定
(setq kuro-default-shell "/usr/bin/fish")
```

### プロンプトのカスタマイズ

Fish は高度なプロンプトカスタマイズをサポートしています：

```fish
# ~/.config/fish/config.fish

# 基本的なプロンプト
function fish_prompt
  set_color green
  echo -n (whoami)'@'(hostname)':'
  set_color blue
  echo -n (prompt_pwd)
  set_color normal
  echo -n '$ '
end

# 右プロンプト
function fish_right_prompt
  set_color yellow
  echo -n (date +%H:%M:%S)
  set_color normal
end

# Git 情報を表示
function fish_git_prompt
  git branch 2>/dev/null | sed -n -e 's/^\* \(.*\)/(\1)/p'
end
```

### 自動補完

Fish は自動補完が組み込まれています：

```fish
# 補完の設定
set fish_complete_path ~/.config/fish/completions $fish_complete_path

# 自動補完の提案を表示
set fish_autosuggestion_enabled 1
```

## Nu (Nushell) との統合

### 基本的な設定

```elisp
;; init.el での設定
(setq kuro-default-shell "/usr/bin/nu")
```

### プロンプトのカスタマイズ

```nu
# ~/.config/nushell/env.nu

# プロンプトの設定
def create_left_prompt [] {
    let dir = ([ $env.PWD ].path split | last)
    [
        $"(ansi green)($env.USER)@(hostname)(ansi reset):"
        $"(ansi blue)($dir)(ansi reset)"
        "(ansi reset)$ "
    ] | str join
}

def create_right_prompt [] {
    [
        $"(ansi yellow)(date now | format date '%H:%M:%S')(ansi reset)"
    ] | str join
}

$env.PROMPT_COMMAND = { create_left_prompt }
$env.PROMPT_COMMAND_RIGHT = { create_right_prompt }
```

## 共通の統合機能

### ウィンドウタイトルの更新

シェル側でウィンドウタイトルを更新：

```zsh
# ~/.zshrc
precmd() {
  print -Pn "\e]0;%n@%m: %~\a"
}
preexec() {
  print -Pn "\e]0;%n@%m: $1\a"
}
```

```bash
# ~/.bashrc
update_title() {
  printf '\033]0;%s@%s: %s\007' "$USER" "$HOSTNAME" "${PWD/#$HOME/~}"
}
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}update_title"
```

### シェル起動時の自動実行

```elisp
;; init.el でシェル起動時の自動コマンドを設定
(add-hook 'kuro-mode-hook
          (lambda ()
            ;; プロジェクトルートへ移動
            (when (projectile-project-p)
              (kuro-send-string (format "cd %s\n" (projectile-project-root))))))

;; または特定のディレクトリで特定のシェルスクリプトを実行
(defun my-kuro-dev-setup ()
  (when (string-match-p "dev" (buffer-name))
    (kuro-send-string "source ~/.config/kuro-dev-env\n")))
(add-hook 'kuro-mode-hook 'my-kuro-dev-setup)
```

### シェル関数の Emacs からの呼び出し

```elisp
;; シェル関数を呼び出す Emacs Lisp 関数
(defun kuro-shell-cd (dir)
  "Change directory in kuro shell."
  (interactive "DDirectory: ")
  (kuro-send-string (format "cd %s\n" (shell-quote-argument dir))))

(defun kuro-shell-clear ()
  "Clear the kuro terminal."
  (interactive)
  (kuro-send-string "clear\n"))

;; キーバインドを設定
(define-key kuro-mode-map (kbd "C-c C-d") 'kuro-shell-cd)
(define-key kuro-mode-map (kbd "C-c C-l") 'kuro-shell-clear)
```

## トラブルシューティング

### プロンプトが正しく表示されない

**解決策**: PS1/PROMPT 変数でエスケープシーケンスを使用：

```zsh
# エスケープシーケンスの使用
PROMPT='%{\e[32m%}%n@%m%{\e[0m%}:%{\e[34m%}%~%{\e[0m%}$ '
```

### 日本語が表示されない

**解決策**: 文字コードを UTF-8 に設定：

```zsh
# ~/.zshrc
export LANG=ja_JP.UTF-8
export LC_ALL=ja_JP.UTF-8
```

### 補完が動作しない

**解決策**: 補完機能を有効化：

```zsh
# ~/.zshrc
autoload -Uz compinit
compinit
```

## 次のステップ

シェル統合が完了したら、次のステップに進みましょう：

- [Configuration](./configure.md) — 詳細な設定方法
- [Performance Tuning](./performance-tuning.md) — パフォーマンスの最適化

## 関連ドキュメント

- [Architecture](../explanation/architecture.md) — アーキテクチャの理解
- [Parser Reference](../reference/rust-core/parser.md) — VTE パーサーの仕様
