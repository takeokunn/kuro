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
  "Dispatch strict OSC 52 clipboard ACTION from Rust.
ACTION must be exactly (write TEXT TARGET) or (query nil TARGET), where
TARGET is \"clipboard\", \"primary\", or \"select\".  Malformed actions and
unsupported targets are ignored."
  (let ((a (make-symbol "action"))
        (payload (make-symbol "payload"))
        (target (make-symbol "target")))
    `(let ((,a ,action))
       (when (kuro--clipboard-action-strict-p ,a)
         (let ((,target (kuro--clipboard-action-target ,a)))
           (when (kuro--clipboard-target-kind ,target)
             (pcase (car ,a)
               ('write
                (let ((,payload (kuro--clipboard-action-payload ,a)))
                  (when (stringp ,payload)
                    (kuro--clipboard-write ,payload ,target))))
               ('query
                (when (null (kuro--clipboard-action-payload ,a))
                  (kuro--clipboard-query ,target))))))))))

(defmacro kuro--gated-poll (cadence fn)
  "Invoke FN when `kuro--mode-poll-frame-count' is an exact multiple of CADENCE.
Built on `kuro--when-divisible': the function FN is only called at intervals
of CADENCE frames, reducing per-frame Mutex acquisitions."
  `(kuro--when-divisible kuro--mode-poll-frame-count ,cadence (funcall ,fn)))

(provide 'kuro-poll-modes-macros)

;;; kuro-poll-modes-macros.el ends here
