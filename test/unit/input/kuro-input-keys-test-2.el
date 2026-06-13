;;; kuro-input-keys-test-2.el --- kuro-input-keys-test (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-keys-test-support)

;;; Group 11: kuro--def-key-sequence — both sequences are strings

(ert-deftest kuro-input-keys--generated-sequences-are-strings ()
  "kuro--def-key-sequence sends string values (not symbols or integers)."
  (dolist (fn '(kuro--arrow-up kuro--arrow-down kuro--arrow-left kuro--arrow-right
                kuro--HOME kuro--END kuro--F1 kuro--F4 kuro--F5 kuro--F12))
    (dolist (mode '(nil t))
      (let ((kuro--application-cursor-keys-mode mode))
        (kuro-input-keys-test--with-capture
          (funcall fn)
          (should (stringp (car kuro-input-keys-test--sent))))))))

;;; Group 12: kuro--ctrl-modified sends via kuro--send-special (Ctrl range coverage)

(ert-deftest kuro-input-keys--ctrl-modified-full-alphabet-range ()
  "Ctrl+A through Ctrl+Z map to control bytes 1-26 respectively."
  (let ((expected-pairs
         (mapcar (lambda (i) (cons (+ ?A i -1) i))
                 (number-sequence 1 26))))
    (dolist (pair expected-pairs)
      (kuro-input-keys-test--with-capture
        (kuro--ctrl-modified (car pair) 0)
        (should (equal (car kuro-input-keys-test--sent)
                       (string (cdr pair))))))))

;;; Group 13: F1-F4 send same SS3 sequences in both cursor modes

(ert-deftest kuro-input-keys--f1-f4-same-in-both-modes ()
  "F1-F4 send identical SS3 sequences regardless of application cursor mode.
These keys do not change between normal and application cursor mode."
  (let ((expected '((kuro--F1 . "\eOP")
                    (kuro--F2 . "\eOQ")
                    (kuro--F3 . "\eOR")
                    (kuro--F4 . "\eOS"))))
    (dolist (pair expected)
      (dolist (mode '(nil t))
        (let ((kuro--application-cursor-keys-mode mode))
          (kuro-input-keys-test--with-capture
            (funcall (car pair))
            (should (equal (car kuro-input-keys-test--sent) (cdr pair)))))))))

;;; Group 14: F5-F12 send same CSI sequences in both cursor modes

(ert-deftest kuro-input-keys--f5-f12-same-in-both-modes ()
  "F5-F12 send identical CSI sequences regardless of application cursor mode."
  (let ((expected '((kuro--F5  . "\e[15~")
                    (kuro--F6  . "\e[17~")
                    (kuro--F7  . "\e[18~")
                    (kuro--F8  . "\e[19~")
                    (kuro--F9  . "\e[20~")
                    (kuro--F10 . "\e[21~")
                    (kuro--F11 . "\e[23~")
                    (kuro--F12 . "\e[24~"))))
    (dolist (pair expected)
      (dolist (mode '(nil t))
        (let ((kuro--application-cursor-keys-mode mode))
          (kuro-input-keys-test--with-capture
            (funcall (car pair))
            (should (equal (car kuro-input-keys-test--sent) (cdr pair)))))))))

;;; Group 15: Navigation keys send exactly one string per call

(ert-deftest kuro-input-keys--navigation-keys-send-exactly-one-string ()
  "Each navigation key handler sends exactly one string per invocation."
  (dolist (fn '(kuro--HOME kuro--END kuro--INSERT kuro--DELETE
                kuro--PAGE-UP kuro--PAGE-DOWN))
    (kuro-input-keys-test--with-capture
      (funcall fn)
      (should (= (length kuro-input-keys-test--sent) 1)))))

;;; Group 16: kuro--alt-modified with special characters

(ert-deftest kuro-input-keys--alt-modified-sends-esc-space ()
  "Alt+Space sends ESC followed by a space character."
  (kuro-input-keys-test--with-capture
    (kuro--alt-modified ?\s)
    (should (equal (car kuro-input-keys-test--sent) (string ?\e ?\s)))))

(ert-deftest kuro-input-keys--alt-modified-sends-esc-dot ()
  "Alt+. sends ESC followed by a period."
  (kuro-input-keys-test--with-capture
    (kuro--alt-modified ?.)
    (should (equal (car kuro-input-keys-test--sent) "\e."))))

