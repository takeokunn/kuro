;;; kuro-input-mode-ext2-send.el --- Minibuffer send for kuro-input-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Minibuffer-based line send path for Kuro line mode.  Split out so the
;; keymap/mode-switch logic in `kuro-input-mode-ext2-mode' stays separate.

;;; Code:

(require 'kuro-input-mode-line)
(require 'kuro-input-mode-macros)
(require 'kuro-config)

(declare-function kuro--schedule-immediate-render "kuro-input-render" ())
(declare-function kuro--send-key "kuro-ffi" (key))

;; Buffer-local variables forward-declared in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-history)

;;;###autoload
(defun kuro-line-minibuffer-send ()
  "Read a line via minibuffer and send it to the PTY.
Unlike the overlay accumulator, `read-from-minibuffer' fully supports
input methods (DDSKK, mozc, skk) because `input-method-function' fires
inside the minibuffer input loop before any keymap dispatch.  Command
history is accessible via \\[previous-history-element] /
\\[next-history-element].

The current `kuro--line-buffer' is used as the initial contents.
Canceling quits without sending; the line buffer is cleared in all cases
so no stale state accumulates.

Bound to \\[kuro-line-minibuffer-send] in line mode.  When
`kuro-line-use-minibuffer' is non-nil, every keypress auto-invokes this
function with the typed character pre-filled."
  (interactive)
  (kuro--with-kuro-mode
   (let ((initial kuro--line-buffer))
     (kuro--line-suspend-state)
     (condition-case nil
         (let ((text (read-from-minibuffer "» " initial nil nil
                                           'kuro--line-history)))
           (kuro--send-key (concat text "\r"))
           (kuro--schedule-immediate-render))
       (quit nil)))))

(provide 'kuro-input-mode-ext2-send)
;;; kuro-input-mode-ext2-send.el ends here
