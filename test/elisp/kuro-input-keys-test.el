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

(unless (fboundp 'kuro--send-key)
  (defalias 'kuro--send-key (lambda (data) (push data kuro-input-keys-test--sent))))
(unless (fboundp 'kuro--schedule-immediate-render)
  (defalias 'kuro--schedule-immediate-render (lambda () nil)))

;; kuro--send-key-sequence and kuro--send-special are defined in kuro-input.el;
;; load kuro-input-keys.el which declares them via declare-function.
;; We need the actual definitions, so provide minimal stubs via kuro-input load path.
(defvar kuro--application-cursor-keys-mode nil)

(unless (fboundp 'kuro--send-key-sequence)
  (defun kuro--send-key-sequence (normal-sequence application-sequence)
    "Stub: send NORMAL-SEQUENCE or APPLICATION-SEQUENCE based on cursor mode."
    (kuro--send-key (if kuro--application-cursor-keys-mode
                        application-sequence
                      normal-sequence))
    (kuro--schedule-immediate-render)))

(unless (fboundp 'kuro--send-special)
  (defun kuro--send-special (byte)
    "Stub: send single BYTE and schedule render."
    (kuro--send-key (string byte))
    (kuro--schedule-immediate-render)))

(require 'kuro-input-keys)


;;; Group 1: Function keys F1-F12

(ert-deftest kuro-input-keys--f1-sends-correct-sequence ()
  "F1 handler sends SS3 P sequence."
  (setq kuro-input-keys-test--sent nil)
  (kuro--F1)
  (should (equal (car kuro-input-keys-test--sent) "\eOP")))

(ert-deftest kuro-input-keys--f2-sends-correct-sequence ()
  "F2 handler sends SS3 Q sequence."
  (setq kuro-input-keys-test--sent nil)
  (kuro--F2)
  (should (equal (car kuro-input-keys-test--sent) "\eOQ")))

(ert-deftest kuro-input-keys--f3-sends-correct-sequence ()
  "F3 handler sends SS3 R sequence."
  (setq kuro-input-keys-test--sent nil)
  (kuro--F3)
  (should (equal (car kuro-input-keys-test--sent) "\eOR")))

(ert-deftest kuro-input-keys--f4-sends-correct-sequence ()
  "F4 handler sends SS3 S sequence."
  (setq kuro-input-keys-test--sent nil)
  (kuro--F4)
  (should (equal (car kuro-input-keys-test--sent) "\eOS")))

(ert-deftest kuro-input-keys--f5-sends-correct-sequence ()
  "F5 handler sends CSI 15~ sequence."
  (setq kuro-input-keys-test--sent nil)
  (kuro--F5)
  (should (equal (car kuro-input-keys-test--sent) "\e[15~")))

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
      (setq kuro-input-keys-test--sent nil)
      (funcall (car pair))
      (should (equal (car kuro-input-keys-test--sent) (cdr pair))))))

;;; Group 2: Arrow keys (normal mode)

(ert-deftest kuro-input-keys--arrow-up-sends-csi-A ()
  "Arrow up sends CSI A in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (setq kuro-input-keys-test--sent nil)
    (kuro--arrow-up)
    (should (equal (car kuro-input-keys-test--sent) "\e[A"))))

(ert-deftest kuro-input-keys--arrow-down-sends-csi-B ()
  "Arrow down sends CSI B in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (setq kuro-input-keys-test--sent nil)
    (kuro--arrow-down)
    (should (equal (car kuro-input-keys-test--sent) "\e[B"))))

(ert-deftest kuro-input-keys--arrow-left-sends-csi-D ()
  "Arrow left sends CSI D in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (setq kuro-input-keys-test--sent nil)
    (kuro--arrow-left)
    (should (equal (car kuro-input-keys-test--sent) "\e[D"))))

(ert-deftest kuro-input-keys--arrow-right-sends-csi-C ()
  "Arrow right sends CSI C in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (setq kuro-input-keys-test--sent nil)
    (kuro--arrow-right)
    (should (equal (car kuro-input-keys-test--sent) "\e[C"))))

;;; Group 3: Arrow keys (application cursor mode)

(ert-deftest kuro-input-keys--arrow-up-app-mode-sends-ss3-A ()
  "Arrow up sends SS3 A in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (setq kuro-input-keys-test--sent nil)
    (kuro--arrow-up)
    (should (equal (car kuro-input-keys-test--sent) "\eOA"))))

(ert-deftest kuro-input-keys--arrow-down-app-mode-sends-ss3-B ()
  "Arrow down sends SS3 B in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (setq kuro-input-keys-test--sent nil)
    (kuro--arrow-down)
    (should (equal (car kuro-input-keys-test--sent) "\eOB"))))

