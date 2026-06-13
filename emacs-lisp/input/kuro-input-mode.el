;;; kuro-input-mode.el --- Three-mode input system for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Provides three named input modes for `kuro-mode' buffers:
;;
;;   `char'      — ALL keys forwarded to PTY (no Emacs interception).
;;                 Raw terminal mode: binary apps, screen editors, etc.
;;
;;   `semi-char' — Keys in `kuro-keymap-exceptions' fall through to Emacs
;;                 (C-x, M-x, C-g, etc.); everything else → PTY.
;;                 This is the DEFAULT mode.
;;
;;   `line'      — Characters accumulate in Emacs.  RET sends the full
;;                 line to the PTY.  Full Emacs editing is available:
;;                 isearch, company-mode, hippie-expand.  Typed input is
;;                 shown via an overlay at the terminal cursor position.
;;                 C-g cancels without sending.
;;
;;                 For full IME support (DDSKK, mozc, skk), set
;;                 `kuro-line-use-minibuffer' to t.  In that mode every
;;                 keypress opens a minibuffer prompt where `input-method-
;;                 function' fires normally.  Alternatively, call
;;                 `kuro-line-minibuffer-send' (C-c C-r in line mode)
;;                 at any time to explicitly switch to the minibuffer path.
;;
;; API:
;;   `kuro-char-mode'            — switch to char mode
;;   `kuro-semi-char-mode'       — switch to semi-char mode (default)
;;   `kuro-line-mode'            — switch to line mode
;;   `kuro-cycle-input-mode'     — cycle: semi-char → char → line → semi-char
;;   `kuro-line-minibuffer-send' — read via minibuffer (IME-compatible)
;;
;; Mode-line: each kuro buffer shows the current mode as "[C]", "[S]", or "[L]"
;; appended after the mode name.

;;; Code:

(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-input-mode-macros)

(declare-function kuro--build-keymap    "kuro-input-keymap" ())
(declare-function kuro--schedule-immediate-render "kuro-input" ())
(declare-function kuro--send-key        "kuro-ffi"   (key))

;; Forward references — declared without a default value so they do not
;; shadow the real initializations in kuro-input-keymap.el and kuro.el.
(defvar kuro--keymap)
(defvar kuro--char-keymap)
(defvar kuro-mode-map)
;; Provided by savehist.el; referenced only under `with-eval-after-load'.
(defvar savehist-additional-variables)


;;;; Buffer-local input mode state

