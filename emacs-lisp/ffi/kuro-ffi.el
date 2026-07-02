;;; kuro-ffi.el --- FFI wrapper functions for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

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
;; Each buffer has a positive `kuro--session-id' set by
;; `kuro--init' (which allocates a new ID via an atomic counter) or by
;; `kuro-attach' (which restores an existing ID for a detached session).
;; Per-session FFI calls pass this ID as their first argument so that
;; multiple kuro buffers can coexist without interfering with each other.
;; Exception: `kuro-core-list-sessions' is a global query that takes no ID.

;;; Code:

(require 'kuro-config)
(require 'kuro-ffi-macros)

(declare-function kuro--ensure-module-loaded "kuro-module" ())

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
ERR is a `condition-case' error value (a list whose car is the error symbol).
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

;; These functions are provided by the Rust dynamic module at runtime.
;; declare-function suppresses byte/native compiler "not known to be defined" warnings.
(declare-function kuro-core-init                    "ext:kuro-core" (command shell-args rows cols))
(declare-function kuro-core-send-key                "ext:kuro-core" (session-id bytes))
(declare-function kuro-core-send-paste              "ext:kuro-core" (session-id text))
(declare-function kuro-core-poll-updates-with-faces "ext:kuro-core" (session-id))
(declare-function kuro-core-resize                  "ext:kuro-core" (session-id rows cols))
(declare-function kuro-core-set-cell-pixel-size     "ext:kuro-core" (session-id width height))
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
Real session IDs are positive; 0 means no session has been assigned.")

(kuro--defvar-permanent-local kuro--col-to-buf-map (make-hash-table :test 'eql)
  "Per-row mapping of grid column → buffer char offset.
Each key is a row number (integer), each value is a vector mapping
grid column index to buffer character offset.")

(kuro--defvar-permanent-local kuro--resize-pending nil
  "Non-nil when a resize event is pending from the window-size-change hook.
Value is a (NEW-ROWS . NEW-COLS) cons cell, or nil when no resize is pending.")

;;; Session lifecycle

(defun kuro--init (command &optional shell-args rows cols)
  "Initialize Kuro with COMMAND (e.g., \"bash\").
SHELL-ARGS is an optional list of string arguments passed to the shell
\(e.g., \\='(\"--norc\" \"--noprofile\")); nil means no extra arguments.
ROWS and COLS specify the initial terminal dimensions.  When omitted,
`kuro--default-rows' and `kuro--default-cols' are used.  Callers should always
pass the actual window dimensions so full-screen programs start with the correct
geometry and do not suffer a SIGWINCH race on their first render.
Returns the session ID (a positive integer) on success, nil otherwise."
  (interactive "sShell command: ")
  (condition-case err
      (let* ((r (or rows kuro--default-rows))
             (c (or cols kuro--default-cols))
             (_ (when (fboundp 'kuro--ensure-module-loaded)
                  (kuro--ensure-module-loaded)))
             (result (kuro-core-init command (or shell-args nil) r c)))
        (when result
          (setq kuro--session-id result)
          (setq kuro--initialized t)
          ;; Push real cell pixel metrics so OSC 1337 ReportCellSize replies
          ;; reflect this frame's font; guarded for headless/older modules.
          (kuro--push-cell-pixel-size-from-font))
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

(defun kuro--send-paste (text)
  "Send TEXT to the terminal through the Rust paste API.
TEXT must be a string.  Rust checks the session's current DEC 2004 mode and
applies bracketed-paste wrapping and sanitization when the mode is active."
  (unless (stringp text)
    (signal 'wrong-type-argument (list 'stringp text)))
  (kuro--call nil
    (kuro-core-send-paste kuro--session-id text)))

(kuro--define-ffi-getters
 (kuro--poll-updates-with-faces
  kuro-core-poll-updates-with-faces nil
  "Poll for terminal updates with face information.
Returns nil or a vector of dirty update vectors.  Each dirty update is
[ROW TEXT FACE-RANGES COL-TO-BUF], where ROW is a u32 row index, TEXT is a
string, FACE-RANGES is a flat stride-6 u32 vector, and COL-TO-BUF is a u32
vector.  Schema validation happens before renderer mutation."))

(defun kuro--resize (rows cols)
  "Resize the terminal to ROWS x COLS.
Returns t if successful, nil otherwise."
  (kuro--call nil (kuro-core-resize kuro--session-id rows cols)))

(defun kuro--set-cell-pixel-size (width height)
  "Report the terminal cell pixel size as WIDTH x HEIGHT points to the core.
Used to answer iTerm2 OSC 1337 `ReportCellSize' queries with real font
metrics.  No-op when the `kuro-core-set-cell-pixel-size' FFI function is
unavailable (older module).  Returns t if successful, nil otherwise."
  (when (fboundp 'kuro-core-set-cell-pixel-size)
    (kuro--call nil
      (kuro-core-set-cell-pixel-size kuro--session-id width height))))

(defun kuro--push-cell-pixel-size-from-font ()
  "Push the current frame font cell metrics to the core.
Reads `default-font-width' / `default-font-height' (guarded by `fboundp')
and forwards them via `kuro--set-cell-pixel-size'.  Safe to call when the
metrics functions are unavailable (returns nil)."
  (when (and (fboundp 'default-font-width)
             (fboundp 'default-font-height))
    (kuro--set-cell-pixel-size (default-font-width) (default-font-height))))

;;; Process state

(kuro--define-ffi-getters
 (kuro--is-process-alive
  kuro-core-is-process-alive t
  "Return non-nil if the PTY child process is still running.
Returns nil when `kuro--initialized' is nil (no active session).
Falls back to t (alive assumed) on FFI error to prevent spurious buffer
kills — unlike other wrappers that return nil on error, this one uses t
so that a transient Rust failure does not destroy the buffer."))

;;; Cursor queries

(kuro--define-ffi-getters
 (kuro--get-cursor
  kuro-core-get-cursor '(0 . 0)
  "Get current cursor position.
Returns (ROW . COL) pair."))

(provide 'kuro-ffi)

;;; kuro-ffi.el ends here
