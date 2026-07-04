;;; kuro-mux-test-12.el --- ERT tests for kuro-mux-ext.el — Groups 42-43  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))

(defmacro kuro-mux-test-12--with-silence-state (seconds timer &rest body)
  "Run BODY with silence-watcher state bound in a temp buffer."
  (declare (indent 2))
  `(with-temp-buffer
     (setq kuro-mux--monitor-silence-seconds ,seconds
           kuro-mux--monitor-silence-timer ,timer)
     ,@body))

(defmacro kuro-mux-test-12--without-fboundp (missing-symbol &rest body)
  "Run BODY with MISSING-SYMBOL hidden from `fboundp'."
  (declare (indent 1))
  `(let ((real-fboundp (symbol-function 'fboundp)))
     (cl-letf (((symbol-function 'fboundp)
                (lambda (sym)
                  (if (eq sym ,missing-symbol)
                      nil
                    (funcall real-fboundp sym)))))
       ,@body)))


;;; Group 42 — kuro-mux--silence-watcher

(ert-deftest kuro-mux-test-silence-watcher-noop-when-seconds-nil ()
  "`kuro-mux--silence-watcher' does nothing when `kuro-mux--monitor-silence-seconds' is nil."
  (kuro-mux-test-12--with-silence-state nil nil
    (let ((timer-called nil))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (&rest _) (setq timer-called t))))
        (kuro-mux--silence-watcher 1 2 0)
        (should (null timer-called))))))

(ert-deftest kuro-mux-test-silence-watcher-schedules-timer ()
  "`kuro-mux--silence-watcher' schedules a timer when `kuro-mux--monitor-silence-seconds' is set."
  (kuro-mux-test-12--with-silence-state 5 nil
    (let ((timer-scheduled nil))
      (cl-letf (((symbol-function 'run-with-timer)
                 (lambda (&rest _) (setq timer-scheduled t) 'fake-timer)))
        (kuro-mux--silence-watcher 1 2 0)
        (should timer-scheduled)))))

(ert-deftest kuro-mux-test-silence-watcher-stores-timer ()
  "`kuro-mux--silence-watcher' stores the new timer in `kuro-mux--monitor-silence-timer'."
  (kuro-mux-test-12--with-silence-state 3 nil
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (&rest _) 'stored-timer)))
      (kuro-mux--silence-watcher 1 2 0)
      (should (eq kuro-mux--monitor-silence-timer 'stored-timer)))))

(ert-deftest kuro-mux-test-silence-watcher-cancels-existing-timer ()
  "`kuro-mux--silence-watcher' cancels an existing timer before scheduling a new one."
  (let ((fake (run-with-timer 999 nil #'ignore)))
    (unwind-protect
        (progn
          (kuro-mux-test-12--with-silence-state 5 fake
            (cl-letf (((symbol-function 'run-with-timer)
                       (lambda (&rest _) 'new-timer)))
              (kuro-mux--silence-watcher 1 2 0)))
          (should-not (memq fake timer-list)))
      (when (timerp fake) (cancel-timer fake)))))

(ert-deftest kuro-mux-test-silence-watcher-uses-silence-seconds-as-delay ()
  "`kuro-mux--silence-watcher' passes `kuro-mux--monitor-silence-seconds' as the timer delay."
  (kuro-mux-test-12--with-silence-state 7 nil
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
  (let ((tab-bar-activated nil))
    (kuro-mux-test-12--without-fboundp 'tab-bar-tabs
      (cl-letf (((symbol-function 'tab-bar-mode)
                 (lambda (&rest _) (setq tab-bar-activated t))))
        (kuro-mux--tab-bar-update)
        (should (null tab-bar-activated))))))

(ert-deftest kuro-mux-test-tab-bar-update-still-works-without-select-tab ()
  "`kuro-mux--tab-bar-update' still creates tabs when `tab-bar-select-tab-by-name' is absent."
  (let ((tab-created nil))
    (kuro-mux-test-12--without-fboundp 'tab-bar-select-tab-by-name
      (cl-letf (((symbol-function 'tab-bar-mode) #'ignore)
                ((symbol-function 'kuro-mux--live-sessions)
                 (lambda () (list (current-buffer))))
                ((symbol-function 'kuro-mux--session-display-name)
                 (lambda (_buf) "test-session"))
                ((symbol-function 'tab-bar-tabs) (lambda () nil))
                ((symbol-function 'tab-bar-new-tab)
                 (lambda () (setq tab-created t)))
                ((symbol-function 'tab-bar-rename-tab) #'ignore))
        (kuro-mux--tab-bar-update)
        (should tab-created)))))


(provide 'kuro-mux-test-12)
;;; kuro-mux-test-12.el ends here
