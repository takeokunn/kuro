;;; kuro-e2e-core-test.el --- Core E2E tests -*- lexical-binding: t -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Core E2E tests for the Kuro terminal emulator.
;; These tests use direct FFI polling (kuro-e2e--wait-for-output) rather than
;; the render pipeline, making them reliable and fast.
;;
;; Test categories:
;;   1. Module availability (static, no PTY)
;;   2. Terminal initialization
;;   3. Echo/input round-trip
;;   4. Cursor state
;;   5. Resize

;;; Code:

(require 'ert)
(require 'kuro-e2e-helpers)

(ert-deftest kuro-e2e-module-loads ()
  "Verify that essential Kuro FFI functions are bound when the Rust module loads."
  (skip-unless kuro-e2e--module-loaded)
  (should (fboundp 'kuro-core-init))
  (should (fboundp 'kuro-core-shutdown))
  (should (fboundp 'kuro-core-send-key))
  (should (fboundp 'kuro-core-poll-updates-binary-with-strings))
  (should (fboundp 'kuro-core-get-cursor))
  (should (fboundp 'kuro-core-resize)))

(ert-deftest kuro-e2e-terminal-init ()
  "Verify terminal session initializes without error and session-id is set."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; If we reach here, kuro--init succeeded and shell is ready.
   (should (integerp kuro--session-id))
   (should (> kuro--session-id 0))
   (should (= kuro--last-rows 24))
   (should (= kuro--last-cols 80))))

(ert-deftest kuro-e2e-echo-command ()
  "Send echo command and verify output appears via direct FFI polling."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "echo KUROX99\r")
   (should (kuro-e2e--wait-for-output kuro--session-id "KUROX99"))))

(ert-deftest kuro-e2e-multiple-commands ()
  "Send two sequential echo commands and verify both outputs appear."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "echo first_cmd\r")
   (should (kuro-e2e--wait-for-output kuro--session-id "first_cmd"))
   (kuro--send-key "echo second_cmd\r")
   (should (kuro-e2e--wait-for-output kuro--session-id "second_cmd"))))

(ert-deftest kuro-e2e-cursor-position ()
  "Verify cursor position is a cons cell of non-negative integers."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
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
   (kuro--resize 24 80)))

(provide 'kuro-e2e-core-test)
;;; kuro-e2e-core-test.el ends here
