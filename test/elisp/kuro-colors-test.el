;;; kuro-colors-test.el --- Unit tests for kuro-colors.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-colors.el (ANSI color palette defcustoms, kuro--named-colors
;; alist, kuro--rebuild-named-colors, and kuro--set-color validator).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Note: kuro-config-test.el already tests kuro--rebuild-named-colors and
;; kuro--set-color via (require 'kuro-config) which loads kuro-colors.el.
;; This file targets kuro-colors.el directly and adds focused coverage.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-colors)

;;; Group 1: kuro--named-colors structure

(ert-deftest kuro-colors--named-colors-is-alist ()
  "kuro--named-colors must be an alist (list of cons cells)."
  (kuro--rebuild-named-colors)
  (should (listp kuro--named-colors))
  (dolist (entry kuro--named-colors)
    (should (consp entry))))

(ert-deftest kuro-colors--named-colors-has-16-entries ()
  "kuro--named-colors must have exactly 16 entries after rebuild."
  (kuro--rebuild-named-colors)
  (should (= (length kuro--named-colors) 16)))

(ert-deftest kuro-colors--named-colors-keys-are-strings ()
  "Every key in kuro--named-colors must be a non-empty string."
  (kuro--rebuild-named-colors)
  (dolist (entry kuro--named-colors)
    (should (stringp (car entry)))
    (should (> (length (car entry)) 0))))

