;;; kuro-hyperlinks-macros.el --- Macros for OSC 8 hyperlinks  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Macro helpers for creating clickable hyperlink overlays.

;;; Code:

(defmacro kuro--make-hyperlink-overlay (beg end uri)
  "Create a clickable hyperlink overlay from BEG to END for URI."
  `(let ((ov (make-overlay ,beg ,end nil t nil)))
     (overlay-put ov 'face 'kuro-hyperlink)
     (overlay-put ov 'kuro-hyperlink-uri ,uri)
     (overlay-put ov 'mouse-face 'highlight)
     (overlay-put ov 'help-echo ,uri)
     (overlay-put ov 'keymap kuro--hyperlink-keymap)
     (push ov kuro--hyperlink-overlays)
     ov))

(provide 'kuro-hyperlinks-macros)

;;; kuro-hyperlinks-macros.el ends here
