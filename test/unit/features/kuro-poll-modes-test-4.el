;;; kuro-poll-modes-test-4.el --- kuro-poll-modes tests Group K  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-poll-modes-test-support)

;;; Group K: kuro--handle-clipboard-actions — allow and prompt policies

(ert-deftest kuro-poll-modes-clipboard-allow-policy-writes-kill-ring ()
  "kuro--handle-clipboard-actions calls kill-new for write actions under allow policy."
  (kuro-poll-test--with-buffer
    (let ((kill-new-called-with nil)
          (kuro-clipboard-policy 'allow))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "allowed text"))))
                ((symbol-function 'kill-new)
                 (lambda (text) (setq kill-new-called-with text)))
                ((symbol-function 'message) #'ignore))
        (kuro--handle-clipboard-actions)
        (should (equal kill-new-called-with "allowed text"))))))

(ert-deftest kuro-poll-modes-clipboard-prompt-write-accepted ()
  "kuro--handle-clipboard-actions calls kill-new under prompt policy when user accepts."
  (kuro-poll-test--with-buffer
    (let ((kill-new-called nil)
          (kuro-clipboard-policy 'prompt))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "prompted text"))))
                ((symbol-function 'yes-or-no-p) (lambda (_prompt) t))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t))))
        (kuro--handle-clipboard-actions)
        (should kill-new-called)))))

(ert-deftest kuro-poll-modes-clipboard-prompt-write-rejected ()
  "kuro--handle-clipboard-actions does NOT call kill-new under prompt policy when user declines."
  (kuro-poll-test--with-buffer
    (let ((kill-new-called nil)
          (kuro-clipboard-policy 'prompt))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "rejected text"))))
                ((symbol-function 'yes-or-no-p) (lambda (_prompt) nil))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t))))
        (kuro--handle-clipboard-actions)
        (should-not kill-new-called)))))

(ert-deftest kuro-poll-modes-clipboard-allow-policy-sends-query-response ()
  "kuro--handle-clipboard-actions sends OSC 52 response for query under allow policy."
  (kuro-poll-test--with-buffer
    (let ((sent-key nil)
          (kuro-clipboard-policy 'allow))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((query))))
                ((symbol-function 'current-kill) (lambda (_n _do-not-move) "clip text"))
                ((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent-key s))))
        (kuro--handle-clipboard-actions)
        (should (stringp sent-key))
        (should (string-prefix-p "\e]52;c;" sent-key))))))

(ert-deftest kuro-poll-modes-clipboard-query-deny-policy-does-not-send ()
  "kuro--handle-clipboard-actions does NOT send query response under deny policy."
  (kuro-poll-test--with-buffer
    (let ((sent-key nil)
          (kuro-clipboard-policy 'deny))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((query))))
                ((symbol-function 'kuro--send-key)
                 (lambda (s) (setq sent-key s))))
        (kuro--handle-clipboard-actions)
        (should-not sent-key)))))

(provide 'kuro-poll-modes-test-4)
;;; kuro-poll-modes-test-4.el ends here
