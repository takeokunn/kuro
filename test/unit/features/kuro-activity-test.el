;;; kuro-activity-test.el --- Unit tests for kuro-activity.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-activity.el (background activity notifications).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Key design note: `kuro-notification-function' is a defcustom variable
;; whose VALUE is the function to call.  `kuro--activity-notify' uses
;; `(funcall kuro-notification-function ...)', which reads the VALUE cell.
;; Tests must rebind via `let', NOT via `cl-letf (symbol-function ...)'.
;;
;; Tests verify:
;;   Group 1: `kuro--activity-visible-p' buffer visibility check
;;   Group 2: `kuro--activity-notify' dispatches via kuro-notification-function
;;   Group 3: `kuro--activity-on-command-complete' threshold/visibility logic
;;   Group 4: `kuro--activity-bell-advice' BEL escalation
;;   Group 5: `kuro--activity-check-exit' process-exit notification
;;   Group 6: `kuro-activity-mode' global minor mode install/uninstall
;;   Group 7: `kuro-on-command-complete-functions' hook in kuro-poll-modes.el
;;   Group 8: `kuro--run-command-complete-hook' dispatches per mark

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-activity)

;;; Helpers

(defmacro kuro-activity-test--with-stubs (notified-var &rest body)
  "Run BODY with notification function stubbed.
NOTIFIED-VAR receives (title . body) when a notification fires, or nil.
Uses `cl-letf (symbol-value ...)' to directly replace the symbol's value
cell — this works regardless of whether the compiler treats the variable
as lexical or dynamic (safe even when `kuro--activity-notify' is inlined
by byte-compilation at the call site)."
  (declare (indent 1))
  `(let ((,notified-var nil)
         (kuro-notifications-enabled t))
     (cl-letf (((symbol-value 'kuro-notification-function)
                (lambda (title body) (setq ,notified-var (cons title body)))))
       ,@body)))

(defmacro kuro-activity-test--with-invisible-buffer (&rest body)
  "Run BODY with `get-buffer-window' stubbed to return nil (invisible)."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'get-buffer-window)
              (lambda (&rest _) nil)))
     ,@body))

(defmacro kuro-activity-test--with-visible-buffer (&rest body)
  "Run BODY with `get-buffer-window' stubbed to return a window (visible)."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'get-buffer-window)
              (lambda (&rest _) (selected-window))))
     ,@body))

;;; Group 1 — kuro--activity-visible-p

(ert-deftest kuro-activity-test-visible-p-invisible ()
  "`kuro--activity-visible-p' returns nil when `get-buffer-window' returns nil."
  (kuro-activity-test--with-invisible-buffer
    (should-not (kuro--activity-visible-p))))

(ert-deftest kuro-activity-test-visible-p-visible ()
  "`kuro--activity-visible-p' returns non-nil when buffer is in a window."
  (kuro-activity-test--with-visible-buffer
    (should (kuro--activity-visible-p))))

;;; Group 2 — kuro--activity-notify

