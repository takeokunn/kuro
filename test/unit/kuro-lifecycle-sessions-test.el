;;; kuro-lifecycle-ext-test.el --- Unit tests for kuro-lifecycle.el (Groups 9–16)  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;;; Commentary:

;; ERT tests for kuro-lifecycle.el public API — continuation file.
;; Groups 9–16 are covered here; Groups 1–8 live in kuro-lifecycle-test.el.
;; Tests run without the Rust dynamic module: all FFI primitives are stubbed
;; before `kuro-lifecycle' is loaded.  When loaded after kuro-test.el
;; (as the Makefile does), the stubs in kuro-test.el are already present;
;; the `unless (fboundp …)' guards here handle standalone loading.
;;
;; Groups:
;;   Group 9:  kuro--def-control-key macro
;;   Group 10: kuro-list-sessions additional coverage
;;   Group 11: kuro-kill teardown ordering and kill-buffer
;;   Group 12: kuro--cleanup-render-state — image overlays and idempotency
;;   Group 13: kuro-attach interactive spec (completing-read)
;;   Group 14: kuro-sessions-mode (tabulated-list-mode)
;;   Group 15: kuro-sessions--entries direct tests
;;   Group 16: kuro-sessions-refresh

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-lifecycle-test-support)

;;; ── Group 9: kuro--def-control-key macro ────────────────────────────────────

(ert-deftest kuro-lifecycle-def-control-key-generates-interactive-command ()
  "kuro--def-control-key generates a bound, interactive defun."
  (should (fboundp 'kuro-send-interrupt))
  (should (fboundp 'kuro-send-sigstop))
  (should (fboundp 'kuro-send-sigquit))
  (should (commandp 'kuro-send-interrupt))
  (should (commandp 'kuro-send-sigstop))
  (should (commandp 'kuro-send-sigquit)))

(ert-deftest kuro-lifecycle-def-control-key-sends-correct-sequence ()
  "kuro-send-interrupt sends [?\\C-c] to the terminal."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (seq) (setq sent seq))))
      (kuro-send-interrupt)
      (should (equal sent [?\C-c])))))

;;; ── Group 10: kuro-list-sessions additional coverage ────────────────────────
;;
;; Covers the error path (kuro-core-list-sessions signals), multiple sessions,
;; and correct use of kuro--buffer-name-sessions.

(ert-deftest kuro-lifecycle--list-sessions-error-path-shows-empty-table ()
  "kuro-list-sessions treats an error from kuro-core-list-sessions as empty.
When the FFI call signals, condition-case in kuro-sessions--entries catches it
and returns nil, so the table is rendered with zero rows."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () (error "module not loaded")))
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

(ert-deftest kuro-lifecycle--list-sessions-multiple-sessions-all-present ()
  "kuro-list-sessions renders all entries when multiple sessions are returned."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda ()
               '((0 "bash"    nil t)
                 (1 "fish"    t   t)
                 (2 "/bin/sh" nil nil))))
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    (with-current-buffer "*kuro-sessions*"
      (let ((s (buffer-string)))
        (should (string-match-p "bash"     s))
        (should (string-match-p "fish"     s))
        (should (string-match-p "/bin/sh"  s))
        (should (string-match-p "running"  s))
        (should (string-match-p "detached" s))
        (should (string-match-p "dead"     s))))))

(ert-deftest kuro-lifecycle--list-sessions-uses-correct-buffer-name ()
  "kuro-list-sessions writes into the buffer named by kuro--buffer-name-sessions."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((0 "bash" nil t))))
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    ;; The sessions buffer must exist and carry the expected name.
    (should (get-buffer kuro--buffer-name-sessions))
    (should (string= (buffer-name (get-buffer kuro--buffer-name-sessions))
                     kuro--buffer-name-sessions))))

(ert-deftest kuro-lifecycle--list-sessions-point-at-min-after ()
  "kuro-list-sessions leaves point at the beginning of the sessions buffer."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((0 "bash" nil t))))
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    (with-current-buffer "*kuro-sessions*"
      (should (= (point) (point-min))))))

