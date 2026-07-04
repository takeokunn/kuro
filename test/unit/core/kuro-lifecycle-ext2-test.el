;;; kuro-lifecycle-ext2-test.el --- Lifecycle tests: cleanup, attach, module  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-lifecycle.el — Groups 17–30.
;; Groups 1–12 are in kuro-lifecycle-test.el.
;; Groups 13–26 are in kuro-lifecycle-ext-test.el.
;;
;; Groups:
;;   Group 17 (cleanup): kuro--rollback-attach — message and kill-buffer
;;   Group 18 (cleanup): kuro--teardown-session — process not alive
;;   Group 19 (cleanup): kuro--prefill-buffer — edge cases
;;   Group 20 (attach): kuro--do-attach — resize and prefill args
;;   Group 21 (attach): kuro-attach — public API
;;   Group 22 (attach): kuro--schedule-initial-render — live-buffer path

;;   Group 23 (attach): kuro--init-session-buffer — font/remap calls
;;   Group 24 (cleanup): kuro--rollback-attach — kill-buffer arg, noop-dead
;;   Group 25 (cleanup): kuro--schedule-initial-render — dead-buffer, live
;;   Group 27: kuro--module-loadable-p
;;   Group 28: kuro--try-load-module
;;   Group 29: kuro--prompt-and-install-module
;;   Group 30: kuro-create — buffer lifecycle

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-lifecycle-test-support)

;;; Helpers

