;;; kuro-mux-test-7.el --- Unit tests for kuro-mux.el — Groups 33-36  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)


;;; Group 33 — kuro-mux-switch-by-name (functional paths)

(ert-deftest kuro-mux-test-switch-by-name-is-interactive ()
  "`kuro-mux-switch-by-name' is an interactive command."
  (should (commandp #'kuro-mux-switch-by-name)))

(ert-deftest kuro-mux-test-switch-by-name-switches-to-matching-session ()
  "`kuro-mux-switch-by-name' calls `switch-to-buffer' on the matching buffer."
  (let* ((buf (generate-new-buffer "*kuro-sbn-test*"))
         switched-to)
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () (list buf)))
                  ((symbol-function 'kuro-mux--session-display-name)
                   (lambda (b) (if (eq b buf) "my-session" "other")))
                  ((symbol-function 'switch-to-buffer)
                   (lambda (b) (setq switched-to b))))
          (kuro-mux-switch-by-name "my-session")
          (should (eq switched-to buf)))
      (kill-buffer buf))))

(ert-deftest kuro-mux-test-switch-by-name-messages-when-not-found ()
  "`kuro-mux-switch-by-name' messages when no session matches."
  (let (msgs)
    (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () nil))
              ((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) msgs))))
      (kuro-mux-switch-by-name "nonexistent"))
    (should (cl-some (lambda (m) (string-match-p "nonexistent" m)) msgs))))

