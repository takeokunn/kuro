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

;;; Group 25: kuro--set-keymap-exceptions

(ert-deftest kuro-config-set-keymap-exceptions-sets-default-value ()
  "kuro--set-keymap-exceptions calls set-default-toplevel-value with symbol and value."
  (let ((set-sym nil) (set-val nil))
    (cl-letf (((symbol-function 'set-default-toplevel-value)
               (lambda (s v) (setq set-sym s set-val v)))
              ((symbol-function 'kuro--build-keymap) #'ignore)
              ((symbol-function 'kuro--kuro-buffers) (lambda () nil)))
      (kuro--set-keymap-exceptions 'kuro-keymap-exceptions '(some-key))
      (should (eq set-sym 'kuro-keymap-exceptions))
      (should (equal set-val '(some-key))))))

(ert-deftest kuro-config-set-keymap-exceptions-calls-build-keymap-when-bound ()
  "kuro--set-keymap-exceptions calls kuro--build-keymap when it is fboundp."
  (let ((built nil))
    (cl-letf (((symbol-function 'set-default-toplevel-value) #'ignore)
              ((symbol-function 'kuro--build-keymap)
               (lambda () (setq built t)))
              ((symbol-function 'kuro--kuro-buffers) (lambda () nil)))
      (kuro--set-keymap-exceptions 'kuro-keymap-exceptions nil)
      (should built))))

(ert-deftest kuro-config-set-keymap-exceptions-skips-build-when-not-bound ()
  "kuro--set-keymap-exceptions skips kuro--build-keymap when it is not fboundp."
  (let ((built nil))
    (cl-letf (((symbol-function 'set-default-toplevel-value) #'ignore)
              ((symbol-function 'kuro--kuro-buffers) (lambda () nil))
              ((symbol-function 'fboundp)
               (lambda (sym) (not (eq sym 'kuro--build-keymap)))))
      ;; Should not error even though build-keymap is unavailable
      (kuro--set-keymap-exceptions 'kuro-keymap-exceptions nil)
      (should-not built))))

;;; Group 26: kuro--in-all-buffers macro

(ert-deftest kuro-config-ext-test-in-all-buffers-empty-list-no-exec ()
  "`kuro--in-all-buffers' does not evaluate body when buffer list is empty."
  (let (called)
    (cl-letf (((symbol-function 'kuro--kuro-buffers) (lambda () nil)))
      (kuro--in-all-buffers (setq called t)))
    (should-not called)))

(ert-deftest kuro-config-ext-test-in-all-buffers-single-buf-executes-once ()
  "`kuro--in-all-buffers' evaluates body exactly once for a single buffer."
  (let ((count 0)
        (buf (get-buffer-create " *kuro-in-all-test-1*")))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro--kuro-buffers) (lambda () (list buf))))
          (kuro--in-all-buffers (cl-incf count))
          (should (= count 1)))
      (kill-buffer buf))))

(ert-deftest kuro-config-ext-test-in-all-buffers-body-runs-with-buf-current ()
  "`kuro--in-all-buffers' evaluates body with each buffer current."
  (let ((buf (get-buffer-create " *kuro-in-all-test-2*"))
        captured)
    (unwind-protect
        (cl-letf (((symbol-function 'kuro--kuro-buffers) (lambda () (list buf))))
          (kuro--in-all-buffers (setq captured (current-buffer)))
          (should (eq captured buf)))
      (kill-buffer buf))))

(ert-deftest kuro-config-ext-test-in-all-buffers-multi-buf-iterates-all ()
  "`kuro--in-all-buffers' visits all buffers in the list."
  (let ((b1 (get-buffer-create " *kuro-in-all-test-3a*"))
        (b2 (get-buffer-create " *kuro-in-all-test-3b*"))
        visited)
    (unwind-protect
        (cl-letf (((symbol-function 'kuro--kuro-buffers) (lambda () (list b1 b2))))
          (kuro--in-all-buffers (push (current-buffer) visited))
          (should (= (length visited) 2))
          (should (member b1 visited))
          (should (member b2 visited)))
      (kill-buffer b1)
      (kill-buffer b2))))

;;; Group 27: kuro--defvar-permanent-local macro

(ert-deftest kuro-config-ext-test-defvar-permanent-local-sets-property ()
  "`kuro--defvar-permanent-local' sets the permanent-local property to t."
  ;; Evaluate the macro with a fresh test symbol so we are not relying on
  ;; kuro-ffi.el's pre-existing variables (tested separately in kuro-ffi-ext2).
  (let ((sym (gensym "kuro-perm-local-test-")))
    (eval `(kuro--defvar-permanent-local ,sym nil "test var") t)
    (should (eq t (get sym 'permanent-local)))))

(ert-deftest kuro-config-ext-test-defvar-permanent-local-variable-is-defvarred ()
  "`kuro--defvar-permanent-local' produces a bound (defvar'd) variable."
  (let ((sym (gensym "kuro-perm-local-bound-")))
    (eval `(kuro--defvar-permanent-local ,sym :initial-value "bound test") t)
    (should (boundp sym))))

(ert-deftest kuro-config-ext-test-defvar-permanent-local-survives-kill-all-local-variables ()
  "A permanent-local variable retains its buffer-local value after `kill-all-local-variables'."
  ;; Use an existing kuro variable that is already declared permanent-local so
  ;; we exercise the real survival semantics without needing to defvar-local
  ;; a gensym (which would require more setup to be buffer-local).
  (with-temp-buffer
    ;; kuro--initialized is declared permanent-local via kuro--defvar-permanent-local.
    (setq kuro--initialized :test-marker)
    ;; kill-all-local-variables clears ordinary buffer-locals but must NOT
    ;; clear permanent-local ones.
    (kill-all-local-variables)
    (should (eq kuro--initialized :test-marker))))

;;; Coverage gap: kuro-validate-config error path + kuro--set-shell nil/empty paths

(ert-deftest test-kuro-validate-config-error-path-message-format ()
  "kuro-validate-config reports errors via `message' with count and details.
The error message includes the error count and joined error strings."
  (let ((messages nil))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) messages)))
              ((symbol-function 'kuro--validate-config)
               (lambda () (list "error A" "error B"))))
      (kuro-validate-config)
      (should (= 1 (length messages)))
      (should (string-match-p "2" (car messages)))
      (should (string-match-p "error A" (car messages)))
      (should (string-match-p "error B" (car messages))))))

(ert-deftest test-kuro-validate-config-no-errors-message ()
  "kuro-validate-config reports the valid message when there are no errors."
  (let ((messages nil))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) messages)))
              ((symbol-function 'kuro--validate-config)
               (lambda () nil)))
      (kuro-validate-config)
      (should (= 1 (length messages)))
      (should (string-match-p "valid" (car messages))))))

(ert-deftest test-kuro-set-shell-nil-is-valid ()
  "kuro--set-shell accepts nil (no shell configured)."
  (let ((orig kuro-shell))
    (unwind-protect
        (should-not (condition-case err
                        (progn (kuro--set-shell 'kuro-shell nil) nil)
                      (error err)))
      (set-default 'kuro-shell orig))))

(ert-deftest test-kuro-set-shell-empty-string-is-valid ()
  "kuro--set-shell accepts an empty string."
  (let ((orig kuro-shell))
    (unwind-protect
        (should-not (condition-case err
                        (progn (kuro--set-shell 'kuro-shell "") nil)
                      (error err)))
      (set-default 'kuro-shell orig))))

(provide 'kuro-config-test-2)

;;; kuro-config-test-2.el ends here
