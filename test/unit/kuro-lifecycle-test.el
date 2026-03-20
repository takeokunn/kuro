;;; kuro-lifecycle-test.el --- Unit tests for kuro-lifecycle.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-lifecycle.el public API.
;; Tests run without the Rust dynamic module: all FFI primitives are stubbed
;; before `kuro-lifecycle' is loaded.  When loaded after kuro-test.el
;; (as the Makefile does), the stubs in kuro-test.el are already present;
;; the `unless (fboundp …)' guards here handle standalone loading.
;;
;; kuro-lifecycle.el transitively requires kuro-ffi, kuro-renderer,
;; kuro-faces, and kuro-render-buffer, all of which guard their Rust calls
;; behind `kuro--initialized'.  We never let kuro--initialized be t without
;; also stubbing every Rust call that the code under test might reach.
;;
;; Groups:
;;   Group 1: kuro-send-string  (delegates to kuro--send-key)
;;   Group 2: kuro-send-interrupt / kuro-send-sigstop / kuro-send-sigquit
;;   Group 3: kuro-kill         (guards on derived-mode-p; calls kuro--shutdown)
;;   Group 4: kuro-create guard (must not attempt a real PTY)

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; ── Stub Rust FFI symbols before loading kuro-lifecycle ─────────────────────
;; These symbols are provided by the Rust dynamic module at runtime.
;; Guard with `unless (fboundp …)' so a real loaded module is not overridden.

(dolist (sym '(kuro-core-init
               kuro-core-send-key
               kuro-core-poll-updates
               kuro-core-poll-updates-with-faces
               kuro-core-resize
               kuro-core-shutdown
               kuro-core-get-cursor
               kuro-core-get-cursor-visible
               kuro-core-get-cursor-shape
               kuro-core-get-scroll-offset
               kuro-core-get-and-clear-title
               kuro-core-get-default-colors
               kuro-core-get-palette-updates
               kuro-core-get-image
               kuro-core-take-bell-pending
               kuro-core-get-focus-events
               kuro-core-get-app-cursor-keys
               kuro-core-get-app-keypad
               kuro-core-get-bracketed-paste
               kuro-core-get-mouse-mode
               kuro-core-get-mouse-sgr
               kuro-core-get-mouse-pixel
               kuro-core-get-keyboard-flags
               kuro-core-get-scrollback-count
               kuro-core-get-scrollback
               kuro-core-get-sync-output
               kuro-core-get-cwd
               kuro-core-has-pending-output
               kuro-core-is-process-alive
               kuro-core-poll-clipboard-actions
               kuro-core-poll-image-notifications
               kuro-core-poll-prompt-marks
               kuro-core-scroll-up
               kuro-core-scroll-down
               kuro-core-consume-scroll-events
               kuro-core-clear-scrollback
               kuro-core-set-scrollback-max-lines))
  (unless (fboundp sym)
    (fset sym (lambda (&rest _) nil))))

(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

;;; ── Ensure emacs-lisp/ is on load-path ─────────────────────────────────────

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro-lifecycle)

;;; ── Helper macros ───────────────────────────────────────────────────────────

(defmacro kuro-lifecycle-test--capture-send-key (&rest body)
  "Execute BODY with `kuro--send-key' stubbed.
Returns the list of arguments passed to it, in order.
`kuro--initialized' is bound to t so the guard inside `kuro--send-key'
allows the call through."
  `(let ((captured nil)
         (kuro--initialized t))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (data) (push data captured))))
       ,@body)
     (nreverse captured)))

;;; ── Group 1: kuro-send-string ───────────────────────────────────────────────
;;
;; kuro-send-string delegates the entire string directly to kuro--send-key in
;; a single call.  The initialization guard lives inside kuro--send-key, so
;; when kuro--initialized is nil the stub is never called.

(ert-deftest kuro-lifecycle--send-string-noop-when-not-initialized ()
  "kuro-send-string does nothing when kuro--initialized is nil.
Stubs kuro-core-send-key (the Rust FFI) rather than kuro--send-key so
that the `kuro--call' guard inside kuro--send-key is exercised."
  (let ((kuro--initialized nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-send-key)
               (lambda (_bytes) (setq called t))))
      (kuro-send-string "hello"))
    (should-not called)))

