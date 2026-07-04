;;; kuro-input-mode-ext2-data.el --- Data tables for kuro-input-mode-ext2  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Pure data for `kuro-input-mode-ext2'.  Keep binding tables and mode
;; dispatch tables here so the companion logic file stays small.

;;; Code:

(defconst kuro--line-mode-bindings
  '(("C-m"   . kuro--line-commit)
    ("C-j"   . kuro--line-commit)
    ("C-o"   . kuro--line-newline)
    ("C-g"   . kuro--line-abort)
    ("DEL"   . kuro--line-delete)
    ("C-h"   . kuro--line-delete)
    ("C-k"   . kuro--line-kill-line)
    ("C-d"   . kuro--line-delete-char)
    ("C-u"   . kuro--line-kill-to-bol)
    ("C-w"   . kuro--line-unix-word-rubout)
    ("C-a"   . kuro--line-beginning-of-line)
    ("C-e"   . kuro--line-end-of-line)
    ("C-f"   . kuro--line-forward-char)
    ("C-b"   . kuro--line-backward-char)
    ("M-f"   . kuro--line-forward-word)
    ("M-b"   . kuro--line-backward-word)
    ("M-d"   . kuro--line-kill-word)
    ("M-DEL" . kuro--line-backward-kill-word)
    ("M-u"   . kuro--line-upcase-word)
    ("M-l"   . kuro--line-downcase-word)
    ("M-c"   . kuro--line-capitalize-word)
    ("M-t"   . kuro--line-transpose-words)
    ("C-t"   . kuro--line-transpose-chars)
    ("C-q"   . kuro--line-quoted-insert)
    ("C-/"   . kuro--line-undo)
    ("C-_"   . kuro--line-undo)
    ("C-y"   . kuro--line-yank)
    ("M-y"   . kuro--line-yank-pop)
    ("M-."   . kuro--line-yank-last-arg)
    ("M-_"   . kuro--line-yank-last-arg)
    ("M-p"   . kuro--line-history-prev)
    ("M-n"   . kuro--line-history-next)
    ("C-p"   . kuro--line-history-prev)
    ("C-n"   . kuro--line-history-next)
    ("M-<"   . kuro--line-goto-history-oldest)
    ("M->"   . kuro--line-goto-history-newest)
    ("TAB"   . kuro--line-complete)
    ("M-/"   . kuro--line-complete-history)
    ("C-r"   . kuro--line-history-search)
    ("C-c C-r" . kuro-line-minibuffer-send)
    ("M-SPC" . kuro--line-expand-abbrev)
    ("C-x C-e" . kuro--line-edit-in-buffer))
  "Key→command binding table for `kuro--line-mode-keymap'.
Vector-keyed special bindings ([remap self-insert-command], [return],
[backspace]) are installed directly in `kuro--build-line-mode-keymap'.")

(defconst kuro--input-mode-keymaps
  '((char      . kuro--char-keymap)
    (semi-char . kuro--keymap))
  "Alist mapping non-line input modes to their parent keymap variables.
Used by `kuro--apply-input-mode' to install the correct keymap for each
mode.
Line mode is absent: it uses a composed keymap via
`kuro--build-line-mode-keymap'.")

(defconst kuro--input-mode-cycle-table
  '((semi-char . kuro-char-mode)
    (char      . kuro-line-mode)
    (line      . kuro-semi-char-mode))
  "Alist mapping the current input mode to the command that activates the next one.
The cycle is: semi-char → char → line → semi-char.
Used by `kuro-cycle-input-mode'.")

(provide 'kuro-input-mode-ext2-data)
;;; kuro-input-mode-ext2-data.el ends here
