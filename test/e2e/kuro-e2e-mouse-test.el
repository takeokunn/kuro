;;; kuro-e2e-mouse-test.el --- E2E tests for mouse tracking modes -*- lexical-binding: t -*-

;;; Commentary:
;; End-to-end tests for mouse tracking protocol modes.
;; Authoritative location for mouse tracking E2E tests.
;; Design policy: NO standalone sleep-for calls.
;; All waiting is done via condition-based polling.

;;; Code:

(require 'ert)
(require 'kuro-e2e-helpers)

(ert-deftest kuro-e2e-mouse-mode-normal-enable ()
  "CSI ?1000h enables normal mouse tracking; CSI ?1000l disables it."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Enable normal mouse tracking
   (kuro--send-key "printf '\\033[?1000h'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (should (= (kuro--get-mouse-mode) 1000)))
   ;; Disable normal mouse tracking
   (kuro--send-key "printf '\\033[?1000l'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (should (= (kuro--get-mouse-mode) 0)))))

(ert-deftest kuro-e2e-mouse-mode-button-event-enable ()
  "CSI ?1002h enables button-event mouse tracking; CSI ?1002l disables it."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Enable button-event mouse tracking
   (kuro--send-key "printf '\\033[?1002h'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (should (= (kuro--get-mouse-mode) 1002)))
   ;; Disable button-event mouse tracking
   (kuro--send-key "printf '\\033[?1002l'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (should (= (kuro--get-mouse-mode) 0)))))

(ert-deftest kuro-e2e-mouse-sgr-mode-enable ()
  "CSI ?1006h enables SGR extended coordinates mouse mode; CSI ?1006l disables it."
  :expected-result kuro-e2e--expected-result
  (kuro-e2e--with-terminal
   ;; Enable SGR mouse encoding
   (kuro--send-key "printf '\\033[?1006h'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (should (kuro--get-mouse-sgr)))
   ;; Disable SGR mouse encoding
   (kuro--send-key "printf '\\033[?1006l'")
   (kuro--send-key "\r")
   (kuro-e2e--render-idle buf)
   (with-current-buffer buf
     (should-not (kuro--get-mouse-sgr)))))

(provide 'kuro-e2e-mouse-test)

;;; kuro-e2e-mouse-test.el ends here
