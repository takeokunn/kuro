;;; kuro-e2e-helpers.el --- Shared helpers for Kuro E2E tests -*- lexical-binding: t -*-

;;; Commentary:
;; Shared infrastructure for all E2E test category files.
;; Design policy: NO unconditional sleep-for calls.
;; All waiting is done via condition-based polling with explicit timeouts.
;; The sleep-for inside polling loops is acceptable (conditional by nature).

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Timeouts and poll interval

(defconst kuro-e2e--timeout 10.0
  "Standard per-test polling timeout in seconds.")

(defconst kuro-e2e--slow-timeout 30.0
  "Extended timeout for external programs (tmux, vim) that have variable startup.")

(defconst kuro-e2e--poll-interval 0.05
  "Seconds between render/poll iterations (50ms).")

(defconst kuro-e2e--idle-stable-cycles 2
  "Number of consecutive idle polls required to consider output settled.")

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

(defconst kuro-e2e--ready-marker "KURO_SHELL_READY"
  "Unique string echoed to confirm shell is fully initialized.")

;;; Buffer management

(defun kuro-e2e--make-buffer ()
  "Create a fresh Kuro terminal buffer for E2E testing."
  (let ((buf (generate-new-buffer "*kuro-e2e*")))
    (with-current-buffer buf
      (setq buffer-read-only t)
      (setq-local bidi-display-reordering nil)
      (setq-local truncate-lines t)
      (setq-local show-trailing-whitespace nil))
    buf))

;;; Core polling primitives

(defun kuro-e2e--render (buf)
  "Run one render cycle in BUF."
  (with-current-buffer buf (kuro--render-cycle)))