;;; ── Group 11: kuro-kill teardown ordering and kill-buffer ────────────────────
;;
;; Verifies that kuro-kill tears down in the correct sequence and that
;; kill-buffer is called on the current buffer at the end.

(ert-deftest kuro-lifecycle--kill-calls-kill-buffer-on-current ()
  "kuro-kill calls kill-buffer with the current buffer."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((killed-buf nil)
          (this-buf   (current-buffer)))
      (kuro-lifecycle-test--with-kill-stubs
        (cl-letf (((symbol-function 'kill-buffer)
                   (lambda (buf) (setq killed-buf buf))))
          (kuro-kill)
          (should (eq killed-buf this-buf)))))))

(ert-deftest kuro-lifecycle--kill-teardown-before-kill-buffer ()
  "kuro-kill calls kuro--teardown-session before kill-buffer."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((order nil))
      (cl-letf (((symbol-function 'kuro--stop-render-loop)     (lambda ()      nil))
                ((symbol-function 'kuro--cleanup-render-state) (lambda ()      nil))
                ((symbol-function 'kuro--clear-all-image-overlays) (lambda ()  nil))
                ((symbol-function 'kuro--teardown-session)
                 (lambda () (push 'teardown order)))
                ((symbol-function 'kill-buffer)
                 (lambda (_buf) (push 'kill order))))
        (kuro-kill)
        (let ((seq (nreverse order)))
          (should (eq (nth 0 seq) 'teardown))
          (should (eq (nth 1 seq) 'kill)))))))

(ert-deftest kuro-lifecycle--kill-cleanup-before-teardown ()
  "kuro-kill calls kuro--cleanup-render-state before kuro--teardown-session."
  (with-temp-buffer
    (setq major-mode 'kuro-mode)
    (let ((order nil))
      (cl-letf (((symbol-function 'kuro--stop-render-loop)
                 (lambda () (push 'stop order)))
                ((symbol-function 'kuro--cleanup-render-state)
                 (lambda () (push 'cleanup order)))
                ((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil))
                ((symbol-function 'kuro--teardown-session)
                 (lambda () (push 'teardown order)))
                ((symbol-function 'kill-buffer) (lambda (_buf) nil)))
        (kuro-kill)
        (let ((seq (nreverse order)))
          (should (equal (list 'stop 'cleanup 'teardown) seq)))))))

;;; ── Group 12: kuro--cleanup-render-state — image overlays and idempotency ────
;;
;; Covers kuro--clear-all-image-overlays being called and the idempotent
;; second-call behaviour.

(ert-deftest kuro-lifecycle--cleanup-render-state-calls-clear-image-overlays ()
  "kuro--cleanup-render-state always calls kuro--clear-all-image-overlays."
  (with-temp-buffer
    (let ((clear-called nil))
      (cl-letf (((symbol-function 'kuro--clear-all-image-overlays)
                 (lambda () (setq clear-called t))))
        (kuro--cleanup-render-state)
        (should clear-called)))))

(ert-deftest kuro-lifecycle--cleanup-render-state-idempotent ()
  "kuro--cleanup-render-state called twice leaves state at nil/0 with no error."
  (with-temp-buffer
    (setq-local kuro--tui-mode-active      t
                kuro--tui-mode-frame-count 3
                kuro--last-dirty-count     7
                kuro--mouse-mode           1
                kuro--mouse-sgr            t
                kuro--mouse-pixel-mode     t
                kuro--scroll-offset        5
                kuro--font-remap-cookie    nil)
    (cl-letf (((symbol-function 'kuro--clear-all-image-overlays) (lambda () nil)))
      (kuro--cleanup-render-state)
      (kuro--cleanup-render-state)   ; second call — must not error
      (should-not kuro--tui-mode-active)
      (should (= kuro--mouse-mode 0))
      (should (= kuro--scroll-offset 0)))))

;;; ── Group 13: kuro-attach interactive spec (completing-read) ────────────────
;;
;; kuro-attach's interactive form calls kuro-core-list-sessions and filters
;; for detached sessions.  When no sessions exist or none are detached, it
;; signals user-error.  When detached sessions exist, completing-read is
;; called with formatted candidates.

(ert-deftest kuro-lifecycle--attach-no-sessions-signals-user-error ()
  "kuro-attach signals user-error when kuro-core-list-sessions returns nil."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () nil)))
    (should-error (call-interactively 'kuro-attach)
                  :type 'user-error)))

(ert-deftest kuro-lifecycle--attach-no-detached-signals-user-error ()
  "kuro-attach signals user-error when all sessions are attached (none detached)."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             ;; Two sessions, both with detached-p=nil (index 2)
             (lambda () '((0 "bash" nil t)
                          (1 "fish" nil t)))))
    (should-error (call-interactively 'kuro-attach)
                  :type 'user-error)))

(ert-deftest kuro-lifecycle--attach-detached-calls-completing-read ()
  "kuro-attach calls completing-read with formatted candidates for detached sessions."
  (let ((cr-candidates nil)
        (cr-prompt nil))
    (cl-letf (((symbol-function 'kuro-core-list-sessions)
               (lambda () '((0 "bash" nil t)
                            (1 "fish" t   t)
                            (2 "zsh"  t   nil))))
              ((symbol-function 'completing-read)
               (lambda (prompt candidates &rest _args)
                 (setq cr-prompt prompt
                       cr-candidates candidates)
                 ;; Return the first candidate
                 (caar candidates)))
              ((symbol-function 'kuro--ensure-module-loaded)
               (lambda () nil))
              ((symbol-function 'kuro-mode)
               (lambda () nil))
              ((symbol-function 'kuro--do-attach)
               (lambda (_id _rows _cols) nil))
              ((symbol-function 'switch-to-buffer)
               (lambda (_buf) nil))
              ((symbol-function 'message)
               (lambda (_fmt &rest _args) nil)))
      (call-interactively 'kuro-attach)
      ;; completing-read must have been called
      (should cr-prompt)
      (should (string-match-p "session" (downcase cr-prompt)))
      ;; Only detached sessions (id=1 and id=2) should appear as candidates
      (should (= (length cr-candidates) 2))
      ;; Candidates should be formatted as "Session ID: cmd"
      (should (cl-some (lambda (c) (string-match-p "Session 1.*fish" (car c)))
                       cr-candidates))
      (should (cl-some (lambda (c) (string-match-p "Session 2.*zsh" (car c)))
                       cr-candidates))
      ;; Attached session (id=0) must NOT appear
      (should-not (cl-some (lambda (c) (string-match-p "Session 0" (car c)))
                           cr-candidates)))))

(ert-deftest kuro-lifecycle--attach-completing-read-returns-session-id ()
  "kuro-attach passes the selected session ID to the body."
  (let ((attached-id nil))
    (cl-letf (((symbol-function 'kuro-core-list-sessions)
               (lambda () '((5 "bash" t t))))
              ((symbol-function 'completing-read)
               (lambda (_prompt candidates &rest _args)
                 ;; Select the only candidate: "Session 5: bash"
                 (caar candidates)))
              ((symbol-function 'kuro--ensure-module-loaded)
               (lambda () nil))
              ((symbol-function 'kuro-mode)
               (lambda () nil))
              ((symbol-function 'kuro--do-attach)
               (lambda (id _rows _cols)
                 (setq attached-id id)))
              ((symbol-function 'switch-to-buffer)
               (lambda (_buf) nil))
              ((symbol-function 'message)
               (lambda (_fmt &rest _args) nil)))
      (call-interactively 'kuro-attach)
      (should (= attached-id 5)))))

(ert-deftest kuro-lifecycle--attach-error-from-list-sessions-signals-user-error ()
  "kuro-attach signals user-error when kuro-core-list-sessions errors (caught as nil)."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () (error "module not loaded"))))
    (should-error (call-interactively 'kuro-attach)
                  :type 'user-error)))

;;; ── Group 14: kuro-sessions-mode (tabulated-list-mode) ─────────────────────
;;
;; Tests for the interactive session list: mode derivation, keymap bindings,
;; kuro-sessions-attach, kuro-sessions-destroy, kuro-sessions-refresh.

(ert-deftest kuro-lifecycle--sessions-mode-derived-from-tabulated-list ()
  "kuro-sessions-mode is derived from tabulated-list-mode."
  (with-temp-buffer
    (kuro-sessions-mode)
    (should (derived-mode-p 'tabulated-list-mode))))

(ert-deftest kuro-lifecycle--sessions-mode-ret-bound-to-attach ()
  "RET is bound to kuro-sessions-attach in kuro-sessions-mode-map."
  (should (eq (lookup-key kuro-sessions-mode-map (kbd "RET"))
              #'kuro-sessions-attach)))

(ert-deftest kuro-lifecycle--sessions-mode-a-bound-to-attach ()
  "`a' is bound to kuro-sessions-attach in kuro-sessions-mode-map."
  (should (eq (lookup-key kuro-sessions-mode-map (kbd "a"))
              #'kuro-sessions-attach)))

(ert-deftest kuro-lifecycle--sessions-mode-d-bound-to-destroy ()
  "`d' is bound to kuro-sessions-destroy in kuro-sessions-mode-map."
  (should (eq (lookup-key kuro-sessions-mode-map (kbd "d"))
              #'kuro-sessions-destroy)))

(ert-deftest kuro-lifecycle--sessions-mode-g-bound-to-refresh ()
  "`g' is bound to kuro-sessions-refresh in kuro-sessions-mode-map."
  (should (eq (lookup-key kuro-sessions-mode-map (kbd "g"))
              #'kuro-sessions-refresh)))

(ert-deftest kuro-lifecycle--sessions-mode-q-bound-to-quit ()
  "`q' is bound to quit-window in kuro-sessions-mode-map."
  (should (eq (lookup-key kuro-sessions-mode-map (kbd "q"))
              #'quit-window)))

(ert-deftest kuro-lifecycle--list-sessions-creates-buffer-in-sessions-mode ()
  "kuro-list-sessions creates a buffer in kuro-sessions-mode."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((0 "bash" nil t))))
            ((symbol-function 'display-buffer)
             (lambda (_buf) nil)))
    (kuro-list-sessions)
    (with-current-buffer "*kuro-sessions*"
      (should (eq major-mode 'kuro-sessions-mode)))))

(ert-deftest kuro-lifecycle--sessions-attach-calls-kuro-attach ()
  "kuro-sessions-attach calls kuro-attach with the session ID at point."
  (let ((attached-id nil))
    (cl-letf (((symbol-function 'kuro-core-list-sessions)
               (lambda () '((42 "bash" t t))))
              ((symbol-function 'display-buffer)
               (lambda (_buf) nil))
              ((symbol-function 'kuro-attach)
               (lambda (id) (setq attached-id id))))
      (kuro-list-sessions)
      (with-current-buffer "*kuro-sessions*"
        (goto-char (point-min))
        (kuro-sessions-attach)
        (should (= attached-id 42))))))

(ert-deftest kuro-lifecycle--sessions-attach-no-entry-signals-error ()
  "kuro-sessions-attach signals user-error when no session is at point."
  (with-temp-buffer
    (kuro-sessions-mode)
    (should-error (kuro-sessions-attach) :type 'user-error)))

(ert-deftest kuro-lifecycle--sessions-destroy-calls-shutdown-and-reverts ()
  "kuro-sessions-destroy calls kuro-core-shutdown and refreshes the list."
  (let ((shutdown-id nil)
        (reverted nil))
    (cl-letf (((symbol-function 'kuro-core-list-sessions)
               (lambda () '((7 "fish" t t))))
              ((symbol-function 'display-buffer)
               (lambda (_buf) nil))
              ((symbol-function 'kuro-core-shutdown)
               (lambda (id) (setq shutdown-id id)))
              ((symbol-function 'y-or-n-p)
               (lambda (_prompt) t))
              ((symbol-function 'tabulated-list-revert)
               (lambda () (setq reverted t))))
      (kuro-list-sessions)
      (with-current-buffer "*kuro-sessions*"
        (goto-char (point-min))
        (kuro-sessions-destroy)
        (should (= shutdown-id 7))
        (should reverted)))))

(ert-deftest kuro-lifecycle--sessions-destroy-aborts-on-no ()
  "kuro-sessions-destroy does nothing when user answers no."
  (let ((shutdown-called nil))
    (cl-letf (((symbol-function 'kuro-core-list-sessions)
               (lambda () '((7 "fish" t t))))
              ((symbol-function 'display-buffer)
               (lambda (_buf) nil))
              ((symbol-function 'kuro-core-shutdown)
               (lambda (_id) (setq shutdown-called t)))
              ((symbol-function 'y-or-n-p)
               (lambda (_prompt) nil)))
      (kuro-list-sessions)
      (with-current-buffer "*kuro-sessions*"
        (goto-char (point-min))
        (kuro-sessions-destroy)
        (should-not shutdown-called)))))

(ert-deftest kuro-lifecycle--session-status-helper ()
  "kuro--session-status returns correct status strings."
  (should (equal (kuro--session-status t t)     "detached"))
  (should (equal (kuro--session-status t nil)   "detached"))
  (should (equal (kuro--session-status nil t)   "running"))
  (should (equal (kuro--session-status nil nil)  "dead")))

(ert-deftest kuro-lifecycle--sessions-entries-returns-tabulated-format ()
  "kuro-sessions--entries returns entries in tabulated-list format."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((1 "bash" nil t)))))
    (let ((entries (kuro-sessions--entries)))
      (should (= (length entries) 1))
      (let ((entry (car entries)))
        ;; Entry is (ID [ID-STRING COMMAND STATUS])
        (should (= (car entry) 1))
        (should (vectorp (cadr entry)))
        (should (equal (aref (cadr entry) 0) "1"))
        (should (equal (aref (cadr entry) 1) "bash"))
        (should (equal (aref (cadr entry) 2) "running"))))))

;;; ── Group 15: kuro-sessions--entries direct tests ───────────────────────────
;;
;; Tests for kuro-sessions--entries independent of the full kuro-list-sessions
;; pipeline: empty return, malformed entries, multi-session, and error path.

(ert-deftest kuro-lifecycle--sessions-entries-empty-when-ffi-returns-nil ()
  "kuro-sessions--entries returns an empty list when kuro-core-list-sessions returns nil."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () nil)))
    (should (null (kuro-sessions--entries)))))

(ert-deftest kuro-lifecycle--sessions-entries-filters-malformed-short-entry ()
  "kuro-sessions--entries ignores entries with fewer than 4 elements."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             ;; 3-element entry is below the (>= (length entry) 4) guard
             (lambda () '((0 "bash" nil)))))
    (should (null (kuro-sessions--entries)))))

(ert-deftest kuro-lifecycle--sessions-entries-filters-non-list-entry ()
  "kuro-sessions--entries ignores entries that are not lists."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '("not-a-list"))))
    (should (null (kuro-sessions--entries)))))

(ert-deftest kuro-lifecycle--sessions-entries-two-valid-produce-two-rows ()
  "kuro-sessions--entries returns two tabulated rows for two valid entries."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda ()
               '((0 "bash" nil t)
                 (1 "fish" t   t)))))
    (let ((entries (kuro-sessions--entries)))
      (should (= (length entries) 2))
      ;; First entry: id=0, running
      (let ((e0 (car entries)))
        (should (= (car e0) 0))
        (should (equal (aref (cadr e0) 2) "running")))
      ;; Second entry: id=1, detached
      (let ((e1 (cadr entries)))
        (should (= (car e1) 1))
        (should (equal (aref (cadr e1) 2) "detached"))))))

(ert-deftest kuro-lifecycle--sessions-entries-ffi-error-returns-nil ()
  "kuro-sessions--entries returns nil when kuro-core-list-sessions signals an error."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () (error "module error"))))
    (should (null (kuro-sessions--entries)))))

;;; ── Group 16: kuro-sessions-refresh ─────────────────────────────────────────

(ert-deftest kuro-lifecycle--sessions-refresh-calls-tabulated-list-revert ()
  "kuro-sessions-refresh calls `tabulated-list-revert'."
  (let ((reverted nil))
    (cl-letf (((symbol-function 'tabulated-list-revert)
               (lambda () (setq reverted t))))
      (kuro-sessions-refresh))
    (should reverted)))

(provide 'kuro-lifecycle-ext-test)

;;; kuro-lifecycle-ext-test.el ends here