(kuro--defvar-permanent-local kuro--input-mode 'semi-char
  "Current input mode for this Kuro buffer.
One of: `char' (all keys → PTY), `semi-char' (exceptions fall through
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
Restored when `kuro--line-history-next' reaches the bottom (idx → -1).")

(kuro--defvar-permanent-local kuro--line-point 0
  "Cursor position within `kuro--line-buffer' in line input mode.
Index is 0-based: 0 = before first character,
\(length kuro--line-buffer\) = after last character (end of line).")

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
survive Emacs restarts when `savehist-mode' is active.  Called
automatically by the `with-eval-after-load' form below; you can also
call it explicitly in your init file."
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
When non-nil it is called with one argument — the word immediately before
point in `kuro--line-buffer' — and must return a list of completion strings.
When nil, TAB falls back to prefix matching against `kuro--line-history',
returning all matching entries for display."
  :type '(choice (const nil) function)
  :group 'kuro)

(defcustom kuro-line-abbrev-alist nil
  "Alist of (ABBREV . EXPANSION) pairs for line-mode abbreviation expansion.
In line mode `kuro--line-expand-abbrev' (M-SPC) looks up the word
immediately before point in this list and replaces it with the expansion.
Example: \\='((\"gs\" . \"git status\") (\"gl\" . \"git log --oneline\"))"
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


;;;; Line mode: undo stack

(defun kuro--line-undo ()
  "Undo the last edit to the line buffer (C-/ or C-_).
Restores the most recent state from `kuro--line-undo-stack'.
No-ops with a message when the stack is empty."
  (interactive)
  (if (null kuro--line-undo-stack)
      (message "kuro: no further undo information")
    (let ((state (pop kuro--line-undo-stack)))
      (setq kuro--line-buffer (car state))
      (setq kuro--line-point  (cdr state))
      (kuro--line-mode-update-display))))


(defun kuro--line-word-bounds-forward ()
  "Return (START . END) for the word at or after `kuro--line-point'."
  (let* ((s   kuro--line-buffer)
         (beg (kuro--line-skip-non-word-fwd s kuro--line-point))
         (end (kuro--line-skip-word-fwd     s beg)))
    (cons beg end)))


;;;; Line mode: overlay display

(defun kuro--line-mode-update-display ()
  "Refresh the line-mode input overlay at the Emacs cursor position.
The overlay uses an after-string so the terminal buffer is never modified
(it remains read-only).  The cursor position `kuro--line-point' is shown
as a cursor-face block; characters before and after use underline."
  (when (overlayp kuro--line-overlay)
    (delete-overlay kuro--line-overlay)
    (setq kuro--line-overlay nil))
  (when (eq kuro--input-mode 'line)
    (let* ((s kuro--line-buffer)
           (p (min kuro--line-point (length s)))
           (before   (substring s 0 p))
           (at-char  (if (< p (length s)) (substring s p (1+ p)) " "))
           (after    (if (< p (length s)) (substring s (1+ p)) ""))
           (ov (make-overlay (point) (point) nil nil t)))
      (overlay-put ov 'after-string
                   (concat
                    (propertize before  'face '(:inherit default :underline t))
                    (propertize at-char 'face 'cursor)
                    (propertize after   'face '(:inherit default :underline t))))
      (setq kuro--line-overlay ov))))

(defun kuro--line-clear-overlay ()
  "Remove the line-mode input overlay without modifying the buffer."
  (when (overlayp kuro--line-overlay)
    (delete-overlay kuro--line-overlay)
    (setq kuro--line-overlay nil)))


;;;; Line mode: key handlers

(defun kuro--line-self-insert ()
  "Append `last-command-event' to the line buffer at `kuro--line-point'.
When `kuro-line-use-minibuffer' is non-nil, pre-fills the typed character
and immediately delegates to `kuro-line-minibuffer-send' for full IME
support (DDSKK, mozc); `input-method-function' then fires in the
minibuffer context where it operates correctly."
  (interactive)
  (when (characterp last-command-event)
    (kuro--line-undo-push)
    (let ((p kuro--line-point))
      (setq kuro--line-buffer
            (concat (substring kuro--line-buffer 0 p)
                    (string last-command-event)
                    (substring kuro--line-buffer p)))
      (setq kuro--line-point (1+ p)))
    (if (bound-and-true-p kuro-line-use-minibuffer)
        (kuro-line-minibuffer-send)
      (kuro--line-mode-update-display))))

(defun kuro--line-quoted-insert ()
  "Read the next key literally and insert it into the line buffer (C-q).
Mirrors readline / Emacs `quoted-insert': the following keystroke — or an
octal/hex/decimal code accepted by `read-quoted-char' — is inserted
verbatim at `kuro--line-point'.  This lets you embed control characters
such as a literal TAB, ESC, or carriage return into the line before it is
dispatched to the PTY on RET, without those keys triggering their normal
line-mode editing commands."
  (interactive)
  (let* ((ch (read-quoted-char "C-q-"))
         (s  (char-to-string ch))
         (p  kuro--line-point))
    (kuro--with-line-edit-undo
     (setq kuro--line-buffer
           (concat (substring kuro--line-buffer 0 p) s (substring kuro--line-buffer p))
           kuro--line-point (+ p (length s))))))

(defun kuro--line-delete ()
  "Remove the character before `kuro--line-point' (backspace in line mode)."
  (interactive)
  (when (> kuro--line-point 0)
    (kuro--line-undo-push)
    (let ((p kuro--line-point))
      (setq kuro--line-buffer
            (concat (substring kuro--line-buffer 0 (1- p))
                    (substring kuro--line-buffer p)))
      (setq kuro--line-point (1- p)))
    (kuro--line-mode-update-display)))

(defun kuro--line-newline ()
  "Insert a literal newline into the line buffer without sending (C-o).
Lets you compose a multi-line command — a for-loop, a heredoc body, a
pasted block — entirely within line mode, then dispatch the whole thing to
the PTY at once with RET.  The embedded newlines are sent verbatim ahead of
the final carriage return, so the shell runs each line in sequence."
  (interactive)
  (kuro--line-undo-push)
  (let ((p kuro--line-point))
    (setq kuro--line-buffer
          (concat (substring kuro--line-buffer 0 p)
                  "\n"
                  (substring kuro--line-buffer p)))
    (setq kuro--line-point (1+ p)))
  (kuro--line-mode-update-display))

(defun kuro--line-kill-line ()
  "Kill from `kuro--line-point' to end of line (C-k in line mode)."
  (interactive)
  (kuro--with-line-edit-undo
   (setq kuro--line-buffer (substring kuro--line-buffer 0 kuro--line-point))))

(defun kuro--line-commit ()
  "Send accumulated line buffer to the PTY followed by a carriage return.
Clears the overlay and the accumulator before dispatching so a failed
send does not leave stale visual state."
  (interactive)
  (let ((text kuro--line-buffer))
    (when (> (length text) 0)
      (push text kuro--line-history)
      (when (and kuro-line-history-max-length
                 (> (length kuro--line-history) kuro-line-history-max-length))
        (setq kuro--line-history
              (seq-take kuro--line-history kuro-line-history-max-length))))
    (setq kuro--line-buffer      ""
          kuro--line-point       0
          kuro--line-history-idx -1
          kuro--line-history-stash ""
          kuro--line-undo-stack  nil)
    (kuro--line-clear-overlay)
    (kuro--send-key (concat text "\r"))
    (kuro--schedule-immediate-render)))

(defun kuro--line-abort ()
  "Cancel line-mode input without sending anything to the PTY."
  (interactive)
  (setq kuro--line-buffer "" kuro--line-point 0 kuro--line-undo-stack nil)
  (kuro--line-clear-overlay)
  (message "kuro: line input cancelled"))


(require 'kuro-input-mode-history)

(provide 'kuro-input-mode)
;;; kuro-input-mode.el ends here
