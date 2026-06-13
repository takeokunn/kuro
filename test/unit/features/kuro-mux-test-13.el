;;; kuro-mux-test-13.el --- ERT tests for kuro-mux-ext2.el — Group 44  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))


;;; Group 44 — kuro-mux--restore-session

(defmacro kuro-mux-test-13--with-restore-buf (buf-name &rest body)
  "Evaluate BODY with a live kuro-mode buffer named BUF-NAME.
Mocks `kuro-create' to switch to the buffer and `kuro-mux--register'
to a no-op, cleaning up the buffer on exit."
  (declare (indent 1))
  `(let ((buf (get-buffer-create ,buf-name)))
     (unwind-protect
         (progn
           (with-current-buffer buf (kuro-mode))
           (cl-letf (((symbol-function 'kuro-create)
                      (lambda (_cmd) (set-buffer buf)))
                     ((symbol-function 'kuro-mux--register) #'ignore))
             ,@body))
       (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-mux-test-restore-session-calls-kuro-create ()
  "`kuro-mux--restore-session' calls `kuro-create' with the spec's :command."
  (let ((buf (get-buffer-create " *kuro-rs-cmd*"))
        (called-with :not-called))
    (unwind-protect
        (progn
          (with-current-buffer buf (kuro-mode))
          (cl-letf (((symbol-function 'kuro-create)
                     (lambda (cmd) (setq called-with cmd) (set-buffer buf)))
                    ((symbol-function 'kuro-mux--register) #'ignore))
            (kuro-mux--restore-session '(:command "bash")))
          (should (equal called-with "bash")))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-mux-test-restore-session-sets-command ()
  "`kuro-mux--restore-session' stores :command in `kuro-mux--command'."
  (kuro-mux-test-13--with-restore-buf " *kuro-rs-set-cmd*"
    (kuro-mux--restore-session '(:command "fish"))
    (should (equal (buffer-local-value 'kuro-mux--command buf) "fish"))))

(ert-deftest kuro-mux-test-restore-session-sets-name ()
  "`kuro-mux--restore-session' stores :name in `kuro-mux--name' when provided."
  (kuro-mux-test-13--with-restore-buf " *kuro-rs-set-name*"
    (kuro-mux--restore-session '(:command "zsh" :name "my-session"))
    (should (equal (buffer-local-value 'kuro-mux--name buf) "my-session"))))

(ert-deftest kuro-mux-test-restore-session-no-name-leaves-nil ()
  "`kuro-mux--restore-session' leaves `kuro-mux--name' nil when :name is absent."
  (kuro-mux-test-13--with-restore-buf " *kuro-rs-no-name*"
    (with-current-buffer buf (setq kuro-mux--name nil))
    (kuro-mux--restore-session '(:command "zsh"))
    (should (null (buffer-local-value 'kuro-mux--name buf)))))

(ert-deftest kuro-mux-test-restore-session-sets-directory ()
  "`kuro-mux--restore-session' stores :directory in `kuro-mux--directory'."
  (kuro-mux-test-13--with-restore-buf " *kuro-rs-set-dir*"
    (kuro-mux--restore-session `(:command "bash" :directory ,temporary-file-directory))
    (should (equal (buffer-local-value 'kuro-mux--directory buf)
                   temporary-file-directory))))

(ert-deftest kuro-mux-test-restore-session-calls-register ()
  "`kuro-mux--restore-session' calls `kuro-mux--register' after creation."
  (let ((buf (get-buffer-create " *kuro-rs-reg*"))
        (registered nil))
    (unwind-protect
        (progn
          (with-current-buffer buf (kuro-mode))
          (cl-letf (((symbol-function 'kuro-create)
                     (lambda (_) (set-buffer buf)))
                    ((symbol-function 'kuro-mux--register)
                     (lambda () (setq registered t))))
            (kuro-mux--restore-session '(:command "bash")))
          (should registered))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest kuro-mux-test-restore-session-noop-outside-kuro-mode ()
  "`kuro-mux--restore-session' skips annotations when `kuro-create' lands in a non-kuro buffer."
  (let ((buf (get-buffer-create " *kuro-rs-noop*"))
        (registered nil))
    (unwind-protect
        (progn
          ;; Leave buf in fundamental-mode — not kuro-mode
          (cl-letf (((symbol-function 'kuro-create)
                     (lambda (_) (set-buffer buf)))
                    ((symbol-function 'kuro-mux--register)
                     (lambda () (setq registered t))))
            (kuro-mux--restore-session '(:command "bash" :name "ignored")))
          (should-not registered))
      (when (buffer-live-p buf) (kill-buffer buf)))))


(provide 'kuro-mux-test-13)
;;; kuro-mux-test-13.el ends here
