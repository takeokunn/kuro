;;; kuro-e2e-helpers.el --- Shared helpers for Kuro E2E tests -*- lexical-binding: t -*-

;;; Commentary:
;; Shared infrastructure for all Kuro E2E test files.
;;
;; # Design: Direct FFI text detection
;;
;; The Kuro rendering pipeline has a 1-frame latency by design:
;;   poll N:   poll_output() reads new PTY bytes → marks rows dirty
;;             get_dirty_lines() returns rows dirty BEFORE this call
;;   poll N+1: get_dirty_lines() returns rows dirty from poll N
;;
;; `kuro-e2e--wait-for-output' handles this by calling the FFI twice per
;; iteration: poll1 reads new data; poll2 retrieves the dirty rows from poll1.
;;
;; This bypasses the full render pipeline (`kuro--render-cycle') for shell-ready
;; detection and assertion, avoiding the buffer-state initialization complexity.
;; The render-pipeline path (`kuro-e2e--wait-for-text') is still available for
;; tests that specifically verify buffer rendering correctness.
;;
;; # No unconditional sleep-for
;; All waiting uses condition-based polling with explicit timeouts.
;; The sleep-for inside polling loops is acceptable (conditional by nature).

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Timeouts and poll interval

(defconst kuro-e2e--timeout 15.0
  "Standard per-test polling timeout in seconds.")

(defconst kuro-e2e--slow-timeout 30.0
  "Extended timeout for external programs (tmux, vim) that have variable startup.")

(defconst kuro-e2e--poll-interval 0.1
  "Seconds between poll iterations (100ms).")

;;; Module availability

(defconst kuro-e2e--module-loaded
  (progn
    (ignore-errors
      (require 'kuro-module)
      (kuro-module-load))
    (and (fboundp 'kuro-core-init)
         (not (eq (symbol-function 'kuro-core-init)
                  (and (boundp 'kuro-test--stub-fn)
                       (symbol-value 'kuro-test--stub-fn))))
         (or (subrp (symbol-function 'kuro-core-init))
             (and (fboundp 'module-function-p)
                  (module-function-p (symbol-function 'kuro-core-init))))))
  "Non-nil when the real Rust kuro-core module is loaded (not stubs).")

(defconst kuro-e2e--expected-result
  (if kuro-e2e--module-loaded :passed :failed)
  "Expected ERT result: :passed with module, :failed without.")

;;; Shell configuration

(defcustom kuro-e2e-shell
  (or (and (file-executable-p "/bin/bash") "/bin/bash")
      (and (file-executable-p "/bin/sh") "/bin/sh")
      (getenv "SHELL"))
  "Shell executable used in E2E tests."
  :type 'string
  :group 'kuro)

(defconst kuro-e2e--shell-args '("--norc" "--noprofile")
  "Shell arguments disabling rc files for a clean, deterministic environment.")

(defconst kuro-e2e--ready-marker "KURO_READY_E2E_7B3F"
  "Unique string echoed to confirm shell is fully initialized.")

;;; Forward declarations for symbols defined in other Kuro modules

(defvar kuro--initialized nil
  "Forward reference; defvar-permanent-local in kuro-ffi.el.")
(defvar kuro--row-positions nil
  "Forward reference; defvar-permanent-local in kuro-render-buffer.el.")
(defvar kuro--cursor-marker nil
  "Forward reference; defvar-local in kuro-renderer.el.")
(defvar kuro--last-rows 0
  "Forward reference; defvar-local in kuro.el.")
(defvar kuro--last-cols 0
  "Forward reference; defvar-local in kuro.el.")
(defvar kuro--scroll-offset 0
  "Forward reference; defvar-local in kuro-input.el.")
(defvar kuro--session-id 0
  "Forward reference; defvar-permanent-local in kuro-ffi.el.")

;; Rust module FFI functions used directly for text detection.
(declare-function kuro-core-poll-updates-binary-with-strings
                  "ext:kuro-core" (session-id))
(declare-function kuro-core-get-scrollback
                  "ext:kuro-core" (session-id max-lines))

;; Kuro Elisp public API functions.
(declare-function kuro--prefill-buffer  "kuro-lifecycle" (rows))
(declare-function kuro--init            "kuro-ffi"       (command &optional shell-args rows cols))
(declare-function kuro--resize          "kuro-ffi"       (rows cols))
(declare-function kuro--send-key        "kuro-ffi"       (data))
(declare-function kuro--shutdown        "kuro-ffi"       ())
(declare-function kuro--render-cycle    "kuro-renderer"  ())
(declare-function kuro--get-cursor      "kuro-ffi"       ())

;;; Buffer management

(defun kuro-e2e--make-buffer ()
  "Create a fresh Kuro terminal buffer for E2E testing."
  (let ((buf (generate-new-buffer "*kuro-e2e*")))
    (with-current-buffer buf
      (setq buffer-read-only t)
      (setq-local bidi-display-reordering nil)
      (setq-local truncate-lines t)
      (setq-local show-trailing-whitespace nil)
      ;; Pre-allocate row-positions cache: renderer navigates rows via this
      ;; vector, falling back to the slow O(row) forward-line path when nil.
      (setq kuro--row-positions (make-vector 24 nil)))
    buf))

;;; Direct FFI polling primitives
;;
;; These functions call the Rust module directly, bypassing the full render
;; pipeline (`kuro--render-cycle').  They are the primary mechanism for
;; text detection in `kuro-e2e--wait-for-output', avoiding the buffer-state
;; initialization complexity of the production render path.

(defun kuro-e2e--ffi-poll-texts (session-id)
  "Call the binary FFI poll once and return a list of dirty row text strings.
Returns nil when there are no dirty rows (either no output or 1-frame latency
means the previous poll read the data; the next poll returns the dirty rows).

Handles the 1-frame latency by design: callers must call this twice to see
output that arrived since the previous call.  See `kuro-e2e--wait-for-output'."
  (when (fboundp 'kuro-core-poll-updates-binary-with-strings)
    (let ((result (kuro-core-poll-updates-binary-with-strings session-id)))
      (when result
        (let ((texts (car result))
              (strs nil))
          (dotimes (i (length texts))
            (push (aref texts i) strs))
          strs)))))

(defun kuro-e2e--ffi-scrollback-contains-p (session-id pattern)
  "Return non-nil if PATTERN matches any line in SESSION-ID's scrollback."
  (when (fboundp 'kuro-core-get-scrollback)
    (condition-case nil
        (let ((lines (kuro-core-get-scrollback session-id 500))
              (found nil))
          (when (listp lines)
            (dolist (line lines)
              (when (string-match-p pattern line)
                (setq found t))))
          found)
      (error nil))))

;;; Primary text detection: direct FFI (bypasses render pipeline)

(defun kuro-e2e--wait-for-output (session-id pattern &optional timeout)
  "Poll SESSION-ID via direct FFI until PATTERN matches or TIMEOUT seconds.

Uses a two-poll-per-iteration strategy to handle the 1-frame latency:
  Iteration N:
    poll-a (discard): poll_output reads new PTY bytes → marks dirty rows
    sleep POLL-INTERVAL: gives PTY reader thread time to deliver data
    poll-b (check):   poll_output reads any new data → returns dirty rows
                      from poll-a's poll_output → search for PATTERN

Also checks the scrollback buffer as a fallback each iteration.

TIMEOUT defaults to `kuro-e2e--timeout'.
Returns t if found, nil on timeout."
  (let ((deadline (+ (float-time) (or timeout kuro-e2e--timeout)))
        (found nil))
    (while (and (not found) (< (float-time) deadline))
      ;; Poll-a: reads new PTY bytes, returns previous dirty rows (discarded).
      (kuro-e2e--ffi-poll-texts session-id)
      ;; Give the PTY reader thread time to deliver the shell's response.
      (sleep-for kuro-e2e--poll-interval)
      ;; Poll-b: returns dirty rows from poll-a's poll_output.
      (let ((texts (kuro-e2e--ffi-poll-texts session-id)))
        (dolist (text texts)
          (when (string-match-p pattern text)
            (setq found t))))
      ;; Scrollback fallback: catches output that scrolled off the visible area.
      (unless found
        (when (kuro-e2e--ffi-scrollback-contains-p session-id pattern)
          (setq found t))))
    (unless found
      (message "[kuro-e2e] TIMEOUT waiting for pattern: %S" pattern))
    found))

;;; Secondary text detection: render buffer (uses production render pipeline)

(defun kuro-e2e--render (buf)
  "Run one render cycle in BUF."
  (with-current-buffer buf (kuro--render-cycle)))

(defun kuro-e2e--wait-for-text (buf pattern &optional timeout)
  "Render BUF in a loop until PATTERN matches buffer content or TIMEOUT.
Uses the production render pipeline (`kuro--render-cycle') to update the
buffer, then checks `buffer-string' for PATTERN.

TIMEOUT defaults to `kuro-e2e--timeout'.
Returns t if found, nil on timeout."
  (let ((deadline (+ (float-time) (or timeout kuro-e2e--timeout)))
        (found nil))
    (while (and (not found) (< (float-time) deadline))
      (kuro-e2e--render buf)
      (with-current-buffer buf
        (when (string-match-p pattern (buffer-string))
          (setq found t)))
      (unless found (sleep-for kuro-e2e--poll-interval)))
    (unless found
      (message "[kuro-e2e] TIMEOUT waiting for render pattern: %S\nBuffer:\n%s"
               pattern (with-current-buffer buf (buffer-string))))
    found))

;;; Terminal setup/teardown macro

(defmacro kuro-e2e--with-terminal (&rest body)
  "Run BODY inside a fresh terminal session with automatic cleanup.

Initialization sequence:
  1. Create a fresh buffer with `kuro-e2e--make-buffer'.
  2. Prefill buffer with blank rows (required for renderer row navigation).
  3. Initialize PTY session via `kuro--init' (24×80 terminal).
  4. Set buffer-local render state (`kuro--last-rows', `kuro--last-cols',
     `kuro--cursor-marker', `kuro--scroll-offset').
  5. Confirm shell readiness: send `echo KURO_READY_E2E_7B3F' and wait for
     the marker to appear via direct FFI polling (up to 5 retries × 8s each).

Shell-ready detection uses `kuro-e2e--wait-for-output' (direct FFI, two-poll
strategy) rather than the render pipeline.  This is more reliable because it
does not depend on the full buffer-state initialization of the production path.

BODY runs inside `with-current-buffer buf'.  The variables `buf' (the terminal
buffer) and the buffer-local `kuro--session-id' are accessible.

Cleanup via `unwind-protect' always shuts down the PTY and kills the buffer."
  `(let ((buf (kuro-e2e--make-buffer)))
     (unwind-protect
         (let ((process-environment (copy-sequence process-environment)))
           ;; Suppress the macOS bash 3.2 deprecation warning so it does not
           ;; race against shell-ready detection.
           (setenv "BASH_SILENCE_DEPRECATION_WARNING" "1")
           (with-current-buffer buf
             ;; Prefill buffer BEFORE init: the renderer navigates rows via
             ;; newline positions.  Without this, kuro--ensure-buffer-row-exists
             ;; falls back to an insertion loop that may mis-position rows.
             (let ((inhibit-read-only t))
               (kuro--prefill-buffer 24))
             ;; Initialize the PTY session.
             (unless (kuro--init kuro-e2e-shell kuro-e2e--shell-args 24 80)
               (error "kuro-e2e: Failed to initialize terminal with %s"
                      kuro-e2e-shell))
             ;; Set render-pipeline state required for kuro--render-cycle.
             ;; kuro--last-rows > 0 enables scroll-event processing and
             ;; col-to-buf cache eviction in the renderer pipeline.
             (setq kuro--cursor-marker (point-marker)
                   kuro--last-rows     24
                   kuro--last-cols     80
                   kuro--scroll-offset 0)
             ;; Confirm shell readiness via direct FFI (bypasses render pipeline).
             ;; Retries up to 5 times with an 8-second window each, totalling
             ;; up to 40 seconds — enough for macOS bash's multi-stage startup.
             (let ((sid     kuro--session-id)
                   (found   nil)
                   (attempt 0))
               (while (and (not found) (< attempt 5))
                 (kuro--send-key
                  (concat "echo " kuro-e2e--ready-marker "\r"))
                 (cl-incf attempt)
                 (setq found
                       (kuro-e2e--wait-for-output
                        sid kuro-e2e--ready-marker 8.0)))
               (unless found
                 (error "kuro-e2e: Timed out waiting for shell ready")))
             ,@body))
       ;; Cleanup: shut down PTY, kill buffer.
       (when (buffer-live-p buf)
         (with-current-buffer buf
           (condition-case nil (kuro--shutdown) (error nil)))
         (kill-buffer buf)))))

(provide 'kuro-e2e-helpers)

;;; kuro-e2e-helpers.el ends here