(defmacro kuro-lifecycle-ext2-test--with-sessions (sessions &rest body)
  "Stub `kuro-core-list-sessions' to return SESSIONS, call `kuro-list-sessions',
then evaluate BODY inside the `*kuro-sessions*' buffer.
`display-buffer' is stubbed to `#\\='ignore' to avoid window changes."
  `(progn
     (cl-letf (((symbol-function 'kuro-core-list-sessions) (lambda () ,sessions))
               ((symbol-function 'display-buffer) #'ignore))
       (kuro-list-sessions)
       (with-current-buffer "*kuro-sessions*"
         ,@body))))

;;; ── Group 17 (cleanup): kuro--rollback-attach — message and kill-buffer ──────
;;
;; Supplements Group 12 by verifying that rollback logs the session ID in
;; the message string and that it kills the supplied buffer.

(ert-deftest kuro-lifecycle--rollback-attach-logs-session-id ()
  "kuro--rollback-attach includes the session ID in the message it prints."
  (with-temp-buffer
    (let ((msg-logged nil))
      (kuro-lifecycle-test--with-rollback-stubs
          (lambda (fmt &rest args) (setq msg-logged (apply #'format fmt args)))
          #'ignore
        (kuro--rollback-attach 88 (current-buffer) "boom")
        (should (stringp msg-logged))
        (should (string-match-p "88" msg-logged))))))

(ert-deftest kuro-lifecycle--rollback-attach-kills-buffer ()
  "kuro--rollback-attach kills the buffer argument it receives."
  (let ((buf (generate-new-buffer " *kuro-rollback-test*"))
        (killed-buf nil))
    (kuro-lifecycle-test--with-rollback-stubs #'ignore
        (lambda (b) (setq killed-buf b))
      (kuro--rollback-attach 1 buf "err")
      (should (eq killed-buf buf)))))

(ert-deftest kuro-lifecycle--rollback-attach-returns-nil ()
  "kuro--rollback-attach always returns nil."
  (with-temp-buffer
    (kuro-lifecycle-test--with-rollback-stubs #'ignore #'ignore
      (should (null (kuro--rollback-attach 2 (current-buffer) "e"))))))

;;; ── Group 18 (cleanup): kuro--teardown-session — process not alive ───────────
;;
;; When kuro--initialized is t but kuro--is-process-alive returns nil, the
;; teardown must call kuro--shutdown directly without prompting the user.

(ert-deftest kuro-lifecycle--teardown-no-prompt-when-process-dead ()
  "kuro--teardown-session skips yes-or-no-p when the process is not alive."
  (let ((kuro--initialized   t)
        (kuro--session-id    40)
        (prompt-called       nil)
        (shutdown-called     nil))
    (cl-letf (((symbol-function 'kuro--is-process-alive)
               (lambda () nil))
              ((symbol-function 'yes-or-no-p)
               (lambda (_p) (setq prompt-called t) t))
              ((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t))))
      (kuro--teardown-session)
      (should-not prompt-called)
      (should     shutdown-called))))

(ert-deftest kuro-lifecycle--teardown-calls-shutdown-when-not-alive ()
  "kuro--teardown-session calls kuro--shutdown when the process is not alive."
  (let ((kuro--initialized  t)
        (kuro--session-id   50)
        (shutdown-called    nil))
    (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () nil))
              ((symbol-function 'kuro--shutdown)
               (lambda () (setq shutdown-called t))))
      (kuro--teardown-session)
      (should shutdown-called))))

;;; ── Group 19 (cleanup): kuro--prefill-buffer — edge cases ───────────────────
;;
;; Verifies zero-row behaviour and that buffer content is replaced (not appended).

(ert-deftest kuro-lifecycle--prefill-buffer-zero-rows-empty-buffer ()
  "kuro--prefill-buffer with 0 rows leaves the buffer empty (no newlines)."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (insert "existing text")
      (kuro--prefill-buffer 0)
      (should (= (buffer-size) 0)))))

(ert-deftest kuro-lifecycle--prefill-buffer-replaces-not-appends ()
  "kuro--prefill-buffer replaces existing content rather than appending to it."
  (with-temp-buffer
    (let ((inhibit-read-only t))
      (dotimes (_ 20)
        (insert "line\n"))
      (kuro--prefill-buffer 3)
      ;; Should have exactly 3 lines, not 20 + 3.
      (should (= (count-lines (point-min) (point-max)) 3)))))

;;; ── Group 20 (attach): kuro--do-attach — resize and prefill args ────────────
;;
;; Verifies that kuro--do-attach forwards rows/cols to kuro--resize and that
;; kuro--prefill-buffer receives the row count.

(ert-deftest kuro-lifecycle--do-attach-calls-resize-with-rows-cols ()
  "kuro--do-attach calls kuro--resize with the supplied rows and cols."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized
          (resize-rows nil)
          (resize-cols nil))
      (kuro-lifecycle-test--with-attach-stubs
        (cl-letf (((symbol-function 'kuro--resize)
                   (lambda (r c) (setq resize-rows r resize-cols c))))
          (kuro--do-attach 3 15 60)
          (should (= resize-rows 15))
          (should (= resize-cols 60)))))))

(ert-deftest kuro-lifecycle--do-attach-calls-prefill-with-rows ()
  "kuro--do-attach passes the rows argument to kuro--prefill-buffer."
  (with-temp-buffer
    (let (kuro--session-id kuro--initialized
          (prefill-rows nil))
      (kuro-lifecycle-test--with-attach-stubs
        (cl-letf (((symbol-function 'kuro--prefill-buffer)
                   (lambda (r) (setq prefill-rows r))))
          (kuro--do-attach 4 18 72)
          (should (= prefill-rows 18)))))))

;;; Group 21 (attach): kuro-attach — public API (error rollback, success message, buffer naming)
;;
;; kuro-attach creates a fresh buffer, enters kuro-mode, then calls kuro--do-attach.
;; On error it calls kuro--rollback-attach; on success it prints a message.

(ert-deftest kuro-lifecycle--attach-calls-rollback-on-do-attach-error ()
  "kuro-attach calls kuro--rollback-attach when kuro--do-attach signals."
  (let ((rollback-called-with-id nil))
    (kuro-lifecycle-test--with-kuro-attach
      (cl-letf (((symbol-function 'kuro--do-attach)
                 (lambda (_id _r _c) (error "attach failed")))
                ((symbol-function 'kuro--rollback-attach)
                 (lambda (id _buf _err) (setq rollback-called-with-id id))))
        (setq kuro-attach-result (kuro-attach 7))
        (should (= rollback-called-with-id 7))))))

(ert-deftest kuro-lifecycle--attach-prints-success-message ()
  "kuro-attach prints a message mentioning the session ID on success."
  (let ((msgs nil))
    (kuro-lifecycle-test--with-kuro-attach
      (cl-letf (((symbol-function 'kuro--do-attach) #'ignore)
                ((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (push (apply #'format fmt args) msgs))))
        (setq kuro-attach-result (kuro-attach 42))
        (should (cl-some (lambda (m) (string-match-p "42" m)) msgs))))))

(ert-deftest kuro-lifecycle--attach-buffer-name-includes-session-id ()
  "kuro-attach creates a buffer whose name contains the session ID."
  (kuro-lifecycle-test--with-kuro-attach
    (cl-letf (((symbol-function 'kuro--do-attach) #'ignore)
              ((symbol-function 'message)          #'ignore))
      (setq kuro-attach-result (kuro-attach 99))
      (should (string-match-p "99" (buffer-name kuro-attach-result))))))

(ert-deftest kuro-lifecycle--attach-returns-buffer ()
  "kuro-attach returns the newly created buffer."
  (kuro-lifecycle-test--with-kuro-attach
    (cl-letf (((symbol-function 'kuro--do-attach) #'ignore)
              ((symbol-function 'message)          #'ignore))
      (setq kuro-attach-result (kuro-attach 3))
      (should (bufferp kuro-attach-result)))))

;;; Group 22 (attach): kuro--schedule-initial-render — live-buffer path and timer lambda
;;
;; Supplements Group 14: verifies that when the buffer IS live, the timer lambda
;; calls kuro--render-cycle.

(ert-deftest kuro-lifecycle--schedule-initial-render-fires-render-when-live ()
  "Timer lambda calls kuro--render-cycle when the buffer is still live."
  (let ((render-called nil)
        (captured-fn nil))
    (cl-letf (((symbol-function 'run-with-idle-timer)
               (lambda (_delay _repeat fn &rest _args)
                 (setq captured-fn fn)))
              ((symbol-function 'kuro--render-cycle)
               (lambda () (setq render-called t))))
      (with-temp-buffer
        (let ((live-buf (current-buffer)))
          (kuro--schedule-initial-render live-buf)
          ;; Invoke the timer lambda directly while the buffer is still live.
          (funcall captured-fn live-buf))))
    (should render-called)))

(ert-deftest kuro-lifecycle--schedule-initial-render-uses-startup-delay-constant ()
  "kuro--schedule-initial-render uses kuro--startup-render-delay (0.05 s)."
  (should (= kuro--startup-render-delay 0.05)))

;;; ── Group 5: kuro-list-sessions (tabulated-list-mode) ──────────────────────

(ert-deftest kuro-lifecycle--list-sessions-no-sessions ()
  "kuro-list-sessions shows an empty table when kuro-core-list-sessions returns nil."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () nil))
            ((symbol-function 'display-buffer) #'ignore))
    (kuro-list-sessions)
    (let ((buf (get-buffer kuro--buffer-name-sessions)))
      (unwind-protect
          (progn
            (should (bufferp buf))
            (with-current-buffer buf
              (should (eq major-mode 'kuro-sessions-mode))
              (should (null (tabulated-list-get-id)))))
        (when buf (kill-buffer buf))))))

(ert-deftest kuro-lifecycle--list-sessions-nth-index-regression ()
  "Regression: entry (id cmd nil t) must show 'running' in the table row."
  (kuro-lifecycle-ext2-test--with-sessions '((0 "bash" nil t))
    (let ((s (buffer-string)))
      (should (string-match-p "running" s))
      (should-not (string-match-p "detached" s)))))

(ert-deftest kuro-lifecycle--list-sessions-detached-status ()
  "A session with detached-p=t (index 2) shows status 'detached'."
  (kuro-lifecycle-ext2-test--with-sessions '((1 "/bin/bash" t t))
    (should (string-match-p "detached" (buffer-string)))))

(ert-deftest kuro-lifecycle--list-sessions-dead-status ()
  "A session with detached-p=nil and alive-p=nil shows 'dead'."
  (kuro-lifecycle-ext2-test--with-sessions '((2 "/bin/sh" nil nil))
    (should (string-match-p "dead" (buffer-string)))))

(ert-deftest kuro-lifecycle--list-sessions-shows-command ()
  "kuro-list-sessions includes the shell command string in the output."
  (kuro-lifecycle-ext2-test--with-sessions '((3 "/usr/bin/fish" nil t))
    (should (string-match-p "/usr/bin/fish" (buffer-string)))))

;;; ── Group 6: kuro-kill detach branch ────────────────────────────────────────

(ert-deftest kuro-lifecycle--kill-detaches-when-user-says-no ()
  "kuro-kill calls kuro-core-detach with the session ID when user says no."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (setq-local kuro--initialized t)
    (setq-local kuro--session-id 99)
    (let ((detach-called-with nil)
          (shutdown-called nil))
      (kuro-lifecycle-test--with-kill-stubs
        (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
                  ((symbol-function 'yes-or-no-p)            (lambda (_p) nil))
                  ((symbol-function 'kuro-core-detach)       (lambda (id) (setq detach-called-with id)))
                  ((symbol-function 'kuro--shutdown)         (lambda () (setq shutdown-called t))))
          (kuro-kill)
          (should (equal detach-called-with 99))
          (should-not shutdown-called)
          (should-not kuro--initialized)
          (should (= kuro--session-id 0)))))))

(ert-deftest kuro-lifecycle--kill-destroys-when-user-says-yes ()
  "kuro-kill calls kuro--shutdown (not kuro-core-detach) when user says yes."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (setq-local kuro--initialized t)
    (setq-local kuro--session-id 77)
    (let ((detach-called nil)
          (shutdown-called nil))
      (kuro-lifecycle-test--with-kill-stubs
        (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
                  ((symbol-function 'yes-or-no-p)            (lambda (_p) t))
                  ((symbol-function 'kuro-core-detach)       (lambda (_id) (setq detach-called t)))
                  ((symbol-function 'kuro--shutdown)         (lambda () (setq shutdown-called t))))
          (kuro-kill)
          (should shutdown-called)
          (should-not detach-called))))))

;;; ── Group 4c: kuro--install-and-load-module ─────────────────────────────────

(ert-deftest kuro-lifecycle--install-and-load-calls-install-fn ()
  "`kuro--install-and-load-module' calls INSTALL-FN exactly once."
  (let ((called 0))
    (cl-letf (((symbol-function 'kuro-module-load)    #'ignore)
              ((symbol-function 'kuro--module-loadable-p) (lambda () t)))
      (kuro--install-and-load-module (lambda () (setq called (1+ called))) "test")
      (should (= called 1)))))

(ert-deftest kuro-lifecycle--install-and-load-returns-t-when-loadable ()
  "`kuro--install-and-load-module' returns t when `kuro--module-loadable-p' is t."
  (cl-letf (((symbol-function 'kuro-module-load)      #'ignore)
            ((symbol-function 'kuro--module-loadable-p) (lambda () t)))
    (should (kuro--install-and-load-module #'ignore "test"))))

(ert-deftest kuro-lifecycle--install-and-load-errors-when-not-loadable ()
  "`kuro--install-and-load-module' signals an error when module cannot be loaded."
  (cl-letf (((symbol-function 'kuro-module-load)      #'ignore)
            ((symbol-function 'kuro--module-loadable-p) (lambda () nil)))
    (should-error
     (kuro--install-and-load-module #'ignore "bad-install")
     :type 'error)))

;;; ── kuro--session-setup-fns invariants ───────────────────────────────────────

(ert-deftest kuro-lifecycle--session-setup-fns-is-non-empty-list ()
  "`kuro--session-setup-fns' is a non-empty list of function symbols."
  (should (and (listp kuro--session-setup-fns)
               (not (null kuro--session-setup-fns)))))

(ert-deftest kuro-lifecycle--session-setup-fns-all-bound ()
  "Every entry in `kuro--session-setup-fns' is a bound function symbol."
  (dolist (fn kuro--session-setup-fns)
    (should (fboundp fn))))

(ert-deftest kuro-lifecycle--session-setup-fns-excludes-reset-cursor-cache ()
  "`kuro--reset-cursor-cache' must NOT be in `kuro--session-setup-fns' (it is a macro)."
  (should-not (memq 'kuro--reset-cursor-cache kuro--session-setup-fns)))

;;; ── kuro--module-install-methods invariants ──────────────────────────────────

(ert-deftest kuro-lifecycle--module-install-methods-non-empty ()
  "`kuro--module-install-methods' is a non-empty list."
  (should (and (listp kuro--module-install-methods)
               (not (null kuro--module-install-methods)))))

(ert-deftest kuro-lifecycle--module-install-methods-has-prebuilt ()
  "`kuro--module-install-methods' has a `prebuilt' entry."
  (should (assq 'prebuilt kuro--module-install-methods)))

(ert-deftest kuro-lifecycle--module-install-methods-has-cargo ()
  "`kuro--module-install-methods' has a `cargo' entry."
  (should (assq 'cargo kuro--module-install-methods)))

(ert-deftest kuro-lifecycle--module-install-methods-all-fns-bound ()
  "Every install function in `kuro--module-install-methods' is a bound symbol."
  (dolist (entry kuro--module-install-methods)
    (should (fboundp (nth 2 entry)))))

(ert-deftest kuro-lifecycle--module-install-methods-all-have-display-names ()
  "Every entry in `kuro--module-install-methods' has a non-empty display name."
  (dolist (entry kuro--module-install-methods)
    (let ((display-name (nth 3 entry)))
      (should (and (stringp display-name) (not (string-empty-p display-name)))))))

(ert-deftest kuro-lifecycle--module-install-methods-all-have-key-chars ()
  "Every entry in `kuro--module-install-methods' has an integer key character."
  (dolist (entry kuro--module-install-methods)
    (should (characterp (nth 1 entry)))))

(ert-deftest kuro-lifecycle--install-module-by-method-macroexpands-to-pcase ()
  "`kuro--install-module-by-method' expands to a fixed `pcase' dispatch."
  (should (equal (macroexpand-1 '(kuro--install-module-by-method method))
                 '(pcase method
                    ('prebuilt
                     (kuro--install-and-load-module #'kuro-module-download "download"))
                    ('cargo
                     (kuro--install-and-load-module #'kuro-module-build "cargo build"))
                    ('manual
                     (user-error "Native module missing; install manually then retry"))
                    (_
                     (kuro--prompt-and-install-module))))))

(ert-deftest kuro-lifecycle--install-module-by-key-macroexpands-to-pcase ()
  "`kuro--install-module-by-key' expands to a fixed `pcase' dispatch."
  (should (equal (macroexpand-1 '(kuro--install-module-by-key key))
                 '(pcase key
                    (?d
                     (kuro--install-and-load-module #'kuro-module-download "download"))
                    (?b
                     (kuro--install-and-load-module #'kuro-module-build "cargo build"))
                    (_
                     (user-error "Aborted: kuro native module is required"))))))

(provide 'kuro-lifecycle-ext2-test)
;;; kuro-lifecycle-ext2-test.el ends here
