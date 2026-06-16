;;; kuro-input-keymap-test-macros.el --- Keymap test helpers and macros  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-input-keymap-test-cases)

;; Stub FFI and input function symbols consumed transitively by
;; kuro-input-keymap.el before loading so the file loads without the module.
(unless (fboundp 'kuro--send-key)
  (defalias 'kuro--send-key (lambda (_data) nil)))
(unless (fboundp 'kuro--schedule-immediate-render)
  (defalias 'kuro--schedule-immediate-render (lambda () nil)))
(unless (fboundp 'kuro--mouse-mode-query)
  (defalias 'kuro--mouse-mode-query (lambda () 0)))
;; kuro-input-keymap.el declare-function stubs (needed if kuro-input is absent)
(dolist (sym '(kuro--self-insert kuro--RET kuro--TAB kuro--DEL
               kuro--arrow-up kuro--arrow-down kuro--arrow-left kuro--arrow-right
               kuro--HOME kuro--END kuro--INSERT kuro--DELETE
               kuro--PAGE-UP kuro--PAGE-DOWN
               kuro-scroll-up kuro-scroll-down kuro-scroll-bottom
               kuro--F1 kuro--F2 kuro--F3 kuro--F4 kuro--F5 kuro--F6
               kuro--F7 kuro--F8 kuro--F9 kuro--F10 kuro--F11 kuro--F12
               kuro--send-ctrl kuro--send-meta))
  (unless (fboundp sym)
    (defalias sym (lambda (&rest _) nil))))
(unless (fboundp 'kuro--yank)
  (defalias 'kuro--yank (lambda () nil)))
(unless (fboundp 'kuro--yank-pop)
  (defalias 'kuro--yank-pop (lambda (&optional _n) nil)))

(require 'kuro-input-keymap)

(defun kuro-keymap-test--built-map ()
  "Return a freshly built Kuro keymap with no exceptions.
Saves and restores `kuro--keymap' so global state is not corrupted."
  (let ((kuro-keymap-exceptions nil)
        (orig kuro--keymap))
    (unwind-protect
        (kuro--build-keymap)
      (setq kuro--keymap orig))))

(defun kuro-input-keymap-test--selected-cases (cases names)
  "Return CASES filtered to NAMES, or all CASES when NAMES is nil."
  (if names
      (cl-remove-if-not (lambda (case) (memq (car case) names)) cases)
    cases))

(defmacro kuro-input-keymap-test--def-setup-binding-case
    (test-name setup-fn binding-specs)
  "Define TEST-NAME asserting SETUP-FN installs BINDING-SPECS."
  `(ert-deftest ,test-name ()
     ,(format "`%s' installs expected key bindings." setup-fn)
     (let ((km (make-sparse-keymap))
           (kuro-keymap-exceptions nil))
       (,setup-fn km)
       ,@(mapcar
          (lambda (spec)
            (pcase-let ((`(,key ,expected) spec))
              (if (eq expected :present)
                  `(should (lookup-key km ,key))
                `(should (eq (lookup-key km ,key) #',expected)))))
          binding-specs))))

(defmacro kuro-input-keymap-test--deftest-setup-binding-cases (&rest names)
  "Define setup binding tests named by NAMES, or all known cases."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,setup-fn ,binding-specs) entry))
            `(kuro-input-keymap-test--def-setup-binding-case
              ,test-name ,setup-fn ,binding-specs)))
        (kuro-input-keymap-test--selected-cases
         kuro-input-keymap-test--setup-binding-cases names))))

(defmacro kuro-input-keymap-test--def-shifted-key-send-case
    (test-name key kkp-enabled expected-sequence)
  "Define TEST-NAME asserting KEY sends EXPECTED-SEQUENCE under KKP-ENABLED."
  `(ert-deftest ,test-name ()
     ,(format "%S sends %S when KKP enabled is %S." key expected-sequence kkp-enabled)
     (let ((sent nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (setq sent s)))
                 ((symbol-function 'kuro--schedule-immediate-render) #'ignore)
                 ((symbol-function 'kuro--kkp-flag-p)
                  (lambda (_) ,kkp-enabled)))
         (let ((map (kuro--build-keymap)))
           (call-interactively (lookup-key map ,key)))
         (should (equal sent ,expected-sequence))))))

(defmacro kuro-input-keymap-test--deftest-shifted-key-send-cases (&rest names)
  "Define shifted key send tests named by NAMES, or all known cases."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,key ,kkp-enabled ,expected-sequence) entry))
            `(kuro-input-keymap-test--def-shifted-key-send-case
              ,test-name ,key ,kkp-enabled ,expected-sequence)))
        (kuro-input-keymap-test--selected-cases
         kuro-input-keymap-test--shifted-key-send-cases names))))

(defmacro kuro-input-keymap-test--def-generated-shifted-key-case
    (test-name command kkp-sequence)
  "Define TEST-NAME asserting generated COMMAND sends KKP-SEQUENCE."
  `(ert-deftest ,test-name ()
     ,(format "`%s' sends KKP seq when DISAMBIGUATE flag is set." command)
     (let ((sent nil))
       (cl-letf (((symbol-function 'kuro--send-key)
                  (lambda (s) (setq sent s)))
                 ((symbol-function 'kuro--schedule-immediate-render) #'ignore)
                 ((symbol-function 'kuro--kkp-flag-p) (lambda (_) t)))
         (funcall #',command)
         (should (equal sent ,kkp-sequence))))))

(defmacro kuro-input-keymap-test--deftest-generated-shifted-key-cases (&rest names)
  "Define generated shifted-key tests named by NAMES, or all known cases."
  `(progn
     ,@(mapcar
        (lambda (entry)
          (pcase-let ((`(,test-name ,command ,kkp-sequence) entry))
            `(kuro-input-keymap-test--def-generated-shifted-key-case
              ,test-name ,command ,kkp-sequence)))
        (kuro-input-keymap-test--selected-cases
         kuro-input-keymap-test--generated-shifted-key-cases names))))

(defmacro kuro-input-keymap-test--deftest-generated-shifted-key-interactive
    (test-name)
  "Define TEST-NAME asserting every generated shifted-key command is interactive."
  `(ert-deftest ,test-name ()
     "All generated shifted-key commands are interactive."
     (dolist (entry kuro-input-keymap-test--generated-shifted-key-cases)
       (should (commandp (symbol-function (nth 1 entry)))))))

(provide 'kuro-input-keymap-test-macros)
;;; kuro-input-keymap-test-macros.el ends here
