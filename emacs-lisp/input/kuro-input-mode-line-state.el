;;; kuro-input-mode-line-state.el --- Line-mode state helpers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Stateful helpers for `kuro-input-mode' line mode.  This module owns the
;; undo stack and transient buffer state so `kuro-input-mode-macros' can stay
;; focused on CPS-style inline forms.

;;; Code:

(require 'seq)

;; Forward declarations for buffer-local state defined in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-point)
(defvar kuro--line-undo-stack)
(defvar kuro--line-history-idx)
(defvar kuro--line-history-stash)
(defvar kuro--line-history)
(defvar kuro--line-yank-length)
(defvar kuro--line-yank-last-arg-idx)
(defvar kuro--line-yank-last-arg-len)

;; Declare the display-refresh continuation so the helper definitions do not
;; produce byte-compiler warnings.
(declare-function kuro--line-mode-update-display "kuro-input-mode-line-display" ())

(defconst kuro--line-undo-max-depth 100
  "Maximum number of undo states retained in `kuro--line-undo-stack'.")

(defun kuro--line-undo-push ()
  "Push the current line-buffer state onto `kuro--line-undo-stack'.
Called at the start of every editing command that mutates `kuro--line-buffer'."
  (push (cons kuro--line-buffer kuro--line-point) kuro--line-undo-stack)
  (when (> (length kuro--line-undo-stack) kuro--line-undo-max-depth)
    (setq kuro--line-undo-stack
          (seq-take kuro--line-undo-stack kuro--line-undo-max-depth))))

(defun kuro--line-set-buffer (text)
  "Set line buffer to TEXT with point at end, then refresh display.
CPS continuation for history navigation and whole-buffer completion."
  (setq kuro--line-buffer text
        kuro--line-point  (length text))
  (kuro--line-mode-update-display))

(defsubst kuro--line-reset-state ()
  "Reset transient line-mode state to its initial values."
  (setq kuro--line-buffer ""
        kuro--line-point 0
        kuro--line-history-idx -1
        kuro--line-history-stash ""
        kuro--line-undo-stack nil
        kuro--line-yank-length 0
        kuro--line-yank-last-arg-idx -1
        kuro--line-yank-last-arg-len 0))

(provide 'kuro-input-mode-line-state)

;;; kuro-input-mode-line-state.el ends here
