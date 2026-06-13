;;; kuro-mux-test-11.el --- ERT tests for kuro-mux.el — Groups 39-41  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))


;;; Group 39 — kuro-mux-pipe-pane (start / stop / guard)

(ert-deftest kuro-mux-test-pipe-pane-rejects-non-kuro ()
  "`kuro-mux-pipe-pane' signals user-error outside kuro-mode."
  (with-temp-buffer
    (should-error (kuro-mux-pipe-pane "/tmp/kuro-test.log") :type 'user-error)))

(ert-deftest kuro-mux-test-pipe-pane-starts-sets-file ()
  "`kuro-mux-pipe-pane' sets `kuro-mux--pipe-pane-file' to the expanded file name."
  (with-temp-buffer
    (kuro-mode)
    (unwind-protect
        (progn
          (kuro-mux-pipe-pane "/tmp/kuro-pipe-test.log")
          (should (equal kuro-mux--pipe-pane-file
                         (expand-file-name "/tmp/kuro-pipe-test.log"))))
      (setq kuro-mux--pipe-pane-file nil)
      (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t))))

(ert-deftest kuro-mux-test-pipe-pane-starts-adds-watcher ()
  "`kuro-mux-pipe-pane' adds `kuro-mux--pipe-pane-watcher' to `after-change-functions'."
  (with-temp-buffer
    (kuro-mode)
    (unwind-protect
        (progn
          (kuro-mux-pipe-pane "/tmp/kuro-watcher-test.log")
          (should (memq #'kuro-mux--pipe-pane-watcher after-change-functions)))
      (setq kuro-mux--pipe-pane-file nil)
      (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t))))

(ert-deftest kuro-mux-test-pipe-pane-stop-clears-file ()
  "`kuro-mux-pipe-pane' with nil stops piping (clears file)."
  (with-temp-buffer
    (kuro-mode)
    (setq kuro-mux--pipe-pane-file "/tmp/kuro-stop-test.log")
    (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
    (kuro-mux-pipe-pane nil)
    (should (null kuro-mux--pipe-pane-file))))

(ert-deftest kuro-mux-test-pipe-pane-stop-removes-watcher ()
  "`kuro-mux-pipe-pane' with nil removes the watcher hook."
  (with-temp-buffer
    (kuro-mode)
    (setq kuro-mux--pipe-pane-file "/tmp/kuro-stop-hook-test.log")
    (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
    (kuro-mux-pipe-pane nil)
    (should (null (memq #'kuro-mux--pipe-pane-watcher after-change-functions)))))

(ert-deftest kuro-mux-test-pipe-pane-is-interactive ()
  "`kuro-mux-pipe-pane' is an interactive command."
  (should (commandp #'kuro-mux-pipe-pane)))


;;; Group 40 — kuro-mux--pipe-pane-watcher (write, noop, error-recovery)

(ert-deftest kuro-mux-test-pipe-pane-watcher-noop-when-file-nil ()
  "`kuro-mux--pipe-pane-watcher' does nothing when `kuro-mux--pipe-pane-file' is nil."
  (with-temp-buffer
    (setq kuro-mux--pipe-pane-file nil)
    (insert "some text")
    (let ((written nil))
      (cl-letf (((symbol-function 'write-region)
                 (lambda (&rest _) (setq written t))))
        (kuro-mux--pipe-pane-watcher (point-min) (point-max) 0)
        (should (null written))))))

(ert-deftest kuro-mux-test-pipe-pane-watcher-noop-when-beg-eq-end ()
  "`kuro-mux--pipe-pane-watcher' does nothing when BEG = END (no new text)."
  (with-temp-buffer
    (kuro-mode)
    (setq kuro-mux--pipe-pane-file "/tmp/kuro-watcher-noop.log")
    (let ((written nil))
      (cl-letf (((symbol-function 'write-region)
                 (lambda (&rest _) (setq written t))))
        (kuro-mux--pipe-pane-watcher 5 5 0)
        (should (null written))))
    (setq kuro-mux--pipe-pane-file nil)))

(ert-deftest kuro-mux-test-pipe-pane-watcher-appends-text ()
  "`kuro-mux--pipe-pane-watcher' calls `write-region' with the new text."
  (with-temp-buffer
    (insert "hello world")
    (setq kuro-mux--pipe-pane-file "/tmp/kuro-append-test.log")
    (let ((written-text nil))
      (cl-letf (((symbol-function 'write-region)
                 (lambda (text _ignored file append _silent)
                   (setq written-text text))))
        (kuro-mux--pipe-pane-watcher (point-min) (point-max) 0)
        (should (equal written-text "hello world"))))
    (setq kuro-mux--pipe-pane-file nil)))

(ert-deftest kuro-mux-test-pipe-pane-watcher-clears-file-on-error ()
  "`kuro-mux--pipe-pane-watcher' clears the file path and removes hook on write error."
  (with-temp-buffer
    (insert "test")
    (setq kuro-mux--pipe-pane-file "/tmp/kuro-error-test.log")
    (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
    (cl-letf (((symbol-function 'write-region)
               (lambda (&rest _) (error "write failed"))))
      (kuro-mux--pipe-pane-watcher (point-min) (point-max) 0))
    (should (null kuro-mux--pipe-pane-file))
    (should (null (memq #'kuro-mux--pipe-pane-watcher after-change-functions)))))


;;; Group 41 — kuro-mux--on-session-created / kuro-mux--on-session-killed behavior

(ert-deftest kuro-mux-test-on-session-created-calls-register ()
  "`kuro-mux--on-session-created' registers the current buffer."
  (let ((kuro-mux--sessions nil)
        (kuro-mux-tab-bar-mode nil))
    (with-temp-buffer
      (kuro-mode)
      (kuro-mux--on-session-created)
      (should (memq (current-buffer) kuro-mux--sessions)))
    (setq kuro-mux--sessions nil)))

(ert-deftest kuro-mux-test-on-session-killed-calls-unregister ()
  "`kuro-mux--on-session-killed' removes the buffer from the registry."
  (let ((kuro-mux--sessions nil)
        (kuro-mux-tab-bar-mode nil))
    (let ((buf (get-buffer-create " *kuro-mux-kill-test*")))
      (unwind-protect
          (progn
            (with-current-buffer buf
              (kuro-mode)
              (kuro-mux--register))
            (should (memq buf kuro-mux--sessions))
            (with-current-buffer buf
              (kuro-mux--on-session-killed))
            (should-not (memq buf kuro-mux--sessions)))
        (when (buffer-live-p buf) (kill-buffer buf))
        (setq kuro-mux--sessions nil)))))

(ert-deftest kuro-mux-test-tab-bar-mode-is-a-minor-mode ()
  "`kuro-mux-tab-bar-mode' is a global minor mode."
  (should (commandp #'kuro-mux-tab-bar-mode)))

(ert-deftest kuro-mux-test-tab-bar-mode-enable-installs-hooks ()
  "Enabling `kuro-mux-tab-bar-mode' installs lifecycle hooks."
  (let ((kuro-mux-tab-bar-mode nil)
        (kuro-mode-hook nil)
        (kill-buffer-hook nil))
    (kuro-mux-tab-bar-mode 1)
    (unwind-protect
        (should (memq #'kuro-mux--on-session-created kuro-mode-hook))
      (kuro-mux-tab-bar-mode -1)
      (setq kuro-mode-hook nil kill-buffer-hook nil))))

(ert-deftest kuro-mux-test-tab-bar-mode-disable-uninstalls-hooks ()
  "Disabling `kuro-mux-tab-bar-mode' removes lifecycle hooks."
  (let ((kuro-mux-tab-bar-mode nil)
        (kuro-mode-hook nil)
        (kill-buffer-hook nil))
    (kuro-mux-tab-bar-mode 1)
    (kuro-mux-tab-bar-mode -1)
    (should-not (memq #'kuro-mux--on-session-created kuro-mode-hook))
    (setq kuro-mode-hook nil kill-buffer-hook nil)))


(provide 'kuro-mux-test-11)
;;; kuro-mux-test-11.el ends here
