;;; kuro-input-keymap-data.el --- Static keymap tables for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Static binding tables used by `kuro-input-keymap.el'.

;;; Code:

(defconst kuro--ctrl-key-table
  ;; (KBD-STRING . CTRL-BYTE): CTRL-BYTE = ASCII code 1-31.
  ;; C-c is reserved as the kuro-mode-map prefix key and is intentionally absent.
  '(("C-a"  .  1) ("C-b"  .  2)
    ("C-d"  .  4) ("C-e"  .  5) ("C-f"  .  6) ("C-g"  .  7)
    ("C-k"  . 11) ("C-l"  . 12) ("C-n"  . 14) ("C-o"  . 15)
    ("C-p"  . 16) ("C-q"  . 17) ("C-r"  . 18) ("C-s"  . 19)
    ("C-t"  . 20) ("C-u"  . 21)               ("C-w"  . 23)
    ("C-x"  . 24) ("C-y"  . 25) ("C-z"  . 26)
    ("C-\\" . 28) ("C-]"  . 29) ("C-_"  . 31))
  "Mapping of Emacs Ctrl+key strings to their ASCII control-byte values.
Each entry is (KBD-STRING . CTRL-BYTE).  The ctrl byte for a letter is
  \\(logand char 31\\): values range from 1 (Control-A) to 26 (Control-Z).
The kuro-mode prefix key is intentionally absent from this map.")

(defconst kuro--meta-punct-bindings
  '(("M-." . ?.) ("M-<" . ?<) ("M->" . ?>)
    ("M-?" . ??) ("M-/" . ?/) ("M-_" . ?_))
  "Alist of (KBD-STRING . CHAR) for Meta+punctuation bindings.
Each entry maps an Emacs key string to the character sent via `kuro--send-meta'.
Applied by `kuro--keymap-setup-meta'.
M-DEL and M-<backspace> are handled separately
\(they call `kuro--send-meta-backspace').")

(defconst kuro--meta-letter-chars
  (append (number-sequence ?a ?z)
          (number-sequence ?A ?Z)
          (number-sequence ?0 ?9))
  "Characters bound by `kuro--keymap-setup-meta' as M-CHAR and ESC CHAR.")

(defconst kuro--xterm-modifier-codes
  '((S . 2) (M . 3) (C . 5))
  "Xterm CSI modifier parameter codes used in \\e[1;Nm sequences.
Shift=2, Alt/Meta=3, Ctrl=5.  Note: code 4 (Shift+Alt) is absent here
because Emacs does not generate a distinct [S-M-up] event.")

(defconst kuro--xterm-arrow-codes
  '((up . ?A) (down . ?B) (right . ?C) (left . ?D))
  "Xterm CSI final-byte characters for arrow directions in \\e[1;Nm sequences.
The letters A/B/C/D are the original VT100 cursor movement codes
\(CUU/CUD/CUF/CUB).  Used with `kuro--xterm-modifier-codes' to build the 12
modifier+arrow sequences like \\e[1;2A (Shift+Up), \\e[1;5C (Ctrl+Right), etc.")

(defconst kuro--kkp-arrow-codepoints
  '((up . 57352) (down . 57353) (right . 57351) (left . 57350))
  "KKP Unicode codepoints for arrow keys.
Used when `kuro--kkp-all-escape' (0x08) is active to send CSI cp;mod u instead
of the xterm CSI 1;Nm form.  Mirrors `kuro--xterm-arrow-codes' key order.")

(defconst kuro--fkey-handlers
  '((f1  . kuro--F1)  (f2  . kuro--F2)  (f3  . kuro--F3)  (f4  . kuro--F4)
    (f5  . kuro--F5)  (f6  . kuro--F6)  (f7  . kuro--F7)  (f8  . kuro--F8)
    (f9  . kuro--F9)  (f10 . kuro--F10) (f11 . kuro--F11) (f12 . kuro--F12))
  "Alist mapping Emacs function-key event symbols to Kuro handler commands.")

(defconst kuro--nav-key-bindings
  '(([up]      . kuro--arrow-up)
    ([down]    . kuro--arrow-down)
    ([left]    . kuro--arrow-left)
    ([right]   . kuro--arrow-right)
    ([home]    . kuro--HOME)
    ([end]     . kuro--END)
    ([prior]   . kuro--PAGE-UP)
    ([next]    . kuro--PAGE-DOWN)
    ([delete]  . kuro--DELETE)
    ([insert]  . kuro--INSERT)
    ([S-prior] . kuro-scroll-up)
    ([S-next]  . kuro-scroll-down)
    ([S-end]   . kuro-scroll-bottom))
  "Alist of (KEY-VECTOR . COMMAND) pairs for navigation keys.
Covers arrow keys, home/end/page/insert/delete, and scrollback viewport.
Applied by `kuro--keymap-setup-navigation'.")

(defconst kuro--mouse-bindings
  '(([down-mouse-1] . kuro--mouse-press)
    ([down-mouse-2] . kuro--mouse-press)
    ([down-mouse-3] . kuro--mouse-press)
    ([mouse-1]      . kuro--mouse-release)
    ([mouse-2]      . kuro--mouse-release)
    ([mouse-3]      . kuro--mouse-release)
    ([mouse-4]      . kuro--mouse-scroll-up)
    ([mouse-5]      . kuro--mouse-scroll-down))
  "Alist of (KEY-VECTOR . COMMAND) pairs for mouse event bindings.
Applied by `kuro--keymap-setup-mouse'.")

(defconst kuro--yank-bindings
  '((yank          . kuro--yank)
    (yank-pop      . kuro--yank-pop)
    (clipboard-yank . kuro--yank))
  "Alist of (EMACS-CMD . KURO-CMD) remap entries for paste interception.
Each entry remaps an Emacs yank command to its kuro equivalent so all paste
paths go through the PTY with optional bracketed-paste wrapping.
Applied by `kuro--keymap-setup-yank'.")

(provide 'kuro-input-keymap-data)

;;; kuro-input-keymap-data.el ends here