(ert-deftest kuro-input-keys--alt-modified-sends-exactly-one-string ()
  "kuro--alt-modified sends exactly one string per invocation."
  (kuro-input-keys-test--with-capture
    (kuro--alt-modified ?b)
    (should (= (length kuro-input-keys-test--sent) 1))))

;;; Group 17: kuro--ctrl-modified — extended control character range

(ert-deftest kuro-input-keys--ctrl-modified-right-bracket ()
  "Ctrl+] (char=?]=93) produces control byte 29 (93 AND 31 = 29)."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?\] 0)
    (should (equal (car kuro-input-keys-test--sent) (string 29)))))

(ert-deftest kuro-input-keys--ctrl-modified-caret ()
  "Ctrl+^ (char=?^=94) produces control byte 30 (94 AND 31 = 30)."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?^ 0)
    (should (equal (car kuro-input-keys-test--sent) (string 30)))))

(ert-deftest kuro-input-keys--ctrl-modified-underscore ()
  "Ctrl+_ (char=?_=95) produces control byte 31 (95 AND 31 = 31)."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?_ 0)
    (should (equal (car kuro-input-keys-test--sent) (string 31)))))

;;; Group 18: kuro--ctrl-modified — render scheduling and output length

(ert-deftest kuro-input-keys--ctrl-modified-schedules-render ()
  "kuro--ctrl-modified schedules an immediate render (via kuro--send-special)."
  (let ((rendered nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (_data) nil))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () (setq rendered t))))
      (kuro--ctrl-modified ?a 0)
      (should rendered))))

(ert-deftest kuro-input-keys--ctrl-modified-sends-exactly-one-string ()
  "kuro--ctrl-modified sends exactly one string per invocation."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?a 0)
    (should (= (length kuro-input-keys-test--sent) 1))))

(ert-deftest kuro-input-keys--ctrl-modified-output-is-one-byte-string ()
  "kuro--ctrl-modified output string has length 1 (single control byte)."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?a 0)
    (should (= (length (car kuro-input-keys-test--sent)) 1))))

(ert-deftest kuro-input-keys--ctrl-modified-uppercase-z ()
  "Ctrl+Z uppercase (char=?Z=90) produces control byte 26 via AND 31."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?Z 0)
    (should (= (aref (car kuro-input-keys-test--sent) 0) 26))))

(ert-deftest kuro-input-keys--ctrl-modified-uppercase-c ()
  "Ctrl+C uppercase (char=?C=67) produces control byte 3 via AND 31."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?C 0)
    (should (= (aref (car kuro-input-keys-test--sent) 0) 3))))

;;; Group 19: kuro--alt-modified — uppercase and output length invariants

(ert-deftest kuro-input-keys--alt-modified-uppercase-a ()
  "Alt+A (uppercase) sends ESC followed by uppercase A."
  (kuro-input-keys-test--with-capture
    (kuro--alt-modified ?A)
    (should (equal (car kuro-input-keys-test--sent) (string ?\e ?A)))))

(ert-deftest kuro-input-keys--alt-modified-uppercase-z ()
  "Alt+Z (uppercase) sends ESC followed by uppercase Z."
  (kuro-input-keys-test--with-capture
    (kuro--alt-modified ?Z)
    (should (equal (car kuro-input-keys-test--sent) (string ?\e ?Z)))))

(ert-deftest kuro-input-keys--alt-modified-output-is-two-byte-string ()
  "kuro--alt-modified output string has length 2 (ESC + char)."
  (kuro-input-keys-test--with-capture
    (kuro--alt-modified ?b)
    (should (= (length (car kuro-input-keys-test--sent)) 2))))

(ert-deftest kuro-input-keys--alt-modified-first-byte-is-esc ()
  "kuro--alt-modified first byte is always ESC (0x1B) regardless of char."
  (dolist (ch (list ?a ?z ?A ?Z ?0 ?9 ?.))
    (kuro-input-keys-test--with-capture
      (kuro--alt-modified ch)
      (should (= (aref (car kuro-input-keys-test--sent) 0) ?\e)))))

