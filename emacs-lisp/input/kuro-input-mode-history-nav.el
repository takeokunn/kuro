;;; kuro-input-mode-history-nav.el --- History navigation for line mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; History navigation commands for Kuro line mode.

;;; Code:

(require 'kuro-input-mode-history-nav-state)
(require 'kuro-input-mode-macros)

(defvar kuro--line-history)
(defvar kuro--line-history-idx)
(defvar kuro--line-history-stash)

(kuro--def-line-history-nav kuro--line-history-prev
  "Navigate to the previous (older) entry in line-mode history.
On the first call stashes the current in-progress input, then moves
backward through `kuro--line-history' (index 0 = most recent)."
  kuro--line-history
  t
  (kuro--line-history-prev-index)
  (nth kuro--line-history-idx kuro--line-history))

(kuro--def-line-history-nav kuro--line-history-next
  "Navigate to the next (newer) entry in line-mode history.
At the bottom (idx -1) does nothing.  At index 0 restores the stashed
in-progress input and resets the navigation index to -1."
  (/= kuro--line-history-idx -1)
  nil
  (kuro--line-history-next-index)
  (if (= kuro--line-history-idx -1)
      kuro--line-history-stash
    (nth kuro--line-history-idx kuro--line-history)))

(kuro--def-line-history-nav kuro--line-goto-history-oldest
  "Jump to the oldest entry in line-mode history (readline M-<).
Stashes the current in-progress input the same way as
`kuro--line-history-prev', then moves directly to the last element of
`kuro--line-history'.  No-op when the history list is empty."
  kuro--line-history
  t
  (kuro--line-history-last-index)
  (nth kuro--line-history-idx kuro--line-history))

(kuro--def-line-history-nav kuro--line-goto-history-newest
  "Return to the most recent (in-progress) input in line-mode (readline M->).
Restores `kuro--line-history-stash' and resets the navigation index to -1,
mirroring the behavior of `kuro--line-history-next' at the bottom of history."
  (/= kuro--line-history-idx -1)
  nil
  -1
  kuro--line-history-stash)

(provide 'kuro-input-mode-history-nav)
;;; kuro-input-mode-history-nav.el ends here
