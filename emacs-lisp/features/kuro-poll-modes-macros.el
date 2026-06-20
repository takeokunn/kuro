;;; kuro-poll-modes-macros.el --- Macros for kuro-poll-modes.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Cadence-gating macro for tiered terminal mode polling.

;;; Code:

(defvar kuro--tier1-poll-fns)

(defmacro kuro--run-tier1-poll-fns ()
  "Run the fixed tier-1 poll sequence in order.
The ordered function list remains data in `kuro--tier1-poll-fns'."
  `(progn
     ,@(mapcar (lambda (fn) `(,fn)) kuro--tier1-poll-fns)))

(defmacro kuro--dispatch-clipboard-action (action)
  "Dispatch a single clipboard ACTION from `kuro--poll-clipboard-actions'.
The action key is one of `write' or `query'.

ACTION is a 3-element list (TAG PAYLOAD TARGET) where TARGET selects the
Emacs selection to route writes to (see `kuro--clipboard-write').  For
backward compatibility a 2-element legacy action — either the list
\(TAG PAYLOAD) or the cons (TAG . PAYLOAD) — is also accepted; the TARGET
then defaults to nil (clipboard)."
  (let ((a (make-symbol "action")))
    `(let ((,a ,action))
       (pcase (car ,a)
         ('write (kuro--clipboard-write (kuro--clipboard-action-payload ,a)
                                        (kuro--clipboard-action-target ,a)))
         ('query (kuro--clipboard-query))))))

(defmacro kuro--gated-poll (cadence fn)
  "Invoke FN when `kuro--mode-poll-frame-count' is an exact multiple of CADENCE.
Built on `kuro--when-divisible': the function FN is only called at intervals
of CADENCE frames, reducing per-frame Mutex acquisitions."
  `(kuro--when-divisible kuro--mode-poll-frame-count ,cadence (funcall ,fn)))

(provide 'kuro-poll-modes-macros)

;;; kuro-poll-modes-macros.el ends here
