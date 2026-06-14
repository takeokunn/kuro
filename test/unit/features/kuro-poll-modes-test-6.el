;;; kuro-poll-modes-test-6.el --- Tests for dispatcher/plumbing poll functions  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-poll-modes.el — dispatcher/plumbing coverage.
;; Covers:
;;   kuro--handle-clipboard-actions  — dispatches write/query actions
;;   kuro--handle-notifications      — drains notification queue
;;   kuro--send-osc52-clipboard-response — formats OSC 52 response
;;   kuro--poll-tier1-modes          — runs all tier-1 fns in order
;;   kuro--poll-terminal-modes       — gates tier-1 and tier-2 polling

;;; Code:

(require 'kuro-poll-modes-test-support)

;;; Group S: kuro--handle-clipboard-actions

(ert-deftest kuro-poll-modes-handle-clipboard-actions-dispatches-write ()
  "kuro--handle-clipboard-actions dispatches (write . TEXT) to kuro--clipboard-write."
  (kuro-poll-test--with-buffer
    (let ((written nil))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "hello"))))
                ((symbol-function 'kuro--clipboard-write)
                 (lambda (text) (setq written text)))
                ((symbol-function 'kuro--clipboard-query) #'ignore))
        (kuro--handle-clipboard-actions)
        (should (equal written "hello"))))))

(ert-deftest kuro-poll-modes-handle-clipboard-actions-dispatches-query ()
  "kuro--handle-clipboard-actions dispatches (query) to kuro--clipboard-query."
  (kuro-poll-test--with-buffer
    (let ((queried nil))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((query . nil))))
                ((symbol-function 'kuro--clipboard-write) #'ignore)
                ((symbol-function 'kuro--clipboard-query)
                 (lambda () (setq queried t))))
        (kuro--handle-clipboard-actions)
        (should queried)))))

(ert-deftest kuro-poll-modes-handle-clipboard-actions-empty-queue-is-noop ()
  "kuro--handle-clipboard-actions does nothing when action queue is empty."
  (kuro-poll-test--with-buffer
    (let ((write-called nil)
          (query-called nil))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions) (lambda () nil))
                ((symbol-function 'kuro--clipboard-write) (lambda (_) (setq write-called t)))
                ((symbol-function 'kuro--clipboard-query) (lambda () (setq query-called t))))
        (kuro--handle-clipboard-actions)
        (should-not write-called)
        (should-not query-called)))))

(ert-deftest kuro-poll-modes-handle-clipboard-actions-multiple-actions ()
  "kuro--handle-clipboard-actions processes all actions in the queue."
  (kuro-poll-test--with-buffer
    (let ((written-texts nil)
          (query-count 0))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "a") (query . nil) (write . "b"))))
                ((symbol-function 'kuro--clipboard-write)
                 (lambda (text) (push text written-texts)))
                ((symbol-function 'kuro--clipboard-query)
                 (lambda () (cl-incf query-count))))
        (kuro--handle-clipboard-actions)
        (should (equal (reverse written-texts) '("a" "b")))
        (should (= query-count 1))))))

;;; Group T: kuro--handle-notifications

