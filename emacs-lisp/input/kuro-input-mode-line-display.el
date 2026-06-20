;;; kuro-input-mode-line-display.el --- Line-mode overlay display helpers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Overlay refresh and suspend helpers for `kuro-input-mode' line mode.
;; Kept in a separate module so editing commands can depend on the display
;; continuation without carrying the overlay implementation inline.

;;; Code:

(declare-function kuro--line-reset-state "kuro-input-mode-line-state" ())

;; Forward declarations for buffer-local state defined in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-overlay)
(defvar kuro--line-point)
(defvar kuro--input-mode)


(defun kuro--line-mode-update-display ()
  "Refresh the line-mode input overlay at the Emacs cursor position.
The overlay uses an after-string, so the terminal buffer remains read-only.
The cursor position `kuro--line-point' is shown
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

(defsubst kuro--line-suspend-state ()
  "Reset transient line state and clear the overlay."
  (kuro--line-reset-state)
  (kuro--line-clear-overlay))

(provide 'kuro-input-mode-line-display)
;;; kuro-input-mode-line-display.el ends here
