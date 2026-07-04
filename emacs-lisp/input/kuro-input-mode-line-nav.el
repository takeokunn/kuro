;;; kuro-input-mode-line-nav.el --- Line-mode cursor motion helpers for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Cursor motion helpers for Kuro line mode.  These are split out from
;; `kuro-input-mode-history' so the history module can focus on completion
;; and history navigation.

;;; Code:

(require 'kuro-input-mode-macros)

;; Buffer-local variables defined in kuro-input-mode.el (loaded before this file).
(defvar kuro--line-buffer)
(defvar kuro--line-point)

(kuro--def-line-nav kuro--line-beginning-of-line
  "Move `kuro--line-point' to the beginning of the line (C-a)."
  (setq kuro--line-point 0))

(kuro--def-line-nav kuro--line-end-of-line
  "Move `kuro--line-point' to the end of the line (C-e)."
  (setq kuro--line-point (length kuro--line-buffer)))

(kuro--def-line-nav kuro--line-forward-char
  "Move `kuro--line-point' one character forward (C-f)."
  (when (< kuro--line-point (length kuro--line-buffer))
    (setq kuro--line-point (1+ kuro--line-point))))

(kuro--def-line-nav kuro--line-backward-char
  "Move `kuro--line-point' one character backward (C-b)."
  (when (> kuro--line-point 0)
    (setq kuro--line-point (1- kuro--line-point))))

(kuro--def-line-nav kuro--line-forward-word
  "Move `kuro--line-point' forward past the end of the next word (M-f)."
  (let ((s kuro--line-buffer))
    (setq kuro--line-point
          (kuro--line-skip-word-fwd s
                                    (kuro--line-skip-non-word-fwd s kuro--line-point)))))

(kuro--def-line-nav kuro--line-backward-word
  "Move `kuro--line-point' backward past the start of the previous word (M-b)."
  (let ((s kuro--line-buffer))
    (setq kuro--line-point
          (kuro--line-skip-word-bwd s
                                    (kuro--line-skip-non-word-bwd s kuro--line-point)))))

(provide 'kuro-input-mode-line-nav)
;;; kuro-input-mode-line-nav.el ends here
