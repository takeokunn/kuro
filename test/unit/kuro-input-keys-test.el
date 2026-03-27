;;; kuro-input-keys-test.el --- Tests for kuro-input-keys.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; ERT tests for kuro-input-keys.el special key handlers.
;; These tests exercise:
;;   - F1-F12 function key handlers (SS3/CSI sequences)
;;   - Arrow key handlers (normal mode sequences)
;;   - Home/End/Insert/Delete/PageUp/PageDown handlers
;;   - Modifier key senders (ctrl-modified, alt-modified)
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


;;; Group 1: Function keys F1-F12

(ert-deftest kuro-input-keys--f1-sends-correct-sequence ()
  "F1 handler sends SS3 P sequence."
  (kuro-input-keys-test--with-capture
    (kuro--F1)
    (should (equal (car kuro-input-keys-test--sent) "\eOP"))))

(ert-deftest kuro-input-keys--f2-sends-correct-sequence ()
  "F2 handler sends SS3 Q sequence."
  (kuro-input-keys-test--with-capture
    (kuro--F2)
    (should (equal (car kuro-input-keys-test--sent) "\eOQ"))))

(ert-deftest kuro-input-keys--f3-sends-correct-sequence ()
  "F3 handler sends SS3 R sequence."
  (kuro-input-keys-test--with-capture
    (kuro--F3)
    (should (equal (car kuro-input-keys-test--sent) "\eOR"))))

(ert-deftest kuro-input-keys--f4-sends-correct-sequence ()
  "F4 handler sends SS3 S sequence."
  (kuro-input-keys-test--with-capture
    (kuro--F4)
    (should (equal (car kuro-input-keys-test--sent) "\eOS"))))

(ert-deftest kuro-input-keys--f5-sends-correct-sequence ()
  "F5 handler sends CSI 15~ sequence."
  (kuro-input-keys-test--with-capture
    (kuro--F5)
    (should (equal (car kuro-input-keys-test--sent) "\e[15~"))))

(ert-deftest kuro-input-keys--f6-through-f12-send-correct-sequences ()
  "F6-F12 handlers send the correct CSI sequences."
  (let ((expected '((kuro--F6  . "\e[17~")
                    (kuro--F7  . "\e[18~")
                    (kuro--F8  . "\e[19~")
                    (kuro--F9  . "\e[20~")
                    (kuro--F10 . "\e[21~")
                    (kuro--F11 . "\e[23~")
                    (kuro--F12 . "\e[24~"))))
    (dolist (pair expected)
      (kuro-input-keys-test--with-capture
        (funcall (car pair))
        (should (equal (car kuro-input-keys-test--sent) (cdr pair)))))))

;;; Group 2: Arrow keys (normal mode)

(ert-deftest kuro-input-keys--arrow-up-sends-csi-A ()
  "Arrow up sends CSI A in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (kuro-input-keys-test--with-capture
      (kuro--arrow-up)
      (should (equal (car kuro-input-keys-test--sent) "\e[A")))))

(ert-deftest kuro-input-keys--arrow-down-sends-csi-B ()
  "Arrow down sends CSI B in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (kuro-input-keys-test--with-capture
      (kuro--arrow-down)
      (should (equal (car kuro-input-keys-test--sent) "\e[B")))))

(ert-deftest kuro-input-keys--arrow-left-sends-csi-D ()
  "Arrow left sends CSI D in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (kuro-input-keys-test--with-capture
      (kuro--arrow-left)
      (should (equal (car kuro-input-keys-test--sent) "\e[D")))))

(ert-deftest kuro-input-keys--arrow-right-sends-csi-C ()
  "Arrow right sends CSI C in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (kuro-input-keys-test--with-capture
      (kuro--arrow-right)
      (should (equal (car kuro-input-keys-test--sent) "\e[C")))))

;;; Group 3: Arrow keys (application cursor mode)

(ert-deftest kuro-input-keys--arrow-up-app-mode-sends-ss3-A ()
  "Arrow up sends SS3 A in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (kuro-input-keys-test--with-capture
      (kuro--arrow-up)
      (should (equal (car kuro-input-keys-test--sent) "\eOA")))))

