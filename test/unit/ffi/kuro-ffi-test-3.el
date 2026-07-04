;;; kuro-ffi-test-3.el --- Unit tests for kuro-ffi.el (part 3)  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-ffi)
(require 'kuro-binary-decoder)

;;; Group 26: kuro--define-ffi-getters macro — structural coverage

(ert-deftest kuro-ffi-define-ffi-getters-expands-to-progn ()
  "`kuro--define-ffi-getters' expands to a `progn' wrapper."
  (let ((exp (macroexpand-1
              '(kuro--define-ffi-getters
                (kuro-test--fake-getter kuro-rs-fake nil "doc")))))
    (should (eq (car exp) 'progn))))

(ert-deftest kuro-ffi-define-ffi-getters-produces-def-ffi-getter-calls ()
  "`kuro--define-ffi-getters' body contains `kuro--def-ffi-getter' forms."
  (let* ((exp (macroexpand-1
               '(kuro--define-ffi-getters
                 (kuro-test--fake-getter kuro-rs-fake nil "doc"))))
         (body (cdr exp)))
    (should (= (length body) 1))
    (should (eq (car (car body)) 'kuro--def-ffi-getter))))

(ert-deftest kuro-ffi-define-ffi-getters-multi-entry-count ()
  "`kuro--define-ffi-getters' with N entries produces N `kuro--def-ffi-getter' forms."
  (let* ((exp (macroexpand-1
               '(kuro--define-ffi-getters
                 (kuro-test--fg1 kuro-rs-fg1 nil "doc1")
                 (kuro-test--fg2 kuro-rs-fg2 nil "doc2")
                 (kuro-test--fg3 kuro-rs-fg3 nil "doc3"))))
         (body (cdr exp)))
    (should (= (length body) 3))
    (should (cl-every (lambda (form) (eq (car form) 'kuro--def-ffi-getter)) body))))

;;; Group 27: kuro--define-ffi-unary-getters macro — structural coverage

(ert-deftest kuro-ffi-define-ffi-unary-getters-expands-to-progn ()
  "`kuro--define-ffi-unary-getters' expands to a `progn' wrapper."
  (let ((exp (macroexpand-1
              '(kuro--define-ffi-unary-getters
                (kuro-test--fake-unary kuro-rs-fake nil arg "doc")))))
    (should (eq (car exp) 'progn))))

(ert-deftest kuro-ffi-define-ffi-unary-getters-body-contains-def-ffi-unary ()
  "`kuro--define-ffi-unary-getters' body contains `kuro--def-ffi-unary' forms."
  (let* ((exp (macroexpand-1
               '(kuro--define-ffi-unary-getters
                 (kuro-test--fake-unary kuro-rs-fake nil arg "doc"))))
         (body (cdr exp)))
    (should (= (length body) 1))
    (should (eq (car (car body)) 'kuro--def-ffi-unary))))

;;; Group 28: kuro--decode-face-range-step macro — compile-time specialization

(ert-deftest kuro-ffi-decode-face-range-step-v1-expands-to-let* ()
  "`kuro--decode-face-range-step' with nil UL-P (v1 path) expands to `let*'."
  (let ((exp (macroexpand-1
              '(kuro--decode-face-range-step r v p b nil))))
    (should (eq (car exp) 'let*))))

(ert-deftest kuro-ffi-decode-face-range-step-v2-expands-to-let* ()
  "`kuro--decode-face-range-step' with non-nil UL-P (v2 path) expands to `let*'."
  (let ((exp (macroexpand-1
              '(kuro--decode-face-range-step r v p b t))))
    (should (eq (car exp) 'let*))))

(ert-deftest kuro-ffi-decode-face-range-step-v2-has-more-bindings-than-v1 ()
  "`kuro--decode-face-range-step' v2 expansion has more `let*' bindings than v1.
v1 is a 24-byte stride (no underline-color); v2 is 28-byte stride (with
underline-color at wire offset +24).  The v2 path therefore introduces
additional gensyms for the extra field positions."
  (let ((v1-bindings (cadr (macroexpand-1
                            '(kuro--decode-face-range-step r v p b nil))))
        (v2-bindings (cadr (macroexpand-1
                            '(kuro--decode-face-range-step r v p b t)))))
    (should (> (length v2-bindings) (length v1-bindings)))))

(provide 'kuro-ffi-test-3)
;;; kuro-ffi-test-3.el ends here
