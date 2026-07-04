;;; kuro-input-mode-data.el --- Data and state for kuro-input-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Pure data and buffer-local state for `kuro-input-mode'.
;; Keep the mode's mutable state, customization variables, and mode-line
;; lighter mapping here so the main aggregator file stays small.

;;; Code:

(require 'kuro-config)
(require 'kuro-ffi)

;; Forward references; declared without defaults so the real initializations
;; in the keymap and core modules remain authoritative.
(defvar kuro--keymap)
(defvar kuro--char-keymap)
(defvar kuro-mode-map)
;; Provided by savehist.el; referenced only under `with-eval-after-load'.
(defvar savehist-additional-variables)


;;;; Buffer-local input mode state

(kuro--defvar-permanent-local kuro--input-mode 'semi-char
  "Current input mode for this Kuro buffer.
One of: `char' (all keys -> PTY), `semi-char' (exceptions fall through
to Emacs), `line' (local Emacs editing; RET sends to PTY).")

(kuro--defvar-permanent-local kuro--line-buffer ""
  "Accumulated input string in `line' input mode.")

(kuro--defvar-permanent-local kuro--line-overlay nil
  "Overlay displaying line-mode typed input at the terminal cursor position.")

(kuro--defvar-permanent-local kuro--line-history-idx -1
  "Navigation index into `kuro--line-history' for the overlay path.
-1 means not navigating (current in-progress input).  0 = most recent entry.")

(kuro--defvar-permanent-local kuro--line-history-stash ""
  "In-progress input stashed while navigating history.
Restored when `kuro--line-history-next' reaches the bottom (idx -> -1).")

(kuro--defvar-permanent-local kuro--line-point 0
  "Cursor position within `kuro--line-buffer' in line input mode.
Index is 0-based: 0 = before first character,
(length kuro--line-buffer) = after last character (end of line).")

(kuro--defvar-permanent-local kuro--line-yank-length 0
  "Length of text most recently yanked into `kuro--line-buffer'.
Set by `kuro--line-yank'; used by `kuro--line-yank-pop' to locate and
replace the yanked region.")

(kuro--defvar-permanent-local kuro--line-undo-stack nil
  "Undo history for line-mode edits.
A list of (buffer-string . point) conses, most-recent-first.
Capped at `kuro--line-undo-max-depth' entries.")

(kuro--defvar-permanent-local kuro--line-yank-last-arg-idx -1
  "History index for M-. cycling in line mode.
-1 = not cycling (first invocation will start at 0 = most recent entry).
N = currently showing last-arg from history entry N.")

(kuro--defvar-permanent-local kuro--line-yank-last-arg-len 0
  "Length of text inserted by the most recent M-. invocation.
Used to locate and replace the inserted region on the next M-. cycle.")

(defvar kuro--line-history nil
  "Command history ring for Kuro line-mode minibuffer input.
Passed to `read-from-minibuffer' so the \\[previous-history-element] and
\\[next-history-element] bindings navigate prior commands.")

(defun kuro-input-mode-savehist-setup ()
  "Register `kuro--line-history' with `savehist-mode' for persistence.
Adds the variable to `savehist-additional-variables' so its contents
survive Emacs restarts when `savehist-mode' is active."
  (add-to-list 'savehist-additional-variables 'kuro--line-history))

(with-eval-after-load 'savehist
  (kuro-input-mode-savehist-setup))

(defcustom kuro-line-history-max-length 100
  "Maximum number of commands to retain in `kuro--line-history'.
When `kuro--line-commit' pushes a new entry and the list grows beyond
this limit, the oldest entries (tail of the list) are discarded.
Set to nil to keep an unlimited history."
  :type '(choice (integer :tag "Maximum entries")
                 (const   :tag "Unlimited" nil))
  :group 'kuro)

(defcustom kuro-line-use-minibuffer nil
  "When non-nil, line mode uses a minibuffer prompt for every keypress.
This enables full IME support (DDSKK, mozc, skk) because
`input-method-function' fires inside the minibuffer loop, before the
keymap layer intercepts events.

When nil (the default), characters accumulate in an overlay via
`kuro--line-self-insert'; `kuro-line-minibuffer-send' is still available
on \\[kuro-line-minibuffer-send] for one-off minibuffer sends."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-line-completion-function nil
  "Function called by `kuro--line-complete' (TAB) to provide word completions.
When non-nil it is called with one argument - the word immediately before
point in `kuro--line-buffer' - and must return a list of completion strings.
When nil, TAB falls back to prefix matching against `kuro--line-history',
returning all matching entries for display."
  :type '(choice (const nil) function)
  :group 'kuro)

(defcustom kuro-line-abbrev-alist nil
  "Alist of (ABBREV . EXPANSION) pairs for line-mode abbreviation expansion.
In line mode `kuro--line-expand-abbrev' (M-SPC) looks up the word
immediately before point in this list and replaces it with the expansion.
Example: `((\"gs\" . \"git status\") (\"gl\" . \"git log --oneline\"))"
  :type '(alist :key-type string :value-type string)
  :group 'kuro)


;;;; Mode-line lighter

(defconst kuro--input-mode-lighter-alist
  '((char      . " [C]")
    (semi-char . " [S]")
    (line      . " [L]"))
  "Alist mapping input mode symbols to their mode-line lighter strings.")

(defun kuro--input-mode-lighter ()
  "Return a mode-line string indicating the current input mode."
  (or (alist-get kuro--input-mode kuro--input-mode-lighter-alist) ""))

(provide 'kuro-input-mode-data)
;;; kuro-input-mode-data.el ends here
