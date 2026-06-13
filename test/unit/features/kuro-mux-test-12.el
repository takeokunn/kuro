;;; kuro-mux-test-12.el --- ERT tests for kuro-mux-ext.el — Groups 42-43  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))


;;; Group 42 — kuro-mux--silence-watcher

(ert-deftest kuro-mux-test-silence-watcher-noop-when-seconds-nil ()
  "`kuro-mux--silence-watcher' does nothing when `kuro-mux--monitor-silence-seconds' is nil."
  (with-temp-buffer
    (setq kuro-mux--monitor-silence-seconds nil)
    (let ((timer-called nil))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (&rest _) (setq timer-called t))))
        (kuro-mux--silence-watcher 1 2 0)
        (should (null timer-called))))))

(ert-deftest kuro-mux-test-silence-watcher-schedules-timer ()
  "`kuro-mux--silence-watcher' schedules a timer when `kuro-mux--monitor-silence-seconds' is set."
  (with-temp-buffer
    (setq kuro-mux--monitor-silence-seconds 5
          kuro-mux--monitor-silence-timer nil)
    (let ((timer-scheduled nil))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (&rest _) (setq timer-scheduled t) 'fake-timer)))
        (kuro-mux--silence-watcher 1 2 0)
        (should timer-scheduled)))))

(ert-deftest kuro-mux-test-silence-watcher-stores-timer ()
  "`kuro-mux--silence-watcher' stores the new timer in `kuro-mux--monitor-silence-timer'."
  (with-temp-buffer
    (setq kuro-mux--monitor-silence-seconds 3
          kuro-mux--monitor-silence-timer nil)
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (&rest _) 'stored-timer)))
      (kuro-mux--silence-watcher 1 2 0)
      (should (eq kuro-mux--monitor-silence-timer 'stored-timer)))))

(ert-deftest kuro-mux-test-silence-watcher-cancels-existing-timer ()
  "`kuro-mux--silence-watcher' cancels an existing timer before scheduling a new one."
  (with-temp-buffer
    (setq kuro-mux--monitor-silence-seconds 5)
    (let ((cancelled nil)
          (fake (run-with-timer 999 nil #'ignore)))
      (unwind-protect
          (progn
            (setq kuro-mux--monitor-silence-timer fake)
            (cl-letf (((symbol-function 'run-with-timer)
                       (lambda (&rest _) 'new-timer)))
              (kuro-mux--silence-watcher 1 2 0))
            (should-not (memq fake timer-list)))
        (when (timerp fake) (cancel-timer fake))))))

(ert-deftest kuro-mux-test-silence-watcher-uses-silence-seconds-as-delay ()
  "`kuro-mux--silence-watcher' passes `kuro-mux--monitor-silence-seconds' as the timer delay."
  (with-temp-buffer
    (setq kuro-mux--monitor-silence-seconds 7
          kuro-mux--monitor-silence-timer nil)
    (let ((timer-delay :not-set))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (delay &rest _) (setq timer-delay delay) 'timer)))
        (kuro-mux--silence-watcher 1 2 0)
        (should (= timer-delay 7))))))


;;; Group 43 — kuro-mux--tab-bar-update

(ert-deftest kuro-mux-test-tab-bar-update-is-callable ()
  "`kuro-mux--tab-bar-update' is a callable function."
  (should (functionp #'kuro-mux--tab-bar-update)))

(ert-deftest kuro-mux-test-tab-bar-update-noop-without-tab-bar ()
  "`kuro-mux--tab-bar-update' does not call `tab-bar-mode' when `tab-bar-tabs' is absent."
  (let ((tab-bar-activated nil)
        (real-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'fboundp)
               (lambda (sym)
                 (if (eq sym 'tab-bar-tabs) nil
                   (funcall real-fboundp sym)))))
      (cl-letf (((symbol-function 'tab-bar-mode)
                 (lambda (&rest _) (setq tab-bar-activated t))))
        (kuro-mux--tab-bar-update)
        (should (null tab-bar-activated))))))

(ert-deftest kuro-mux-test-tab-bar-update-noop-without-select-tab ()
  "`kuro-mux--tab-bar-update' does not call `tab-bar-mode' when `tab-bar-select-tab-by-name' is absent."
  (let ((tab-bar-activated nil)
        (real-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'fboundp)
               (lambda (sym)
                 (if (eq sym 'tab-bar-select-tab-by-name) nil
                   (funcall real-fboundp sym)))))
      (cl-letf (((symbol-function 'tab-bar-mode)
                 (lambda (&rest _) (setq tab-bar-activated t))))
        (kuro-mux--tab-bar-update)
        (should (null tab-bar-activated))))))


(provide 'kuro-mux-test-12)
;;; kuro-mux-test-12.el ends here
