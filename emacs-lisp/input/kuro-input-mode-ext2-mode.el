;;; kuro-input-mode-ext2-mode.el --- Public input-mode commands  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Public input-mode switching commands for Kuro.  Internal keymap
;; construction and installation live in kuro-input-mode-ext2-keymap.el.

;;; Code:

(require 'kuro-config)
(eval-and-compile
  (require 'kuro-keymap-macros)
  (require 'kuro-input-mode-ext2-data)
  (require 'kuro-input-mode-ext2-mode-macros))
(require 'kuro-input-mode-ext2-keymap)
(require 'kuro-input-mode-edit)
(require 'kuro-input-mode-line-nav)
(require 'kuro-input-mode-macros)

;; Functions defined in kuro-input-mode-line-display.el.
(declare-function kuro--line-mode-update-display "kuro-input-mode-line-display" ())
(declare-function kuro--line-clear-overlay        "kuro-input-mode-line-display" ())
(declare-function kuro--line-reset-state          "kuro-input-mode-line-state" ())
(declare-function kuro--line-commit               "kuro-input-mode-line" ())
(declare-function kuro--line-delete               "kuro-input-mode-line" ())
(declare-function kuro--line-newline              "kuro-input-mode-line" ())
(declare-function kuro--line-abort                "kuro-input-mode-line" ())
(declare-function kuro--line-kill-line            "kuro-input-mode-line" ())
(declare-function kuro--line-delete-char          "kuro-input-mode-line-ops" ())
(declare-function kuro--line-kill-to-bol          "kuro-input-mode-line-ops" ())
(declare-function kuro--line-unix-word-rubout     "kuro-input-mode-line-ops" ())
(declare-function kuro--line-beginning-of-line    "kuro-input-mode-line-nav" ())
(declare-function kuro--line-end-of-line          "kuro-input-mode-line-nav" ())
(declare-function kuro--line-forward-char         "kuro-input-mode-line-nav" ())
(declare-function kuro--line-backward-char        "kuro-input-mode-line-nav" ())
(declare-function kuro--line-forward-word         "kuro-input-mode-line-nav" ())
(declare-function kuro--line-backward-word        "kuro-input-mode-line-nav" ())
(declare-function kuro--line-kill-word            "kuro-input-mode-line-ops" ())
(declare-function kuro--line-backward-kill-word   "kuro-input-mode-line-ops" ())
(declare-function kuro--line-upcase-word          "kuro-input-mode-transform" ())
(declare-function kuro--line-downcase-word        "kuro-input-mode-transform" ())
(declare-function kuro--line-capitalize-word      "kuro-input-mode-transform" ())
(declare-function kuro--line-transpose-words      "kuro-input-mode-transform" ())
(declare-function kuro--line-transpose-chars      "kuro-input-mode-line-ops" ())
(declare-function kuro--line-quoted-insert        "kuro-input-mode-line" ())
(declare-function kuro--line-undo                 "kuro-input-mode-line" ())
(declare-function kuro--line-yank                 "kuro-input-mode-yank" ())
(declare-function kuro--line-yank-pop             "kuro-input-mode-yank" ())
(declare-function kuro--line-yank-last-arg        "kuro-input-mode-yank" ())
(declare-function kuro--line-history-prev         "kuro-input-mode-history-nav" ())
(declare-function kuro--line-history-next         "kuro-input-mode-history-nav" ())
(declare-function kuro--line-goto-history-oldest  "kuro-input-mode-history-nav" ())
(declare-function kuro--line-goto-history-newest  "kuro-input-mode-history-nav" ())
(declare-function kuro--line-complete             "kuro-input-mode-completion" ())
(declare-function kuro--line-complete-history     "kuro-input-mode-completion" ())
(declare-function kuro--line-history-search       "kuro-input-mode-completion" ())
(declare-function kuro--line-expand-abbrev        "kuro-input-mode-completion" ())
(declare-function kuro--line-self-insert          "kuro-input-mode-line" ())
(declare-function kuro--line-edit-in-buffer       "kuro-input-mode-edit" ())
(declare-function kuro-line-edit-send             "kuro-input-mode-edit" ())
(declare-function kuro-line-edit-discard          "kuro-input-mode-edit" ())

;; Buffer-local variable forward-declared in kuro-input-mode.el.
(defvar kuro--input-mode)

;;;; Public commands

;;;###autoload
(kuro--def-input-mode kuro-char-mode char
  "Kuro: char mode — all keys forwarded to PTY"
  (kuro--line-clear-overlay))

;;;###autoload
(kuro--def-input-mode kuro-semi-char-mode semi-char
  "Kuro: semi-char mode — exception keys pass through to Emacs"
  (kuro--line-clear-overlay))

;;;###autoload
(kuro--def-input-mode kuro-line-mode line
  "Kuro: line mode — type locally, RET sends, C-g cancels"
  (kuro--line-mode-update-display))

;;;###autoload
(defun kuro-cycle-input-mode ()
  "Cycle through Kuro input modes."
  (interactive)
  (kuro--with-kuro-mode
   (pcase (cdr (assq kuro--input-mode kuro--input-mode-cycle-table))
     ((and command (pred commandp))
      (funcall command))
     (_
      (kuro-semi-char-mode)))))

(provide 'kuro-input-mode-ext2-mode)
;;; kuro-input-mode-ext2-mode.el ends here
