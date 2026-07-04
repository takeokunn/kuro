;;; kuro-input-mode-history.el --- Completion/history compatibility wrapper  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Compatibility wrapper that loads the split line-mode completion and
;; history-navigation modules.  Loaded automatically at the end of
;; `kuro-input-mode'.

;;; Code:

(require 'kuro-input-mode-completion)
(require 'kuro-input-mode-history-nav)

(provide 'kuro-input-mode-history)
;;; kuro-input-mode-history.el ends here
