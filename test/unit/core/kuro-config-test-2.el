;;; kuro-config-test-2.el --- Unit tests for kuro-config.el (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-config)

;;; Group 15: kuro--positive-integer-p additional edge cases

(defconst kuro-config-test--positive-integer-p-rejects-table
  '((test-kuro-positive-integer-p-float-one-point-five 1.5)
    (test-kuro-positive-integer-p-symbol               foo)
    (test-kuro-positive-integer-p-list                 (1)))
  "Table of (test-name value) for non-integer inputs rejected by `kuro--positive-integer-p'.")

(defmacro kuro-config-test--def-positive-integer-p-rejects (test-name value)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--positive-integer-p' rejects %s." value)
     (should-not (kuro--positive-integer-p ',value))))

(kuro-config-test--def-positive-integer-p-rejects test-kuro-positive-integer-p-float-one-point-five 1.5)
(kuro-config-test--def-positive-integer-p-rejects test-kuro-positive-integer-p-symbol               foo)
(kuro-config-test--def-positive-integer-p-rejects test-kuro-positive-integer-p-list                 (1))

(ert-deftest kuro-config-test--all-positive-integer-p-rejects-correct ()
  "All entries in `kuro-config-test--positive-integer-p-rejects-table' are rejected."
  (dolist (entry kuro-config-test--positive-integer-p-rejects-table)
    (pcase-let ((`(,_name ,value) entry))
      (should-not (kuro--positive-integer-p value)))))

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

(defconst kuro-config-test--invalid-color-table
  '((test-kuro-validate-config-color-no-hash-prefix kuro-color-green   "00ff00")
    (test-kuro-validate-config-color-too-short       kuro-color-yellow  "#abcde")
    (test-kuro-validate-config-color-too-long        kuro-color-cyan    "#aabbccdd")
    (test-kuro-validate-config-color-nil-rejected    kuro-color-magenta nil))
  "Table of (test-name color-var invalid-value) for invalid color rejection in kuro--validate-config.")

(defmacro kuro-config-test--def-invalid-color (test-name color-var invalid-value)
  `(ert-deftest ,test-name ()
     ,(format "kuro--validate-config rejects `%s' set to %S." color-var invalid-value)
     (let ((,color-var ,invalid-value))
       (let ((errors (kuro--validate-config)))
         (should (cl-some (lambda (e) (string-match-p ,(symbol-name color-var) e)) errors))))))

(kuro-config-test--def-invalid-color test-kuro-validate-config-color-no-hash-prefix kuro-color-green   "00ff00")
(kuro-config-test--def-invalid-color test-kuro-validate-config-color-too-short       kuro-color-yellow  "#abcde")
(kuro-config-test--def-invalid-color test-kuro-validate-config-color-too-long        kuro-color-cyan    "#aabbccdd")
(kuro-config-test--def-invalid-color test-kuro-validate-config-color-nil-rejected    kuro-color-magenta nil)

(ert-deftest kuro-config-test--all-invalid-colors-rejected ()
  "Every entry in `kuro-config-test--invalid-color-table' produces a validation error."
  (dolist (entry kuro-config-test--invalid-color-table)
    (pcase-let ((`(,_name ,var ,val) entry))
      (cl-progv (list var) (list val)
        (let ((errors (kuro--validate-config)))
          (should (cl-some (lambda (e) (string-match-p (symbol-name var) e)) errors)))))))

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

(defconst kuro-config-test--constant-value-table
  '((test-kuro-default-rows-constant    const     kuro--default-rows    24)
    (test-kuro-default-cols-constant    const     kuro--default-cols    80)
    (test-kuro-scrollback-size-default  defcustom kuro-scrollback-size  10000)
    (test-kuro-frame-rate-default       defcustom kuro-frame-rate       120)
    (test-kuro-tui-frame-rate-default   defcustom kuro-tui-frame-rate   5)
    (test-kuro-input-echo-delay-default defcustom kuro-input-echo-delay 0.01))
  "Table of (test-name type var-sym expected) for constant and defcustom default value checks.")

(defmacro kuro-config-test--def-constant (test-name type var-sym expected)
  `(ert-deftest ,test-name ()
     ,(format "%s `%s' equals %S." (if (eq type 'defcustom) "Default of" "Constant") var-sym expected)
     ,(if (eq type 'defcustom)
          `(should (equal (default-value ',var-sym) ,expected))
        `(should (equal ,var-sym ,expected)))))

(kuro-config-test--def-constant test-kuro-default-rows-constant    const     kuro--default-rows    24)
(kuro-config-test--def-constant test-kuro-default-cols-constant    const     kuro--default-cols    80)
(kuro-config-test--def-constant test-kuro-scrollback-size-default  defcustom kuro-scrollback-size  10000)
(kuro-config-test--def-constant test-kuro-frame-rate-default       defcustom kuro-frame-rate       120)
(kuro-config-test--def-constant test-kuro-tui-frame-rate-default   defcustom kuro-tui-frame-rate   5)
(kuro-config-test--def-constant test-kuro-input-echo-delay-default defcustom kuro-input-echo-delay 0.01)

(ert-deftest kuro-config-test--all-constant-values-correct ()
  "Every entry in `kuro-config-test--constant-value-table' has the expected value."
  (dolist (entry kuro-config-test--constant-value-table)
    (pcase-let ((`(,_name ,type ,var-sym ,expected) entry))
      (if (eq type 'defcustom)
          (should (equal (default-value var-sym) expected))
        (should (equal (symbol-value var-sym) expected))))))

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

;;; Group 22b: positive-integer validation tables

(ert-deftest test-kuro-positive-integer-config-vars-enumerates-required-settings ()
  "`kuro--positive-integer-config-vars' lists all required positive integer settings."
  (should (equal kuro--positive-integer-config-vars
                 '(kuro-scrollback-size
                   kuro-frame-rate
                   kuro-tui-frame-rate))))

(ert-deftest test-kuro-optional-positive-integer-config-vars-enumerates-optional-settings ()
  "`kuro--optional-positive-integer-config-vars' lists nullable positive integer settings."
  (should (equal kuro--optional-positive-integer-config-vars
                 '(kuro-font-size))))

(ert-deftest test-kuro-check-positive-integer-vars-accumulates-symbol-errors ()
  "`kuro--check-positive-integer-vars' pushes errors for invalid symbol values."
  (let ((errors nil)
        (kuro-frame-rate 0)
        (kuro-tui-frame-rate "5"))
    (kuro--check-positive-integer-vars
     '(kuro-frame-rate kuro-tui-frame-rate) errors)
    (should (= (length errors) 2))
    (should (cl-some (lambda (e) (string-match-p "kuro-frame-rate" e)) errors))
    (should (cl-some (lambda (e) (string-match-p "kuro-tui-frame-rate" e)) errors))))

(ert-deftest test-kuro-check-optional-positive-integer-vars-skips-nil ()
  "`kuro--check-optional-positive-integer-vars' accepts nil and rejects bad values."
  (let ((errors nil)
        (kuro-font-size nil))
    (kuro--check-optional-positive-integer-vars '(kuro-font-size) errors)
    (should (null errors))
    (setq kuro-font-size -1)
    (kuro--check-optional-positive-integer-vars '(kuro-font-size) errors)
    (should (= (length errors) 1))
    (should (string-match-p "kuro-font-size" (car errors)))))

;;; Group 23: kuro--check-hex-color macro

(ert-deftest test-kuro-check-hex-color-valid-lowercase ()
  "kuro--check-hex-color accepts a valid lowercase 6-digit hex color."
  (let ((errors nil))
    (kuro--check-hex-color 'kuro-color-black errors)
    (should (null errors))))

(defconst kuro-config-test--check-hex-color-invalid-table
  '((test-kuro-check-hex-color-invalid-short      kuro-color-red   "#fff")
    (test-kuro-check-hex-color-invalid-no-hash    kuro-color-green "00ff00")
    (test-kuro-check-hex-color-invalid-non-string kuro-color-blue  42))
  "Table of (test-name var-sym bad-value) for `kuro--check-hex-color' rejection cases.")

(defmacro kuro-config-test--def-check-hex-color-invalid (test-name var-sym bad-value)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--check-hex-color' rejects %s = %s." var-sym bad-value)
     (let ((errors nil)
           (,var-sym ,bad-value))
       (kuro--check-hex-color ',var-sym errors)
       (should (consp errors))
       (should (string-match-p ,(symbol-name var-sym) (car errors))))))

(kuro-config-test--def-check-hex-color-invalid test-kuro-check-hex-color-invalid-short      kuro-color-red   "#fff")
(kuro-config-test--def-check-hex-color-invalid test-kuro-check-hex-color-invalid-no-hash    kuro-color-green "00ff00")
(kuro-config-test--def-check-hex-color-invalid test-kuro-check-hex-color-invalid-non-string kuro-color-blue  42)

(ert-deftest kuro-config-test--all-check-hex-color-invalid-correct ()
  "All entries in `kuro-config-test--check-hex-color-invalid-table' are rejected with name in error."
  (dolist (entry kuro-config-test--check-hex-color-invalid-table)
    (pcase-let ((`(,_name ,var-sym ,bad-value) entry))
      (let ((errors nil))
        (cl-letf (((symbol-value var-sym) bad-value))
          (kuro--check-hex-color var-sym errors)
          (should (consp errors))
          (should (string-match-p (symbol-name var-sym) (car errors))))))))

(ert-deftest test-kuro-check-hex-color-accumulates-errors ()
  "kuro--check-hex-color pushes onto an existing error list."
  (let ((errors '("pre-existing"))
        (kuro-color-yellow "bad"))
    (kuro--check-hex-color 'kuro-color-yellow errors)
    (should (= (length errors) 2))
    (should (string= (cadr errors) "pre-existing"))))

;;; Group 24: kuro--color-defcustom-vars enumeration

(ert-deftest test-kuro-color-defcustom-vars-count ()
  "kuro--color-defcustom-vars contains exactly 16 color variable symbols."
  (should (= (length kuro--color-defcustom-vars) 16)))

(ert-deftest test-kuro-color-defcustom-vars-all-bound ()
  "All variables in kuro--color-defcustom-vars are bound."
  (dolist (v kuro--color-defcustom-vars)
    (should (boundp v))))

(ert-deftest test-kuro-color-defcustom-vars-all-hex-strings ()
  "All variables in kuro--color-defcustom-vars are valid 6-digit hex colors."
  (dolist (v kuro--color-defcustom-vars)
    (should (string-match-p "^#[0-9a-fA-F]\\{6\\}$" (symbol-value v)))))

(defconst kuro-config-test--color-defcustom-membership-table
  '((test-kuro-color-defcustom-vars-contains-black        kuro-color-black)
    (test-kuro-color-defcustom-vars-contains-bright-white kuro-color-bright-white))
  "Table of (test-name color-sym) for kuro--color-defcustom-vars membership checks.")

(defmacro kuro-config-test--def-color-membership (test-name color-sym)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--color-defcustom-vars' contains `%s'." color-sym)
     (should (memq ',color-sym kuro--color-defcustom-vars))))

(kuro-config-test--def-color-membership test-kuro-color-defcustom-vars-contains-black        kuro-color-black)
(kuro-config-test--def-color-membership test-kuro-color-defcustom-vars-contains-bright-white kuro-color-bright-white)

(ert-deftest kuro-config-test--all-color-memberships-present ()
  "Every entry in `kuro-config-test--color-defcustom-membership-table' is in the list."
  (dolist (entry kuro-config-test--color-defcustom-membership-table)
    (pcase-let ((`(,_name ,color-sym) entry))
      (should (memq color-sym kuro--color-defcustom-vars)))))

;;; Group 27: kuro--set-shell

(ert-deftest test-kuro-set-shell-accepts-nil ()
  "`kuro--set-shell' accepts nil without signaling."
  (let ((sym (make-symbol "kuro-shell-test")))
    (set sym "old")
    (should-not (condition-case err
                    (progn (kuro--set-shell sym nil) nil)
                  (user-error err)))
    (should (null (symbol-value sym)))))

(ert-deftest test-kuro-set-shell-accepts-empty-string ()
  "`kuro--set-shell' accepts the empty string (treated like nil)."
  (let ((sym (make-symbol "kuro-shell-test")))
    (set sym "old")
    (kuro--set-shell sym "")
    (should (equal "" (symbol-value sym)))))

(ert-deftest test-kuro-set-shell-rejects-nonexistent-executable ()
  "`kuro--set-shell' signals user-error for a nonexistent program."
  (let ((sym (make-symbol "kuro-shell-test")))
    (set sym "old")
    (should-error (kuro--set-shell sym "/no/such/executable/x9zq")
                  :type 'user-error)))

;;; Group 28: kuro--with-mode / kuro--with-kuro-mode

(ert-deftest test-kuro-with-mode-runs-body-in-matching-mode ()
  "`kuro--with-mode' executes BODY when `derived-mode-p' matches."
  (with-temp-buffer
    (text-mode)
    (should (eq :ok (kuro--with-mode text-mode "wrong mode" :ok)))))

(ert-deftest test-kuro-with-mode-signals-user-error-in-wrong-mode ()
  "`kuro--with-mode' raises user-error when the major mode does not match."
  (with-temp-buffer
    (fundamental-mode)
    (should-error (kuro--with-mode text-mode "wrong mode" :ok)
                  :type 'user-error)))

(ert-deftest test-kuro-with-kuro-mode-signals-in-non-kuro-buffer ()
  "`kuro--with-kuro-mode' raises user-error outside kuro-mode."
  (with-temp-buffer
    (fundamental-mode)
    (should-error (kuro--with-kuro-mode :ok)
                  :type 'user-error)))

(provide 'kuro-config-test-2)

;;; kuro-config-test-2.el ends here
