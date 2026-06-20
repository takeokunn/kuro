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

;;; Group: Shifted function keys S-F1..S-F12

(ert-deftest kuro-input-keys--shifted-f1-legacy-csi-1-2-P ()
  "S-F1 sends xterm legacy CSI 1;2P when KKP all-escape is inactive."
  (kuro-input-keys-test--with-kkp 0
    (kuro--S-F1)
    (should (equal (car kuro-input-keys-test--sent) "\e[1;2P"))))

(ert-deftest kuro-input-keys--shifted-f1-kkp-csi-cp-2u ()
  "S-F1 sends KKP CSI 57364;2u when all-escape (0x08) is active."
  (kuro-input-keys-test--with-kkp #x08
    (kuro--S-F1)
    (should (equal (car kuro-input-keys-test--sent)
                   (format "\e[%d;2u" kuro--kkp-cp-f1)))))

(ert-deftest kuro-input-keys--shifted-f5-legacy-csi-15-2-tilde ()
  "S-F5 sends xterm legacy CSI 15;2~ when KKP all-escape is inactive."
  (kuro-input-keys-test--with-kkp 0
    (kuro--S-F5)
    (should (equal (car kuro-input-keys-test--sent) "\e[15;2~"))))

(ert-deftest kuro-input-keys--shifted-f5-kkp-csi-cp-2u ()
  "S-F5 sends KKP CSI 57368;2u when all-escape (0x08) is active."
  (kuro-input-keys-test--with-kkp #x08
    (kuro--S-F5)
    (should (equal (car kuro-input-keys-test--sent)
                   (format "\e[%d;2u" kuro--kkp-cp-f5)))))

(ert-deftest kuro-input-keys--shifted-f4-legacy-csi-1-2-S ()
  "S-F4 sends xterm legacy CSI 1;2S (last of the SS3-style F1-F4 group)."
  (kuro-input-keys-test--with-kkp 0
    (kuro--S-F4)
    (should (equal (car kuro-input-keys-test--sent) "\e[1;2S"))))

(ert-deftest kuro-input-keys--shifted-f12-legacy-csi-24-2-tilde ()
  "S-F12 sends xterm legacy CSI 24;2~."
  (kuro-input-keys-test--with-kkp 0
    (kuro--S-F12)
    (should (equal (car kuro-input-keys-test--sent) "\e[24;2~"))))

;;; Group: Numeric keypad keys (normal vs application keypad mode)

(ert-deftest kuro-input-keys--keypad-7-normal-sends-plain-char ()
  "KP-7 sends the plain character \"7\" when application keypad mode is off."
  (kuro-input-keys-test--with-capture
    (let ((kuro--app-keypad-mode nil))
      (kuro--KP-7))
    (should (equal (car kuro-input-keys-test--sent) "7"))))

(ert-deftest kuro-input-keys--keypad-7-application-sends-ss3 ()
  "KP-7 sends the SS3 application form ESC O w when app keypad mode is on."
  (kuro-input-keys-test--with-capture
    (let ((kuro--app-keypad-mode t))
      (kuro--KP-7))
    (should (equal (car kuro-input-keys-test--sent) "\eOw"))))

(ert-deftest kuro-input-keys--keypad-0-normal-and-application ()
  "KP-0 sends \"0\" normally and ESC O p in application keypad mode."
  (kuro-input-keys-test--with-capture
    (let ((kuro--app-keypad-mode nil)) (kuro--KP-0))
    (should (equal (car kuro-input-keys-test--sent) "0")))
  (kuro-input-keys-test--with-capture
    (let ((kuro--app-keypad-mode t)) (kuro--KP-0))
    (should (equal (car kuro-input-keys-test--sent) "\eOp"))))

(ert-deftest kuro-input-keys--keypad-operators-normal-and-application ()
  "Keypad operators send their plain char normally and SS3 form in app mode."
  (dolist (case '((kuro--KP-DECIMAL  "." "\eOn")
                  (kuro--KP-ENTER    "\r" "\eOM")
                  (kuro--KP-ADD      "+" "\eOl")
                  (kuro--KP-SUBTRACT "-" "\eOm")
                  (kuro--KP-MULTIPLY "*" "\eOj")
                  (kuro--KP-DIVIDE   "/" "\eOo")))
    (kuro-input-keys-test--with-capture
      (let ((kuro--app-keypad-mode nil)) (funcall (nth 0 case)))
      (should (equal (car kuro-input-keys-test--sent) (nth 1 case))))
    (kuro-input-keys-test--with-capture
      (let ((kuro--app-keypad-mode t)) (funcall (nth 0 case)))
      (should (equal (car kuro-input-keys-test--sent) (nth 2 case))))))

(provide 'kuro-input-keys-test-3)

;;; kuro-input-keys-test-3.el ends here
