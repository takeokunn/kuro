;;; kuro-poll-modes-clipboard-test.el --- Tests for clipboard message-emission and edge-case policies  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-poll-modes.el — Groups Q-R.
;; kuro-poll-modes-test-3.el covers the policy dispatch matrix for
;; kuro--clipboard-write and kuro--clipboard-query. This file adds:
;;   Group Q: message-emission behavior and unknown-policy edge cases
;;            not covered by test-3 (which stubs message to #'ignore)
;;   Group R: kuro--clipboard-query write-only and unknown-policy edge cases

;;; Code:

(require 'kuro-poll-modes-test-support)

;;; Group Q: kuro--clipboard-write — message emission and edge cases
;; kuro-poll-modes-test-3 stubs (message) to #'ignore in the policy matrix;
;; these tests verify that message IS actually called under write-only/allow.

(ert-deftest kuro-poll-modes-clipboard-write-allow-emits-clipboard-message ()
  "kuro--clipboard-write under allow policy calls message (clipboard notification)."
  (kuro-poll-test--with-buffer
    (let ((kuro-clipboard-policy 'allow)
          (msg-called nil))
      (cl-letf (((symbol-function 'kill-new) #'ignore)
                ((symbol-function 'message)
                 (lambda (fmt &rest _args) (setq msg-called fmt))))
        (kuro--clipboard-write "data" "clipboard")
        (should msg-called)))))

(ert-deftest kuro-poll-modes-clipboard-write-write-only-emits-clipboard-message ()
  "kuro--clipboard-write under write-only policy calls message."
  (kuro-poll-test--with-buffer
    (let ((kuro-clipboard-policy 'write-only)
          (msg-called nil))
      (cl-letf (((symbol-function 'kill-new) #'ignore)
                ((symbol-function 'message)
                 (lambda (fmt &rest _args) (setq msg-called fmt))))
        (kuro--clipboard-write "data" "clipboard")
        (should msg-called)))))

(ert-deftest kuro-poll-modes-clipboard-write-unknown-policy-does-not-call-kill-new ()
  "kuro--clipboard-write with an unrecognised policy symbol does nothing."
  (kuro-poll-test--with-buffer
    (let ((kuro-clipboard-policy 'bogus-unrecognised)
          (kill-new-called nil))
      (cl-letf (((symbol-function 'kill-new) (lambda (_) (setq kill-new-called t)))
                ((symbol-function 'message) #'ignore))
        (kuro--clipboard-write "text" "clipboard")
        (should-not kill-new-called)))))

(ert-deftest kuro-poll-modes-clipboard-write-prompt-includes-text-length ()
  "kuro--clipboard-write under prompt policy shows the text length in the prompt."
  (kuro-poll-test--with-buffer
    (let ((kuro-clipboard-policy 'prompt)
          (prompt-text nil))
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (msg) (setq prompt-text msg) nil))
                ((symbol-function 'kill-new) #'ignore))
        (kuro--clipboard-write "hello-world" "clipboard")
        ;; The prompt must mention the 11-character length.
        (should (string-match-p "11" prompt-text))))))

;;; Group R: kuro--clipboard-query — write-only and unknown policies
;; kuro-poll-modes-test-3 covers allow/deny/prompt.
;; write-only and unknown are distinct: they fall through the pcase with no clause.

(ert-deftest kuro-poll-modes-clipboard-query-write-only-does-not-send ()
  "kuro--clipboard-query under write-only policy does NOT send OSC 52 response.
write-only allows the terminal to WRITE to Emacs, not READ from Emacs."
  (kuro-poll-test--with-buffer
    (let ((kuro-clipboard-policy 'write-only)
          (sent nil))
      (cl-letf (((symbol-function 'kuro--send-osc52-clipboard-response)
                 (lambda () (setq sent t))))
        (kuro--clipboard-query "clipboard")
        (should-not sent)))))

(ert-deftest kuro-poll-modes-clipboard-query-unknown-policy-does-not-send ()
  "kuro--clipboard-query with an unrecognised policy does NOT send OSC 52 response."
  (kuro-poll-test--with-buffer
    (let ((kuro-clipboard-policy 'bogus-unrecognised)
          (sent nil))
      (cl-letf (((symbol-function 'kuro--send-osc52-clipboard-response)
                 (lambda () (setq sent t))))
        (kuro--clipboard-query "clipboard")
        (should-not sent)))))


(provide 'kuro-poll-modes-clipboard-test)
;;; kuro-poll-modes-clipboard-test.el ends here