(ert-deftest kuro-activity-test-notify-calls-function ()
  "`kuro--activity-notify' calls `kuro-notification-function' when enabled."
  (kuro-activity-test--with-stubs notif
    (kuro--activity-notify "T" "B")
    (should (equal notif '("T" . "B")))))

(ert-deftest kuro-activity-test-notify-skips-when-disabled ()
  "`kuro--activity-notify' does nothing when `kuro-notifications-enabled' is nil."
  (let ((called nil)
        (kuro-notifications-enabled nil)
        (kuro-notification-function (lambda (&rest _) (setq called t))))
    (kuro--activity-notify "T" "B")
    (should-not called)))

;;; Group 3 — kuro--activity-on-command-complete

(ert-deftest kuro-activity-test-complete-notifies-invisible-long ()
  "Fires notification when buffer invisible and duration >= threshold."
  (kuro-activity-test--with-stubs notif
    (kuro-activity-test--with-invisible-buffer
      (let ((kuro-activity-notify-threshold 10.0))
        ;; 15 seconds (15000ms) >= 10 second threshold
        (kuro--activity-on-command-complete 0 15000 nil nil nil)
        (should notif)))))

(ert-deftest kuro-activity-test-complete-no-notify-visible ()
  "Does NOT fire when buffer is visible (buffer-visible-p = t)."
  (kuro-activity-test--with-stubs notif
    (let ((kuro-activity-notify-threshold 10.0))
      (kuro--activity-on-command-complete 0 15000 nil nil t)
      (should-not notif))))

(ert-deftest kuro-activity-test-complete-no-notify-short ()
  "Does NOT fire when command duration is below threshold."
  (kuro-activity-test--with-stubs notif
    (kuro-activity-test--with-invisible-buffer
      (let ((kuro-activity-notify-threshold 10.0))
        ;; 5000ms < 10000ms threshold
        (kuro--activity-on-command-complete 0 5000 nil nil nil)
        (should-not notif)))))

(ert-deftest kuro-activity-test-complete-no-notify-threshold-nil ()
  "Does NOT fire when `kuro-activity-notify-threshold' is nil."
  (kuro-activity-test--with-stubs notif
    (kuro-activity-test--with-invisible-buffer
      (let ((kuro-activity-notify-threshold nil))
        (kuro--activity-on-command-complete 0 30000 nil nil nil)
        (should-not notif)))))

(ert-deftest kuro-activity-test-complete-no-notify-nil-duration ()
  "Does NOT fire when duration-ms is nil (shell did not provide it)."
  (kuro-activity-test--with-stubs notif
    (kuro-activity-test--with-invisible-buffer
      (let ((kuro-activity-notify-threshold 10.0))
        (kuro--activity-on-command-complete 0 nil nil nil nil)
        (should-not notif)))))

(ert-deftest kuro-activity-test-complete-body-includes-duration ()
  "Notification body includes formatted duration string."
  (let (body-out)
    (kuro-activity-test--with-invisible-buffer
      (let ((kuro-notifications-enabled t)
            (kuro-activity-notify-threshold 10.0))
        (cl-letf (((symbol-value 'kuro-notification-function)
                   (lambda (_title body) (setq body-out body))))
          ;; 90 seconds → "1m30s"
          (kuro--activity-on-command-complete 0 90000 nil nil nil)
          (should (stringp body-out))
          (should (string-match-p "1m30s" body-out)))))))

(ert-deftest kuro-activity-test-complete-body-shows-failure ()
  "Notification body indicates non-zero exit code with ✗."
  (let (body-out)
    (kuro-activity-test--with-invisible-buffer
      (let ((kuro-notifications-enabled t)
            (kuro-activity-notify-threshold 10.0))
        (cl-letf (((symbol-value 'kuro-notification-function)
                   (lambda (_title body) (setq body-out body))))
          (kuro--activity-on-command-complete 1 15000 nil nil nil)
          (should (string-match-p "✗" body-out)))))))

(ert-deftest kuro-activity-test-complete-body-shows-success ()
  "Notification body shows success checkmark ✓ for exit code 0."
  (let (body-out)
    (kuro-activity-test--with-invisible-buffer
      (let ((kuro-notifications-enabled t)
            (kuro-activity-notify-threshold 10.0))
        (cl-letf (((symbol-value 'kuro-notification-function)
                   (lambda (_title body) (setq body-out body))))
          (kuro--activity-on-command-complete 0 15000 nil nil nil)
          (should (string-match-p "✓" body-out)))))))

;;; Group 4 — kuro--activity-bell-advice (BEL escalation)

(ert-deftest kuro-activity-test-bell-notifies-invisible ()
  "`kuro--activity-bell-advice' fires notification when buffer is invisible."
  (kuro-activity-test--with-stubs notif
    (kuro-activity-test--with-invisible-buffer
      (let ((kuro-activity-notify-on-bell t))
        (kuro--activity-bell-advice)
        (should notif)))))

(ert-deftest kuro-activity-test-bell-no-notify-visible ()
  "`kuro--activity-bell-advice' does NOT fire when buffer is visible."
  (kuro-activity-test--with-stubs notif
    (kuro-activity-test--with-visible-buffer
      (let ((kuro-activity-notify-on-bell t))
        (kuro--activity-bell-advice)
        (should-not notif)))))

(ert-deftest kuro-activity-test-bell-no-notify-when-disabled ()
  "`kuro--activity-bell-advice' does NOT fire when `kuro-activity-notify-on-bell' nil."
  (kuro-activity-test--with-stubs notif
    (kuro-activity-test--with-invisible-buffer
      (let ((kuro-activity-notify-on-bell nil))
        (kuro--activity-bell-advice)
        (should-not notif)))))

;;; Group 5 — kuro--activity-check-exit

(ert-deftest kuro-activity-test-exit-notifies-invisible ()
  "`kuro--activity-check-exit' fires notification when buffer is invisible."
  (kuro-activity-test--with-stubs notif
    (kuro-activity-test--with-invisible-buffer
      (let ((kuro-activity-notify-on-exit t))
        (with-temp-buffer
          (kuro--activity-check-exit)
          (should notif))))))

(ert-deftest kuro-activity-test-exit-no-notify-visible ()
  "`kuro--activity-check-exit' does NOT fire when buffer is visible."
  (kuro-activity-test--with-stubs notif
    (kuro-activity-test--with-visible-buffer
      (let ((kuro-activity-notify-on-exit t))
        (with-temp-buffer
          (kuro--activity-check-exit)
          (should-not notif))))))

(ert-deftest kuro-activity-test-exit-no-notify-disabled ()
  "`kuro--activity-check-exit' does NOT fire when `kuro-activity-notify-on-exit' nil."
  (kuro-activity-test--with-stubs notif
    (kuro-activity-test--with-invisible-buffer
      (let ((kuro-activity-notify-on-exit nil))
        (with-temp-buffer
          (kuro--activity-check-exit)
          (should-not notif))))))

;;; Group 6 — kuro-activity-mode (global minor mode)

(ert-deftest kuro-activity-test-mode-adds-hook-on-enable ()
  "`kuro-activity-mode' adds `kuro--activity-on-command-complete' to hook."
  (let ((kuro-on-command-complete-functions nil))
    (kuro-activity-mode 1)
    (should (memq #'kuro--activity-on-command-complete
                  kuro-on-command-complete-functions))
    (kuro-activity-mode -1)))

(ert-deftest kuro-activity-test-mode-removes-hook-on-disable ()
  "`kuro-activity-mode' removes the hook when disabled."
  (let ((kuro-on-command-complete-functions nil))
    (kuro-activity-mode 1)
    (kuro-activity-mode -1)
    (should-not (memq #'kuro--activity-on-command-complete
                      kuro-on-command-complete-functions))))

(ert-deftest kuro-activity-test-mode-installs-bell-advice ()
  "`kuro-activity-mode' adds `:after' advice on `kuro--ring-pending-bell'."
  (unless (fboundp 'kuro--ring-pending-bell)
    (defalias 'kuro--ring-pending-bell #'ignore))
  (kuro-activity-mode 1)
  (should (advice-member-p #'kuro--activity-bell-advice
                            'kuro--ring-pending-bell))
  (kuro-activity-mode -1))

(ert-deftest kuro-activity-test-mode-removes-bell-advice ()
  "`kuro-activity-mode' removes the bell advice when disabled."
  (unless (fboundp 'kuro--ring-pending-bell)
    (defalias 'kuro--ring-pending-bell #'ignore))
  (kuro-activity-mode 1)
  (kuro-activity-mode -1)
  (should-not (advice-member-p #'kuro--activity-bell-advice
                                'kuro--ring-pending-bell)))

;;; Group 7 — kuro-on-command-complete-functions hook (kuro-poll-modes.el)

(ert-deftest kuro-activity-test-hook-is-defvar ()
  "`kuro-on-command-complete-functions' is a defvar (abnormal hook variable)."
  (should (boundp 'kuro-on-command-complete-functions)))

(ert-deftest kuro-activity-test-hook-initially-nil ()
  "`kuro-on-command-complete-functions' default value is nil."
  (should (null (default-value 'kuro-on-command-complete-functions))))

;;; Group 8 — kuro--run-command-complete-hook

(ert-deftest kuro-activity-test-run-hook-fires-for-command-end ()
  "`kuro--run-command-complete-hook' calls hook fns for command-end marks."
  (let ((called nil))
    (let ((kuro-on-command-complete-functions
           (list (lambda (exit-code duration-ms &rest _)
                   (setq called (list exit-code duration-ms))))))
      (cl-letf (((symbol-function 'get-buffer-window)
                 (lambda (&rest _) nil)))
        (kuro--run-command-complete-hook
         '(("command-end" 5 10 0 nil 15000 nil)))
        (should (equal called '(0 15000)))))))

(ert-deftest kuro-activity-test-run-hook-ignores-non-command-end ()
  "`kuro--run-command-complete-hook' ignores marks with type != command-end."
  (let ((called nil))
    (let ((kuro-on-command-complete-functions
           (list (lambda (&rest _) (setq called t)))))
      (kuro--run-command-complete-hook
       '(("command-start" 5 0 nil nil nil nil)))
      (should-not called))))

(ert-deftest kuro-activity-test-run-hook-skips-when-no-fns ()
  "`kuro--run-command-complete-hook' is a no-op when hook list is nil."
  (let ((kuro-on-command-complete-functions nil))
    (kuro--run-command-complete-hook
     '(("command-end" 0 0 0 nil 15000 nil)))
    (should t)))

(ert-deftest kuro-activity-test-run-hook-passes-visibility ()
  "`kuro--run-command-complete-hook' passes nil BUFFER-VISIBLE-P when invisible."
  (let ((visibility :unset))
    (let ((kuro-on-command-complete-functions
           (list (lambda (_ec _dur _aid _err visible)
                   (setq visibility visible)))))
      (cl-letf (((symbol-function 'get-buffer-window)
                 (lambda (&rest _) nil)))
        (kuro--run-command-complete-hook
         '(("command-end" 0 0 0 nil 15000 nil)))
        (should (eq visibility nil))))))

(ert-deftest kuro-activity-test-run-hook-passes-visible-true ()
  "`kuro--run-command-complete-hook' passes t BUFFER-VISIBLE-P when visible."
  (let ((visibility :unset))
    (let ((kuro-on-command-complete-functions
           (list (lambda (_ec _dur _aid _err visible)
                   (setq visibility visible)))))
      (cl-letf (((symbol-function 'get-buffer-window)
                 (lambda (&rest _) (selected-window))))
        (kuro--run-command-complete-hook
         '(("command-end" 0 0 0 nil 15000 nil)))
        (should (eq visibility t))))))

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

;;; Group 11 — kuro-activity-list-mode keymap

(ert-deftest kuro-activity-test-list-map-binds-revert ()
  "`kuro-activity-list-mode-map' binds g to tabulated-list-revert."
  (should (eq (lookup-key kuro-activity-list-mode-map (kbd "g"))
              #'tabulated-list-revert)))

(ert-deftest kuro-activity-test-list-map-binds-delete ()
  "`kuro-activity-list-mode-map' binds d to kuro-activity-list-delete-entry."
  (should (eq (lookup-key kuro-activity-list-mode-map (kbd "d"))
              #'kuro-activity-list-delete-entry)))

(ert-deftest kuro-activity-test-list-map-binds-clear ()
  "`kuro-activity-list-mode-map' binds c to kuro-activity-clear."
  (should (eq (lookup-key kuro-activity-list-mode-map (kbd "c"))
              #'kuro-activity-clear)))

(ert-deftest kuro-activity-test-list-map-binds-quit ()
  "`kuro-activity-list-mode-map' binds q to quit-window."
  (should (eq (lookup-key kuro-activity-list-mode-map (kbd "q"))
              #'quit-window)))

(ert-deftest kuro-activity-test-list-delete-entry-removes-from-log ()
  "`kuro-activity-list-delete-entry' removes the entry from `kuro-activity--log'."
  (let* ((entry (list nil "s" "b"))
         (kuro-activity--log (list entry)))
    (cl-letf (((symbol-function 'tabulated-list-get-id)    (lambda () entry))
              ((symbol-function 'tabulated-list-delete-entry) #'ignore))
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

(kuro-activity-test--def-exit-code-status kuro-activity-exit-code-status-nil-is-empty  nil "")
(kuro-activity-test--def-exit-code-status kuro-activity-exit-code-status-zero-is-check 0   " ✓")
(kuro-activity-test--def-exit-code-status kuro-activity-exit-code-status-one-is-cross  1   " ✗ (exit 1)")
(kuro-activity-test--def-exit-code-status kuro-activity-exit-code-status-127-is-cross 127  " ✗ (exit 127)")

(ert-deftest kuro-activity-test--all-exit-code-statuses-correct ()
  "Invariant: every entry in the exit-code-status table maps to the expected string."
  (dolist (entry kuro-activity-test--exit-code-status-table)
    (pcase-let ((`(,_name ,code ,expected) entry))
      (should (equal (kuro--activity-exit-code-status code) expected)))))

(provide 'kuro-activity-test)
;;; kuro-activity-test.el ends here
