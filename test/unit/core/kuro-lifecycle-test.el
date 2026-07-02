;;; kuro-lifecycle-test.el --- Unit tests for kuro-lifecycle.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-lifecycle.el public API — Groups 1–8.
;; Groups 9–16 are in kuro-lifecycle-ext-test.el.
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
;;   Group 1: kuro-send-string  (delegates text to kuro--send-paste-or-raw)
;;   Group 2: kuro-send-interrupt / kuro-send-sigstop / kuro-send-sigquit
;;   Group 3: kuro-kill         (guards on derived-mode-p; calls kuro--shutdown)
;;   Group 4: kuro-create guard (must not attempt a real PTY)
;;   Group 5: kuro-list-sessions (nth-index regression: idx2=detached-p, idx3=alive-p)
;;   Group 6: kuro-kill detach branch (yes-or-no-p nil → kuro-core-detach, not shutdown)
;;   Group 7: kuro--cleanup-render-state
;;   Group 8: kuro--clear-session-state macro

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-lifecycle-test-support)

;;; ── Group 1: kuro-send-string ───────────────────────────────────────────────
;;
;; kuro-send-string delegates the entire string to the paste-safe text path in
;; a single call.  The initialization guard lives inside the Rust send FFIs, so
;; when kuro--initialized is nil no Rust send function is called.