(ert-deftest kuro-mux-test-switch-by-name-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds \"s\" to `kuro-mux-switch-by-name'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "s"))
              #'kuro-mux-switch-by-name)))


;;; Group 34 — kuro-mux--track-window-change (function body)

(ert-deftest kuro-mux-test-track-fn-records-kuro-buffer ()
  "`kuro-mux--track-window-change' records the old window's buffer when it is a kuro buffer."
  (let* ((buf (generate-new-buffer "*kuro-track-fn-test*"))
         (other (generate-new-buffer "*kuro-track-other*"))
         (kuro-mux--last-session nil))
    (unwind-protect
        (cl-letf (((symbol-function 'old-selected-window) (lambda () 'fake-win))
                  ((symbol-function 'window-live-p) (lambda (_) t))
                  ((symbol-function 'window-buffer) (lambda (_) buf))
                  ((symbol-function 'derived-mode-p) (lambda (&rest _) t))
                  ((symbol-function 'current-buffer) (lambda () other)))
          (kuro-mux--track-window-change nil)
          (should (eq kuro-mux--last-session buf)))
      (kill-buffer buf)
      (kill-buffer other))))

(ert-deftest kuro-mux-test-track-fn-skips-non-kuro-buffer ()
  "`kuro-mux--track-window-change' leaves `kuro-mux--last-session' unchanged for non-kuro buffers."
  (let* ((buf (generate-new-buffer "*non-kuro-track-fn*"))
         (kuro-mux--last-session 'sentinel))
    (unwind-protect
        (cl-letf (((symbol-function 'old-selected-window) (lambda () 'fake-win))
                  ((symbol-function 'window-live-p) (lambda (_) t))
                  ((symbol-function 'window-buffer) (lambda (_) buf))
                  ((symbol-function 'derived-mode-p) (lambda (&rest _) nil)))
          (kuro-mux--track-window-change nil)
          (should (eq kuro-mux--last-session 'sentinel)))
      (kill-buffer buf))))

(ert-deftest kuro-mux-test-track-fn-skips-dead-window ()
  "`kuro-mux--track-window-change' does nothing when the old window is dead."
  (let ((kuro-mux--last-session 'sentinel))
    (cl-letf (((symbol-function 'old-selected-window) (lambda () nil))
              ((symbol-function 'window-live-p) (lambda (_) nil)))
      (kuro-mux--track-window-change nil)
      (should (eq kuro-mux--last-session 'sentinel)))))

(ert-deftest kuro-mux-test-track-fn-skips-same-buffer ()
  "`kuro-mux--track-window-change' does not record the buffer if it matches the current buffer."
  (let* ((buf (generate-new-buffer "*kuro-track-same*"))
         (kuro-mux--last-session 'sentinel))
    (unwind-protect
        (cl-letf (((symbol-function 'old-selected-window) (lambda () 'fake-win))
                  ((symbol-function 'window-live-p) (lambda (_) t))
                  ((symbol-function 'window-buffer) (lambda (_) buf))
                  ((symbol-function 'derived-mode-p) (lambda (&rest _) t))
                  ((symbol-function 'current-buffer) (lambda () buf)))
          (kuro-mux--track-window-change nil)
          (should (eq kuro-mux--last-session 'sentinel)))
      (kill-buffer buf))))


;;; Group 35 — kuro-mux-install-mode-line

(ert-deftest kuro-mux-test-install-mode-line-adds-to-hook ()
  "`kuro-mux-install-mode-line' adds `kuro-mux--buffer-mode-line-setup' to `kuro-mode-hook'."
  (let ((kuro-mode-hook nil))
    (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () nil)))
      (kuro-mux-install-mode-line)
      (should (memq #'kuro-mux--buffer-mode-line-setup kuro-mode-hook)))))

(ert-deftest kuro-mux-test-install-mode-line-calls-setup-on-existing-sessions ()
  "`kuro-mux-install-mode-line' calls `kuro-mux--buffer-mode-line-setup' on all live sessions."
  (let* ((buf (generate-new-buffer "*kuro-ml-setup-test*"))
         called-on
         (kuro-mode-hook nil))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () (list buf)))
                  ((symbol-function 'kuro-mux--buffer-mode-line-setup)
                   (lambda () (push (current-buffer) called-on))))
          (kuro-mux-install-mode-line)
          (should (memq buf called-on)))
      (kill-buffer buf))))


;;; Group 36 — kuro-mux-split-right / kuro-mux-split-below (kuro--def-mux-split)

(ert-deftest kuro-mux-test-split-right-is-interactive ()
  "`kuro-mux-split-right' is an interactive command."
  (should (commandp #'kuro-mux-split-right)))

(ert-deftest kuro-mux-test-split-below-is-interactive ()
  "`kuro-mux-split-below' is an interactive command."
  (should (commandp #'kuro-mux-split-below)))

(ert-deftest kuro-mux-test-split-right-calls-split-window-right ()
  "`kuro-mux-split-right' splits horizontally and creates a kuro session."
  (let (split-called create-cmd)
    (cl-letf (((symbol-function 'split-window-right)
               (lambda () (setq split-called t) (selected-window)))
              ((symbol-function 'select-window) #'ignore)
              ((symbol-function 'kuro-create)
               (lambda (cmd) (setq create-cmd cmd))))
      (kuro-mux-split-right "bash")
      (should split-called)
      (should (equal create-cmd "bash")))))

(ert-deftest kuro-mux-test-split-below-calls-split-window-below ()
  "`kuro-mux-split-below' splits vertically and creates a kuro session."
  (let (split-called create-cmd)
    (cl-letf (((symbol-function 'split-window-below)
               (lambda () (setq split-called t) (selected-window)))
              ((symbol-function 'select-window) #'ignore)
              ((symbol-function 'kuro-create)
               (lambda (cmd) (setq create-cmd cmd))))
      (kuro-mux-split-below "zsh")
      (should split-called)
      (should (equal create-cmd "zsh")))))

(ert-deftest kuro-mux-test-split-right-uses-kuro-shell-as-default ()
  "`kuro-mux-split-right' falls back to `kuro-shell' when COMMAND is nil."
  (let ((kuro-shell "/bin/sh") create-cmd)
    (cl-letf (((symbol-function 'split-window-right) (lambda () (selected-window)))
              ((symbol-function 'select-window) #'ignore)
              ((symbol-function 'kuro-create) (lambda (cmd) (setq create-cmd cmd))))
      (kuro-mux-split-right nil)
      (should (equal create-cmd "/bin/sh")))))

(ert-deftest kuro-mux-test-split-below-uses-kuro-shell-as-default ()
  "`kuro-mux-split-below' falls back to `kuro-shell' when COMMAND is nil."
  (let ((kuro-shell "/bin/sh") create-cmd)
    (cl-letf (((symbol-function 'split-window-below) (lambda () (selected-window)))
              ((symbol-function 'select-window) #'ignore)
              ((symbol-function 'kuro-create) (lambda (cmd) (setq create-cmd cmd))))
      (kuro-mux-split-below nil)
      (should (equal create-cmd "/bin/sh")))))

(provide 'kuro-mux-test-7)
;;; kuro-mux-test-7.el ends here