(ert-deftest kuro-lifecycle--send-string-passes-string-to-send-key ()
  "kuro-send-string passes the whole string to kuro--send-key in one call."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-string "hello"))))
    (should (equal received '("hello")))))

(ert-deftest kuro-lifecycle--send-string-empty-string ()
  "kuro-send-string with an empty string calls kuro--send-key with \"\"."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-string ""))))
    (should (equal received '("")))))

(ert-deftest kuro-lifecycle--send-string-multi-char ()
  "kuro-send-string sends the full multi-char string in a single call."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-string "abc"))))
    (should (= (length received) 1))
    (should (equal (car received) "abc"))))

(ert-deftest kuro-lifecycle--send-string-newline ()
  "kuro-send-string correctly forwards a string containing a newline."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-string "line\n"))))
    (should (equal received '("line\n")))))

;;; ── Group 2: kuro-send-interrupt / kuro-send-sigstop / kuro-send-sigquit ───
;;
;; Each function sends a control-character vector to kuro--send-key.
;; kuro--send-key converts vectors to strings before forwarding to Rust.
;; We stub kuro--send-key and verify it receives the expected vector.

(ert-deftest kuro-lifecycle--send-interrupt-noop-when-not-initialized ()
  "kuro-send-interrupt does nothing when kuro--initialized is nil.
Stubs kuro-core-send-key so the kuro--call guard is exercised."
  (let ((kuro--initialized nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-send-key)
               (lambda (_bytes) (setq called t))))
      (kuro-send-interrupt))
    (should-not called)))

(ert-deftest kuro-lifecycle--send-sigstop-noop-when-not-initialized ()
  "kuro-send-sigstop does nothing when kuro--initialized is nil.
Stubs kuro-core-send-key so the kuro--call guard is exercised."
  (let ((kuro--initialized nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-send-key)
               (lambda (_bytes) (setq called t))))
      (kuro-send-sigstop))
    (should-not called)))

(ert-deftest kuro-lifecycle--send-sigquit-noop-when-not-initialized ()
  "kuro-send-sigquit does nothing when kuro--initialized is nil.
Stubs kuro-core-send-key so the kuro--call guard is exercised."
  (let ((kuro--initialized nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro-core-send-key)
               (lambda (_bytes) (setq called t))))
      (kuro-send-sigquit))
    (should-not called)))

(ert-deftest kuro-lifecycle--send-interrupt-sends-ctrl-c ()
  "kuro-send-interrupt calls kuro--send-key with the C-c vector (byte 3)."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-interrupt))))
    (should (= (length received) 1))
    (should (equal (car received) [?\C-c]))))

(ert-deftest kuro-lifecycle--send-sigstop-sends-ctrl-z ()
  "kuro-send-sigstop calls kuro--send-key with the C-z vector (byte 26)."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-sigstop))))
    (should (= (length received) 1))
    (should (equal (car received) [?\C-z]))))

(ert-deftest kuro-lifecycle--send-sigquit-sends-ctrl-backslash ()
  "kuro-send-sigquit calls kuro--send-key with the C-\\ vector (byte 28)."
  (let ((received (kuro-lifecycle-test--capture-send-key
                   (kuro-send-sigquit))))
    (should (= (length received) 1))
    (should (equal (car received) [?\C-\\]))))

(ert-deftest kuro-lifecycle--ctrl-c-is-byte-3 ()
  "Verify that ?\\C-c has the numeric value 3 (SIGINT byte)."
  (should (= ?\C-c 3)))

(ert-deftest kuro-lifecycle--ctrl-z-is-byte-26 ()
  "Verify that ?\\C-z has the numeric value 26 (SIGSTOP byte)."
  (should (= ?\C-z 26)))

(ert-deftest kuro-lifecycle--ctrl-backslash-is-byte-28 ()
  "Verify that ?\\C-\\ has the numeric value 28 (SIGQUIT byte)."
  (should (= ?\C-\\ 28)))

