;;; kuro-lifecycle-ext2-test-6.el --- Lifecycle tests — Group 37: start-session-in-buffer  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-lifecycle-test-support)


;;; ── Group 37: kuro--start-session-in-buffer ──────────────────────────────────
;;
;; `kuro--start-session-in-buffer' always returns its buffer argument, activates
;; kuro-mode, sets `kuro--shell-command', then delegates to the render pipeline.
;; The `kuro--init' call is the branch point: non-nil triggers render loop
;; startup; nil silently skips it.  All FFI + render deps are mocked.

(ert-deftest kuro-lifecycle--start-session-in-buffer-returns-buffer ()
  "`kuro--start-session-in-buffer' always returns the buffer argument."
  (let ((buf (get-buffer-create " *kuro-ssb-ret*")))
    (unwind-protect
        (kuro-lifecycle-test--with-start-session-stubs t
          (should (eq buf (kuro--start-session-in-buffer buf "bash"))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-lifecycle--start-session-in-buffer-sets-shell-command ()
  "`kuro--start-session-in-buffer' sets `kuro--shell-command' to COMMAND in the buffer."
  (let ((buf (get-buffer-create " *kuro-ssb-cmd*")))
    (unwind-protect
        (kuro-lifecycle-test--with-start-session-stubs t
          (kuro--start-session-in-buffer buf "fish")
          (should (equal (buffer-local-value 'kuro--shell-command buf) "fish")))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-lifecycle--start-session-in-buffer-calls-init-with-command ()
  "`kuro--start-session-in-buffer' passes COMMAND to `kuro--init'."
  (let ((buf (get-buffer-create " *kuro-ssb-init-arg*"))
        (init-cmd :not-called))
    (unwind-protect
        (kuro-lifecycle-test--with-start-session-stubs t
          (cl-letf (((symbol-function 'kuro--init)
                     (lambda (cmd &rest _) (setq init-cmd cmd) t)))
            (kuro--start-session-in-buffer buf "zsh")
            (should (equal init-cmd "zsh"))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-lifecycle--start-session-in-buffer-calls-init-session-buffer-on-success ()
  "`kuro--start-session-in-buffer' calls `kuro--init-session-buffer' when `kuro--init' returns non-nil."
  (let ((buf (get-buffer-create " *kuro-ssb-isb*"))
        (isb-called nil))
    (unwind-protect
        (kuro-lifecycle-test--with-start-session-stubs t
          (cl-letf (((symbol-function 'kuro--init-session-buffer)
                     (lambda (&rest _) (setq isb-called t))))
            (kuro--start-session-in-buffer buf "bash")
            (should isb-called)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-lifecycle--start-session-in-buffer-rolls-back-on-failure ()
  "Init and post-init errors remove all session and process-global state."
  (let ((original-env (getenv "KURO_SHELL_INTEGRATION_DIR")))
    (unwind-protect
        (progn
          (setenv "KURO_SHELL_INTEGRATION_DIR" "before")
          (dolist (scenario (quote (init-error post-init-error)))
            (let ((buf (generate-new-buffer (format " *kuro-ssb-%s*" scenario)))
                  (render-started nil)
                  (shutdown-called nil))
              (kuro-lifecycle-test--with-start-session-stubs t
                (cl-letf (((symbol-function (quote kuro--setup-shell-integration-env))
                           (lambda () (setenv "KURO_SHELL_INTEGRATION_DIR" "during")))
                          ((symbol-function (quote kuro--init))
                           (lambda (&rest _)
                             (if (eq scenario (quote init-error))
                                 (error "init failed")
                               t)))
                          ((symbol-function (quote kuro--start-render-loop))
                           (lambda ()
                             (setq render-started t)
                             (when (eq scenario (quote post-init-error))
                               (error "render failed"))))
                          ((symbol-function (quote kuro--stop-render-loop)) (function ignore))
                          ((symbol-function (quote kuro--shutdown))
                           (lambda () (setq shutdown-called t))))
                  (should-error (kuro--start-session-in-buffer buf "bash") :type (quote error))
                  (should (eq render-started (eq scenario (quote post-init-error))))
                  (should shutdown-called)
                  (should-not (buffer-live-p buf))
                  (should (equal (getenv "KURO_SHELL_INTEGRATION_DIR") "before")))))))
      (setenv "KURO_SHELL_INTEGRATION_DIR" original-env))))

(ert-deftest kuro-lifecycle--start-session-in-buffer-schedules-render-with-buffer ()
  "`kuro--start-session-in-buffer' passes the buffer to `kuro--schedule-initial-render'."
  (let ((buf (get-buffer-create " *kuro-ssb-sched*"))
        (scheduled-for :not-called))
    (unwind-protect
        (kuro-lifecycle-test--with-start-session-stubs t
          (cl-letf (((symbol-function 'kuro--schedule-initial-render)
                     (lambda (b) (setq scheduled-for b))))
            (kuro--start-session-in-buffer buf "bash")
            (should (eq scheduled-for buf))))
      (when (buffer-live-p buf) (kill-buffer buf)))))


(provide 'kuro-lifecycle-ext2-test-6)
;;; kuro-lifecycle-ext2-test-6.el ends here
