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

(ert-deftest test-kuro-validate-config-invalid-scrollback ()
  "A negative scrollback size produces an error."
  (let ((kuro-scrollback-size -1))
    (let ((errors (kuro--validate-config)))
      (should (consp errors)))))

(ert-deftest test-kuro-validate-config-zero-scrollback ()
  "Zero scrollback size produces an error (must be positive)."
  (let ((kuro-scrollback-size 0))
    (let ((errors (kuro--validate-config)))
      (should (consp errors)))))

(ert-deftest test-kuro-validate-config-invalid-color ()
  "An invalid color string produces an error that mentions kuro-color-red."
  (let ((kuro-color-red "not-a-color"))
    (let ((errors (kuro--validate-config)))
      (should (consp errors))
      (should (cl-some (lambda (e)
                         (string-match-p "kuro-color-red" e))
                       errors)))))

(ert-deftest test-kuro-validate-config-invalid-color-short ()
  "A 3-digit hex color (#fff) is rejected because it is not 6 digits."
  (let ((kuro-color-red "#fff"))
    (let ((errors (kuro--validate-config)))
      (should (consp errors)))))

(ert-deftest test-kuro-validate-config-invalid-font-size ()
  "A negative font size produces an error."
  (let ((kuro-font-size -5))
    (let ((errors (kuro--validate-config)))
      (should (consp errors)))))

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

(ert-deftest test-kuro-positive-integer-p-positive ()
  "Positive integers return non-nil."
  (should (kuro--positive-integer-p 1))
  (should (kuro--positive-integer-p 100))
  (should (kuro--positive-integer-p 10000)))

(ert-deftest test-kuro-positive-integer-p-zero ()
  "Zero is not positive: returns nil."
  (should-not (kuro--positive-integer-p 0)))

(ert-deftest test-kuro-positive-integer-p-negative ()
  "Negative integers return nil."
  (should-not (kuro--positive-integer-p -1))
  (should-not (kuro--positive-integer-p -100)))

(ert-deftest test-kuro-positive-integer-p-non-integer ()
  "Non-integers (float, string, nil) return nil."
  (should-not (kuro--positive-integer-p 1.0))
  (should-not (kuro--positive-integer-p "1"))
  (should-not (kuro--positive-integer-p nil)))

;;; Group 6: kuro--check-positive-integer

(ert-deftest test-kuro-check-positive-integer-valid ()
  "kuro--check-positive-integer does not push error for positive integer."
  (let ((errors nil)
        (kuro-frame-rate 60))
    (kuro--check-positive-integer kuro-frame-rate errors)
    (should (null errors))))

(ert-deftest test-kuro-check-positive-integer-zero ()
  "kuro--check-positive-integer pushes error for zero."
  (let ((errors nil)
        (kuro-frame-rate 0))
    (kuro--check-positive-integer kuro-frame-rate errors)
    (should (consp errors))
    (should (string-match-p "kuro-frame-rate" (car errors)))))

(ert-deftest test-kuro-check-positive-integer-negative ()
  "kuro--check-positive-integer pushes error for negative value."
  (let ((errors nil)
        (kuro-scrollback-size -5))
    (kuro--check-positive-integer kuro-scrollback-size errors)
    (should (consp errors))
    (should (string-match-p "kuro-scrollback-size" (car errors)))))

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

