;;; kuro-activity-test-2.el --- kuro-activity tests Groups 9-12  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-activity)

;;; Group 9 — kuro-activity--log logging behaviour

(ert-deftest kuro-activity-test-notify-pushes-to-log ()
  "`kuro--activity-notify' appends an entry to `kuro-activity--log'."
  (let ((kuro-activity--log nil)
        (kuro-notifications-enabled nil))
    (kuro--activity-notify "sess" "msg")
    (should (= (length kuro-activity--log) 1))
    (should (string= (cadr  (car kuro-activity--log)) "sess"))
    (should (string= (caddr (car kuro-activity--log)) "msg"))))

(ert-deftest kuro-activity-test-notify-logs-even-when-disabled ()
  "`kuro--activity-notify' logs the entry even when notifications are off."
  (let ((kuro-activity--log nil)
        (kuro-notifications-enabled nil))
    (kuro--activity-notify "s" "b")
    (should (= (length kuro-activity--log) 1))))

(ert-deftest kuro-activity-test-log-truncates-at-max ()
  "`kuro--activity-notify' truncates log at `kuro-activity-log-max-length'."
  (let ((kuro-activity--log (make-list 3 '(nil "x" "y")))
        (kuro-activity-log-max-length 3)
        (kuro-notifications-enabled nil))
    (kuro--activity-notify "new" "entry")
    (should (= (length kuro-activity--log) 3))
    (should (string= (cadr (car kuro-activity--log)) "new"))))

(ert-deftest kuro-activity-test-log-max-nil-keeps-all ()
  "`kuro--activity-notify' keeps unlimited entries when max is nil."
  (let ((kuro-activity--log (make-list 500 '(nil "x" "y")))
        (kuro-activity-log-max-length nil)
        (kuro-notifications-enabled nil))
    (kuro--activity-notify "s" "b")
    (should (= (length kuro-activity--log) 501))))

(ert-deftest kuro-activity-test-clear-empties-log ()
  "`kuro-activity-clear' sets `kuro-activity--log' to nil."
  (let ((kuro-activity--log (list '(nil "s" "b"))))
    (cl-letf (((symbol-function 'get-buffer) (lambda (_) nil)))
      (kuro-activity-clear)
      (should (null kuro-activity--log)))))

(ert-deftest kuro-activity-test-log-max-defcustom-exists ()
  "`kuro-activity-log-max-length' is a customization variable."
  (should (boundp 'kuro-activity-log-max-length)))

;;; Group 10 — kuro-activity-list-mode and kuro-activity-list

(ert-deftest kuro-activity-test-list-entries-empty-when-log-empty ()
  "`kuro-activity-list--entries' returns nil when log is empty."
  (let ((kuro-activity--log nil))
    (should (null (kuro-activity-list--entries)))))

(ert-deftest kuro-activity-test-list-entries-reflect-log ()
  "`kuro-activity-list--entries' returns one row per log entry."
  (let ((kuro-activity--log (list (list nil "sess" "msg"))))
    (let ((entries (kuro-activity-list--entries)))
      (should (= (length entries) 1))
      (let ((row (cadr (car entries))))
        (should (string= (aref row 1) "sess"))
        (should (string= (aref row 2) "msg"))))))

(ert-deftest kuro-activity-test-list-mode-is-defined ()
  "`kuro-activity-list-mode' is a major mode command."
  (should (fboundp 'kuro-activity-list-mode)))

(ert-deftest kuro-activity-test-list-interactive-is-defined ()
  "`kuro-activity-list' is an interactive command."
  (should (commandp #'kuro-activity-list)))

(ert-deftest kuro-activity-test-clear-is-interactive ()
  "`kuro-activity-clear' is an interactive command."
  (should (commandp #'kuro-activity-clear)))

(ert-deftest kuro-activity-test-list-creates-activity-buffer ()
  "`kuro-activity-list' creates (or reuses) the *kuro-activity* buffer."
  (let ((display-called nil)
        (buf (get-buffer "*kuro-activity*")))
    (when buf (kill-buffer buf))
    (cl-letf (((symbol-function 'display-buffer)
               (lambda (b) (setq display-called b))))
      (kuro-activity-list)
      (should (buffer-live-p (get-buffer "*kuro-activity*")))
      (should display-called))
    (when (buffer-live-p (get-buffer "*kuro-activity*"))
      (kill-buffer "*kuro-activity*"))))

(ert-deftest kuro-activity-test-list-activates-mode-on-fresh-buffer ()
  "`kuro-activity-list' sets kuro-activity-list-mode on a newly created buffer."
  (let ((buf (get-buffer "*kuro-activity*")))
    (when buf (kill-buffer buf))
    (cl-letf (((symbol-function 'display-buffer) #'ignore))
      (kuro-activity-list)
      (with-current-buffer "*kuro-activity*"
        (should (derived-mode-p 'kuro-activity-list-mode))))
    (when (buffer-live-p (get-buffer "*kuro-activity*"))
      (kill-buffer "*kuro-activity*"))))

(ert-deftest kuro-activity-test-list-idempotent-when-mode-already-set ()
  "`kuro-activity-list' does not error when called twice (mode already active)."
  (let ((buf (get-buffer "*kuro-activity*")))
    (when buf (kill-buffer buf))
    (cl-letf (((symbol-function 'display-buffer) #'ignore))
      (kuro-activity-list)
      (should-not (condition-case err (progn (kuro-activity-list) nil) (error err))))
    (when (buffer-live-p (get-buffer "*kuro-activity*"))
      (kill-buffer "*kuro-activity*"))))

;;; Group 11 — kuro-activity-list-mode keymap

(defconst kuro-activity-test--list-map-binding-table
  '((kuro-activity-test-list-map-binds-revert "g" tabulated-list-revert)
    (kuro-activity-test-list-map-binds-delete "d" kuro-activity-list-delete-entry)
    (kuro-activity-test-list-map-binds-clear   "c" kuro-activity-clear)
    (kuro-activity-test-list-map-binds-quit    "q" quit-window))
  "Table of (test-name key command) for `kuro-activity-list-mode-map'.")

(defmacro kuro-activity-test--def-list-map-binding (test-name key command)
  `(ert-deftest ,test-name ()
     ,(format "`kuro-activity-list-mode-map' binds %s to %s." key command)
     (should (eq (lookup-key kuro-activity-list-mode-map (kbd ,key))
                 #',command))))

(defmacro kuro-activity-test--deftest-list-map-bindings ()
  "Define all `kuro-activity-list-mode-map' binding checks from the case table."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,key ,command) entry))
            `(kuro-activity-test--def-list-map-binding
              ,test-name ,key ,command)))
        kuro-activity-test--list-map-binding-table)))

(kuro-activity-test--deftest-list-map-bindings)

(ert-deftest kuro-activity-test--all-list-map-bindings-correct ()
  "Invariant: every entry in the list-mode keymap table is bound correctly."
  (dolist (entry kuro-activity-test--list-map-binding-table)
    (pcase-let ((`(,_name ,key ,command) entry))
      (should (eq (lookup-key kuro-activity-list-mode-map (kbd key))
                  command)))))

(ert-deftest kuro-activity-test-list-delete-entry-removes-from-log ()
  "`kuro-activity-list-delete-entry' removes the entry from `kuro-activity--log'."
  (let* ((entry (list nil "s" "b"))
         (kuro-activity--log (list entry)))
    (cl-letf (((symbol-function 'tabulated-list-get-id) (lambda () entry)))
      (kuro-activity-list-delete-entry)
      (should (null kuro-activity--log)))))

(ert-deftest kuro-activity-test-list-delete-entry-noop-when-no-id ()
  "`kuro-activity-list-delete-entry' does nothing when point is not on an entry."
  (let ((kuro-activity--log (list '(nil "s" "b"))))
    (cl-letf (((symbol-function 'tabulated-list-get-id) (lambda () nil)))
      (kuro-activity-list-delete-entry)
      (should (= (length kuro-activity--log) 1)))))

(ert-deftest kuro-activity-test-list-delete-entry-is-interactive ()
  "`kuro-activity-list-delete-entry' is an interactive command."
  (should (commandp #'kuro-activity-list-delete-entry)))

;;; Group 12 — kuro--activity-exit-code-status

(defconst kuro-activity-test--exit-code-status-table
  '((kuro-activity-exit-code-status-nil-is-empty    nil  "")
    (kuro-activity-exit-code-status-zero-is-check   0    " ✓")
    (kuro-activity-exit-code-status-one-is-cross     1    " ✗ (exit 1)")
    (kuro-activity-exit-code-status-127-is-cross    127  " ✗ (exit 127)"))
  "Table: (test-name exit-code expected-string) for `kuro--activity-exit-code-status'.")

(defmacro kuro-activity-test--def-exit-code-status (test-name exit-code expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--activity-exit-code-status' exit-code=%S → %S." exit-code expected)
     (should (equal (kuro--activity-exit-code-status ,exit-code) ,expected))))

(defmacro kuro-activity-test--deftest-exit-code-statuses ()
  "Define all exit-code status checks from the case table."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,code ,expected) entry))
            `(kuro-activity-test--def-exit-code-status
              ,test-name ,code ,expected)))
        kuro-activity-test--exit-code-status-table)))

(kuro-activity-test--deftest-exit-code-statuses)

(ert-deftest kuro-activity-test--all-exit-code-statuses-correct ()
  "Invariant: every entry in the exit-code-status table maps to the expected string."
  (dolist (entry kuro-activity-test--exit-code-status-table)
    (pcase-let ((`(,_name ,code ,expected) entry))
      (should (equal (kuro--activity-exit-code-status code) expected)))))

;;; Group 13 — kuro-activity-clear with-live-buffer branch

(ert-deftest kuro-activity-test-clear-refreshes-live-list-buffer ()
  "`kuro-activity-clear' calls `kuro-activity-list--refresh' when `*kuro-activity*' is live."
  (let ((kuro-activity--log (list '(nil "s" "b")))
        (refresh-called nil))
    (with-temp-buffer
      (let ((the-buf (current-buffer)))
        (cl-letf (((symbol-function 'get-buffer)
                   (lambda (_name) the-buf))
                  ((symbol-function 'kuro-activity-list--refresh)
                   (lambda () (setq refresh-called t))))
          (kuro-activity-clear)
          (should (null kuro-activity--log))
          (should refresh-called))))))

(provide 'kuro-activity-test-2)
;;; kuro-activity-test-2.el ends here
