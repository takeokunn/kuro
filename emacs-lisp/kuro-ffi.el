;;; kuro-ffi.el --- FFI wrapper functions for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides wrapper functions around the Rust FFI bindings.
;; These functions handle the low-level communication with the Rust core.
;;
;; # Architecture
;;
;; All wrappers share the same error-handling pattern via `kuro--call':
;;   1. Guard: only call Rust when `kuro--initialized' is non-nil.
;;   2. Catch: wrap every Rust call in `condition-case' to prevent crashes.
;;   3. Fallback: return a caller-supplied default on error.
;;
;; This eliminates the boilerplate that previously appeared in every function.

;;; Code:

(require 'kuro-config)

;; These functions are provided by the Rust dynamic module at runtime.
;; declare-function suppresses byte/native compiler "not known to be defined" warnings.
(declare-function kuro-core-init                    "ext:kuro-core" (command rows cols))
(declare-function kuro-core-send-key                "ext:kuro-core" (bytes))
(declare-function kuro-core-poll-updates            "ext:kuro-core" ())
(declare-function kuro-core-poll-updates-with-faces "ext:kuro-core" ())
(declare-function kuro-core-resize                  "ext:kuro-core" (rows cols))
(declare-function kuro-core-shutdown                "ext:kuro-core" ())
(declare-function kuro-core-get-cursor              "ext:kuro-core" ())
(declare-function kuro-core-is-process-alive        "ext:kuro-core" ())

(defvar-local kuro--initialized nil
  "Non-nil if Kuro has been initialized.
Buffer-local so that multiple kuro buffers each track their own
session state independently.  When nil, all FFI calls are suppressed.")
(put 'kuro--initialized 'permanent-local t)

(defvar-local kuro--col-to-buf-map (make-hash-table :test 'eql)
  "Per-row mapping of grid column → buffer char offset.
Each key is a row number (integer), each value is a vector mapping
grid column index to buffer character offset.")
(put 'kuro--col-to-buf-map 'permanent-local t)

(defvar-local kuro--resize-pending nil
  "Non-nil when a resize event is pending from the window-size-change hook.
Value is a (NEW-ROWS . NEW-COLS) cons cell, or nil when no resize is pending.")
(put 'kuro--resize-pending 'permanent-local t)

;;; Core dispatch macro

(defmacro kuro--call (fallback &rest body)
  "Guard a Rust FFI call with initialization check and error recovery.

Evaluates BODY only when `kuro--initialized' is non-nil.
On error, logs a message and returns FALLBACK.

Usage:
  (kuro--call nil (kuro-core-get-cursor))
  (kuro--call 0   (kuro-core-get-scroll-offset))"
  (declare (indent 1))
  `(when kuro--initialized
     (condition-case _err
         (progn ,@body)
       (error ,fallback))))

;;; Session lifecycle

(defun kuro--init (command &optional rows cols)
  "Initialize Kuro with COMMAND (e.g., \"bash\").
ROWS and COLS specify the initial terminal dimensions.  When omitted,
`kuro--default-rows' and `kuro--default-cols' are used.  Callers should always
pass the actual window dimensions so full-screen programs start with the correct
geometry and do not suffer a SIGWINCH race on their first render.
Returns t if successful, nil otherwise."
  (interactive "sShell command: ")
  (condition-case err
      (let* ((r (or rows kuro--default-rows))
             (c (or cols kuro--default-cols))
             (result (kuro-core-init command r c)))
        (setq kuro--initialized (not (null result)))
        result)
    (error
     (message "Kuro initialization error: %s" err)
     nil)))

(defun kuro--shutdown ()
  "Shutdown the Kuro terminal session.
Returns t if successful, nil otherwise."
  (kuro--call nil
    (kuro-core-shutdown)
    (setq kuro--initialized nil)
    t))

;;; Input / output

(defun kuro--send-key (data)
  "Send DATA to the terminal.
DATA may be a string or a vector of integer character codes.
Vectors are converted to strings before being passed to the Rust FFI.
Returns t if successful, nil otherwise."
  (kuro--call nil
    (let ((bytes (if (stringp data)
                     data
                   (apply #'string (append data nil)))))
      (kuro-core-send-key bytes))))

(defun kuro--poll-updates ()
  "Poll for terminal updates.
Returns a list of (ROW . TEXT) pairs for dirty lines."
  (kuro--call nil (kuro-core-poll-updates)))

(defun kuro--poll-updates-with-faces ()
  "Poll for terminal updates with face information.
Returns (DIRTY-LINES . COL-TO-BUF-VECTOR) where DIRTY-LINES is a list
of ((ROW . TEXT) . FACE-RANGES) and COL-TO-BUF-VECTOR is a vector mapping
grid columns to buffer character offsets.  FACE-RANGES is a list of
\(START-COL END-COL FG BG FLAGS) for each text segment."
  (kuro--call nil (kuro-core-poll-updates-with-faces)))

(defun kuro--resize (rows cols)
  "Resize the terminal to ROWS x COLS.
Returns t if successful, nil otherwise."
  (kuro--call nil (kuro-core-resize rows cols)))

;;; Process state

(defun kuro--is-process-alive ()
  "Return non-nil if the PTY child process is still running.
Returns nil when `kuro--initialized' is nil (no active session).
Falls back to t (alive assumed) on FFI error to prevent spurious buffer
kills — unlike other wrappers that return nil on error, this one uses t
so that a transient Rust failure does not destroy the buffer."
  (kuro--call t (kuro-core-is-process-alive)))

;;; Cursor queries

(defun kuro--get-cursor ()
  "Get current cursor position.
Returns (ROW . COL) pair."
  (kuro--call '(0 . 0) (kuro-core-get-cursor)))

(provide 'kuro-ffi)

;;; kuro-ffi.el ends here