(ert-deftest kuro-lifecycle--send-string-noop-when-not-initialized ()
  "kuro-send-string does nothing when kuro--initialized is nil.
Stubs Rust send FFIs rather than high-level wrappers so that the
`kuro--call' guard is exercised."
  (kuro-lifecycle-test--assert-noop-when-uninitialized (kuro-send-string "hello")))

(ert-deftest kuro-lifecycle--send-string-passes-string-to-paste-or-raw ()
  "kuro-send-string passes the whole string to kuro--send-paste-or-raw."
  (let ((received (kuro-lifecycle-test--capture-send-paste-or-raw
                   (kuro-send-string "hello"))))
    (should (equal received '("hello")))))

(ert-deftest kuro-lifecycle--send-string-empty-string ()
  "kuro-send-string with an empty string sends \"\" through paste-safe path."
  (let ((received (kuro-lifecycle-test--capture-send-paste-or-raw
                   (kuro-send-string ""))))
    (should (equal received '("")))))

(ert-deftest kuro-lifecycle--send-string-multi-char ()
  "kuro-send-string sends the full multi-char string in a single call."
  (let ((received (kuro-lifecycle-test--capture-send-paste-or-raw
                   (kuro-send-string "abc"))))
    (should (= (length received) 1))
    (should (equal (car received) "abc"))))

(ert-deftest kuro-lifecycle--send-string-newline ()
  "kuro-send-string correctly forwards a string containing a newline."
  (let ((received (kuro-lifecycle-test--capture-send-paste-or-raw
                   (kuro-send-string "line\n"))))
    (should (equal received '("line\n")))))

(ert-deftest kuro-lifecycle--send-string-rejects-non-string ()
  "kuro-send-string rejects non-string payloads before dispatch."
  (should-error (kuro-send-string 42) :type 'wrong-type-argument))

(ert-deftest kuro-lifecycle--send-string-schedules-immediate-render ()
  "kuro-send-string schedules an immediate render after dispatch."
  (let ((scheduled nil))
    (cl-letf (((symbol-function 'kuro--send-paste-or-raw) #'ignore)
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () (setq scheduled t))))
      (kuro-send-string "hello"))
    (should scheduled)))

;;; ── Group 2: kuro-send-interrupt / kuro-send-sigstop / kuro-send-sigquit ───
;;
;; Each function sends a control-character vector to kuro--send-key.
;; kuro--send-key converts vectors to strings before forwarding to Rust.
;; We stub kuro--send-key and verify it receives the expected vector.

(ert-deftest kuro-lifecycle--send-interrupt-noop-when-not-initialized ()
  "kuro-send-interrupt does nothing when kuro--initialized is nil."
  (kuro-lifecycle-test--assert-noop-when-uninitialized (kuro-send-interrupt)))

(ert-deftest kuro-lifecycle--send-sigstop-noop-when-not-initialized ()
  "kuro-send-sigstop does nothing when kuro--initialized is nil."
  (kuro-lifecycle-test--assert-noop-when-uninitialized (kuro-send-sigstop)))

(ert-deftest kuro-lifecycle--send-sigquit-noop-when-not-initialized ()
  "kuro-send-sigquit does nothing when kuro--initialized is nil."
  (kuro-lifecycle-test--assert-noop-when-uninitialized (kuro-send-sigquit)))

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
  (kuro-lifecycle-test--check-kill-shutdown 'fundamental-mode should-not))

(ert-deftest kuro-lifecycle--kill-calls-shutdown-in-kuro-mode ()
  "kuro-kill calls kuro--shutdown when the buffer is in kuro-mode."
  (kuro-lifecycle-test--check-kill-shutdown 'kuro-mode should))

(ert-deftest kuro-lifecycle--kill-stops-render-loop-before-cleanup ()
  "kuro-kill calls kuro--stop-render-loop before kuro--cleanup-render-state."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((call-order nil))
      (cl-letf (((symbol-function 'kuro--stop-render-loop)
                 (lambda () (push 'stop-render call-order)))
                ((symbol-function 'kuro--cleanup-render-state)
                 (lambda () (push 'cleanup call-order)))
                ((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil))
                ((symbol-function 'kuro--shutdown)                 (lambda () nil))
                ((symbol-function 'kill-buffer)                    (lambda (_buf) nil)))
        (kuro-kill)
        (let ((ordered (nreverse call-order)))
          (should (eq (nth 0 ordered) 'stop-render))
          (should (eq (nth 1 ordered) 'cleanup)))))))

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
  "kuro-create calls kuro--ensure-module-installed as its first action.
When the module is unavailable, that call may signal an error.
We verify kuro-create does not succeed silently when the stub errors."
  (cl-letf (((symbol-function 'kuro--ensure-module-installed)
             (lambda () (error "module not available"))))
    (should-error (kuro-create "echo hello" "*kuro-test*")
                  :type 'error)))

;;; ── Group 4b: kuro--ensure-module-installed (install-prompt orchestration) ──
;;
;; kuro--ensure-module-installed wraps kuro-module-load with an installation
;; prompt for first-time users.  It honours kuro-module-installation-method
;; (`prebuilt' / `cargo' / `manual' / nil) to bypass or steer the prompt.
;; The interactive read-char-choice path is intentionally NOT exercised here —
;; stubbing it portably across Emacs versions is brittle and the dispatch
;; logic is already covered by the symbolic-method branches.

(ert-deftest kuro-lifecycle-test--ensure-module-installed-success-when-loaded ()
  "When the module loads on the first try, no install command runs."
  (let ((download-calls 0)
        (build-calls 0))
    (cl-letf (((symbol-function 'kuro-module-load)   (lambda () t))
              ((symbol-function 'kuro--module-loadable-p) (lambda () t))
              ((symbol-function 'kuro-module-download)
               (lambda (&optional _v) (cl-incf download-calls)))
              ((symbol-function 'kuro-module-build)
               (lambda () (cl-incf build-calls))))
      (let ((kuro-module-installation-method nil))
        (should (kuro--ensure-module-installed))
        (should (= download-calls 0))
        (should (= build-calls 0))))))

(ert-deftest kuro-lifecycle-test--ensure-module-installed-prebuilt-method ()
  "With `prebuilt' method, kuro-module-download is invoked when load fails first."
  (let ((download-calls 0)
        (load-calls 0)
        (loaded nil))
    (cl-letf (((symbol-function 'kuro-module-load)
               (lambda ()
                 (cl-incf load-calls)
                 (when (>= load-calls 2) (setq loaded t))))
              ((symbol-function 'kuro--module-loadable-p)
               (lambda () loaded))
              ((symbol-function 'kuro-module-download)
               (lambda (&optional _v) (cl-incf download-calls)))
              ((symbol-function 'kuro-module-build)
               (lambda () (error "should not build"))))
      (let ((kuro-module-installation-method 'prebuilt))
        (should (kuro--ensure-module-installed))
        (should (= download-calls 1))))))

(ert-deftest kuro-lifecycle-test--ensure-module-installed-cargo-method ()
  "With `cargo' method, kuro-module-build is invoked when load fails first."
  (let ((build-calls 0)
        (load-calls 0)
        (loaded nil))
    (cl-letf (((symbol-function 'kuro-module-load)
               (lambda ()
                 (cl-incf load-calls)
                 (when (>= load-calls 2) (setq loaded t))))
              ((symbol-function 'kuro--module-loadable-p)
               (lambda () loaded))
              ((symbol-function 'kuro-module-build)
               (lambda () (cl-incf build-calls)))
              ((symbol-function 'kuro-module-download)
               (lambda (&optional _v) (error "should not download"))))
      (let ((kuro-module-installation-method 'cargo))
        (should (kuro--ensure-module-installed))
        (should (= build-calls 1))))))

(ert-deftest kuro-lifecycle-test--ensure-module-installed-manual-method-errors ()
  "With `manual' method, a user-error is signalled when the module is missing."
  (cl-letf (((symbol-function 'kuro-module-load) (lambda () nil))
            ((symbol-function 'kuro--module-loadable-p) (lambda () nil))
            ((symbol-function 'kuro-module-download)
             (lambda (&optional _v) (error "should not download")))
            ((symbol-function 'kuro-module-build)
             (lambda () (error "should not build"))))
    (let ((kuro-module-installation-method 'manual))
      (should-error (kuro--ensure-module-installed) :type 'user-error))))

(provide 'kuro-lifecycle-test)
;;; kuro-lifecycle-test.el ends here