(ert-deftest kuro-input-keys--arrow-down-app-mode-sends-ss3-B ()
  "Arrow down sends SS3 B in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (kuro-input-keys-test--with-capture
      (kuro--arrow-down)
      (should (equal (car kuro-input-keys-test--sent) "\eOB")))))

(ert-deftest kuro-input-keys--arrow-left-app-mode-sends-ss3-D ()
  "Arrow left sends SS3 D in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (kuro-input-keys-test--with-capture
      (kuro--arrow-left)
      (should (equal (car kuro-input-keys-test--sent) "\eOD")))))

(ert-deftest kuro-input-keys--arrow-right-app-mode-sends-ss3-C ()
  "Arrow right sends SS3 C in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (kuro-input-keys-test--with-capture
      (kuro--arrow-right)
      (should (equal (car kuro-input-keys-test--sent) "\eOC")))))

;;; Group 4: Navigation keys

(ert-deftest kuro-input-keys--home-sends-csi-H ()
  "Home key sends CSI H in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (kuro-input-keys-test--with-capture
      (kuro--HOME)
      (should (equal (car kuro-input-keys-test--sent) "\e[H")))))

(ert-deftest kuro-input-keys--end-sends-csi-F ()
  "End key sends CSI F in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (kuro-input-keys-test--with-capture
      (kuro--END)
      (should (equal (car kuro-input-keys-test--sent) "\e[F")))))

(ert-deftest kuro-input-keys--home-app-mode-sends-csi-1-tilde ()
  "Home key sends CSI 1~ in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (kuro-input-keys-test--with-capture
      (kuro--HOME)
      (should (equal (car kuro-input-keys-test--sent) "\e[1~")))))

(ert-deftest kuro-input-keys--end-app-mode-sends-csi-4-tilde ()
  "End key sends CSI 4~ in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (kuro-input-keys-test--with-capture
      (kuro--END)
      (should (equal (car kuro-input-keys-test--sent) "\e[4~")))))

(ert-deftest kuro-input-keys--insert-sends-csi-2-tilde ()
  "Insert key sends CSI 2~ sequence."
  (kuro-input-keys-test--with-capture
    (kuro--INSERT)
    (should (equal (car kuro-input-keys-test--sent) "\e[2~"))))

(ert-deftest kuro-input-keys--delete-sends-csi-3-tilde ()
  "Delete key sends CSI 3~ sequence."
  (kuro-input-keys-test--with-capture
    (kuro--DELETE)
    (should (equal (car kuro-input-keys-test--sent) "\e[3~"))))

(ert-deftest kuro-input-keys--page-up-sends-csi-5-tilde ()
  "Page Up key sends CSI 5~ sequence."
  (kuro-input-keys-test--with-capture
    (kuro--PAGE-UP)
    (should (equal (car kuro-input-keys-test--sent) "\e[5~"))))

(ert-deftest kuro-input-keys--page-down-sends-csi-6-tilde ()
  "Page Down key sends CSI 6~ sequence."
  (kuro-input-keys-test--with-capture
    (kuro--PAGE-DOWN)
    (should (equal (car kuro-input-keys-test--sent) "\e[6~"))))

;;; Group 5: Modifier helpers

(ert-deftest kuro-input-keys--ctrl-modified-sends-control-byte ()
  "kuro--ctrl-modified sends the correct control byte (char AND 31)."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?a 0)
    (should (equal (car kuro-input-keys-test--sent) (string 1)))))

(ert-deftest kuro-input-keys--alt-modified-sends-esc-prefix ()
  "kuro--alt-modified sends ESC followed by the character."
  (kuro-input-keys-test--with-capture
    (kuro--alt-modified ?x)
    (should (equal (car kuro-input-keys-test--sent) (string ?\e ?x)))))

;;; Group 6: kuro--def-key-sequence macro validation

