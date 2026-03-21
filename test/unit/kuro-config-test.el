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

(provide 'kuro-config-test)

;;; kuro-config-test.el ends here