(ert-deftest kuro-input-keys--arrow-left-app-mode-sends-ss3-D ()
  "Arrow left sends SS3 D in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (setq kuro-input-keys-test--sent nil)
    (kuro--arrow-left)
    (should (equal (car kuro-input-keys-test--sent) "\eOD"))))

(ert-deftest kuro-input-keys--arrow-right-app-mode-sends-ss3-C ()
  "Arrow right sends SS3 C in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (setq kuro-input-keys-test--sent nil)
    (kuro--arrow-right)
    (should (equal (car kuro-input-keys-test--sent) "\eOC"))))

;;; Group 4: Navigation keys

(ert-deftest kuro-input-keys--home-sends-csi-H ()
  "Home key sends CSI H in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (setq kuro-input-keys-test--sent nil)
    (kuro--HOME)
    (should (equal (car kuro-input-keys-test--sent) "\e[H"))))

(ert-deftest kuro-input-keys--end-sends-csi-F ()
  "End key sends CSI F in normal mode."
  (let ((kuro--application-cursor-keys-mode nil))
    (setq kuro-input-keys-test--sent nil)
    (kuro--END)
    (should (equal (car kuro-input-keys-test--sent) "\e[F"))))

(ert-deftest kuro-input-keys--home-app-mode-sends-csi-1-tilde ()
  "Home key sends CSI 1~ in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (setq kuro-input-keys-test--sent nil)
    (kuro--HOME)
    (should (equal (car kuro-input-keys-test--sent) "\e[1~"))))

(ert-deftest kuro-input-keys--end-app-mode-sends-csi-4-tilde ()
  "End key sends CSI 4~ in application cursor keys mode."
  (let ((kuro--application-cursor-keys-mode t))
    (setq kuro-input-keys-test--sent nil)
    (kuro--END)
    (should (equal (car kuro-input-keys-test--sent) "\e[4~"))))

(ert-deftest kuro-input-keys--insert-sends-csi-2-tilde ()
  "Insert key sends CSI 2~ sequence."
  (setq kuro-input-keys-test--sent nil)
  (kuro--INSERT)
  (should (equal (car kuro-input-keys-test--sent) "\e[2~")))

(ert-deftest kuro-input-keys--delete-sends-csi-3-tilde ()
  "Delete key sends CSI 3~ sequence."
  (setq kuro-input-keys-test--sent nil)
  (kuro--DELETE)
  (should (equal (car kuro-input-keys-test--sent) "\e[3~")))

(ert-deftest kuro-input-keys--page-up-sends-csi-5-tilde ()
  "Page Up key sends CSI 5~ sequence."
  (setq kuro-input-keys-test--sent nil)
  (kuro--PAGE-UP)
  (should (equal (car kuro-input-keys-test--sent) "\e[5~")))

(ert-deftest kuro-input-keys--page-down-sends-csi-6-tilde ()
  "Page Down key sends CSI 6~ sequence."
  (setq kuro-input-keys-test--sent nil)
  (kuro--PAGE-DOWN)
  (should (equal (car kuro-input-keys-test--sent) "\e[6~")))

;;; Group 5: Modifier helpers

(ert-deftest kuro-input-keys--ctrl-modified-sends-control-byte ()
  "kuro--ctrl-modified sends the correct control byte (char AND 31)."
  (setq kuro-input-keys-test--sent nil)
  (kuro--ctrl-modified ?a 0)
  (should (equal (car kuro-input-keys-test--sent) (string 1))))

(ert-deftest kuro-input-keys--alt-modified-sends-esc-prefix ()
  "kuro--alt-modified sends ESC followed by the character."
  (setq kuro-input-keys-test--sent nil)
  (kuro--alt-modified ?x)
  (should (equal (car kuro-input-keys-test--sent) (string ?\e ?x))))

(provide 'kuro-input-keys-test)
;;; kuro-input-keys-test.el ends here