;;; ── Group 3: kuro-kill ──────────────────────────────────────────────────────
;;
;; kuro-kill guards on `(derived-mode-p 'kuro-mode)' — it does NOT check
;; kuro--initialized directly.  When the buffer is not in kuro-mode,
;; the body (including kuro--shutdown) is never reached.

(ert-deftest kuro-lifecycle--kill-noop-in-non-kuro-buffer ()
  "kuro-kill does nothing when the buffer is not in kuro-mode."
  (with-temp-buffer
    (setq major-mode 'fundamental-mode)
    (let ((shutdown-called nil))
      (cl-letf (((symbol-function 'kuro--shutdown)
                 (lambda () (setq shutdown-called t)))
                ((symbol-function 'kuro--stop-render-loop)
                 (lambda () nil))
                ((symbol-function 'kuro--clear-all-image-overlays)
                 (lambda () nil)))
        (kuro-kill)
        (should-not shutdown-called)))))

(ert-deftest kuro-lifecycle--kill-calls-shutdown-in-kuro-mode ()
  "kuro-kill calls kuro--shutdown when the buffer is in kuro-mode."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((shutdown-called nil))
      (cl-letf (((symbol-function 'kuro--shutdown)
                 (lambda () (setq shutdown-called t)))
                ((symbol-function 'kuro--stop-render-loop)
                 (lambda () nil))
                ((symbol-function 'kuro--clear-all-image-overlays)
                 (lambda () nil))
                ((symbol-function 'kill-buffer)
                 (lambda (_buf) nil)))
        (kuro-kill)
        (should shutdown-called)))))

(ert-deftest kuro-lifecycle--kill-stops-render-loop ()
  "kuro-kill calls kuro--stop-render-loop before kuro--shutdown."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((call-order nil))
      (cl-letf (((symbol-function 'kuro--stop-render-loop)
                 (lambda () (push 'stop-render call-order)))
                ((symbol-function 'kuro--shutdown)
                 (lambda () (push 'shutdown call-order)))
                ((symbol-function 'kuro--clear-all-image-overlays)
                 (lambda () nil))
                ((symbol-function 'kill-buffer)
                 (lambda (_buf) nil)))
        (kuro-kill)
        ;; nreverse because push builds in reverse order
        (let ((ordered (nreverse call-order)))
          (should (eq (nth 0 ordered) 'stop-render))
          (should (eq (nth 1 ordered) 'shutdown)))))))

(ert-deftest kuro-lifecycle--kill-resets-mouse-state ()
  "kuro-kill resets kuro--mouse-mode, kuro--mouse-sgr, and kuro--mouse-pixel-mode."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode t)
    (cl-letf (((symbol-function 'kuro--stop-render-loop) (lambda () nil))
              ((symbol-function 'kuro--shutdown)          (lambda () nil))
              ((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil))
              ((symbol-function 'kill-buffer)             (lambda (_buf) nil)))
      (kuro-kill)
      (should (= kuro--mouse-mode 0))
      (should (null kuro--mouse-sgr))
      (should (null kuro--mouse-pixel-mode)))))

(ert-deftest kuro-lifecycle--kill-resets-scroll-offset ()
  "kuro-kill resets kuro--scroll-offset to 0."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (setq-local kuro--scroll-offset 42)
    (cl-letf (((symbol-function 'kuro--stop-render-loop) (lambda () nil))
              ((symbol-function 'kuro--shutdown)          (lambda () nil))
              ((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil))
              ((symbol-function 'kill-buffer)             (lambda (_buf) nil)))
      (kuro-kill)
      (should (= kuro--scroll-offset 0)))))

;;; ── Group 4: kuro-create guard ──────────────────────────────────────────────
;;
;; kuro-create spawns a real PTY process.  We do NOT test that path.
;; Instead, we verify the structural guards that prevent breakage before
;; a real terminal environment is available.

(ert-deftest kuro-lifecycle--create-is-autoloaded-function ()
  "kuro-create is a defined interactive function."
  (should (fboundp 'kuro-create))
  (should (commandp 'kuro-create)))

(ert-deftest kuro-lifecycle--create-aborts-without-module ()
  "kuro-create calls kuro--ensure-module-loaded as its first action.
When the module is unavailable, that call may signal an error.
We verify kuro-create does not succeed silently when the stub errors."
  (cl-letf (((symbol-function 'kuro--ensure-module-loaded)
             (lambda () (error "module not available"))))
    (should-error (kuro-create "echo hello" "*kuro-test*")
                  :type 'error)))

(provide 'kuro-lifecycle-test)

;;; kuro-lifecycle-test.el ends here
