;;; kuro-lifecycle-ext2-test-4.el --- Lifecycle tests (part 4) — Groups 31-33  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-lifecycle-test-support)


;;; ── Group 31: kuro--detached-sessions / kuro--session-candidates / kuro--list-sessions-safe ──
;;
;; Pure-function coverage for the attach-session helpers.  Each entry in
;; SESSIONS is (ID COMMAND DETACHED-P ALIVE-P).

(ert-deftest kuro-lifecycle--detached-sessions-empty ()
  "`kuro--detached-sessions' returns nil for an empty list."
  (should (null (kuro--detached-sessions nil))))

(ert-deftest kuro-lifecycle--detached-sessions-all-attached ()
  "`kuro--detached-sessions' returns nil when no session is detached."
  (should (null (kuro--detached-sessions '((1 "sh" nil t) (2 "bash" nil t))))))

(ert-deftest kuro-lifecycle--detached-sessions-all-detached ()
  "`kuro--detached-sessions' returns all entries when all are detached."
  (let ((sessions '((1 "sh" t t) (2 "bash" t nil))))
    (should (equal (kuro--detached-sessions sessions) sessions))))

(ert-deftest kuro-lifecycle--detached-sessions-mixed ()
  "`kuro--detached-sessions' filters to only detached entries."
  (let* ((sessions '((1 "sh" nil t) (2 "bash" t t) (3 "zsh" nil nil)))
         (result   (kuro--detached-sessions sessions)))
    (should (= (length result) 1))
    (should (= (car (nth 0 result)) 2))))

(ert-deftest kuro-lifecycle--session-candidates-empty ()
  "`kuro--session-candidates' returns nil for an empty list."
  (should (null (kuro--session-candidates nil))))

(ert-deftest kuro-lifecycle--session-candidates-label-format ()
  "`kuro--session-candidates' produces (\"Session N: CMD\" . N) pairs."
  (let ((result (kuro--session-candidates '((42 "bash" t t)))))
    (should (= (length result) 1))
    (should (equal (car (nth 0 result)) "Session 42: bash"))
    (should (= (cdr (nth 0 result)) 42))))

(ert-deftest kuro-lifecycle--session-candidates-multiple ()
  "`kuro--session-candidates' produces one pair per entry, IDs preserved."
  (let ((result (kuro--session-candidates '((1 "sh" t t) (99 "fish" t nil)))))
    (should (= (length result) 2))
    (should (= (cdr (assoc "Session 1: sh" result)) 1))
    (should (= (cdr (assoc "Session 99: fish" result)) 99))))

(ert-deftest kuro-lifecycle--list-sessions-safe-returns-value ()
  "`kuro--list-sessions-safe' returns the value from kuro-core-list-sessions."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((1 "bash" nil t)))))
    (should (equal (kuro--list-sessions-safe) '((1 "bash" nil t))))))

(ert-deftest kuro-lifecycle--list-sessions-safe-returns-nil-on-error ()
  "`kuro--list-sessions-safe' returns nil when kuro-core-list-sessions signals an error."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () (error "FFI not available"))))
    (should (null (kuro--list-sessions-safe)))))

(ert-deftest kuro-lifecycle--list-sessions-safe-empty-list ()
  "`kuro--list-sessions-safe' passes through an empty list unchanged."
  (cl-letf (((symbol-function 'kuro-core-list-sessions) (lambda () nil)))
    (should (null (kuro--list-sessions-safe)))))


;;; ── Group 32: kuro--session-buffer-name / kuro--module-loadable-p / kuro--terminal-dimensions ──

(ert-deftest kuro-lifecycle--session-buffer-name-zero ()
  "`kuro--session-buffer-name' formats session-id 0 correctly."
  (should (equal "*kuro<0>*" (kuro--session-buffer-name 0))))

(ert-deftest kuro-lifecycle--session-buffer-name-positive ()
  "`kuro--session-buffer-name' formats a positive session-id correctly."
  (should (equal "*kuro<42>*" (kuro--session-buffer-name 42))))

(ert-deftest kuro-lifecycle--session-buffer-name-large ()
  "`kuro--session-buffer-name' handles large session IDs without truncation."
  (should (equal "*kuro<99999>*" (kuro--session-buffer-name 99999))))

(ert-deftest kuro-lifecycle--module-loadable-p-when-unbound ()
  "`kuro--module-loadable-p' returns nil when `kuro-core-init' is not bound."
  (let ((was-bound (fboundp 'kuro-core-init)))
    (unless was-bound
      (should (null (kuro--module-loadable-p))))))

(ert-deftest kuro-lifecycle--module-loadable-p-when-bound ()
  "`kuro--module-loadable-p' returns non-nil when `kuro-core-init' is fboundp."
  (cl-letf (((symbol-function 'kuro-core-init) (lambda () nil)))
    (should (kuro--module-loadable-p))))

(ert-deftest kuro-lifecycle--terminal-dimensions-noninteractive-rows ()
  "`kuro--terminal-dimensions' returns kuro--default-rows as car in batch mode."
  (let ((noninteractive t))
    (should (= kuro--default-rows (car (kuro--terminal-dimensions))))))

(ert-deftest kuro-lifecycle--terminal-dimensions-noninteractive-cols ()
  "`kuro--terminal-dimensions' returns kuro--default-cols as cdr in batch mode."
  (let ((noninteractive t))
    (should (= kuro--default-cols (cdr (kuro--terminal-dimensions))))))

(ert-deftest kuro-lifecycle--terminal-dimensions-returns-cons ()
  "`kuro--terminal-dimensions' always returns a cons cell."
  (let ((dims (kuro--terminal-dimensions)))
    (should (consp dims))
    (should (integerp (car dims)))
    (should (integerp (cdr dims)))))


;;; ── Group 33: kuro--shell-integration-dir / kuro--setup-shell-integration-env / kuro--most-recent-buffer ──

(ert-deftest kuro-lifecycle--shell-integration-dir-nil-when-disabled ()
  "`kuro--shell-integration-dir' returns nil when `kuro-shell-integration' is nil."
  (let ((kuro-shell-integration nil))
    (should (null (kuro--shell-integration-dir)))))

(ert-deftest kuro-lifecycle--setup-shell-integration-env-unsets-when-dir-nil ()
  "`kuro--setup-shell-integration-env' clears the env var when dir is nil."
  (let ((kuro-shell-integration nil)
        (captured :not-set))
    (cl-letf (((symbol-function 'setenv)
               (lambda (_var val) (setq captured val))))
      (kuro--setup-shell-integration-env)
      (should (null captured)))))

(ert-deftest kuro-lifecycle--most-recent-buffer-nil-when-no-kuro-buffers ()
  "`kuro--most-recent-buffer' returns nil when no buffer is in kuro-mode."
  (cl-letf (((symbol-function 'buffer-list) (lambda () nil)))
    (should (null (kuro--most-recent-buffer)))))

(ert-deftest kuro-lifecycle--attach-buffer-returns-buffer-with-correct-name ()
  "`kuro--attach-buffer' creates a buffer named via `kuro--session-buffer-name'."
  (cl-letf (((symbol-function 'kuro--show-buffer-if-interactive)
             (lambda (buf) buf)))
    (let ((buf (kuro--attach-buffer 7)))
      (unwind-protect
          (should (string-match-p "kuro<7>" (buffer-name buf)))
        (kill-buffer buf)))))


;;; ── Group 34: kuro--show-buffer-if-interactive / kuro--buffer-name-default / env set path ──

(ert-deftest kuro-lifecycle--show-buffer-if-interactive-returns-buffer ()
  "`kuro--show-buffer-if-interactive' returns the buffer in batch mode."
  (let ((buf (get-buffer-create " *kuro-test-display*")))
    (unwind-protect
        (should (eq (kuro--show-buffer-if-interactive buf) buf))
      (kill-buffer buf))))

(ert-deftest kuro-lifecycle--show-buffer-if-interactive-no-switch-in-batch ()
  "`kuro--show-buffer-if-interactive' does NOT call `switch-to-buffer' in batch mode."
  (let ((switched nil)
        (buf (get-buffer-create " *kuro-test-nosw*")))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'switch-to-buffer) (lambda (_b) (setq switched t))))
            (kuro--show-buffer-if-interactive buf))
          (should-not switched))
      (kill-buffer buf))))

(ert-deftest kuro-lifecycle--show-buffer-if-interactive-calls-switch-when-interactive ()
  "`kuro--show-buffer-if-interactive' calls `switch-to-buffer' when not in batch mode."
  (let ((switched nil)
        (buf (get-buffer-create " *kuro-test-sw*")))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'switch-to-buffer) (lambda (_b) (setq switched t))))
            (let ((noninteractive nil))
              (kuro--show-buffer-if-interactive buf)))
          (should switched))
      (kill-buffer buf))))

(ert-deftest kuro-lifecycle--buffer-name-default-is-kuro ()
  "`kuro--buffer-name-default' is the string \"*kuro*\"."
  (should (equal kuro--buffer-name-default "*kuro*")))

(ert-deftest kuro-lifecycle--setup-shell-integration-env-sets-when-dir-found ()
  "`kuro--setup-shell-integration-env' sets KURO_SHELL_INTEGRATION_DIR when a dir is found."
  (let ((captured :not-set))
    (cl-letf (((symbol-function 'kuro--shell-integration-dir) (lambda () "/test/shell"))
              ((symbol-function 'setenv) (lambda (_var val) (setq captured val))))
      (kuro--setup-shell-integration-env)
      (should (equal captured "/test/shell")))))


(provide 'kuro-lifecycle-ext2-test-4)

;;; kuro-lifecycle-ext2-test-4.el ends here