(ert-deftest test-kuro-def-positive-int-setter-rejects-zero ()
  "Generated setter signals user-error for zero."
  (kuro--def-positive-int-setter kuro--test-pi-setter-zero
      "kuro: test must be positive integer, got: %s"
      "Test setter."
    nil)
  (should-error (kuro--test-pi-setter-zero 'ignored 0) :type 'user-error))

(ert-deftest test-kuro-def-positive-int-setter-rejects-negative ()
  "Generated setter signals user-error for negative values."
  (kuro--def-positive-int-setter kuro--test-pi-setter-neg
      "kuro: test must be positive integer, got: %s"
      "Test setter."
    nil)
  (should-error (kuro--test-pi-setter-neg 'ignored -5) :type 'user-error))

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

(ert-deftest test-kuro-set-input-echo-delay-valid ()
  "kuro--set-input-echo-delay accepts a positive number."
  (let ((orig kuro-input-echo-delay))
    (unwind-protect
        (progn
          (should-not (condition-case err
                          (progn (kuro--set-input-echo-delay
                                  'kuro-input-echo-delay 0.05)
                                 nil)
                        (error err)))
          (should (= kuro-input-echo-delay 0.05)))
      (set-default 'kuro-input-echo-delay orig))))

(ert-deftest test-kuro-set-input-echo-delay-zero ()
  "kuro--set-input-echo-delay accepts zero (non-negative)."
  (let ((orig kuro-input-echo-delay))
    (unwind-protect
        (progn
          (should-not (condition-case err
                          (progn (kuro--set-input-echo-delay
                                  'kuro-input-echo-delay 0)
                                 nil)
                        (error err)))
          (should (= kuro-input-echo-delay 0)))
      (set-default 'kuro-input-echo-delay orig))))

(ert-deftest test-kuro-set-input-echo-delay-negative ()
  "kuro--set-input-echo-delay rejects a negative number."
  (should-error (kuro--set-input-echo-delay 'kuro-input-echo-delay -0.1)
                :type 'user-error))

(ert-deftest test-kuro-set-input-echo-delay-non-number ()
  "kuro--set-input-echo-delay rejects non-number values."
  (should-error (kuro--set-input-echo-delay 'kuro-input-echo-delay "0.01")
                :type 'user-error)
  (should-error (kuro--set-input-echo-delay 'kuro-input-echo-delay nil)
                :type 'user-error))

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
               (lambda () (setq apply-called t))))
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

(ert-deftest test-kuro-set-shell-null-value ()
  "kuro--set-shell accepts nil as value (null means system default)."
  (let ((orig kuro-shell))
    (unwind-protect
        (progn
          (should-not (condition-case err
                          (progn (kuro--set-shell 'kuro-shell nil) nil)
                        (error err)))
          (should (null kuro-shell)))
      (set-default 'kuro-shell orig))))

(ert-deftest test-kuro-set-shell-empty-string ()
  "kuro--set-shell accepts an empty string (treated as no-shell override)."
  (let ((orig kuro-shell))
    (unwind-protect
        (progn
          (should-not (condition-case err
                          (progn (kuro--set-shell 'kuro-shell "") nil)
                        (error err)))
          (should (equal kuro-shell "")))
      (set-default 'kuro-shell orig))))

(ert-deftest test-kuro-set-shell-nonexistent-signals-error ()
  "kuro--set-shell signals user-error for a non-existent shell path."
  (should-error
   (kuro--set-shell 'kuro-shell "/nonexistent/shell/no/such/file")
   :type 'user-error))

(ert-deftest test-kuro-set-shell-valid-executable ()
  "kuro--set-shell accepts a valid shell found on PATH."
  ;; /bin/sh is virtually guaranteed to exist on any Unix-like system.
  (let ((orig kuro-shell))
    (unwind-protect
        (progn
          (should-not (condition-case err
                          (progn (kuro--set-shell 'kuro-shell "/bin/sh") nil)
                        (error err)))
          (should (equal kuro-shell "/bin/sh")))
      (set-default 'kuro-shell orig))))

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

(ert-deftest test-kuro-set-scrollback-size-zero-errors ()
  "kuro--set-scrollback-size signals user-error for zero."
  (should-error (kuro--set-scrollback-size 'kuro-scrollback-size 0)
                :type 'user-error))

(ert-deftest test-kuro-set-scrollback-size-negative-errors ()
  "kuro--set-scrollback-size signals user-error for negative value."
  (should-error (kuro--set-scrollback-size 'kuro-scrollback-size -1)
                :type 'user-error))

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

(ert-deftest test-kuro-set-tui-frame-rate-zero-errors ()
  "kuro--set-tui-frame-rate signals user-error for zero."
  (should-error (kuro--set-tui-frame-rate 'kuro-tui-frame-rate 0)
                :type 'user-error))

(ert-deftest test-kuro-set-tui-frame-rate-negative-errors ()
  "kuro--set-tui-frame-rate signals user-error for negative value."
  (should-error (kuro--set-tui-frame-rate 'kuro-tui-frame-rate -3)
                :type 'user-error))

;;; Group 15: kuro--positive-integer-p additional edge cases

(ert-deftest test-kuro-positive-integer-p-float-one-point-five ()
  "1.5 is a float, not an integer — returns nil."
  (should-not (kuro--positive-integer-p 1.5)))

(ert-deftest test-kuro-positive-integer-p-symbol ()
  "A symbol is not an integer — returns nil."
  (should-not (kuro--positive-integer-p 'foo)))

(ert-deftest test-kuro-positive-integer-p-list ()
  "A list is not an integer — returns nil."
  (should-not (kuro--positive-integer-p '(1))))

;;; Group 16: kuro--check-positive-integer edge cases

(ert-deftest test-kuro-check-positive-integer-float-is-invalid ()
  "kuro--check-positive-integer treats a float as invalid and pushes an error."
  (let ((errors nil)
        (kuro-frame-rate 1.5))
    (kuro--check-positive-integer kuro-frame-rate errors)
    (should (consp errors))
    (should (string-match-p "kuro-frame-rate" (car errors)))))

(ert-deftest test-kuro-check-positive-integer-string-is-invalid ()
  "kuro--check-positive-integer treats a string as invalid and pushes an error."
  (let ((errors nil)
        (kuro-scrollback-size "1000"))
    (kuro--check-positive-integer kuro-scrollback-size errors)
    (should (consp errors))))

;;; Group 17: kuro--broadcast-to-buffers with multiple buffers

(ert-deftest test-kuro-broadcast-to-buffers-calls-fn-in-each-kuro-buffer ()
  "kuro--broadcast-to-buffers calls the function in every kuro-mode buffer."
  (let ((visited nil))
    (cl-letf (((symbol-function 'kuro-mode)
               (lambda () (setq major-mode 'kuro-mode)))
              ((symbol-function 'kuro--test-broadcast-fn)
               (lambda () (push (current-buffer) visited))))
      (let ((buf1 (generate-new-buffer " *kuro-bcast-test-1*"))
            (buf2 (generate-new-buffer " *kuro-bcast-test-2*")))
        (unwind-protect
            (progn
              (with-current-buffer buf1 (funcall 'kuro-mode))
              (with-current-buffer buf2 (funcall 'kuro-mode))
              (kuro--broadcast-to-buffers kuro--test-broadcast-fn)
              (should (memq buf1 visited))
              (should (memq buf2 visited)))
          (kill-buffer buf1)
          (kill-buffer buf2))))))

;;; Group 18: kuro--validate-config additional coverage

(ert-deftest test-kuro-validate-config-positive-font-size-no-error ()
  "A positive font size produces no font-size error."
  (let ((kuro-font-size 14))
    (let ((errors (kuro--validate-config)))
      (should-not (cl-some (lambda (e) (string-match-p "font-size" e)) errors)))))

(ert-deftest test-kuro-validate-config-zero-tui-frame-rate ()
  "Zero tui-frame-rate produces an error."
  (let ((kuro-tui-frame-rate 0))
    (let ((errors (kuro--validate-config)))
      (should (consp errors))
      (should (cl-some (lambda (e) (string-match-p "tui-frame-rate" e)) errors)))))

(ert-deftest test-kuro-validate-config-color-uppercase-hex-valid ()
  "An uppercase 6-digit hex color like #AABBCC is valid."
  (let ((kuro-color-blue "#AABBCC"))
    (let ((errors (kuro--validate-config)))
      (should-not (cl-some (lambda (e) (string-match-p "kuro-color-blue" e))
                           errors)))))

(ert-deftest test-kuro-validate-config-shell-null-is-valid ()
  "nil kuro-shell is valid (no shell error produced)."
  (let ((kuro-shell nil))
    (let ((errors (kuro--validate-config)))
      (should-not (cl-some (lambda (e) (string-match-p "shell" e)) errors)))))

;;; Group 19: kuro--validate-config — color string edge cases

(ert-deftest test-kuro-validate-config-color-no-hash-prefix ()
  "A hex color without the # prefix is rejected."
  (let ((kuro-color-green "00ff00"))
    (let ((errors (kuro--validate-config)))
      (should (cl-some (lambda (e) (string-match-p "kuro-color-green" e)) errors)))))

(ert-deftest test-kuro-validate-config-color-too-short ()
  "A 5-digit hex color is rejected."
  (let ((kuro-color-yellow "#abcde"))
    (let ((errors (kuro--validate-config)))
      (should (cl-some (lambda (e) (string-match-p "kuro-color-yellow" e)) errors)))))

(ert-deftest test-kuro-validate-config-color-too-long ()
  "An 8-digit hex color (RGBA) is rejected — must be exactly 6 digits."
  (let ((kuro-color-cyan "#aabbccdd"))
    (let ((errors (kuro--validate-config)))
      (should (cl-some (lambda (e) (string-match-p "kuro-color-cyan" e)) errors)))))

(ert-deftest test-kuro-validate-config-color-nil-rejected ()
  "nil as a color value is rejected."
  (let ((kuro-color-magenta nil))
    (let ((errors (kuro--validate-config)))
      (should (cl-some (lambda (e) (string-match-p "kuro-color-magenta" e)) errors)))))

(ert-deftest test-kuro-validate-config-shell-empty-string-is-valid ()
  "An empty string kuro-shell is valid (no shell error)."
  (let ((kuro-shell ""))
    (let ((errors (kuro--validate-config)))
      (should-not (cl-some (lambda (e) (string-match-p "shell" e)) errors)))))

(ert-deftest test-kuro-validate-config-negative-frame-rate-errors ()
  "A negative frame-rate produces an error mentioning frame-rate."
  (let ((kuro-frame-rate -10))
    (let ((errors (kuro--validate-config)))
      (should (cl-some (lambda (e) (string-match-p "frame-rate" e)) errors)))))

;;; Group 20: kuro-validate-config interactive wrapper — error message branch

(ert-deftest test-kuro-validate-config-interactive-error-branch ()
  "kuro-validate-config prints error count in message when errors exist."
  (let ((msgs nil))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) msgs))))
      (let ((kuro-scrollback-size -1)
            (kuro-frame-rate 0))
        (kuro-validate-config)))
    (should (cl-some (lambda (m) (string-match-p "error" m)) msgs))))

(ert-deftest test-kuro-validate-config-interactive-ok-branch ()
  "kuro-validate-config prints 'valid' message when all settings are correct."
  (let ((msgs nil))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) msgs))))
      (kuro-validate-config))
    (should (cl-some (lambda (m) (string-match-p "valid" m)) msgs))))

;;; Group 21: defcustom default values and constants

(ert-deftest test-kuro-default-rows-constant ()
  "kuro--default-rows is 24."
  (should (= kuro--default-rows 24)))

(ert-deftest test-kuro-default-cols-constant ()
  "kuro--default-cols is 80."
  (should (= kuro--default-cols 80)))

(ert-deftest test-kuro-scrollback-size-default ()
  "kuro-scrollback-size defaults to 10000."
  (should (= (default-value 'kuro-scrollback-size) 10000)))

(ert-deftest test-kuro-frame-rate-default ()
  "kuro-frame-rate defaults to 120."
  (should (= (default-value 'kuro-frame-rate) 120)))

(ert-deftest test-kuro-tui-frame-rate-default ()
  "kuro-tui-frame-rate defaults to 5."
  (should (= (default-value 'kuro-tui-frame-rate) 5)))

(ert-deftest test-kuro-input-echo-delay-default ()
  "kuro-input-echo-delay defaults to 0.01."
  (should (= (default-value 'kuro-input-echo-delay) 0.01)))

;;; Group 22: kuro--check-positive-integer — nil and multi-accumulation

(ert-deftest test-kuro-check-positive-integer-nil-is-invalid ()
  "kuro--check-positive-integer treats nil as invalid."
  (let ((errors nil)
        (kuro-scrollback-size nil))
    (kuro--check-positive-integer kuro-scrollback-size errors)
    (should (consp errors))))

(ert-deftest test-kuro-check-positive-integer-accumulates-multiple ()
  "kuro--check-positive-integer pushes onto an existing error list (now 2 items)."
  (let ((errors '("pre-existing error"))
        (kuro-frame-rate 0))
    (kuro--check-positive-integer kuro-frame-rate errors)
    ;; push prepends: new error is at car, pre-existing is at cadr.
    (should (= (length errors) 2))
    (should (string-match-p "kuro-frame-rate" (car errors)))
    (should (string= (cadr errors) "pre-existing error"))))

(ert-deftest test-kuro-check-positive-integer-string-value ()
  "kuro--check-positive-integer treats a string value as invalid."
  (let ((errors nil)
        (kuro-tui-frame-rate "5"))
    (kuro--check-positive-integer kuro-tui-frame-rate errors)
    (should (consp errors))
    (should (string-match-p "kuro-tui-frame-rate" (car errors)))))

(ert-deftest test-kuro-check-positive-integer-large-value-valid ()
  "kuro--check-positive-integer treats a large positive integer as valid."
  (let ((errors nil)
        (kuro-scrollback-size 1000000))
    (kuro--check-positive-integer kuro-scrollback-size errors)
    (should (null errors))))

(provide 'kuro-config-test)

;;; kuro-config-test.el ends here
