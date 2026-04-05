;;; kuro-e2e-core-test.el --- Core E2E tests -*- lexical-binding: t -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Core E2E tests for the Kuro terminal emulator.
;; Tests module loading, terminal initialization, basic echo, cursor, resize,
;; and public send-string API.

;;; Code:

(require 'ert)
(require 'kuro-e2e-helpers)

(ert-deftest kuro-e2e-module-loads ()
  "Verify that essential Kuro functions are bound when the Rust module is loaded."
  (skip-unless kuro-e2e--module-loaded)
  (should (fboundp 'kuro-core-init))
  (should (fboundp 'kuro-core-shutdown))
  (should (fboundp 'kuro-core-send-key))
  (should (fboundp 'kuro-core-poll-updates-with-faces))
  (should (fboundp 'kuro-core-get-cursor))
  (should (fboundp 'kuro-core-resize)))

(ert-deftest kuro-e2e-terminal-init ()
  "Verify terminal initializes and renders non-whitespace content."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (let ((content (with-current-buffer buf (buffer-string))))
     (should (string-match-p "[^[:space:]]" content)))))

(ert-deftest kuro-e2e-echo-command ()
  "Send echo command and verify output appears in terminal."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "echo KUROX99")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KUROX99"))))

(ert-deftest kuro-e2e-multiple-commands ()
  "Send two sequential echo commands and verify both outputs appear."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "echo first_cmd")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "first_cmd"))
   (kuro--send-key "echo second_cmd")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "second_cmd"))))

(ert-deftest kuro-e2e-cursor-position ()
  "Verify cursor position is a cons cell of non-negative integers."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-e2e--render-idle buf)
   (let ((cursor (kuro--get-cursor)))
     (should (consp cursor))
     (should (integerp (car cursor)))
     (should (integerp (cdr cursor)))
     (should (>= (car cursor) 0))
     (should (>= (cdr cursor) 0)))))

(ert-deftest kuro-e2e-resize ()
  "Verify terminal can be resized and restored without error."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--resize 10 40)
   (kuro-e2e--render-idle buf)
   (kuro--resize 24 80)
   (kuro-e2e--render-idle buf)))

(ert-deftest kuro-e2e-no-double-newlines ()
  "Verify that normal rendering does not produce triple consecutive newlines."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-e2e--render-idle buf)
   (let ((content (with-current-buffer buf (buffer-string))))
     (should-not (string-match-p "\n\n\n" content)))))

(ert-deftest kuro-e2e-send-string-api ()
  "Verify kuro-send-string public API delivers text to the terminal."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro-send-string "echo KSENDSTR99\r")
   (should (kuro-e2e--wait-for-text buf "KSENDSTR99"))))

(provide 'kuro-e2e-core-test)
;;; kuro-e2e-core-test.el ends here
