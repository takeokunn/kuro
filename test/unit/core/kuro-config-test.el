;;; kuro-config-test.el --- Unit tests for kuro-config.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the Kuro configuration system.
;; These tests cover pure Emacs Lisp functions only and do NOT require
;; the Rust dynamic module (kuro-core-*).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-config)

;;; Group 1: kuro--validate-config

(ert-deftest test-kuro-validate-config-valid ()
  "All settings at their defaults are valid: returns nil (empty list)."
  (let ((errors (kuro--validate-config)))
    (should (null errors))))

(ert-deftest test-kuro-validate-config-invalid-shell ()
  "A non-existent shell path produces an error mentioning \"shell\" and the path."
  (let ((kuro-shell "/nonexistent/shell/that/does/not/exist"))
    (let ((errors (kuro--validate-config)))
      (should (consp errors))
      (should (cl-some (lambda (e)
                         (and (string-match-p "shell" e)
                              (string-match-p "/nonexistent/shell/that/does/not/exist" e)))
                       errors)))))

(defconst kuro-config-test--validate-consp-table
  '((test-kuro-validate-config-invalid-scrollback  kuro-scrollback-size -1)
    (test-kuro-validate-config-zero-scrollback      kuro-scrollback-size  0)
    (test-kuro-validate-config-invalid-color-short  kuro-color-red       "#fff")
    (test-kuro-validate-config-invalid-font-size    kuro-font-size       -5))
  "Table of (test-name var-sym value): each binding yields (consp errors) from kuro--validate-config.")

(defmacro kuro-config-test--def-validate-consp (test-name var-sym value)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--validate-config' returns errors for `%s' = %S." var-sym value)
     (let ((,var-sym ,value))
       (should (consp (kuro--validate-config))))))

(kuro-config-test--def-validate-consp test-kuro-validate-config-invalid-scrollback  kuro-scrollback-size -1)
(kuro-config-test--def-validate-consp test-kuro-validate-config-zero-scrollback      kuro-scrollback-size  0)
(kuro-config-test--def-validate-consp test-kuro-validate-config-invalid-color-short  kuro-color-red       "#fff")
(kuro-config-test--def-validate-consp test-kuro-validate-config-invalid-font-size    kuro-font-size       -5)