(ert-deftest kuro-poll-modes-handle-notifications-calls-fn-when-enabled ()
  "kuro--handle-notifications calls kuro-notification-function for each notification."
  (kuro-poll-test--with-buffer
    ;; let* so the lambda for kuro-notification-function is evaluated AFTER calls is bound.
    ;; Plain let evaluates all init-forms in the surrounding scope (before any binding takes
    ;; effect), so the lambda would not capture calls from the same let.
    (let* ((calls nil)
           (kuro-notifications-enabled t)
           (kuro-notification-function (lambda (title body) (push (list title body) calls))))
      (cl-letf (((symbol-function 'kuro--poll-notifications)
                 (lambda () '(("Shell" . "Command finished") ("System" . "Alert")))))
        (kuro--handle-notifications)
        (should (equal (length calls) 2))
        (should (equal (car (last calls)) '("Shell" "Command finished")))))))

(ert-deftest kuro-poll-modes-handle-notifications-skips-fn-when-disabled ()
  "kuro--handle-notifications does NOT call the notification function when disabled."
  (kuro-poll-test--with-buffer
    (let ((fn-called nil)
          (kuro-notifications-enabled nil)
          (kuro-notification-function (lambda (_t _b) (setq fn-called t))))
      (cl-letf (((symbol-function 'kuro--poll-notifications)
                 (lambda () '(("T" . "B")))))
        (kuro--handle-notifications)
        (should-not fn-called)))))

(ert-deftest kuro-poll-modes-handle-notifications-always-drains-queue ()
  "kuro--handle-notifications drains the queue regardless of enabled state."
  (kuro-poll-test--with-buffer
    (let ((drain-count 0)
          (kuro-notifications-enabled nil)
          (kuro-notification-function #'ignore))
      (cl-letf (((symbol-function 'kuro--poll-notifications)
                 (lambda () (cl-incf drain-count) '(("T" . "B")))))
        (kuro--handle-notifications)
        (should (= drain-count 1))))))

;;; Group U: kuro--send-osc52-clipboard-response

(ert-deftest kuro-poll-modes-send-osc52-sends-escape-sequence ()
  "kuro--send-osc52-clipboard-response sends an OSC 52 escape sequence."
  (kuro-poll-test--with-buffer
    (let ((sent nil))
      (cl-letf (((symbol-function 'current-kill) (lambda (_n _nomove) "abc"))
                ((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro--send-osc52-clipboard-response)
        (should (stringp sent))
        (should (string-prefix-p "\e]52;c;" sent))
        (should (string-suffix-p "\a" sent))))))

(ert-deftest kuro-poll-modes-send-osc52-base64-encodes-text ()
  "kuro--send-osc52-clipboard-response base64-encodes the kill ring text."
  (kuro-poll-test--with-buffer
    (let ((sent nil))
      (cl-letf (((symbol-function 'current-kill) (lambda (_n _nomove) "hello"))
                ((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro--send-osc52-clipboard-response)
        ;; base64 of "hello" = "aGVsbG8="
        (should (string-match-p "aGVsbG8=" sent))))))

(ert-deftest kuro-poll-modes-send-osc52-empty-on-kill-ring-error ()
  "kuro--send-osc52-clipboard-response sends empty string when kill-ring errors."
  (kuro-poll-test--with-buffer
    (let ((sent nil))
      (cl-letf (((symbol-function 'current-kill)
                 (lambda (_n _nomove) (error "kill-ring empty")))
                ((symbol-function 'kuro--send-key) (lambda (s) (setq sent s))))
        (kuro--send-osc52-clipboard-response)
        ;; base64 of "" = ""
        (should (string-match-p "\e]52;c;\a" sent))))))

;;; Group V2: kuro--poll-tier1-modes and kuro--poll-terminal-modes

(ert-deftest kuro-poll-modes-poll-tier1-modes-calls-all-fns ()
  "kuro--poll-tier1-modes calls every function in kuro--tier1-poll-fns in order."
  (kuro-poll-test--with-buffer
    (let ((called-order nil))
      ;; Stub every tier-1 function to record call order
      (let ((stubs (mapcar (lambda (fn)
                             (cons fn (lambda () (push fn called-order))))
                           kuro--tier1-poll-fns)))
        (dolist (s stubs)
          (cl-letf* (((symbol-function (car s)) (cdr s)))
            nil))
        ;; Use a single cl-letf* for all stubs
        (eval `(cl-letf* ,(mapcar (lambda (s)
                                    `((symbol-function ',(car s)) ,(cdr s)))
                                  stubs)
                 (kuro--poll-tier1-modes)))
        (should (= (length called-order) (length kuro--tier1-poll-fns)))
        (should (equal (reverse called-order) kuro--tier1-poll-fns))))))

(ert-deftest kuro-poll-modes-poll-terminal-modes-calls-tier1-when-cadence-fires ()
  "kuro--poll-terminal-modes calls kuro--poll-tier1-modes on cadence boundary."
  (kuro-poll-test--with-buffer
    (let ((tier1-called nil)
          (kuro--mode-poll-frame-count 0)
          (kuro--mode-poll-cadence 1))
      (cl-letf (((symbol-function 'kuro--poll-tier1-modes)
                 (lambda () (setq tier1-called t)))
                ((symbol-function 'kuro--poll-osc-events) #'ignore))
        (kuro--poll-terminal-modes)
        (should tier1-called)))))

(ert-deftest kuro-poll-modes-poll-terminal-modes-skips-tier1-between-cadences ()
  "kuro--poll-terminal-modes skips tier-1 when frame count is between cadence boundaries."
  (kuro-poll-test--with-buffer
    (let ((tier1-called nil)
          (kuro--mode-poll-frame-count 1)
          (kuro--mode-poll-cadence 10))
      (cl-letf (((symbol-function 'kuro--poll-tier1-modes)
                 (lambda () (setq tier1-called t)))
                ((symbol-function 'kuro--poll-osc-events) #'ignore))
        (kuro--poll-terminal-modes)
        (should-not tier1-called)))))

(ert-deftest kuro-poll-modes-poll-terminal-modes-calls-osc-at-rare-cadence ()
  "kuro--poll-terminal-modes calls kuro--poll-osc-events on the rare cadence boundary."
  (kuro-poll-test--with-buffer
    (let ((osc-called nil)
          (kuro--mode-poll-frame-count 0)
          (kuro--osc-rare-poll-cadence 1))
      (cl-letf (((symbol-function 'kuro--poll-tier1-modes) #'ignore)
                ((symbol-function 'kuro--poll-osc-events)
                 (lambda () (setq osc-called t))))
        (kuro--poll-terminal-modes)
        (should osc-called)))))


;;; Group G2: kuro--default-notify D-Bus path

(ert-deftest kuro-poll-modes-default-notify-dbus-success-skips-message ()
  "`kuro--default-notify' calls `notifications-notify' and skips `message' when D-Bus succeeds."
  (let (notify-called message-called)
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'notifications-notify)
               (lambda (&rest _) (setq notify-called t) t))
              ((symbol-function 'message)
               (lambda (&rest _) (setq message-called t))))
      (kuro--default-notify "Title" "Body")
      (should notify-called)
      (should-not message-called))))

(ert-deftest kuro-poll-modes-default-notify-dbus-error-falls-back-to-message ()
  "`kuro--default-notify' falls back to `message' when `notifications-notify' errors."
  (let ((shown nil))
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'notifications-notify)
               (lambda (&rest _) (error "dbus error")))
              ((symbol-function 'message)
               (lambda (fmt &rest args) (setq shown (apply #'format fmt args)))))
      (kuro--default-notify "Title" "Body")
      (should (equal shown "Title: Body")))))

(ert-deftest kuro-poll-modes-default-notify-dbus-nil-title-uses-default ()
  "`kuro--default-notify' passes \"kuro\" as title to `notifications-notify' when title is nil."
  (let ((received-title nil))
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'notifications-notify)
               (lambda (&rest args)
                 (setq received-title (plist-get args :title))
                 t))
              ((symbol-function 'message) #'ignore))
      (kuro--default-notify nil "Body")
      (should (equal received-title "kuro")))))

(provide 'kuro-poll-modes-test-6)
;;; kuro-poll-modes-test-6.el ends here
