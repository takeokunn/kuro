;;; kuro-input-mode-transform.el --- Word-case transforms for line mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Line-mode word transforms split out from `kuro-input-mode-ext'.

;;; Code:

(require 'kuro-input-mode-line)
(require 'kuro-input-mode-macros)

;; Buffer-local variables defined in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-point)


(kuro--def-line-word-transform kuro--line-upcase-word
  "Upcase the word from `kuro--line-point' forward."
  (upcase (substring s start end)))

(kuro--def-line-word-transform kuro--line-downcase-word
  "Downcase the word from `kuro--line-point' forward."
  (downcase (substring s start end)))

(kuro--def-line-word-transform kuro--line-capitalize-word
  "Capitalize the word from `kuro--line-point' forward."
  (concat (upcase (substring s start (1+ start)))
          (downcase (substring s (1+ start) end))))

(defun kuro--line-transpose-words ()
  "Transpose the word before `kuro--line-point' with the word after it.
Point advances to the end of the second word after transposition."
  (interactive)
  (let* ((s        kuro--line-buffer)
         (p        kuro--line-point)
         (w1-end   (kuro--line-skip-non-word-bwd s p))
         (w1-start (kuro--line-skip-word-bwd     s w1-end))
         (w2-start (kuro--line-skip-non-word-fwd s p))
         (w2-end   (kuro--line-skip-word-fwd     s w2-start)))
    (when (and (> w1-end w1-start) (> w2-end w2-start))
      (let ((between (substring s w1-end w2-start))
            (w1      (substring s w1-start w1-end))
            (w2      (substring s w2-start w2-end)))
        (kuro--line-replace-range-with-undo w1-start w2-end
                                            (concat w2 between w1))))))

(provide 'kuro-input-mode-transform)
;;; kuro-input-mode-transform.el ends here
