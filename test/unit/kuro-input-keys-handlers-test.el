;;; kuro-input-keys-ext-test.el --- Extended tests for kuro-input-keys.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Extended ERT tests for kuro-input-keys.el special key handlers (Groups 12-20).
;; These tests exercise:
;;   - Ctrl+A-Z full alphabet range coverage (Group 12)
;;   - F1-F4 and F5-F12 mode invariants (Groups 13-14)
;;   - Navigation keys count invariants (Group 15)
;;   - Alt+modified special characters (Group 16)
;;   - Extended control character range (Group 17)
;;   - Ctrl+modified render scheduling and output length (Group 18)
;;   - Alt+modified uppercase and output length invariants (Group 19)
;;   - Sequence value spot-checks and mode invariants (Group 20)
;;
;; Pure Elisp tests -- no Rust dynamic module required.
;; All FFI dependencies are stubbed before requiring the module.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Capture sent keys
(defvar kuro-input-keys-test--sent nil
  "List of strings sent via `kuro--send-key' during tests (most recent first).")

(require 'kuro-input-keys)

;; Helper macro: run BODY with kuro--send-key captured to kuro-input-keys-test--sent.
;; Using cl-letf inside each test ensures isolation even when the real functions
;; are already bound (kuro.el was loaded as part of test-suite bootstrap).
(defmacro kuro-input-keys-test--with-capture (&rest body)
  "Execute BODY with `kuro--send-key' capturing to `kuro-input-keys-test--sent'."
  `(cl-letf (((symbol-function 'kuro--send-key)
              (lambda (data) (push data kuro-input-keys-test--sent)))
             ((symbol-function 'kuro--schedule-immediate-render)
              (lambda () nil)))
     (setq kuro-input-keys-test--sent nil)
     ,@body))


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

(provide 'kuro-input-keys-ext-test)
;;; kuro-input-keys-ext-test.el ends here