(ert-deftest kuro-input-keys--def-key-sequence-generates-interactive-fn ()
  "kuro--def-key-sequence generates an interactive function."
  (kuro--def-key-sequence kuro--test-seq-fn
    "Test sequence function." "\e[TEST" "\eOTEST")
  (should (fboundp 'kuro--test-seq-fn))
  (should (commandp 'kuro--test-seq-fn)))

(ert-deftest kuro-input-keys--def-key-sequence-sends-normal-seq-in-normal-mode ()
  "Macro-generated function sends normal sequence in normal cursor mode."
  (kuro--def-key-sequence kuro--test-normal-fn
    "Test normal mode." "\e[NORM" "\eOAPP")
  (kuro-input-keys-test--with-capture
    (let ((kuro--application-cursor-keys-mode nil))
      (kuro--test-normal-fn)
      (should (equal (car kuro-input-keys-test--sent) "\e[NORM")))))

(ert-deftest kuro-input-keys--def-key-sequence-sends-app-seq-in-app-mode ()
  "Macro-generated function sends application sequence in application cursor mode."
  (kuro--def-key-sequence kuro--test-app-fn
    "Test app mode." "\e[NORM" "\eOAPP")
  (kuro-input-keys-test--with-capture
    (let ((kuro--application-cursor-keys-mode t))
      (kuro--test-app-fn)
      (should (equal (car kuro-input-keys-test--sent) "\eOAPP")))))

(ert-deftest kuro-input-keys--all-22-handlers-are-bound ()
  "All 22 key sequence handlers generated by kuro--def-key-sequence are fboundp."
  (dolist (fn '(kuro--arrow-up kuro--arrow-down kuro--arrow-left kuro--arrow-right
                kuro--HOME kuro--END kuro--INSERT kuro--DELETE
                kuro--PAGE-UP kuro--PAGE-DOWN
                kuro--F1 kuro--F2 kuro--F3 kuro--F4 kuro--F5 kuro--F6
                kuro--F7 kuro--F8 kuro--F9 kuro--F10 kuro--F11 kuro--F12))
    (should (fboundp fn))))

;;; Group 7: kuro--ctrl-modified — control byte calculations

(ert-deftest kuro-input-keys--ctrl-modified-uppercase-A ()
  "Ctrl+A (char=?A=65) produces control byte 1 (65 AND 31 = 1)."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?A 0)
    (should (equal (car kuro-input-keys-test--sent) (string 1)))))

(ert-deftest kuro-input-keys--ctrl-modified-lowercase-a ()
  "Ctrl+a (char=?a=97) produces control byte 1 (97 AND 31 = 1)."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?a 0)
    (should (equal (car kuro-input-keys-test--sent) (string 1)))))

(ert-deftest kuro-input-keys--ctrl-modified-char-c ()
  "Ctrl+C (char=?C=67) produces control byte 3 (67 AND 31 = 3)."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?C 0)
    (should (equal (car kuro-input-keys-test--sent) (string 3)))))

(ert-deftest kuro-input-keys--ctrl-modified-char-z ()
  "Ctrl+Z (char=?Z=90) produces control byte 26 (90 AND 31 = 26)."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?Z 0)
    (should (equal (car kuro-input-keys-test--sent) (string 26)))))

(ert-deftest kuro-input-keys--ctrl-modified-bracket ()
  "Ctrl+[ (char=?[=91) produces control byte 27 (ESC) (91 AND 31 = 27)."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?\[ 0)
    (should (equal (car kuro-input-keys-test--sent) (string 27)))))

(ert-deftest kuro-input-keys--ctrl-modified-space ()
  "Ctrl+Space (char=?\s=32) produces control byte 0 (32 AND 31 = 0)."
  (kuro-input-keys-test--with-capture
    (kuro--ctrl-modified ?\s 0)
    (should (equal (car kuro-input-keys-test--sent) (string 0)))))

