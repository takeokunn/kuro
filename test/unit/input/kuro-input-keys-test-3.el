;;; kuro-input-keys-test-3.el --- kuro-input-keys-test (part 3)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-keys-test-support)

;;; Group 21: Kitty Keyboard Protocol (KKP) encoding

(kuro-input-keys-test--deftest-kkp-send-cases)

(ert-deftest kuro-input-keys--g21-kkp-codepoints-are-integers ()
  "All KKP codepoint constants are positive integers."
  (dolist (cp (list kuro--kkp-cp-up kuro--kkp-cp-down kuro--kkp-cp-left
                    kuro--kkp-cp-right kuro--kkp-cp-home kuro--kkp-cp-end
                    kuro--kkp-cp-insert kuro--kkp-cp-delete
                    kuro--kkp-cp-page-up kuro--kkp-cp-page-down
                    kuro--kkp-cp-f1 kuro--kkp-cp-f12))
    (should (and (integerp cp) (> cp 0)))))

(kuro-input-keys-test--deftest-encode-kitty-key-cases)

;;; ── KKP flag constants and F-key codepoints ──────────────────────────────────

(ert-deftest kuro-input-keys-kkp-flags-are-distinct-power-of-two ()
  "KKP protocol flag constants are distinct powers of two (non-overlapping bits)."
  (let ((flags (list kuro--kkp-disambiguate kuro--kkp-report-events kuro--kkp-all-escape)))
    ;; Each flag is a power of two
    (dolist (f flags)
      (should (and (integerp f) (> f 0) (= 0 (logand f (1- f))))))
    ;; No two flags share bits
    (let ((combined 0))
      (dolist (f flags)
        (should (= 0 (logand combined f)))
        (setq combined (logior combined f))))))

(ert-deftest kuro-input-keys-kkp-f-key-codepoints-sequential ()
  "kuro--kkp-cp-f2 through kuro--kkp-cp-f11 are consecutive (F1 baseline = 57364)."
  (let ((base kuro--kkp-cp-f2))
    (should (= kuro--kkp-cp-f3  (+ base 1)))
    (should (= kuro--kkp-cp-f4  (+ base 2)))
    (should (= kuro--kkp-cp-f5  (+ base 3)))
    (should (= kuro--kkp-cp-f6  (+ base 4)))
    (should (= kuro--kkp-cp-f7  (+ base 5)))
    (should (= kuro--kkp-cp-f8  (+ base 6)))
    (should (= kuro--kkp-cp-f9  (+ base 7)))
    (should (= kuro--kkp-cp-f10 (+ base 8)))
    (should (= kuro--kkp-cp-f11 (+ base 9)))))

;;; ── kuro--send-kkp-functional dispatch ───────────────────────────────────────

(ert-deftest kuro-input-keys-send-kkp-functional-uses-kkp-when-all-escape-set ()
  "`kuro--send-kkp-functional' sends CSI CP;1u when ALL_ESCAPE flag is active."
  (let ((sent nil)
        (kuro--keyboard-flags kuro--kkp-all-escape))
    (cl-letf (((symbol-function 'kuro--send-key) (lambda (s) (setq sent s)))
              ((symbol-function 'kuro--schedule-immediate-render) #'ignore))
      (kuro--send-kkp-functional 57364 "\e[A" "\eOA"))
    (should (equal sent "\e[57364;1u"))))

(ert-deftest kuro-input-keys-send-kkp-functional-uses-legacy-when-flag-clear ()
  "`kuro--send-kkp-functional' delegates to `kuro--send-key-sequence' when flag is clear."
  (let ((seq-args nil)
        (kuro--keyboard-flags 0))
    (cl-letf (((symbol-function 'kuro--send-key-sequence)
               (lambda (n a) (setq seq-args (list n a)))))
      (kuro--send-kkp-functional 57364 "\e[A" "\eOA"))
    (should (equal seq-args '("\e[A" "\eOA")))))

;;; Group 22: kuro--kkp-flag-p direct tests

(kuro-input-keys-test--deftest-kkp-flag-p-cases)

;;; Group 23: kuro--def-key-sequence macro — structural coverage
;;
;; The macro has two compile-time branches:
;;   • no kkp-cp  → (kuro--send-key-sequence normal application)
;;   • with kkp-cp → (kuro--send-kkp-functional kkp-cp normal application)

(ert-deftest kuro-input-keys-def-key-sequence-without-kkp-expands-to-defun ()
  "`kuro--def-key-sequence' (no KKP-CP) expands to `defun'."
  (let ((exp (macroexpand-1
              '(kuro--def-key-sequence kuro-test--seq "doc" "\e[A" "\eOA"))))
    (should (eq (car exp) 'defun))
    (should (eq (cadr exp) 'kuro-test--seq))))

(ert-deftest kuro-input-keys-def-key-sequence-with-kkp-expands-to-defun ()
  "`kuro--def-key-sequence' (with KKP-CP) expands to `defun'."
  (let ((exp (macroexpand-1
              '(kuro--def-key-sequence kuro-test--seq-kkp "doc" "\e[A" "\eOA" 57350))))
    (should (eq (car exp) 'defun))
    (should (eq (cadr exp) 'kuro-test--seq-kkp))))

(ert-deftest kuro-input-keys-def-key-sequence-without-kkp-uses-send-key-sequence ()
  "`kuro--def-key-sequence' (no KKP-CP) body calls `kuro--send-key-sequence'."
  (let* ((exp (macroexpand-1
               '(kuro--def-key-sequence kuro-test--seq2 "doc" "\e[A" "\eOA")))
         (body (cddr exp)))
    (should (cl-find-if (lambda (form)
                          (and (consp form) (eq (car form) 'kuro--send-key-sequence)))
                        body))))

(ert-deftest kuro-input-keys-def-key-sequence-with-kkp-uses-send-kkp-functional ()
  "`kuro--def-key-sequence' (with KKP-CP) body calls `kuro--send-kkp-functional'."
  (let* ((exp (macroexpand-1
               '(kuro--def-key-sequence kuro-test--seq3 "doc" "\e[A" "\eOA" 57350)))
         (body (cddr exp)))
    (should (cl-find-if (lambda (form)
                          (and (consp form) (eq (car form) 'kuro--send-kkp-functional)))
                        body))))

(provide 'kuro-input-keys-test-3)

;;; kuro-input-keys-test-3.el ends here
