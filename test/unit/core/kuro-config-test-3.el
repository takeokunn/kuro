;;; kuro-config-test-3.el --- Unit tests for kuro-config.el — Groups 11-14  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-config)

;;; Group 11: kuro--set-font

(ert-deftest test-kuro-set-font-sets-default-value ()
  "kuro--set-font sets the default value of the given symbol."
  (let ((kuro--test-font-sym nil))
    (defvar kuro--test-font-sym nil)
    (cl-letf (((symbol-function 'kuro--apply-font-to-buffer) #'ignore))
      (kuro--set-font 'kuro--test-font-sym "Mono 12")
      (should (equal (default-value 'kuro--test-font-sym) "Mono 12")))))

(ert-deftest test-kuro-set-font-broadcasts-to-kuro-buffers ()
  "kuro--set-font calls kuro--apply-font-to-buffer in each kuro-mode buffer."
  ;; kuro--broadcast-to-buffers expands to (kuro--apply-font-to-buffer buf),
  ;; so the stub must accept one argument.
  (let ((apply-called-in nil))
    (cl-letf (((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--apply-font-to-buffer)
               (lambda (_buf) (push (current-buffer) apply-called-in))))
      (with-temp-buffer
        (funcall 'kuro-mode)
        (let ((kuro-buf (current-buffer)))
          (defvar kuro--test-font-sym2 nil)
          (kuro--set-font 'kuro--test-font-sym2 "DejaVu Mono")
          (should (memq kuro-buf apply-called-in)))))))

(ert-deftest test-kuro-set-font-skips-non-kuro-buffers ()
  "kuro--set-font does not call kuro--apply-font-to-buffer on non-kuro buffers."
  (let ((apply-called nil))
    (cl-letf (((symbol-function 'kuro--apply-font-to-buffer)
               (lambda (_buf) (setq apply-called t))))
      (with-temp-buffer
        ;; This buffer is NOT in kuro-mode.
        (defvar kuro--test-font-sym3 nil)
        (kuro--set-font 'kuro--test-font-sym3 "Inconsolata")
        ;; kuro--kuro-buffers returns nil (kuro-mode not defined or this buf not in it)
        ;; so apply-font-to-buffer must not be called for this buffer.
        (should-not apply-called)))))

(ert-deftest test-kuro-set-font-handles-no-kuro-buffers ()
  "kuro--set-font completes without error when no kuro-mode buffers are active."
  (defvar kuro--test-font-sym4 nil)
  (should-not
   (condition-case err
       (progn (kuro--set-font 'kuro--test-font-sym4 "Courier") nil)
     (error err))))

;;; Group 12: kuro--set-shell

(defconst kuro-config-test--set-shell-valid-table
  '((test-kuro-set-shell-null-value          nil       nil)
    (test-kuro-set-shell-empty-string         ""        "")
    (test-kuro-set-shell-valid-executable     "/bin/sh" "/bin/sh"))
  "Table of (test-name value expected) for kuro--set-shell valid inputs.")

(defmacro kuro-config-test--def-set-shell-valid (test-name value expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--set-shell' accepts %S and sets kuro-shell to %S." value expected)
     (let ((orig kuro-shell))
       (unwind-protect
           (progn
             (should-not (condition-case err
                             (progn (kuro--set-shell 'kuro-shell ,value) nil)
                           (error err)))
             (should (equal kuro-shell ,expected)))
         (set-default 'kuro-shell orig)))))

(kuro-config-test--def-set-shell-valid test-kuro-set-shell-null-value         nil       nil)
(kuro-config-test--def-set-shell-valid test-kuro-set-shell-empty-string        ""        "")
(kuro-config-test--def-set-shell-valid test-kuro-set-shell-valid-executable    "/bin/sh" "/bin/sh")

(ert-deftest kuro-config-test--all-set-shell-valid-inputs-accepted ()
  "All kuro-config-test--set-shell-valid-table entries are accepted without error."
  (dolist (entry kuro-config-test--set-shell-valid-table)
    (pcase-let ((`(,_name ,value ,expected) entry))
      (let ((orig kuro-shell))
        (unwind-protect
            (progn
              (should-not (condition-case err
                              (progn (kuro--set-shell 'kuro-shell value) nil)
                            (error err)))
              (should (equal kuro-shell expected)))
          (set-default 'kuro-shell orig))))))

(ert-deftest test-kuro-set-shell-nonexistent-signals-error ()
  "kuro--set-shell signals user-error for a non-existent shell path."
  (should-error
   (kuro--set-shell 'kuro-shell "/nonexistent/shell/no/such/file")
   :type 'user-error))

;;; Group 13: kuro--set-scrollback-size

(ert-deftest test-kuro-set-scrollback-size-valid ()
  "kuro--set-scrollback-size accepts a positive integer."
  (let ((orig kuro-scrollback-size))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'kuro--set-scrollback-max-lines) #'ignore))
            (should-not (condition-case err
                            (progn (kuro--set-scrollback-size
                                    'kuro-scrollback-size 5000)
                                   nil)
                          (error err)))
            (should (= kuro-scrollback-size 5000))))
      (set-default 'kuro-scrollback-size orig))))

(defconst kuro-config-test--positive-setter-error-table
  '((test-kuro-set-scrollback-size-zero-errors     kuro--set-scrollback-size kuro-scrollback-size  0)
    (test-kuro-set-scrollback-size-negative-errors kuro--set-scrollback-size kuro-scrollback-size -1)
    (test-kuro-set-tui-frame-rate-zero-errors      kuro--set-tui-frame-rate  kuro-tui-frame-rate   0)
    (test-kuro-set-tui-frame-rate-negative-errors  kuro--set-tui-frame-rate  kuro-tui-frame-rate  -3))
  "Table of (test-name setter-fn var-sym value) for positive-integer setter error cases.")

(defmacro kuro-config-test--def-positive-setter-error (test-name setter-fn var-sym value)
  `(ert-deftest ,test-name ()
     ,(format "`%s' signals user-error for %S." setter-fn value)
     (should-error (,setter-fn ',var-sym ,value) :type 'user-error)))

(kuro-config-test--def-positive-setter-error test-kuro-set-scrollback-size-zero-errors     kuro--set-scrollback-size kuro-scrollback-size  0)
(kuro-config-test--def-positive-setter-error test-kuro-set-scrollback-size-negative-errors kuro--set-scrollback-size kuro-scrollback-size -1)
(kuro-config-test--def-positive-setter-error test-kuro-set-tui-frame-rate-zero-errors      kuro--set-tui-frame-rate  kuro-tui-frame-rate   0)
(kuro-config-test--def-positive-setter-error test-kuro-set-tui-frame-rate-negative-errors  kuro--set-tui-frame-rate  kuro-tui-frame-rate  -3)

(ert-deftest kuro-config-test--all-positive-setter-errors-signal-user-error ()
  "All kuro-config-test--positive-setter-error-table entries signal user-error."
  (dolist (entry kuro-config-test--positive-setter-error-table)
    (pcase-let ((`(,_name ,setter-fn ,var-sym ,value) entry))
      (should-error (funcall setter-fn var-sym value) :type 'user-error))))

;;; Group 14: kuro--set-tui-frame-rate

(ert-deftest test-kuro-set-tui-frame-rate-valid ()
  "kuro--set-tui-frame-rate accepts a positive integer."
  (let ((orig kuro-tui-frame-rate))
    (unwind-protect
        (progn
          (should-not (condition-case err
                          (progn (kuro--set-tui-frame-rate
                                  'kuro-tui-frame-rate 10)
                                 nil)
                        (error err)))
          (should (= kuro-tui-frame-rate 10)))
      (set-default 'kuro-tui-frame-rate orig))))


(provide 'kuro-config-test-3)
;;; kuro-config-test-3.el ends here
