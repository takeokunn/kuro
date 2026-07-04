;;; kuro-input-mode-history-nav-state.el --- History navigation state helpers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Pure helpers and shared state for line-mode history navigation.

;;; Code:

(require 'kuro-input-mode-line-state)

(defsubst kuro--line-history-stash-if-fresh ()
  "Stash the current buffer when first entering history navigation (idx = -1)."
  (when (= kuro--line-history-idx -1)
    (setq kuro--line-history-stash kuro--line-buffer)))

(defsubst kuro--line-history-last-index ()
  "Return the index of the oldest history entry."
  (1- (length kuro--line-history)))

(defsubst kuro--line-history-prev-index ()
  "Return the history index reached by moving to older history."
  (if (= kuro--line-history-idx -1)
      0
    (min (1+ kuro--line-history-idx)
         (kuro--line-history-last-index))))

(defsubst kuro--line-history-next-index ()
  "Return the history index reached by moving to newer history."
  (1- kuro--line-history-idx))

(provide 'kuro-input-mode-history-nav-state)
;;; kuro-input-mode-history-nav-state.el ends here