(ert-deftest kuro-colors--named-colors-values-are-hex-strings ()
  "Every value in kuro--named-colors must match #RRGGBB."
  (kuro--rebuild-named-colors)
  (dolist (entry kuro--named-colors)
    (should (stringp (cdr entry)))
    (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" (cdr entry)))))

(ert-deftest kuro-colors--named-colors-contains-all-16-keys ()
  "kuro--named-colors must contain all 16 expected ANSI color name keys."
  (kuro--rebuild-named-colors)
  (dolist (key '("black" "red" "green" "yellow"
                 "blue" "magenta" "cyan" "white"
                 "bright-black" "bright-red" "bright-green" "bright-yellow"
                 "bright-blue" "bright-magenta" "bright-cyan" "bright-white"))
    (should (assoc key kuro--named-colors))))

(ert-deftest kuro-colors--named-colors-bright-black-key ()
  "The bright-black entry key must be \"bright-black\" (hyphenated)."
  (kuro--rebuild-named-colors)
  (let ((entry (assoc "bright-black" kuro--named-colors)))
    (should entry)
    (should (equal (car entry) "bright-black"))))

;;; Group 2: kuro--rebuild-named-colors

(ert-deftest kuro-colors--rebuild-named-colors-reflects-custom-value ()
  "After changing a defcustom variable, rebuild reflects the new hex value."
  (let ((original kuro-color-green))
    (unwind-protect
        (progn
          (setq kuro-color-green "#123456")
          (kuro--rebuild-named-colors)
          (let ((entry (assoc "green" kuro--named-colors)))
            (should entry)
            (should (equal (cdr entry) "#123456"))))
      (setq kuro-color-green original)
      (kuro--rebuild-named-colors))))

(ert-deftest kuro-colors--rebuild-named-colors-idempotent ()
  "Calling kuro--rebuild-named-colors twice produces the same result."
  (kuro--rebuild-named-colors)
  (let ((first-result (copy-sequence kuro--named-colors)))
    (kuro--rebuild-named-colors)
    (should (equal (length kuro--named-colors) (length first-result)))
    (dolist (entry first-result)
      (should (equal (cdr (assoc (car entry) kuro--named-colors))
                     (cdr entry))))))

(ert-deftest kuro-colors--rebuild-named-colors-black-maps-to-defcustom ()
  "\"black\" key value matches kuro-color-black defcustom."
  (kuro--rebuild-named-colors)
  (let ((entry (assoc "black" kuro--named-colors)))
    (should entry)
    (should (equal (cdr entry) kuro-color-black))))

(ert-deftest kuro-colors--rebuild-named-colors-bright-white-maps-to-defcustom ()
  "\"bright-white\" key value matches kuro-color-bright-white defcustom."
  (kuro--rebuild-named-colors)
  (let ((entry (assoc "bright-white" kuro--named-colors)))
    (should entry)
    (should (equal (cdr entry) kuro-color-bright-white))))

;;; Group 3: kuro--set-color validator

(ert-deftest kuro-colors--set-color-accepts-valid-hex ()
  "kuro--set-color accepts a valid 6-digit lowercase hex string."
  (let ((orig kuro-color-cyan))
    (unwind-protect
        (should-not (condition-case err
                        (progn (kuro--set-color 'kuro-color-cyan "#abcdef") nil)
                      (error err)))
      (setq kuro-color-cyan orig)
      (kuro--rebuild-named-colors))))

(ert-deftest kuro-colors--set-color-accepts-uppercase-hex ()
  "kuro--set-color accepts a valid 6-digit uppercase hex string."
  (let ((orig kuro-color-cyan))
    (unwind-protect
        (should-not (condition-case err
                        (progn (kuro--set-color 'kuro-color-cyan "#ABCDEF") nil)
                      (error err)))
      (setq kuro-color-cyan orig)
      (kuro--rebuild-named-colors))))

(ert-deftest kuro-colors--set-color-rejects-non-hex-string ()
  "kuro--set-color signals user-error for a non-hex color string."
  (should-error (kuro--set-color 'kuro-color-red "not-a-color") :type 'user-error))

(ert-deftest kuro-colors--set-color-rejects-short-hex ()
  "kuro--set-color signals user-error for a 3-digit hex string (#fff)."
  (should-error (kuro--set-color 'kuro-color-red "#fff") :type 'user-error))

(ert-deftest kuro-colors--set-color-rejects-missing-hash ()
  "kuro--set-color signals user-error when the leading # is absent."
  (should-error (kuro--set-color 'kuro-color-red "ff0000") :type 'user-error))

(ert-deftest kuro-colors--set-color-rejects-empty-string ()
  "kuro--set-color signals user-error for an empty string."
  (should-error (kuro--set-color 'kuro-color-red "") :type 'user-error))

(ert-deftest kuro-colors--set-color-updates-defcustom-variable ()
  "kuro--set-color sets the defcustom variable to the provided value."
  (let ((orig kuro-color-blue))
    (unwind-protect
        (progn
          (kuro--set-color 'kuro-color-blue "#010203")
          (should (equal kuro-color-blue "#010203")))
      (set-default 'kuro-color-blue orig)
      (kuro--rebuild-named-colors))))

(ert-deftest kuro-colors--set-color-triggers-rebuild ()
  "kuro--set-color causes kuro--named-colors to reflect the new value."
  (let ((orig kuro-color-magenta))
    (unwind-protect
        (progn
          (kuro--set-color 'kuro-color-magenta "#aabbcc")
          (let ((entry (assoc "magenta" kuro--named-colors)))
            (should entry)
            (should (equal (cdr entry) "#aabbcc"))))
      (set-default 'kuro-color-magenta orig)
      (kuro--rebuild-named-colors))))

;;; Group 4: defcustom defaults have expected format

(ert-deftest kuro-colors--all-defcustoms-are-hex-strings ()
  "All 16 kuro-color-* defcustom defaults must be 6-digit hex strings."
  (dolist (sym '(kuro-color-black kuro-color-red kuro-color-green kuro-color-yellow
                 kuro-color-blue kuro-color-magenta kuro-color-cyan kuro-color-white
                 kuro-color-bright-black kuro-color-bright-red kuro-color-bright-green
                 kuro-color-bright-yellow kuro-color-bright-blue kuro-color-bright-magenta
                 kuro-color-bright-cyan kuro-color-bright-white))
    (let ((val (symbol-value sym)))
      (should (stringp val))
      (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" val)))))

(provide 'kuro-colors-test)

;;; kuro-colors-test.el ends here
