;;; kuro-input-mode-ext2.el --- Aggregator for kuro-input-mode-ext2 helpers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Second extension of `kuro-input-mode'.  Split from `kuro-input-mode-ext'
;; to keep files under the 500-line policy.  This file now just loads the
;; data, minibuffer-send, keymap, and mode-command helpers.
;;
;; Loaded automatically via `kuro-input-mode-ext'.  Do not require directly.

;;; Code:

(require 'kuro-input-mode-ext2-data)
(require 'kuro-input-mode-ext2-send)
(require 'kuro-input-mode-ext2-keymap)
(require 'kuro-input-mode-ext2-mode)

(provide 'kuro-input-mode-ext2)
;;; kuro-input-mode-ext2.el ends here
