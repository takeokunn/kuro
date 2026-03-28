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
;;
;; # Multi-session support
;;
;; Each buffer has a `kuro--session-id' (a non-negative integer) set by
;; `kuro--init' (which allocates a new ID via an atomic counter) or by
;; `kuro-attach' (which restores an existing ID for a detached session).
;; Per-session FFI calls pass this ID as their first argument so that
;; multiple kuro buffers can coexist without interfering with each other.
;; Exception: `kuro-core-list-sessions' is a global query that takes no ID.

;;; Code:

(require 'kuro-config)

;;; Error logging

(defcustom kuro-log-errors t
  "Non-nil means log FFI errors to the `*kuro-log*' buffer.
When nil, errors caught by `kuro--call' are silently discarded."
  :type 'boolean
  :group 'kuro)

(defconst kuro--log-buffer-name "*kuro-log*"
  "Name of the buffer used for Kuro error logging.")

(defconst kuro--log-max-size 102400
  "Maximum size in bytes for the `*kuro-log*' buffer.
When exceeded, the oldest half of the buffer is truncated.")

(defsubst kuro--log (err)
  "Write a timestamped error entry for ERR to the `*kuro-log*' buffer.
ERR is a condition-case error value (a list whose car is the error symbol).
Only called when `kuro-log-errors' is non-nil.  Uses `with-current-buffer'
and `insert' for speed (no echo-area overhead)."
  (let ((buf (get-buffer-create kuro--log-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'special-mode)
        (special-mode))
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (format "[%s] ERROR: %s\n"
                        (format-time-string "%H:%M:%S")
                        (error-message-string err)))
        (when (> (buffer-size) kuro--log-max-size)
          (delete-region (point-min) (- (point-max) (/ kuro--log-max-size 2))))))))

(defun kuro-show-log ()
  "Display the `*kuro-log*' buffer."
  (interactive)
  (let ((buf (get-buffer-create kuro--log-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'special-mode)
        (special-mode)))
    (display-buffer buf)))

;;; Structural macros
;; Defined first so they are available for the variable declarations below.

(defmacro kuro--when-divisible (counter divisor &rest body)
  "Execute BODY when COUNTER is divisible by DIVISOR (counter mod divisor = 0).
This is the fundamental cadence-gating primitive used for periodic polling and
animation timing: BODY is a continuation invoked at exact multiples of DIVISOR."
  (declare (indent 2))
  `(when (zerop (mod ,counter ,divisor))
     ,@body))

(defmacro kuro--defvar-permanent-local (name value &optional doc)
  "Define NAME as a buffer-local variable with VALUE, marked permanent-local.
Convenience macro for the common pattern:
  (defvar-local NAME VALUE DOC)
  (put \\='NAME \\='permanent-local t)

Variables marked permanent-local survive `kill-all-local-variables', which is
called when a major mode is activated.  This is required for all Kuro state
variables so that mode re-activation (e.g., after a theme change) does not
destroy in-progress terminal session state."
  (declare (doc-string 3) (indent defun))
  `(progn
     (defvar-local ,name ,value ,doc)
     (put ',name 'permanent-local t)))

;; These functions are provided by the Rust dynamic module at runtime.
;; declare-function suppresses byte/native compiler "not known to be defined" warnings.
(declare-function kuro-core-init                    "ext:kuro-core" (command rows cols))
(declare-function kuro-core-send-key                "ext:kuro-core" (session-id bytes))
(declare-function kuro-core-poll-updates-with-faces "ext:kuro-core" (session-id))
(declare-function kuro-core-resize                  "ext:kuro-core" (session-id rows cols))
(declare-function kuro-core-shutdown                "ext:kuro-core" (session-id))
(declare-function kuro-core-get-cursor              "ext:kuro-core" (session-id))
(declare-function kuro-core-is-process-alive        "ext:kuro-core" (session-id))

(kuro--defvar-permanent-local kuro--initialized nil
  "Non-nil if Kuro has been initialized.
Buffer-local so that multiple kuro buffers each track their own
session state independently.  When nil, all FFI calls are suppressed.")

(kuro--defvar-permanent-local kuro--session-id 0
  "Session ID returned by `kuro-core-init'.
Buffer-local so each kuro buffer routes FFI calls to its own session.
The first session gets ID 0; subsequent sessions get incrementing integers.")

(kuro--defvar-permanent-local kuro--col-to-buf-map (make-hash-table :test 'eql)
  "Per-row mapping of grid column → buffer char offset.
Each key is a row number (integer), each value is a vector mapping
grid column index to buffer character offset.")

(kuro--defvar-permanent-local kuro--resize-pending nil
  "Non-nil when a resize event is pending from the window-size-change hook.
Value is a (NEW-ROWS . NEW-COLS) cons cell, or nil when no resize is pending.")

;;; FFI definition macros

(defmacro kuro--def-ffi-getter (name core-fn default doc)
  "Define a zero-argument FFI getter function NAME.
CORE-FN is called with `kuro--session-id'; DEFAULT is returned on error.
DOC is the docstring for the generated function."
  `(defun ,name () ,doc (kuro--call ,default (,core-fn kuro--session-id))))

(defmacro kuro--def-ffi-unary (name core-fn default arg doc)
  "Define a one-argument FFI wrapper wrapping CORE-FN with fallback DEFAULT.
ARG is the parameter name symbol (used in the docstring)."
  `(defun ,name (,arg) ,doc (kuro--call ,default (,core-fn kuro--session-id ,arg))))

;;; Core dispatch macro

(defmacro kuro--call (fallback &rest body)
  "Guard a Rust FFI call with initialization check and error recovery.

Evaluates BODY only when `kuro--initialized' is non-nil.
On error, logs a message and returns FALLBACK.

Usage:
  (kuro--call nil (kuro-core-get-cursor kuro--session-id))
  (kuro--call 0   (kuro-core-get-scroll-offset kuro--session-id))"
  (declare (indent 1))
  `(when kuro--initialized
     (condition-case err
         (progn ,@body)
       (error
        (when kuro-log-errors (kuro--log err))
        ,fallback))))

;;; Session lifecycle

(defun kuro--init (command &optional rows cols)
  "Initialize Kuro with COMMAND (e.g., \"bash\").
ROWS and COLS specify the initial terminal dimensions.  When omitted,
`kuro--default-rows' and `kuro--default-cols' are used.  Callers should always
pass the actual window dimensions so full-screen programs start with the correct
geometry and do not suffer a SIGWINCH race on their first render.
Returns the session ID (a non-negative integer) on success, nil otherwise."
  (interactive "sShell command: ")
  (condition-case err
      (let* ((r (or rows kuro--default-rows))
             (c (or cols kuro--default-cols))
             (result (kuro-core-init command r c)))
        (when result
          (setq kuro--session-id result)
          (setq kuro--initialized t))
        result)
    (error
     (message "Kuro initialization error: %s" err)
     nil)))

(defun kuro--shutdown ()
  "Shutdown the Kuro terminal session.
Returns t if successful, nil otherwise."
  (kuro--call nil
    (kuro-core-shutdown kuro--session-id)
    (setq kuro--initialized nil)
    (setq kuro--session-id 0)
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
      (kuro-core-send-key kuro--session-id bytes))))

(defun kuro--poll-updates-with-faces ()
  "Poll for terminal updates with face information.
Returns (DIRTY-LINES . COL-TO-BUF-VECTOR) where DIRTY-LINES is a list
of ((ROW . TEXT) . FACE-RANGES) and COL-TO-BUF-VECTOR is a vector mapping
grid columns to buffer character offsets.  FACE-RANGES is a list of
\(START-COL END-COL FG BG FLAGS) for each text segment."
  (kuro--call nil (kuro-core-poll-updates-with-faces kuro--session-id)))

(defun kuro--resize (rows cols)
  "Resize the terminal to ROWS x COLS.
Returns t if successful, nil otherwise."
  (kuro--call nil (kuro-core-resize kuro--session-id rows cols)))

;;; Process state

(defun kuro--is-process-alive ()
  "Return non-nil if the PTY child process is still running.
Returns nil when `kuro--initialized' is nil (no active session).
Falls back to t (alive assumed) on FFI error to prevent spurious buffer
kills — unlike other wrappers that return nil on error, this one uses t
so that a transient Rust failure does not destroy the buffer."
  (kuro--call t (kuro-core-is-process-alive kuro--session-id)))

;;; Cursor queries

(defun kuro--get-cursor ()
  "Get current cursor position.
Returns (ROW . COL) pair."
  (kuro--call '(0 . 0) (kuro-core-get-cursor kuro--session-id)))

(provide 'kuro-ffi)

;;; kuro-ffi.el ends here
