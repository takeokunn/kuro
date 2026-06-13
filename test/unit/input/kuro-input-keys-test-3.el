;;; kuro-input-keys-test-3.el --- kuro-input-keys-test (part 3)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-keys-test-support)

;;; Group 21: Kitty Keyboard Protocol (KKP) encoding

;; Helper macro: run BODY with keyboard-flags set to FLAGS and send-key captured.
(defmacro kuro-input-keys-test--with-kkp (flags &rest body)
  "Execute BODY with `kuro--keyboard-flags' = FLAGS and key capture active."
  `(kuro-input-keys-test--with-capture
     (let ((kuro--keyboard-flags ,flags))
       ,@body)))

(ert-deftest kuro-input-keys--g21-kkp-flags-zero-legacy-arrow ()
  "With keyboard-flags=0, arrow up sends legacy sequence."
  (kuro-input-keys-test--with-kkp 0
    (let ((kuro--application-cursor-keys-mode nil))
      (kuro--arrow-up))
    (should (equal (car kuro-input-keys-test--sent) "\e[A"))))

(ert-deftest kuro-input-keys--g21-kkp-all-escape-arrow-up-csi-u ()
  "With flag 0x08 (ALL_ESCAPE), arrow up sends KKP codepoint CSI 57352;1u."
  (kuro-input-keys-test--with-kkp #x08
    (kuro--arrow-up)
    (should (equal (car kuro-input-keys-test--sent)
                   (format "\e[%d;1u" kuro--kkp-cp-up)))))

(ert-deftest kuro-input-keys--g21-kkp-all-escape-f1-csi-u ()
  "With flag 0x08, F1 sends CSI 57364;1u."
  (kuro-input-keys-test--with-kkp #x08
    (kuro--F1)
    (should (equal (car kuro-input-keys-test--sent)
                   (format "\e[%d;1u" kuro--kkp-cp-f1)))))

(ert-deftest kuro-input-keys--g21-kkp-all-escape-home-csi-u ()
  "With flag 0x08, Home sends CSI 57356;1u."
  (kuro-input-keys-test--with-kkp #x08
    (kuro--HOME)
    (should (equal (car kuro-input-keys-test--sent)
                   (format "\e[%d;1u" kuro--kkp-cp-home)))))

(ert-deftest kuro-input-keys--g21-kkp-all-escape-delete-csi-u ()
  "With flag 0x08, Delete sends CSI 57349;1u."
  (kuro-input-keys-test--with-kkp #x08
    (kuro--DELETE)
    (should (equal (car kuro-input-keys-test--sent)
                   (format "\e[%d;1u" kuro--kkp-cp-delete)))))

(ert-deftest kuro-input-keys--g21-kkp-only-disambiguate-arrow-legacy ()
  "With only flag 0x01 (DISAMBIGUATE), arrow keys still use legacy encoding."
  (kuro-input-keys-test--with-kkp #x01
    (let ((kuro--application-cursor-keys-mode nil))
      (kuro--arrow-down))
    (should (equal (car kuro-input-keys-test--sent) "\e[B"))))

(ert-deftest kuro-input-keys--g21-kkp-ctrl-all-escape-sends-csi-u ()
  "With flag 0x08, Ctrl+A sends CSI 65;5u (distinguishable from C0 control codes)."
  (kuro-input-keys-test--with-kkp #x08
    (kuro--ctrl-modified ?A nil))
  ;; After exiting with-kkp scope, check: sent in kuro-input-keys-test--sent
  ;; Re-test inline since the macro resets sent list:
  (kuro-input-keys-test--with-capture
    (let ((kuro--keyboard-flags #x08))
      (kuro--ctrl-modified ?A nil))
    (should (equal (car kuro-input-keys-test--sent) "\e[65;5u"))))

(ert-deftest kuro-input-keys--g21-kkp-ctrl-zero-flags-sends-c0 ()
  "With flags=0, Ctrl+A sends raw C0 control byte (legacy)."
  (kuro-input-keys-test--with-capture
    (let ((kuro--keyboard-flags 0))
      (kuro--ctrl-modified ?A nil))
    ;; logand ?A 31 = 1 = C-a
    (should (equal (car kuro-input-keys-test--sent) "\x01"))))

(ert-deftest kuro-input-keys--g21-kkp-alt-disambiguate-sends-csi-u ()
  "With flag 0x01 (DISAMBIGUATE), Alt+a sends CSI 97;3u instead of ESC+a."
  (kuro-input-keys-test--with-capture
    (let ((kuro--keyboard-flags #x01))
      (kuro--alt-modified ?a))
    (should (equal (car kuro-input-keys-test--sent) "\e[97;3u"))))

(ert-deftest kuro-input-keys--g21-kkp-alt-zero-flags-sends-esc-prefix ()
  "With flags=0, Alt+a sends legacy ESC+a."
  (kuro-input-keys-test--with-capture
    (let ((kuro--keyboard-flags 0))
      (kuro--alt-modified ?a))
    (should (equal (car kuro-input-keys-test--sent) "\ea"))))

(ert-deftest kuro-input-keys--g21-kkp-codepoints-are-integers ()
  "All KKP codepoint constants are positive integers."
  (dolist (cp (list kuro--kkp-cp-up kuro--kkp-cp-down kuro--kkp-cp-left
                    kuro--kkp-cp-right kuro--kkp-cp-home kuro--kkp-cp-end
                    kuro--kkp-cp-insert kuro--kkp-cp-delete
                    kuro--kkp-cp-page-up kuro--kkp-cp-page-down
                    kuro--kkp-cp-f1 kuro--kkp-cp-f12))
    (should (and (integerp cp) (> cp 0)))))

(ert-deftest kuro-input-keys--g21-kkp-encode-kitty-key-no-modifier ()
  "kuro--encode-kitty-key with modifier 0 produces ESC [ key u."
  (should (equal (kuro--encode-kitty-key 97 0) "\e[97u")))

(ert-deftest kuro-input-keys--g21-kkp-encode-kitty-key-with-ctrl ()
  "kuro--encode-kitty-key with ctrl modifier encodes as ESC [ key ; 5 u."
  (should (equal (kuro--encode-kitty-key 65 4) "\e[65;5u")))

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

(ert-deftest kuro-input-keys--g22-kkp-flag-p-returns-t-when-bit-set ()
  "`kuro--kkp-flag-p' returns non-nil when the flag bit is set in keyboard-flags."
  (let ((kuro--keyboard-flags kuro--kkp-disambiguate))
    (should (kuro--kkp-flag-p kuro--kkp-disambiguate))))

(ert-deftest kuro-input-keys--g22-kkp-flag-p-returns-nil-when-bit-clear ()
  "`kuro--kkp-flag-p' returns nil when the flag bit is not set."
  (let ((kuro--keyboard-flags 0))
    (should-not (kuro--kkp-flag-p kuro--kkp-disambiguate))))

(ert-deftest kuro-input-keys--g22-kkp-flag-p-checks-specific-bit-only ()
  "`kuro--kkp-flag-p' is true for set bits and false for clear bits independently."
  (let ((kuro--keyboard-flags kuro--kkp-disambiguate))
    (should     (kuro--kkp-flag-p kuro--kkp-disambiguate))
    (should-not (kuro--kkp-flag-p kuro--kkp-all-escape))))

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
