;;; kuro-poll-modes-test-4.el --- kuro-poll-modes tests Group K  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-poll-modes-test-support)

;;; Group K: kuro--handle-clipboard-actions — allow and prompt policies

(ert-deftest kuro-poll-modes-clipboard-allow-policy-writes-kill-ring ()
  "kuro--handle-clipboard-actions calls kill-new for write actions under allow policy."
  (kuro-poll-test--with-clipboard-write-action 'allow "allowed text" nil
    (kuro--handle-clipboard-actions)
    (should kill-new-called)
    (should (equal kill-new-called-with "allowed text"))))

(ert-deftest kuro-poll-modes-clipboard-prompt-write-accepted ()
  "kuro--handle-clipboard-actions calls kill-new under prompt policy when user accepts."
  (kuro-poll-test--with-clipboard-write-action 'prompt "prompted text" t
    (kuro--handle-clipboard-actions)
    (should kill-new-called)
    (should (equal kill-new-called-with "prompted text"))))

(ert-deftest kuro-poll-modes-clipboard-prompt-write-rejected ()
  "kuro--handle-clipboard-actions does NOT call kill-new under prompt policy when user declines."
  (kuro-poll-test--with-clipboard-write-action 'prompt "rejected text" nil
    (kuro--handle-clipboard-actions)
    (should-not kill-new-called)
    (should-not kill-new-called-with)))

(ert-deftest kuro-poll-modes-clipboard-allow-policy-sends-query-response ()
  "kuro--handle-clipboard-actions sends OSC 52 response for query under allow policy."
  (kuro-poll-test--with-clipboard-query-action 'allow "clip text"
    (kuro--handle-clipboard-actions)
    (should (stringp sent-key))
    (should (string-prefix-p "\e]52;c;" sent-key))))

(ert-deftest kuro-poll-modes-clipboard-query-deny-policy-does-not-send ()
  "kuro--handle-clipboard-actions does NOT send query response under deny policy."
  (kuro-poll-test--with-clipboard-query-action 'deny "clip text"
    (kuro--handle-clipboard-actions)
    (should-not sent-key)))

(provide 'kuro-poll-modes-test-4)
;;; kuro-poll-modes-test-4.el ends here