(defun kuro-e2e--pending-output-p ()
  "Return non-nil when the terminal has queued PTY output."
  (cond ((fboundp 'kuro--has-pending-output)
         (condition-case nil (kuro--has-pending-output) (error t)))
        ((and kuro--initialized (fboundp 'kuro-core-has-pending-output))
         (condition-case nil (kuro-core-has-pending-output) (error t)))
        (t nil)))

(defun kuro-e2e--render-idle (buf &optional stable-cycles timeout)
  "Render BUF until STABLE-CYCLES consecutive idle polls or TIMEOUT.
STABLE-CYCLES defaults to `kuro-e2e--idle-stable-cycles'.
TIMEOUT defaults to 1.0 second (20 polls at 50ms).
Returns non-nil when idle was observed before timeout."
  (let ((deadline (+ (float-time) (or timeout 1.0)))
        (stable 0)
        (target (or stable-cycles kuro-e2e--idle-stable-cycles)))
    (while (and (< (float-time) deadline) (< stable target))
      (kuro-e2e--render buf)
      (setq stable (if (kuro-e2e--pending-output-p) 0 (1+ stable)))
      (when (< stable target)
        (sleep-for kuro-e2e--poll-interval)))
    (>= stable target)))

(defun kuro-e2e--wait-for-text (buf pattern &optional timeout)
  "Poll BUF until PATTERN matches visible screen or scrollback, or TIMEOUT.
TIMEOUT defaults to `kuro-e2e--timeout'.
On timeout, emits diagnostic to stderr. Returns t if found, nil on timeout."
  (let ((deadline (+ (float-time) (or timeout kuro-e2e--timeout)))
        (found nil))
    (while (and (not found) (< (float-time) deadline))
      (kuro-e2e--render buf)
      (with-current-buffer buf
        (when (string-match-p pattern (buffer-string))
          (setq found t)))
      (unless found
        (when kuro--initialized
          (condition-case nil
              (let ((scrollback (kuro-core-get-scrollback 100)))
                (when (and scrollback (listp scrollback))
                  (dolist (line scrollback)
                    (when (and (stringp line) (string-match-p pattern line))
                      (setq found t)))))
            (error nil))))
      (unless found
        (sleep-for kuro-e2e--poll-interval)))
    (unless found
      (message "[kuro-e2e] TIMEOUT waiting for pattern: %S\nBuffer:\n%s"
               pattern
               (with-current-buffer buf (buffer-string))))
    found))

;;; Face inspection

(defun kuro-e2e--face-props-at (pos)
  "Return a plist-like face description at POS, regardless of storage shape."
  (let ((face (get-text-property pos 'face)))
    (cond
     ((and (listp face) (keywordp (car face))) face)
     ((and (listp face) (listp (car face))) (car face))
     (t nil))))

;;; Buffer-name polling

(defun kuro-e2e--wait-for-buffer-name (buf pattern &optional timeout)
  "Poll until (buffer-name BUF) matches PATTERN or TIMEOUT.
TIMEOUT defaults to `kuro-e2e--timeout'. Returns t if matched, nil on timeout."
  (let ((deadline (+ (float-time) (or timeout kuro-e2e--timeout)))
        (found nil))
    (while (and (not found) (< (float-time) deadline))
      (kuro-e2e--render buf)
      (when (string-match-p pattern (buffer-name buf))
        (setq found t))
      (unless found (sleep-for kuro-e2e--poll-interval)))
    found))

;;; tmux polling helpers

(defun kuro-e2e--wait-for-tmux (buf &optional timeout)
  "Poll BUF until tmux status bar pattern appears or TIMEOUT.
Returns t if found, nil on timeout."
  (let ((deadline (+ (float-time) (or timeout kuro-e2e--slow-timeout)))
        (found nil))
    (while (and (not found) (< (float-time) deadline))
      (kuro-e2e--render buf)
      (with-current-buffer buf
        (when (string-match-p "\\[kuro-test[0-9]" (buffer-string))
          (setq found t)))
      (unless found (sleep-for kuro-e2e--poll-interval)))
    found))

(defun kuro-e2e--wait-for-tmux-pane (n &optional timeout)
  "Poll until tmux list-panes shows exactly N panes, or TIMEOUT.
Returns t if pane count reached N, nil on timeout."
  (let ((deadline (+ (float-time) (or timeout kuro-e2e--slow-timeout)))
        (found nil))
    (while (and (not found) (< (float-time) deadline))
      (let* ((out (shell-command-to-string
                   "tmux -L kuro-e2e-test list-panes -a 2>/dev/null"))
             (trimmed (string-trim out))
             (count (if (string-empty-p trimmed)
                        0
                      (length (split-string trimmed "\n" t)))))
        (when (= count n) (setq found t)))
      (unless found (sleep-for kuro-e2e--poll-interval)))
    found))

(defun kuro-e2e--wait-for-tmux-dead (&optional timeout)
  "Poll until the tmux server (kuro-e2e-test socket) is gone, or TIMEOUT.
Returns t if server is confirmed dead, nil on timeout."
  (let ((deadline (+ (float-time) (or timeout kuro-e2e--slow-timeout)))
        (dead nil))
    (while (and (not dead) (< (float-time) deadline))
      (let ((out (shell-command-to-string
                  "tmux -L kuro-e2e-test list-sessions 2>&1")))
        (when (string-match-p "error\\|no server\\|failed\\|No such" out)
          (setq dead t)))
      (unless dead (sleep-for kuro-e2e--poll-interval)))
    dead))

;;; Terminal setup/teardown macro

(defmacro kuro-e2e--with-terminal (&rest body)
  "Run BODY in a fresh terminal session with automatic cleanup.
Waits for `kuro-e2e--ready-marker' to confirm shell is initialized.
The retry loop (3 attempts) handles macOS bash multi-stage startup without
any unconditional sleep."
  `(let ((buf (kuro-e2e--make-buffer)))
     (unwind-protect
         (progn
           (let ((process-environment (copy-sequence process-environment)))
             (setenv "BASH_SILENCE_DEPRECATION_WARNING" "1")
             (setenv "PS1" "kuro$ ")
             (unless (with-current-buffer buf
                       (and (kuro--init kuro-e2e-shell kuro-e2e--shell-args)
                            (progn (kuro--resize 24 80) t)))
               (error "Failed to initialize Kuro terminal"))
             (with-current-buffer buf
               ;; Wait for any initial shell output
               (kuro-e2e--wait-for-text buf ".")
               ;; Let startup quiesce (idle detection, no fixed sleep)
               (kuro-e2e--render-idle buf)
               ;; Confirm readiness: retry up to 3 times.
               ;; The retry loop itself accommodates multi-stage bash startup
               ;; (e.g. macOS bash 3.2 deprecation warning + prompt two-phase).
               (let ((found nil) (attempts 0))
                 (while (and (not found) (< attempts 3))
                   (kuro--send-key (concat "echo " kuro-e2e--ready-marker))
                   (kuro--send-key "\r")
                   (setq attempts (1+ attempts))
                   (when (setq found
                               (kuro-e2e--wait-for-text buf kuro-e2e--ready-marker))
                     (setq attempts 3)))
                 (unless found
                   (error "Timed out waiting for shell ready marker")))
               ;; Disable echo so commands don't pollute assertions
               (kuro--send-key "stty -echo")
               (kuro--send-key "\r")
               (kuro-e2e--render-idle buf 1)
               ;; Remove PS1 and PROMPT_COMMAND to silence prompt noise
               (kuro--send-key
                "PS1=''; export PS1; PROMPT_COMMAND=''; export PROMPT_COMMAND")
               (kuro--send-key "\r")
               (kuro-e2e--render-idle buf 1)
               ;; Clear the visible screen
               (kuro--send-key "printf '\\033[2J\\033[H'")
               (kuro--send-key "\r")
               (kuro-e2e--render-idle buf 1)
               ,@body)))
       ;; Cleanup
       (condition-case nil (kuro--shutdown) (error nil))
       (when (buffer-live-p buf)
         (ignore-errors (kuro-e2e--render-idle buf 1)))
       (when (buffer-live-p buf) (kill-buffer buf)))))

(provide 'kuro-e2e-helpers)

;;; kuro-e2e-helpers.el ends here
