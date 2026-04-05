;;; kuro-e2e-text-test.el --- Input and text E2E tests -*- lexical-binding: t -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; E2E tests for text input and output in the Kuro terminal emulator covering:
;; multiline output, tab alignment, Unicode, large output, backspace, SIGINT,
;; bracketed paste, the kuro--RET function, and kuro-send-interrupt API.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-e2e-helpers)

(ert-deftest kuro-e2e-multiline-output ()
  "printf three labeled lines; verify each marker appears in the terminal."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf 'KLINE1\\nKLINE2\\nKLINE3\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KLINE1"))
   (should (kuro-e2e--wait-for-text buf "KLINE2"))
   (should (kuro-e2e--wait-for-text buf "KLINE3"))))

(ert-deftest kuro-e2e-tab-alignment ()
  "A tab before KTABTEXT should produce leading whitespace before the word."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\tKTABTEXT\\n'")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KTABTEXT"))
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (when (string-match "KTABTEXT" (buffer-string))
       ;; There should be at least one space/tab character before the marker
       ;; on the same line.
       (should (string-match-p "[[:space:]]+KTABTEXT" (buffer-string)))))))

(ert-deftest kuro-e2e-unicode-output ()
  "printf Japanese UTF-8 text; verify non-ASCII characters appear."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "printf '\\xe3\\x81\\x82\\xe3\\x81\\x84\\xe3\\x81\\x86\\n'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (let ((content (buffer-string)))
       (should (string-match-p "[^\x00-\x7f]" content))))))

(ert-deftest kuro-e2e-large-output ()
  "seq 200 produces 200 numbered lines; wait up to 15s for the final marker."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "seq 200 && echo KLARGE_200")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KLARGE_200" 15.0))))

(ert-deftest kuro-e2e-backspace-input ()
  "Type a wrong character, erase it with backspace, then send a command."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "X")
   (kuro--send-key "\x7f")           ; DEL / backspace
   (kuro--send-key "echo KBSTEST")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KBSTEST"))))

(ert-deftest kuro-e2e-sigint-interrupts-command ()
  "C-c (\\x03) interrupts a sleeping process; subsequent echo verifies recovery."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "sleep 100")
   (kuro--send-key "\r")
   ;; Wait for the shell to start the sleep process
   (kuro-e2e--render-idle buf)
   ;; Send SIGINT
   (kuro--send-key "\x03")
   ;; Wait for shell to recover
   (kuro-e2e--render-idle buf)
   ;; Confirm the shell is responsive
   (kuro--send-key "echo KSIGINTOK")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KSIGINTOK"))))

(ert-deftest kuro-e2e-bracketed-paste-yank ()
  "kuro--send-paste-or-raw wraps text with BP sequences when mode is active.
When kuro--bracketed-paste-mode is nil, text is sent verbatim."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Test 1: plain mode — no wrapping
   (let ((sent nil))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (data) (setq sent data))))
       (setq kuro--bracketed-paste-mode nil)
       (kuro--send-paste-or-raw "hello")
       (should (equal sent "hello"))))
   ;; Test 2: bracketed mode — wrapped and sanitized
   (let ((sent nil))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (data) (setq sent data))))
       (setq kuro--bracketed-paste-mode t)
       (kuro--send-paste-or-raw "hello")
       (should (string-prefix-p "\e[200~" sent))
       (should (string-suffix-p "\e[201~" sent))
       (should (string-match-p "hello" sent))))
   ;; Test 3: bracketed mode sanitizes ESC bytes
   (let ((sent nil))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (data) (setq sent data))))
       (setq kuro--bracketed-paste-mode t)
       (kuro--send-paste-or-raw "ab\x1bcd")
       ;; ESC must be removed from the payload
       (let ((payload (substring sent
                                 (length "\e[200~")
                                 (- (length sent) (length "\e[201~")))))
         (should-not (string-match-p "\x1b" payload))
         (should (string-match-p "abcd" payload)))))))

(ert-deftest kuro-e2e-ret-key-function ()
  "kuro--RET sends a carriage return to the PTY."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (let ((sent nil))
     (cl-letf (((symbol-function 'kuro--send-key)
                (lambda (data) (setq sent data))))
       (kuro--RET)
       (should (equal sent "\r"))))))

(ert-deftest kuro-e2e-kuro-send-interrupt-api ()
  "kuro-send-interrupt public API interrupts a running process."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   (kuro--send-key "sleep 100")
   (kuro--send-key "\r")
   ;; Wait for the shell to start the sleep process
   (kuro-e2e--render-idle buf)
   ;; Use the public API to send interrupt
   (kuro-send-interrupt)
   ;; Wait for shell to recover
   (kuro-e2e--render-idle buf)
   ;; Confirm the shell is responsive
   (kuro--send-key "echo KSENDINTOK")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KSENDINTOK"))))

(provide 'kuro-e2e-text-test)
;;; kuro-e2e-text-test.el ends here
