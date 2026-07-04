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



;;; Group 9 — kuro-activity-list--refresh

(ert-deftest kuro-activity-test--refresh-sets-tabulated-list-entries ()
  "`kuro-activity-list--refresh' assigns `tabulated-list-entries' from the log."
  (with-temp-buffer
    (let ((kuro-activity--log nil)
          (tabulated-list-entries :unset))
      (cl-letf (((symbol-function 'tabulated-list-print) #'ignore))
        (kuro-activity-list--refresh)
        (should (equal tabulated-list-entries (kuro-activity-list--entries)))))))

(ert-deftest kuro-activity-test--refresh-calls-tabulated-list-print-with-t ()
  "`kuro-activity-list--refresh' calls `tabulated-list-print' with argument t."
  (with-temp-buffer
    (let ((kuro-activity--log nil)
          (tabulated-list-entries nil)
          (print-args :unset))
      (cl-letf (((symbol-function 'tabulated-list-print)
                 (lambda (&rest args) (setq print-args args))))
        (kuro-activity-list--refresh)
        (should (equal print-args '(t)))))))

(ert-deftest kuro-activity-test--refresh-reflects-log-count ()
  "`kuro-activity-list--refresh' sets entries matching the log length."
  (with-temp-buffer
    (let ((kuro-activity--log (list (list (current-time) "sess-1" "ev-1")
                                    (list (current-time) "sess-2" "ev-2")))
          (tabulated-list-entries nil))
      (cl-letf (((symbol-function 'tabulated-list-print) #'ignore))
        (kuro-activity-list--refresh)
        (should (= 2 (length tabulated-list-entries)))))))

(provide 'kuro-activity-test)
;;; kuro-activity-test.el ends here