(ert-deftest kuro-input-keys--ctrl-modified-modifier-arg-ignored ()
  "kuro--ctrl-modified ignores the MODIFIER argument (reserved for future use)."
  (kuro-input-keys-test--with-capture
    ;; Same char, different modifier values — result must be identical
    (kuro--ctrl-modified ?b 0)
    (let ((sent-0 (car kuro-input-keys-test--sent)))
      (setq kuro-input-keys-test--sent nil)
      (kuro--ctrl-modified ?b 4)
      (should (equal sent-0 (car kuro-input-keys-test--sent))))))

;;; Group 8: kuro--alt-modified — ESC prefix sequences

(ert-deftest kuro-input-keys--alt-modified-sends-esc-a ()
  "Alt+a sends ESC followed by ?a."
  (kuro-input-keys-test--with-capture
    (kuro--alt-modified ?a)
    (should (equal (car kuro-input-keys-test--sent) "\ea"))))

(ert-deftest kuro-input-keys--alt-modified-sends-esc-digit ()
  "Alt+1 sends ESC followed by ?1."
  (kuro-input-keys-test--with-capture
    (kuro--alt-modified ?1)
    (should (equal (car kuro-input-keys-test--sent) "\e1"))))

(ert-deftest kuro-input-keys--alt-modified-sends-esc-z ()
  "Alt+z sends ESC followed by ?z."
  (kuro-input-keys-test--with-capture
    (kuro--alt-modified ?z)
    (should (equal (car kuro-input-keys-test--sent) "\ez"))))

(ert-deftest kuro-input-keys--alt-modified-triggers-render-schedule ()
  "kuro--alt-modified calls kuro--schedule-immediate-render."
  (let ((rendered nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (_data) nil))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () (setq rendered t))))
      (kuro--alt-modified ?a)
      (should rendered))))

;;; Group 9: All arrows send one string per call (no extra output)

(ert-deftest kuro-input-keys--arrows-send-exactly-one-string ()
  "Each arrow key handler sends exactly one string per invocation."
  (dolist (pair '((kuro--arrow-up    . nil)
                  (kuro--arrow-down  . nil)
                  (kuro--arrow-left  . nil)
                  (kuro--arrow-right . nil)))
    (let ((kuro--application-cursor-keys-mode (cdr pair)))
      (kuro-input-keys-test--with-capture
        (funcall (car pair))
        (should (= (length kuro-input-keys-test--sent) 1))))))

;;; Group 10: Navigation keys same-sequence in both modes (INSERT/DELETE/PAGE-UP/PAGE-DOWN)

(ert-deftest kuro-input-keys--insert-same-in-both-modes ()
  "INSERT sends CSI 2~ in both normal and application cursor modes."
  (dolist (mode '(nil t))
    (let ((kuro--application-cursor-keys-mode mode))
      (kuro-input-keys-test--with-capture
        (kuro--INSERT)
        (should (equal (car kuro-input-keys-test--sent) "\e[2~"))))))

(ert-deftest kuro-input-keys--delete-same-in-both-modes ()
  "DELETE sends CSI 3~ in both normal and application cursor modes."
  (dolist (mode '(nil t))
    (let ((kuro--application-cursor-keys-mode mode))
      (kuro-input-keys-test--with-capture
        (kuro--DELETE)
        (should (equal (car kuro-input-keys-test--sent) "\e[3~"))))))

(ert-deftest kuro-input-keys--page-up-same-in-both-modes ()
  "PAGE-UP sends CSI 5~ in both normal and application cursor modes."
  (dolist (mode '(nil t))
    (let ((kuro--application-cursor-keys-mode mode))
      (kuro-input-keys-test--with-capture
        (kuro--PAGE-UP)
        (should (equal (car kuro-input-keys-test--sent) "\e[5~"))))))

(ert-deftest kuro-input-keys--page-down-same-in-both-modes ()
  "PAGE-DOWN sends CSI 6~ in both normal and application cursor modes."
  (dolist (mode '(nil t))
    (let ((kuro--application-cursor-keys-mode mode))
      (kuro-input-keys-test--with-capture
        (kuro--PAGE-DOWN)
        (should (equal (car kuro-input-keys-test--sent) "\e[6~"))))))

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

(provide 'kuro-input-keys-test)
;;; kuro-input-keys-test.el ends here
