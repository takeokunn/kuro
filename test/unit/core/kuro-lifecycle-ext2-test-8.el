;;; kuro-lifecycle-ext2-test-8.el --- Lifecycle tests — Groups 40-41: prefill-buffer + teardown-session  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-lifecycle-test-support)


;;; ── Group 40: kuro--prefill-buffer — boundary cases ────────────────────────

(ert-deftest kuro-lifecycle--prefill-buffer-zero-rows-empties-buffer ()
  "`kuro--prefill-buffer' with 0 rows produces an empty buffer."
  (with-temp-buffer
    (insert "old content")
    (let ((inhibit-read-only t))
      (kuro--prefill-buffer 0))
    (should (= (buffer-size) 0))))

(ert-deftest kuro-lifecycle--prefill-buffer-newline-count-matches ()
  "`kuro--prefill-buffer' with N rows inserts exactly N newline characters."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (kuro--prefill-buffer 5))
    (should (= (count-matches "\n" (point-min) (point-max)) 5))))

(ert-deftest kuro-lifecycle--prefill-buffer-one-row ()
  "`kuro--prefill-buffer' with 1 row inserts exactly one newline."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (kuro--prefill-buffer 1))
    (should (= (buffer-size) 1))
    (should (string= (buffer-string) "\n"))))


;;; ── Group 41: kuro--teardown-session — 4 code paths ───────────────────────
;;
;; The function guards on:
;;   (and kuro--initialized (kuro--is-process-alive) (not (yes-or-no-p ...)))
;;
;; Paths:
;;   A. initialized=nil          → else branch → kuro--shutdown
;;   B. alive=nil                → else branch → kuro--shutdown
;;   C. alive, user says "kill"  → else branch → kuro--shutdown
;;   D. alive, user says "detach"→ then branch → kuro-core-detach + kuro--clear-session-state

(ert-deftest kuro-lifecycle--teardown-session-calls-shutdown-when-not-initialized ()
  "`kuro--teardown-session' calls `kuro--shutdown' when session is not initialized."
  (let ((kuro--initialized nil)
        shutdown-called)
    (cl-letf (((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t)))
              ((symbol-function 'kuro--is-process-alive) (lambda () t))
              ((symbol-function 'yes-or-no-p) (lambda (_) t)))
      (kuro--teardown-session))
    (should shutdown-called)))

(ert-deftest kuro-lifecycle--teardown-session-calls-shutdown-when-process-dead ()
  "`kuro--teardown-session' calls `kuro--shutdown' when the process is not alive."
  (let ((kuro--initialized t)
        shutdown-called)
    (cl-letf (((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t)))
              ((symbol-function 'kuro--is-process-alive) (lambda () nil))
              ((symbol-function 'yes-or-no-p) (lambda (_) t)))
      (kuro--teardown-session))
    (should shutdown-called)))

(ert-deftest kuro-lifecycle--teardown-session-calls-shutdown-when-user-kills ()
  "`kuro--teardown-session' calls `kuro--shutdown' when user confirms killing."
  (let ((kuro--initialized t)
        (kuro--session-id 7)
        shutdown-called)
    (cl-letf (((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t)))
              ((symbol-function 'kuro--is-process-alive) (lambda () t))
              ((symbol-function 'yes-or-no-p) (lambda (_) t)))
      (kuro--teardown-session))
    (should shutdown-called)))

(ert-deftest kuro-lifecycle--teardown-session-detaches-when-user-declines-kill ()
  "`kuro--teardown-session' calls `kuro-core-detach' when user declines killing."
  (let ((kuro--initialized t)
        (kuro--session-id 3)
        detach-called)
    (cl-letf (((symbol-function 'kuro--shutdown) (lambda () nil))
              ((symbol-function 'kuro--is-process-alive) (lambda () t))
              ((symbol-function 'yes-or-no-p) (lambda (_) nil))
              ((symbol-function 'kuro-core-detach)
               (lambda (_id) (setq detach-called t)))
              ((symbol-function 'kuro--clear-session-state) (lambda () nil)))
      (kuro--teardown-session))
    (should detach-called)))

(ert-deftest kuro-lifecycle--teardown-session-clears-state-after-detach-error ()
  "`kuro--teardown-session' resets session state when `kuro-core-detach' errors.
Since `kuro--clear-session-state' is a macro (expanded inline), we verify the
side effects directly: `kuro--initialized' becomes nil and `kuro--session-id' 0."
  (let ((kuro--initialized t)
        (kuro--session-id 5))
    (cl-letf (((symbol-function 'kuro--shutdown) (lambda () nil))
              ((symbol-function 'kuro--is-process-alive) (lambda () t))
              ((symbol-function 'yes-or-no-p) (lambda (_) nil))
              ((symbol-function 'kuro-core-detach)
               (lambda (_id) (error "FFI error"))))
      (kuro--teardown-session))
    (should (null kuro--initialized))
    (should (= kuro--session-id 0))))


(provide 'kuro-lifecycle-ext2-test-8)
;;; kuro-lifecycle-ext2-test-8.el ends here