(ert-deftest kuro-config-test--all-validate-consp-errors-correct ()
  "All kuro-config-test--validate-consp-table entries produce (consp errors)."
  (dolist (entry kuro-config-test--validate-consp-table)
    (pcase-let ((`(,_name ,var-sym ,value) entry))
      (cl-letf (((symbol-value var-sym) value))
        (should (consp (kuro--validate-config)))))))

(ert-deftest test-kuro-validate-config-invalid-color ()
  "An invalid color string produces an error that mentions kuro-color-red."
  (let ((kuro-color-red "not-a-color"))
    (let ((errors (kuro--validate-config)))
      (should (consp errors))
      (should (cl-some (lambda (e)
                         (string-match-p "kuro-color-red" e))
                       errors)))))

(ert-deftest test-kuro-validate-config-nil-font-size ()
  "nil font size is valid (inherit from default face) — no font-size error."
  (let ((kuro-font-size nil))
    (let ((errors (kuro--validate-config)))
      (should-not (cl-some (lambda (e)
                              (string-match-p "font-size" e))
                            errors)))))

(ert-deftest test-kuro-validate-config-zero-frame-rate ()
  "Zero frame-rate produces an error (must be positive)."
  (let ((kuro-frame-rate 0))
    (let ((errors (kuro--validate-config)))
      (should (consp errors))
      (should (cl-some (lambda (e)
                         (string-match-p "frame-rate" e))
                       errors)))))

(ert-deftest test-kuro-validate-config-multi-error ()
  "Multiple invalid settings accumulate multiple errors."
  (let ((kuro-scrollback-size -1)
        (kuro-frame-rate 0)
        (kuro-color-black "invalid"))
    (let ((errors (kuro--validate-config)))
      (should (>= (length errors) 3)))))

;;; Group 2: kuro--rebuild-named-colors

(ert-deftest test-kuro-rebuild-named-colors-basic ()
  "After kuro--rebuild-named-colors, kuro--named-colors is a hash table and
\"black\" maps to the value of kuro-color-black."
  (kuro--rebuild-named-colors)
  (should (hash-table-p kuro--named-colors))
  (should (equal (gethash "black" kuro--named-colors) kuro-color-black)))

(ert-deftest test-kuro-rebuild-named-colors-length ()
  "kuro--named-colors has exactly 16 entries (8 normal + 8 bright)."
  (kuro--rebuild-named-colors)
  (should (= (hash-table-count kuro--named-colors) 16)))

(ert-deftest test-kuro-rebuild-named-colors-reflects-custom ()
  "Changing kuro-color-red and calling kuro--rebuild-named-colors updates
the \"red\" entry in kuro--named-colors."
  (let ((original-red kuro-color-red))
    (unwind-protect
        (progn
          (setq kuro-color-red "#abcdef")
          (kuro--rebuild-named-colors)
          (should (equal (gethash "red" kuro--named-colors) "#abcdef")))
      ;; Restore original value and rebuild so other tests are unaffected.
      (setq kuro-color-red original-red)
      (kuro--rebuild-named-colors))))

(ert-deftest test-kuro-rebuild-named-colors-all-keys ()
  "kuro--named-colors contains all 16 expected ANSI color keys."
  (kuro--rebuild-named-colors)
  (let ((expected-keys '("black" "red" "green" "yellow"
                         "blue" "magenta" "cyan" "white"
                         "bright-black" "bright-red" "bright-green" "bright-yellow"
                         "bright-blue" "bright-magenta" "bright-cyan" "bright-white")))
    (dolist (key expected-keys)
      (should (gethash key kuro--named-colors)))))

;;; Group 3: kuro-validate-config (interactive wrapper)

(ert-deftest test-kuro-validate-config-callable ()
  "kuro-validate-config is callable without signalling an error."
  (should (fboundp 'kuro-validate-config))
  ;; Call non-interactively; it writes to the echo area, which is fine in batch.
  (should-not (condition-case err
                  (progn (kuro-validate-config) nil)
                (error err))))

;;; Group 4: kuro--set-frame-rate (structural test)


(ert-deftest test-kuro-set-frame-rate-valid ()
  "kuro--set-frame-rate with a positive integer sets kuro-frame-rate without error."
  (let ((orig kuro-frame-rate))
    (unwind-protect
        (progn
          ;; :set handlers receive (symbol value) as arguments
          (should-not (condition-case err
                          (progn (kuro--set-frame-rate 'kuro-frame-rate 60) nil)
                        (error err)))
          (should (= 60 kuro-frame-rate)))
      ;; Restore original value via the set handler to avoid side effects
      (set-default 'kuro-frame-rate orig))))

(ert-deftest test-kuro-set-frame-rate-invalid ()
  "kuro--set-frame-rate with zero or negative value signals a user-error."
  (should-error (kuro--set-frame-rate 'kuro-frame-rate 0) :type 'user-error)
  (should-error (kuro--set-frame-rate 'kuro-frame-rate -1) :type 'user-error))

;;; Group 5: kuro--positive-integer-p

(defconst kuro-config-test--positive-integer-p-table
  '((test-kuro-positive-integer-p-one          1      t)
    (test-kuro-positive-integer-p-hundred      100    t)
    (test-kuro-positive-integer-p-ten-thousand 10000  t)
    (test-kuro-positive-integer-p-zero         0      nil)
    (test-kuro-positive-integer-p-neg-one      -1     nil)
    (test-kuro-positive-integer-p-neg-hundred  -100   nil)
    (test-kuro-positive-integer-p-float        1.0    nil)
    (test-kuro-positive-integer-p-string       "1"    nil)
    (test-kuro-positive-integer-p-nil          nil    nil))
  "Table of (test-name val expectedp) for `kuro--positive-integer-p'.")

(defmacro kuro-config-test--def-positive-integer-p (test-name val expectedp)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--positive-integer-p' (%S) => %s." val (if expectedp "non-nil" "nil"))
     ,(if expectedp
          `(should     (kuro--positive-integer-p ,val))
        `(should-not (kuro--positive-integer-p ,val)))))

(kuro-config-test--def-positive-integer-p test-kuro-positive-integer-p-one          1      t)
(kuro-config-test--def-positive-integer-p test-kuro-positive-integer-p-hundred      100    t)
(kuro-config-test--def-positive-integer-p test-kuro-positive-integer-p-ten-thousand 10000  t)
(kuro-config-test--def-positive-integer-p test-kuro-positive-integer-p-zero         0      nil)
(kuro-config-test--def-positive-integer-p test-kuro-positive-integer-p-neg-one      -1     nil)
(kuro-config-test--def-positive-integer-p test-kuro-positive-integer-p-neg-hundred  -100   nil)
(kuro-config-test--def-positive-integer-p test-kuro-positive-integer-p-float        1.0    nil)
(kuro-config-test--def-positive-integer-p test-kuro-positive-integer-p-string       "1"    nil)
(kuro-config-test--def-positive-integer-p test-kuro-positive-integer-p-nil          nil    nil)

(ert-deftest test-kuro-positive-integer-p--all-cases-correct ()
  "Every entry in `kuro-config-test--positive-integer-p-table' produces the expected result."
  (dolist (entry kuro-config-test--positive-integer-p-table)
    (pcase-let ((`(,_name ,val ,expectedp) entry))
      (if expectedp
          (should     (kuro--positive-integer-p val))
        (should-not (kuro--positive-integer-p val))))))

;;; Group 6: kuro--check-positive-integer

(ert-deftest test-kuro-check-positive-integer-valid ()
  "kuro--check-positive-integer does not push error for positive integer."
  (let ((errors nil)
        (kuro-frame-rate 60))
    (kuro--check-positive-integer kuro-frame-rate errors)
    (should (null errors))))

(defconst kuro-config-test--check-pi-error-table
  '((test-kuro-check-positive-integer-zero     kuro-frame-rate    0)
    (test-kuro-check-positive-integer-negative kuro-scrollback-size -5))
  "Table of (test-name var-sym value) for kuro--check-positive-integer error cases.")

(defmacro kuro-config-test--def-check-pi-error (test-name var-sym value)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--check-positive-integer' pushes error for `%s' bound to %S."
              var-sym value)
     (let ((errors nil)
           (,var-sym ,value))
       (kuro--check-positive-integer ,var-sym errors)
       (should (consp errors))
       (should (string-match-p ,(symbol-name var-sym) (car errors))))))

(kuro-config-test--def-check-pi-error test-kuro-check-positive-integer-zero     kuro-frame-rate     0)
(kuro-config-test--def-check-pi-error test-kuro-check-positive-integer-negative kuro-scrollback-size -5)

(ert-deftest kuro-config-test--all-check-pi-errors-push-error ()
  "All kuro-config-test--check-pi-error-table entries push an error with the var name."
  (dolist (entry kuro-config-test--check-pi-error-table)
    (pcase-let ((`(,_name ,var-sym ,value) entry))
      (let ((errors nil))
        (cl-progv (list var-sym) (list value)
          (kuro--check-positive-integer var-sym errors))
        (should (consp errors))
        (should (string-match-p (symbol-name var-sym) (car errors)))))))

;;; Group 7: kuro--broadcast-to-buffers (structural)

(ert-deftest test-kuro-broadcast-to-buffers-noop-when-unbound ()
  "kuro--broadcast-to-buffers is a no-op when the function is not bound."
  ;; kuro--fictional-fn should not exist; the macro must not error
  (should-not
   (condition-case err
       (progn (kuro--broadcast-to-buffers kuro--fictional-fn) nil)
     (error err))))

;;; Group 8: kuro--def-positive-int-setter macro

(ert-deftest test-kuro-def-positive-int-setter-generates-callable ()
  "kuro--def-positive-int-setter generates a two-argument callable defun."
  (kuro--def-positive-int-setter kuro--test-pi-setter
      "kuro: test must be positive integer, got: %s"
      "Test setter docstring."
    nil)
  (should (fboundp 'kuro--test-pi-setter)))

(ert-deftest test-kuro-def-positive-int-setter-sets-value ()
  "Generated setter calls set-default with the provided value."
  (kuro--def-positive-int-setter kuro--test-pi-setter-set
      "kuro: test must be positive integer, got: %s"
      "Test setter."
    nil)
  (defvar kuro--test-pi-setter-var 0)
  (kuro--test-pi-setter-set 'kuro--test-pi-setter-var 42)
  (should (= (default-value 'kuro--test-pi-setter-var) 42)))

(defmacro kuro-config-test--def-pi-setter-reject (test-name setter-name value)
  `(ert-deftest ,test-name ()
     ,(format "Generated setter `%s' signals user-error for %S." setter-name value)
     (kuro--def-positive-int-setter ,setter-name
         "kuro: test must be positive integer, got: %s"
         "Test setter."
       nil)
     (should-error (,setter-name 'ignored ,value) :type 'user-error)))

(kuro-config-test--def-pi-setter-reject test-kuro-def-positive-int-setter-rejects-zero     kuro--test-pi-setter-zero 0)
(kuro-config-test--def-pi-setter-reject test-kuro-def-positive-int-setter-rejects-negative kuro--test-pi-setter-neg  -5)

(ert-deftest test-kuro-def-positive-int-setter-runs-body ()
  "Generated setter evaluates BODY after set-default."
  (defvar kuro--test-pi-side-effect nil)
  (kuro--def-positive-int-setter kuro--test-pi-setter-body
      "kuro: test must be positive integer, got: %s"
      "Test setter."
    (setq kuro--test-pi-side-effect value))
  (setq kuro--test-pi-side-effect nil)
  (kuro--test-pi-setter-body 'ignored 7)
  (should (= kuro--test-pi-side-effect 7)))

;;; Group 9: kuro--set-input-echo-delay

(defmacro kuro-config-test--def-echo-delay-valid (test-name value)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--set-input-echo-delay' accepts %S without error." value)
     (let ((orig kuro-input-echo-delay))
       (unwind-protect
           (progn
             (should-not (condition-case err
                             (progn (kuro--set-input-echo-delay
                                     'kuro-input-echo-delay ,value)
                                    nil)
                           (error err)))
             (should (= kuro-input-echo-delay ,value)))
         (set-default 'kuro-input-echo-delay orig)))))

(kuro-config-test--def-echo-delay-valid test-kuro-set-input-echo-delay-valid 0.05)
(kuro-config-test--def-echo-delay-valid test-kuro-set-input-echo-delay-zero  0)

(defconst kuro-config-test--echo-delay-error-table
  '((test-kuro-set-input-echo-delay-negative           -0.1)
    (test-kuro-set-input-echo-delay-non-number-string  "0.01")
    (test-kuro-set-input-echo-delay-non-number-nil     nil))
  "Table of (test-name value) for kuro--set-input-echo-delay user-error cases.")

(defmacro kuro-config-test--def-echo-delay-error (test-name value)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--set-input-echo-delay' signals user-error for %S." value)
     (should-error (kuro--set-input-echo-delay 'kuro-input-echo-delay ,value)
                   :type 'user-error)))

(kuro-config-test--def-echo-delay-error test-kuro-set-input-echo-delay-negative          -0.1)
(kuro-config-test--def-echo-delay-error test-kuro-set-input-echo-delay-non-number-string "0.01")
(kuro-config-test--def-echo-delay-error test-kuro-set-input-echo-delay-non-number-nil    nil)

(ert-deftest kuro-config-test--all-echo-delay-errors-signal-user-error ()
  "All kuro-config-test--echo-delay-error-table entries signal user-error."
  (dolist (entry kuro-config-test--echo-delay-error-table)
    (pcase-let ((`(,_name ,value) entry))
      (should-error (kuro--set-input-echo-delay 'kuro-input-echo-delay value)
                    :type 'user-error))))

;;; Group 10: kuro--kuro-buffers

(ert-deftest test-kuro-kuro-buffers-excludes-dead-buffers ()
  "kuro--kuro-buffers never returns a dead buffer."
  ;; kuro-mode is not defined in the test environment, so kuro--kuro-buffers
  ;; returns nil via the (when (fboundp 'kuro-mode) ...) guard.
  ;; The important thing is that it does not include dead buffers and does
  ;; not signal an error.
  (let ((buf (generate-new-buffer " *kuro-test-dead*")))
    (kill-buffer buf)
    (let ((result (kuro--kuro-buffers)))
      (should-not (memq buf result)))))

(ert-deftest test-kuro-kuro-buffers-excludes-non-kuro-mode ()
  "kuro--kuro-buffers does not return buffers without kuro-mode active."
  (with-temp-buffer
    ;; This temp buffer is in fundamental-mode (or text-mode), not kuro-mode.
    (let ((this-buf (current-buffer)))
      (let ((result (kuro--kuro-buffers)))
        (should-not (memq this-buf result))))))

(ert-deftest test-kuro-kuro-buffers-includes-kuro-mode-buffer ()
  "kuro--kuro-buffers returns buffers where kuro-mode is the major mode."
  ;; Define a minimal kuro-mode stub so fboundp passes and derived-mode-p works.
  (cl-letf (((symbol-function 'kuro-mode)
             (lambda () (setq major-mode 'kuro-mode))))
    (with-temp-buffer
      (funcall 'kuro-mode)
      (let ((this-buf (current-buffer)))
        (let ((result (kuro--kuro-buffers)))
          (should (memq this-buf result)))))))


(provide 'kuro-config-test)
;;; kuro-config-test.el ends here
