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
        (kuro-lifecycle-test--with-start-session-stubs nil
          (should (eq buf (kuro--start-session-in-buffer buf "bash"))))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-lifecycle--start-session-in-buffer-sets-shell-command ()
  "`kuro--start-session-in-buffer' sets `kuro--shell-command' to COMMAND in the buffer."
  (let ((buf (get-buffer-create " *kuro-ssb-cmd*")))
    (unwind-protect
        (kuro-lifecycle-test--with-start-session-stubs nil
          (kuro--start-session-in-buffer buf "fish")
          (should (equal (buffer-local-value 'kuro--shell-command buf) "fish")))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-lifecycle--start-session-in-buffer-calls-init-with-command ()
  "`kuro--start-session-in-buffer' passes COMMAND to `kuro--init'."
  (let ((buf (get-buffer-create " *kuro-ssb-init-arg*"))
        (init-cmd :not-called))
    (unwind-protect
        (kuro-lifecycle-test--with-start-session-stubs nil
          (cl-letf (((symbol-function 'kuro--init)
                     (lambda (cmd &rest _) (setq init-cmd cmd) nil)))
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

(ert-deftest kuro-lifecycle--start-session-in-buffer-skips-render-on-init-failure ()
  "`kuro--start-session-in-buffer' does not start render loop when `kuro--init' returns nil."
  (let ((buf (get-buffer-create " *kuro-ssb-skip*"))
        (render-started nil))
    (unwind-protect
        (kuro-lifecycle-test--with-start-session-stubs nil
          (cl-letf (((symbol-function 'kuro--start-render-loop)
                     (lambda () (setq render-started t))))
            (kuro--start-session-in-buffer buf "bash")
            (should-not render-started)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

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
