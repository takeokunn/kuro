;;; kuro-config-ext-test.el --- Unit tests for kuro-config.el (extended)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the Kuro configuration system (Groups 13–25).
;; These tests cover pure Emacs Lisp functions only and do NOT require
;; the Rust dynamic module (kuro-core-*).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-config)

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

;;; Group 23: kuro--check-hex-color macro

(ert-deftest test-kuro-check-hex-color-valid-lowercase ()
  "kuro--check-hex-color accepts a valid lowercase 6-digit hex color."
  (let ((errors nil))
    (kuro--check-hex-color 'kuro-color-black errors)
    (should (null errors))))

(ert-deftest test-kuro-check-hex-color-invalid-short ()
  "kuro--check-hex-color rejects a 3-digit hex string."
  (let ((errors nil)
        (kuro-color-red "#fff"))
    (kuro--check-hex-color 'kuro-color-red errors)
    (should (consp errors))
    (should (string-match-p "kuro-color-red" (car errors)))))

(ert-deftest test-kuro-check-hex-color-invalid-no-hash ()
  "kuro--check-hex-color rejects a hex string without the # prefix."
  (let ((errors nil)
        (kuro-color-green "00ff00"))
    (kuro--check-hex-color 'kuro-color-green errors)
    (should (consp errors))))

(ert-deftest test-kuro-check-hex-color-invalid-non-string ()
  "kuro--check-hex-color rejects a non-string value."
  (let ((errors nil)
        (kuro-color-blue 42))
    (kuro--check-hex-color 'kuro-color-blue errors)
    (should (consp errors))))

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

(ert-deftest test-kuro-color-defcustom-vars-contains-black ()
  "kuro--color-defcustom-vars includes kuro-color-black."
  (should (memq 'kuro-color-black kuro--color-defcustom-vars)))

(ert-deftest test-kuro-color-defcustom-vars-contains-bright-white ()
  "kuro--color-defcustom-vars includes kuro-color-bright-white."
  (should (memq 'kuro-color-bright-white kuro--color-defcustom-vars)))

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

(provide 'kuro-config-ext-test)

;;; kuro-config-ext-test.el ends here
