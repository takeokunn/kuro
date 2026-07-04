;;; kuro-config-test-4.el --- Unit tests for kuro-config.el (part 4)  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Bootstrap the FFI macro directory for tests that run without the full
;; emacs-lisp tree on `load-path'.
(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (ffi-dir (expand-file-name "../../../emacs-lisp/ffi" this-dir)))
  (add-to-list 'load-path ffi-dir t))
(require 'kuro-ffi-macros)
(require 'kuro-config)

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

(defmacro kuro-config-test--with-fresh-permanent-local (value &rest body)
  "Bind SYM to a fresh symbol and define it as a permanent-local variable."
  (declare (indent 1))
  (let ((sym (make-symbol "kuro-perm-local-test-")))
    `(let ((sym ',sym))
       (kuro--defvar-permanent-local ,sym ,value "test var")
       ,@body)))

(ert-deftest kuro-config-ext-test-defvar-permanent-local-sets-property ()
  "`kuro--defvar-permanent-local' sets the permanent-local property to t."
  ;; Evaluate the macro with a fresh test symbol so we are not relying on
  ;; kuro-ffi.el's pre-existing variables (tested separately in kuro-ffi-ext2).
  (kuro-config-test--with-fresh-permanent-local nil
    (should (eq t (get sym 'permanent-local)))))

(ert-deftest kuro-config-ext-test-defvar-permanent-local-variable-is-defvarred ()
  "`kuro--defvar-permanent-local' produces a bound (defvar'd) variable."
  (kuro-config-test--with-fresh-permanent-local :initial-value
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

;;; Group 28: kuro--with-kuro-mode macro

(ert-deftest kuro-config-with-kuro-mode-executes-body-in-kuro-mode ()
  "`kuro--with-kuro-mode' evaluates BODY when `derived-mode-p' returns non-nil."
  (let (executed)
    (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t)))
      (kuro--with-kuro-mode (setq executed t)))
    (should executed)))

(ert-deftest kuro-config-with-kuro-mode-signals-user-error-outside-kuro-mode ()
  "`kuro--with-kuro-mode' signals `user-error' when `derived-mode-p' returns nil."
  (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) nil)))
    (should-error (kuro--with-kuro-mode (error "should not reach"))
                  :type 'user-error)))

(ert-deftest kuro-config-with-kuro-mode-returns-body-value ()
  "`kuro--with-kuro-mode' returns the value of the last body form."
  (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t)))
    (should (equal 42 (kuro--with-kuro-mode 42)))))

(ert-deftest kuro-config-with-kuro-mode-error-message-lowercase ()
  "`kuro--with-kuro-mode' error message uses lowercase \"kuro buffer\"."
  (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) nil)))
    (let ((err (should-error (kuro--with-kuro-mode t) :type 'user-error)))
      (should (string-match-p "kuro buffer" (cadr err))))))

(ert-deftest kuro-config-with-kuro-mode-multi-body-forms ()
  "`kuro--with-kuro-mode' evaluates multiple body forms in sequence."
  (let (log)
    (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t)))
      (kuro--with-kuro-mode
       (push 1 log)
       (push 2 log)
       (push 3 log)))
    (should (equal (nreverse log) '(1 2 3)))))

;;; Group 29: kuro--with-mode macro (base form)

(ert-deftest kuro-config-with-mode-executes-body-when-in-mode ()
  "`kuro--with-mode' evaluates BODY when `derived-mode-p' matches the given mode."
  (let (executed)
    (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t)))
      (kuro--with-mode kuro-mode "Not in kuro" (setq executed t)))
    (should executed)))

(ert-deftest kuro-config-with-mode-signals-user-error-outside-mode ()
  "`kuro--with-mode' signals `user-error' with MSG when not in MODE."
  (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) nil)))
    (let ((err (should-error
                (kuro--with-mode some-mode "custom error msg" t)
                :type 'user-error)))
      (should (string-match-p "custom error msg" (cadr err))))))

(ert-deftest kuro-config-with-mode-returns-body-value ()
  "`kuro--with-mode' returns the value of the last body form."
  (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t)))
    (should (equal 99 (kuro--with-mode kuro-mode "err" 99)))))

(ert-deftest kuro-config-with-kuro-mode-delegates-to-with-mode ()
  "`kuro--with-kuro-mode' single-step expands to `kuro--with-mode' for kuro-mode."
  (let ((expansion (macroexpand-1 '(kuro--with-kuro-mode (+ 1 2)))))
    (should (eq (car expansion) 'kuro--with-mode))
    (should (eq (cadr expansion) 'kuro-mode))))

(provide 'kuro-config-test-4)
;;; kuro-config-test-4.el ends here
