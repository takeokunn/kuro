;;; kuro-input-mode-line-ops.el --- Line-mode kill and word ops  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Line-mode editing commands that mutate the in-memory buffer.  Keep these
;; separate from keymap wiring and from the navigation/transform helpers so
;; the command layer stays narrow.

;;; Code:

(require 'kuro-input-mode-macros)

;; Functions defined in kuro-input-mode-line.el.
(declare-function kuro--line-skip-non-word-fwd "kuro-input-mode-line" (s pos))
(declare-function kuro--line-skip-word-fwd     "kuro-input-mode-line" (s pos))
(declare-function kuro--line-skip-non-word-bwd "kuro-input-mode-line" (s pos))
(declare-function kuro--line-skip-word-bwd     "kuro-input-mode-line" (s pos))
(declare-function kuro--line-skip-unix-word-bwd "kuro-input-mode-line" (s pos))

;; Buffer-local variables defined in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-point)

(kuro--def-line-command kuro--line-kill-word
    "Kill from `kuro--line-point' to the end of the next word."
  (let* ((p     kuro--line-point)
         (bound (kuro--line-skip-word-fwd
                 kuro--line-buffer
                 (kuro--line-skip-non-word-fwd kuro--line-buffer p))))
    (kuro--line-delete-with-undo p bound)))

(kuro--def-line-command kuro--line-backward-kill-word
    "Kill from the start of the previous word to `kuro--line-point'."
  (let* ((p     kuro--line-point)
         (bound (kuro--line-skip-word-bwd
                 kuro--line-buffer
                 (kuro--line-skip-non-word-bwd kuro--line-buffer p))))
    (kuro--line-delete-with-undo bound p)))

(kuro--def-line-command kuro--line-delete-char
    "Delete the character at `kuro--line-point'."
  (when (< kuro--line-point (length kuro--line-buffer))
    (kuro--line-delete-with-undo kuro--line-point (1+ kuro--line-point))))

(kuro--def-line-command kuro--line-kill-to-bol
    "Kill from the beginning of the line to `kuro--line-point'."
  (kuro--line-delete-with-undo 0 kuro--line-point))

(kuro--def-line-command kuro--line-transpose-chars
    "Transpose the character before point with the one at point.
At end of line, transposes the two characters before point."
  (let* ((s kuro--line-buffer)
         (len (length s))
         (p (if (= kuro--line-point len)
                (max 0 (1- kuro--line-point))
              kuro--line-point)))
    (when (>= p 1)
      (kuro--line-replace-range-with-undo (1- p) (1+ p)
                                          (string (aref s p) (aref s (1- p)))))))

(kuro--def-line-command kuro--line-unix-word-rubout
    "Kill from `kuro--line-point' backward to the nearest whitespace.
Uses bash unix-word-rubout semantics: only space/tab delimit tokens, so
hyphenated words and dotted paths are killed as a single token.  Contrast
with `kuro--line-backward-kill-word', which stops at any non-word char."
  (let* ((s kuro--line-buffer)
         (p kuro--line-point)
         (start (kuro--line-skip-unix-word-bwd s p)))
    (kuro--line-delete-with-undo start p)))

(provide 'kuro-input-mode-line-ops)
;;; kuro-input-mode-line-ops.el ends here
