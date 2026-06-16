;;; kuro-lifecycle-ext-test.el --- Lifecycle tests: sessions, buffer-init  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-lifecycle.el — Groups 13–26.
;; Groups 1–12 are in kuro-lifecycle-test.el.
;; Groups 27–30 are in kuro-lifecycle-ext2-test.el.
;;
;; Groups:
;;   Group 13: kuro-attach interactive spec (completing-read)
;;   Group 14: kuro-sessions-mode (tabulated-list-mode)
;;   Group 15: kuro-sessions--entries direct tests
;;   Group 16: kuro-sessions-refresh

;;   Group 10 (buffer-init): kuro--init-session-buffer
;;   Group 11 (buffer-init): kuro--prefill-buffer
;;   Group 12 (buffer-init): kuro--do-attach and kuro--rollback-attach
;;   Group 13 (buffer-init): kuro--teardown-session
;;   Group 14 (buffer-init): kuro--schedule-initial-render
;;   Group 15 (buffer-init): kuro--do-attach additional coverage
;;   Group 16 (buffer-init): kuro--init-session-buffer additional coverage
;;   Group 26: kuro-create init-failure + kuro-attach switch-to-buffer guard

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-lifecycle-test-support)

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


;;; ── Group 17: kuro-sessions--entry and kuro-sessions--fetch-raw ──────────────

(ert-deftest kuro-lifecycle--sessions-entry-nil-for-non-list ()
  "`kuro-sessions--entry' returns nil when entry is not a list."
  (should (null (kuro-sessions--entry "not-a-list")))
  (should (null (kuro-sessions--entry 42)))
  (should (null (kuro-sessions--entry nil))))

(ert-deftest kuro-lifecycle--sessions-entry-nil-for-short-entry ()
  "`kuro-sessions--entry' returns nil when entry has fewer than 4 elements."
  (should (null (kuro-sessions--entry '(0 "bash" nil))))
  (should (null (kuro-sessions--entry '(0))))
  (should (null (kuro-sessions--entry '()))))

(kuro-lifecycle-test--def-session-status
 kuro-lifecycle--sessions-entry-running  (5 "fish" nil t)   "running")
(kuro-lifecycle-test--def-session-status
 kuro-lifecycle--sessions-entry-detached (3 "bash" t   t)   "detached")
(kuro-lifecycle-test--def-session-status
 kuro-lifecycle--sessions-entry-dead     (7 "zsh"  nil nil) "dead")

(ert-deftest kuro-lifecycle--sessions-entry-status-invariant ()
  "Invariant: every entry in the status table converts to the expected status string."
  (dolist (spec kuro-lifecycle-test--session-status-table)
    (pcase-let ((`(,_name ,raw ,expected) spec))
      (let ((row (kuro-sessions--entry raw)))
        (should row)
        (should (equal (aref (cadr row) 2) expected))))))

(ert-deftest kuro-lifecycle--sessions-fetch-raw-returns-list-on-success ()
  "`kuro-sessions--fetch-raw' returns the list from `kuro-core-list-sessions'."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () '((0 "fish" nil t) (1 "bash" t nil)))))
    (should (equal (kuro-sessions--fetch-raw)
                   '((0 "fish" nil t) (1 "bash" t nil))))))

(ert-deftest kuro-lifecycle--sessions-fetch-raw-nil-on-error ()
  "`kuro-sessions--fetch-raw' returns nil when `kuro-core-list-sessions' errors."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () (error "module unavailable"))))
    (should (null (kuro-sessions--fetch-raw)))))

(ert-deftest kuro-lifecycle--sessions-fetch-raw-nil-when-returns-nil ()
  "`kuro-sessions--fetch-raw' returns nil when `kuro-core-list-sessions' returns nil."
  (cl-letf (((symbol-function 'kuro-core-list-sessions)
             (lambda () nil)))
    (should (null (kuro-sessions--fetch-raw)))))

(provide 'kuro-lifecycle-ext-test)
;;; kuro-lifecycle-ext-test.el ends here