(ert-deftest kuro-input-keys--alt-modified-second-byte-is-char ()
  "kuro--alt-modified second byte is the verbatim character argument."
  (dolist (ch (list ?a ?b ?f ?r ?u ?l))
    (kuro-input-keys-test--with-capture
      (kuro--alt-modified ch)
      (should (= (aref (car kuro-input-keys-test--sent) 1) ch)))))

(ert-deftest kuro-input-keys--alt-modified-sends-esc-backspace ()
  "Alt+Backspace (char=\\x7f) sends ESC followed by DEL byte."
  (kuro-input-keys-test--with-capture
    (kuro--alt-modified ?\x7f)
    (should (equal (car kuro-input-keys-test--sent) (string ?\e ?\x7f)))))

;;; Group 20 — sequence value spot-checks and mode invariants

(defmacro kuro-input-keys-test--assert-sequence (fn mode expected)
  "Assert that FN sends EXPECTED when kuro--application-cursor-keys-mode is MODE."
  `(let ((kuro--application-cursor-keys-mode ,mode))
     (kuro-input-keys-test--with-capture
       (funcall ,fn)
       (should (equal (car kuro-input-keys-test--sent) ,expected)))))

(ert-deftest kuro-input-keys--g20-f1-sends-ss3-p-normal ()
  "F1 sends ESC O P (SS3 P) in normal cursor mode."
  (kuro-input-keys-test--assert-sequence #'kuro--F1 nil "\eOP"))

(ert-deftest kuro-input-keys--g20-f1-sends-ss3-p-app ()
  "F1 sends ESC O P (SS3 P) in application cursor mode — same sequence."
  (kuro-input-keys-test--assert-sequence #'kuro--F1 t "\eOP"))

(ert-deftest kuro-input-keys--g20-f12-sends-csi-24-tilde-normal ()
  "F12 sends ESC [ 24 ~ in normal cursor mode."
  (kuro-input-keys-test--assert-sequence #'kuro--F12 nil "\e[24~"))

(ert-deftest kuro-input-keys--g20-f12-sends-csi-24-tilde-app ()
  "F12 sends ESC [ 24 ~ in application cursor mode — same sequence."
  (kuro-input-keys-test--assert-sequence #'kuro--F12 t "\e[24~"))

(ert-deftest kuro-input-keys--g20-home-csi-H-normal ()
  "HOME sends ESC [ H in normal cursor mode."
  (kuro-input-keys-test--assert-sequence #'kuro--HOME nil "\e[H"))

(ert-deftest kuro-input-keys--g20-home-csi-1-tilde-app ()
  "HOME sends ESC [ 1 ~ in application cursor mode."
  (kuro-input-keys-test--assert-sequence #'kuro--HOME t "\e[1~"))

(ert-deftest kuro-input-keys--g20-end-csi-F-normal ()
  "END sends ESC [ F in normal cursor mode."
  (kuro-input-keys-test--assert-sequence #'kuro--END nil "\e[F"))

(ert-deftest kuro-input-keys--g20-end-csi-4-tilde-app ()
  "END sends ESC [ 4 ~ in application cursor mode."
  (kuro-input-keys-test--assert-sequence #'kuro--END t "\e[4~"))

(ert-deftest kuro-input-keys--g20-page-up-both-modes ()
  "PAGE-UP sends ESC [ 5 ~ in both cursor modes."
  (dolist (mode '(nil t))
    (kuro-input-keys-test--assert-sequence #'kuro--PAGE-UP mode "\e[5~")))

(ert-deftest kuro-input-keys--g20-page-down-both-modes ()
  "PAGE-DOWN sends ESC [ 6 ~ in both cursor modes."
  (dolist (mode '(nil t))
    (kuro-input-keys-test--assert-sequence #'kuro--PAGE-DOWN mode "\e[6~")))

(ert-deftest kuro-input-keys--g20-insert-both-modes ()
  "INSERT sends ESC [ 2 ~ in both cursor modes."
  (dolist (mode '(nil t))
    (kuro-input-keys-test--assert-sequence #'kuro--INSERT mode "\e[2~")))

(ert-deftest kuro-input-keys--g20-delete-both-modes ()
  "DELETE sends ESC [ 3 ~ in both cursor modes."
  (dolist (mode '(nil t))
    (kuro-input-keys-test--assert-sequence #'kuro--DELETE mode "\e[3~")))

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

(provide 'kuro-input-keys-test-2)
;;; kuro-input-keys-test-2.el ends here
