;;; kuro-mux-ext-test.el --- Tests for kuro-mux-ext.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)
(require 'kuro-mux-ext)
(require 'kuro-mux-ext-test-support)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))

(kuro-mux-ext-test--deftest-interactive-commands)

;;; Group 55 — kuro-mux-break-pane

(ert-deftest kuro-mux-ext-break-pane-creates-frame ()
  "`kuro-mux-break-pane' calls `make-frame' and `switch-to-buffer'."
  (kuro-mux-ext-test--with-buf
    (let (frame-made switch-called)
      (cl-letf (((symbol-function 'window-list)     (lambda (&rest _) '(w1)))
                ((symbol-function 'make-frame)       (lambda () (setq frame-made t) (selected-frame)))
                ((symbol-function 'switch-to-buffer) (lambda (_b) (setq switch-called t))))
        (kuro-mux-break-pane)
        (should frame-made)
        (should switch-called)))))

(ert-deftest kuro-mux-ext-break-pane-deletes-window-when-multiple ()
  "`kuro-mux-break-pane' calls `delete-window' when more than one window exists."
  (kuro-mux-ext-test--with-buf
    (let (deleted)
      (cl-letf (((symbol-function 'window-list)     (lambda (&rest _) '(w1 w2)))
                ((symbol-function 'make-frame)       (lambda () (selected-frame)))
                ((symbol-function 'switch-to-buffer) #'ignore)
                ((symbol-function 'delete-window)    (lambda () (setq deleted t))))
        (kuro-mux-break-pane)
        (should deleted)))))


;;; Group 56 — kuro-mux-join-pane

(ert-deftest kuro-mux-ext-join-pane-errors-on-dead-buffer ()
  "`kuro-mux-join-pane' signals user-error when the named buffer is not live."
  (should-error (kuro-mux-join-pane " *no-such-buf-xyz-ext*") :type 'user-error))

(ert-deftest kuro-mux-ext-join-pane-splits-and-selects ()
  "`kuro-mux-join-pane' splits right, sets window buffer, and selects."
  (let* ((buf (get-buffer-create " *kuro-join-target*"))
         set-win set-buf selected-win)
    (unwind-protect
        (cl-letf (((symbol-function 'split-window-right)
                   (lambda () 'new-win))
                  ((symbol-function 'set-window-buffer)
                   (lambda (w b) (setq set-win w set-buf b)))
                  ((symbol-function 'select-window)
                   (lambda (w) (setq selected-win w))))
          (kuro-mux-join-pane (buffer-name buf))
          (should (eq set-win 'new-win))
          (should (eq set-buf buf))
          (should (eq selected-win 'new-win)))
      (kill-buffer buf))))


;;; Group 57 — kuro-mux-rename + kuro-mux--name-lighter

(ert-deftest kuro-mux-ext-rename-sets-name ()
  "`kuro-mux-rename' sets `kuro-mux--name' to the provided name."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--name nil)
          (kuro-mux-tab-bar-mode nil))
      (cl-letf (((symbol-function 'force-mode-line-update) #'ignore))
        (kuro-mux-rename "my-session")
        (should (equal kuro-mux--name "my-session"))))))

(ert-deftest kuro-mux-ext-rename-empty-sets-nil ()
  "`kuro-mux-rename' sets `kuro-mux--name' to nil for empty string."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--name "old")
          (kuro-mux-tab-bar-mode nil))
      (cl-letf (((symbol-function 'force-mode-line-update) #'ignore))
        (kuro-mux-rename "")
        (should (null kuro-mux--name))))))

(ert-deftest kuro-mux-ext-name-lighter-with-name ()
  "`kuro-mux--name-lighter' returns ` {NAME}' when name is set."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--name "proj"))
      (should (equal (kuro-mux--name-lighter) " {proj}")))))

(ert-deftest kuro-mux-ext-name-lighter-without-name ()
  "`kuro-mux--name-lighter' returns empty string when name is nil."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--name nil))
      (should (equal (kuro-mux--name-lighter) "")))))


;;; Group 58 — kuro-mux-send-to-session

(ert-deftest kuro-mux-ext-send-to-session-sends-to-target ()
  "`kuro-mux-send-to-session' calls `kuro--send-paste-or-raw' in the target buffer."
  (let* ((target (generate-new-buffer " *kuro-send-target*"))
         sent-text sent-buf)
    (unwind-protect
        (progn
          (with-current-buffer target (kuro-mode))
          (cl-letf (((symbol-function 'kuro-mux--live-sessions)  (lambda () (list target)))
                    ((symbol-function 'kuro-mux--session-display-name) #'buffer-name)
                    ((symbol-function 'kuro--send-paste-or-raw)
                     (lambda (text) (setq sent-text text sent-buf (current-buffer)))))
            (kuro-mux-send-to-session (buffer-name target) "hello")
            (should (equal sent-text "hello"))
            (should (eq sent-buf target))))
      (kill-buffer target))))

(ert-deftest kuro-mux-ext-send-to-session-errors-when-not-found ()
  "`kuro-mux-send-to-session' signals user-error when no session matches NAME."
  (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () nil))
            ((symbol-function 'kuro-mux--session-display-name) #'buffer-name))
    (should-error (kuro-mux-send-to-session "no-such-session" "text") :type 'user-error)))


;;; Group 59 — hook management + kuro-mux--lifecycle-hooks

(ert-deftest kuro-mux-ext-lifecycle-hooks-covers-all-four ()
  "`kuro-mux--lifecycle-hooks' has entries for all four lifecycle events."
  (should (assq 'kuro-mode-hook kuro-mux--lifecycle-hooks))
  (should (assq 'kill-buffer-hook kuro-mux--lifecycle-hooks))
  (should (assq 'window-selection-change-functions kuro-mux--lifecycle-hooks))
  (should (assq 'kill-emacs-hook kuro-mux--lifecycle-hooks)))

(ert-deftest kuro-mux-ext-install-hooks-adds-all ()
  "`kuro-mux--install-hooks' calls `add-hook' for every lifecycle hook entry."
  (let (added)
    (cl-letf (((symbol-function 'add-hook)
               (lambda (hook fn) (push (cons hook fn) added))))
      (kuro-mux--install-hooks))
    (should (= (length added) (length kuro-mux--lifecycle-hooks)))))

(ert-deftest kuro-mux-ext-uninstall-hooks-removes-all ()
  "`kuro-mux--uninstall-hooks' calls `remove-hook' for every lifecycle hook entry."
  (let (removed)
    (cl-letf (((symbol-function 'remove-hook)
               (lambda (hook fn) (push (cons hook fn) removed))))
      (kuro-mux--uninstall-hooks))
    (should (= (length removed) (length kuro-mux--lifecycle-hooks)))))

(ert-deftest kuro-mux-ext-on-session-created-registers ()
  "`kuro-mux--on-session-created' calls `kuro-mux--register'."
  (let ((kuro-mux-tab-bar-mode nil) registered)
    (cl-letf (((symbol-function 'kuro-mux--register) (lambda () (setq registered t))))
      (kuro-mux--on-session-created)
      (should registered))))

(ert-deftest kuro-mux-ext-on-session-killed-unregisters ()
  "`kuro-mux--on-session-killed' calls `kuro-mux--unregister'."
  (let (unregistered)
    (cl-letf (((symbol-function 'kuro-mux--unregister) (lambda () (setq unregistered t))))
      (kuro-mux--on-session-killed)
      (should unregistered))))


;;; Group 60 — kuro-mux--auto-save-on-exit

(kuro-mux-ext-test--deftest-auto-save-on-exit)


;;; Group 61 — kuro-mux--activity-watcher

(ert-deftest kuro-mux-ext-activity-watcher-noop-when-monitoring-off ()
  "`kuro-mux--activity-watcher' is a no-op when `kuro-mux--monitor-activity' is nil."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--monitor-activity nil)
          notified)
      (cl-letf (((symbol-function 'kuro--activity-notify) (lambda (&rest _) (setq notified t))))
        (kuro-mux--activity-watcher 1 2 0)
        (should-not notified)))))

(ert-deftest kuro-mux-ext-activity-watcher-noop-when-buffer-visible ()
  "`kuro-mux--activity-watcher' skips notification when buffer is visible."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--monitor-activity t)
          (kuro-mux--monitor-activity-last-notified 0.0)
          (kuro-mux-monitor-activity-debounce 0)
          notified)
      (cl-letf (((symbol-function 'get-buffer-window) (lambda (_b _f) 'some-window))
                ((symbol-function 'kuro--activity-notify) (lambda (&rest _) (setq notified t))))
        (kuro-mux--activity-watcher 1 2 0)
        (should-not notified)))))

(ert-deftest kuro-mux-ext-activity-watcher-fires-when-hidden ()
  "`kuro-mux--activity-watcher' fires when monitoring on, buffer hidden, debounce elapsed."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--monitor-activity t)
          (kuro-mux--monitor-activity-last-notified 0.0)
          (kuro-mux-monitor-activity-debounce 0)
          notified)
      (cl-letf (((symbol-function 'get-buffer-window) (lambda (_b _f) nil))
                ((symbol-function 'float-time) (lambda () 9999999.0))
                ((symbol-function 'kuro--activity-notify) (lambda (&rest _) (setq notified t))))
        (kuro-mux--activity-watcher 1 2 0)
        (should notified)))))


;;; Group 62 — kuro-mux-monitor-activity-toggle

(ert-deftest kuro-mux-ext-monitor-activity-toggle-on ()
  "`kuro-mux-monitor-activity-toggle' enables monitoring when currently off."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--monitor-activity nil) hook-added)
      (cl-letf (((symbol-function 'add-hook)
                 (lambda (hook fn &rest _) (setq hook-added (cons hook fn)))))
        (kuro-mux-monitor-activity-toggle)
        (should kuro-mux--monitor-activity)
        (should (eq (car hook-added) 'after-change-functions))))))

(ert-deftest kuro-mux-ext-monitor-activity-toggle-off ()
  "`kuro-mux-monitor-activity-toggle' disables monitoring when currently on."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--monitor-activity t) hook-removed)
      (cl-letf (((symbol-function 'remove-hook)
                 (lambda (hook fn &rest _) (setq hook-removed (cons hook fn)))))
        (kuro-mux-monitor-activity-toggle)
        (should-not kuro-mux--monitor-activity)
        (should (eq (car hook-removed) 'after-change-functions))))))


;;; Group 63 — kuro-mux-monitor-silence

(ert-deftest kuro-mux-ext-monitor-silence-enables ()
  "`kuro-mux-monitor-silence' sets seconds and adds hook when SECONDS > 0."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--monitor-silence-seconds nil)
          (kuro-mux--monitor-silence-timer nil)
          hook-added)
      (cl-letf (((symbol-function 'add-hook)
                 (lambda (hook fn &rest _) (setq hook-added (cons hook fn)))))
        (kuro-mux-monitor-silence 30)
        (should (= kuro-mux--monitor-silence-seconds 30))
        (should (eq (car hook-added) 'after-change-functions))))))

(ert-deftest kuro-mux-ext-monitor-silence-disables-when-zero ()
  "`kuro-mux-monitor-silence' clears seconds and removes hook when SECONDS = 0."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--monitor-silence-seconds 30)
          (kuro-mux--monitor-silence-timer nil)
          hook-removed)
      (cl-letf (((symbol-function 'remove-hook)
                 (lambda (hook fn &rest _) (setq hook-removed (cons hook fn)))))
        (kuro-mux-monitor-silence 0)
        (should (null kuro-mux--monitor-silence-seconds))
        (should (eq (car hook-removed) 'after-change-functions))))))


;;; Group 64 — kuro-mux--pipe-pane-watcher + kuro-mux-pipe-pane

(ert-deftest kuro-mux-ext-pipe-pane-watcher-noop-when-no-file ()
  "`kuro-mux--pipe-pane-watcher' is a no-op when `kuro-mux--pipe-pane-file' is nil."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--pipe-pane-file nil) written)
      (cl-letf (((symbol-function 'write-region) (lambda (&rest _) (setq written t))))
        (kuro-mux--pipe-pane-watcher 1 2 0)
        (should-not written)))))

(ert-deftest kuro-mux-ext-pipe-pane-watcher-appends-text ()
  "`kuro-mux--pipe-pane-watcher' appends buffer text to the pipe file."
  (let ((buf (generate-new-buffer " *kuro-pipe-test*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "hello world")
          (let ((kuro-mux--pipe-pane-file "/tmp/kuro-test-pipe.log")
                written-text)
            (cl-letf (((symbol-function 'write-region)
                       (lambda (text nil file append _)
                         (setq written-text text))))
              (kuro-mux--pipe-pane-watcher 1 6 0)
              (should (equal written-text "hello")))))
      (kill-buffer buf))))

(ert-deftest kuro-mux-ext-pipe-pane-start-adds-hook ()
  "`kuro-mux-pipe-pane' with a non-nil FILE sets the var and adds the hook."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--pipe-pane-file nil) hook-added)
      (cl-letf (((symbol-function 'expand-file-name) (lambda (f) f))
                ((symbol-function 'add-hook)
                 (lambda (hook fn &rest _) (setq hook-added (cons hook fn)))))
        (kuro-mux-pipe-pane "/tmp/kuro-test.log")
        (should (equal kuro-mux--pipe-pane-file "/tmp/kuro-test.log"))
        (should (eq (car hook-added) 'after-change-functions))))))

(ert-deftest kuro-mux-ext-pipe-pane-stop-clears-var ()
  "`kuro-mux-pipe-pane' with nil FILE clears var and removes hook."
  (kuro-mux-ext-test--with-buf
    (let ((kuro-mux--pipe-pane-file "/tmp/old.log") hook-removed)
      (cl-letf (((symbol-function 'remove-hook)
                 (lambda (hook fn &rest _) (setq hook-removed (cons hook fn)))))
        (kuro-mux-pipe-pane nil)
        (should (null kuro-mux--pipe-pane-file))
        (should (eq (car hook-removed) 'after-change-functions))))))


;;; Group 65 — kuro-mux--on-session-created tab-bar branch

(ert-deftest kuro-mux-ext-on-session-created-calls-tab-bar-update-when-mode-active ()
  "`kuro-mux--on-session-created' calls `kuro-mux--tab-bar-update' when `kuro-mux-tab-bar-mode' is non-nil."
  (let ((kuro-mux-tab-bar-mode t)
        tab-bar-update-called)
    (cl-letf (((symbol-function 'kuro-mux--register) #'ignore)
              ((symbol-function 'kuro-mux--tab-bar-update)
               (lambda () (setq tab-bar-update-called t))))
      (kuro-mux--on-session-created)
      (should tab-bar-update-called))))

(ert-deftest kuro-mux-ext-on-session-created-skips-tab-bar-update-when-mode-nil ()
  "`kuro-mux--on-session-created' does not call `kuro-mux--tab-bar-update' when `kuro-mux-tab-bar-mode' is nil."
  (let ((kuro-mux-tab-bar-mode nil)
        tab-bar-update-called)
    (cl-letf (((symbol-function 'kuro-mux--register) #'ignore)
              ((symbol-function 'kuro-mux--tab-bar-update)
               (lambda () (setq tab-bar-update-called t))))
      (kuro-mux--on-session-created)
      (should-not tab-bar-update-called))))

;;; Group 66 — kuro-mux--tab-bar-update active path

(kuro-mux-ext-test--deftest-tab-bar-updates)

(provide 'kuro-mux-ext-test)
;;; kuro-mux-ext-test.el ends here
