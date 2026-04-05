;;; kuro-e2e-vim-test.el --- E2E tests for vim and pager interaction -*- lexical-binding: t -*-

;;; Commentary:
;; End-to-end tests for full-screen terminal programs (vim, less).
;; Uses slow-timeout (30s) for all program-lifecycle waits.
;; Design policy: NO standalone sleep-for calls.
;; All waiting is done via condition-based polling.

;;; Code:

(require 'ert)
(require 'kuro-e2e-helpers)

(ert-deftest kuro-e2e-vim-basic ()
  "Vim opens a file on the alternate screen and exits cleanly back to shell."
  :expected-result kuro-e2e--expected-result
  (skip-unless (executable-find "vim"))
  (kuro-e2e--with-terminal
   (let* ((unique-id (format "%d" (abs (random))))
          (tmpname (format "kurovimtest%s" unique-id))
          (tmpfile (format "/tmp/%s" tmpname)))
     ;; Create temp file and wait for confirmation
     (kuro--send-key (format "touch %s && echo KTOUCH_OK" tmpfile))
     (kuro--send-key "\r")
     (should (kuro-e2e--wait-for-text buf "KTOUCH_OK"))
     ;; Open vim, wait for filename in status bar (slow timeout for startup)
     (kuro--send-key (format "vim %s" tmpfile))
     (kuro--send-key "\r")
     (should (kuro-e2e--wait-for-text buf tmpname kuro-e2e--slow-timeout))
     (kuro-e2e--render-idle buf)
     ;; Quit vim: ESC to ensure normal mode, then :q!
     (kuro--send-key "\x1b")
     (kuro--send-key ":q!")
     (kuro--send-key "\r")
     ;; Wait for shell to return (send ready marker, poll for it)
     (kuro--send-key (concat "echo " kuro-e2e--ready-marker))
     (kuro--send-key "\r")
     (should (kuro-e2e--wait-for-text buf kuro-e2e--ready-marker kuro-e2e--slow-timeout))
     ;; Cleanup
     (kuro--send-key (format "rm -f %s" tmpfile))
     (kuro--send-key "\r")
     (kuro-e2e--render-idle buf))))

(ert-deftest kuro-e2e-less-pager ()
  "Less pager uses the alternate screen and returns to shell on quit."
  :expected-result kuro-e2e--expected-result
  (skip-unless (executable-find "less"))
  (kuro-e2e--with-terminal
   ;; Launch less with numeric output
   (kuro--send-key "seq 1 50 | less")
   (kuro--send-key "\r")
   ;; Wait for content to appear (digits from seq)
   (should (kuro-e2e--wait-for-text buf "[0-9]" kuro-e2e--slow-timeout))
   (kuro-e2e--render-idle buf)
   ;; Quit less
   (kuro--send-key "q")
   (kuro-e2e--render-idle buf)
   ;; Confirm shell is alive
   (kuro--send-key "echo KLESSOK")
   (kuro--send-key "\r")
   (should (kuro-e2e--wait-for-text buf "KLESSOK" kuro-e2e--slow-timeout))))

(provide 'kuro-e2e-vim-test)

;;; kuro-e2e-vim-test.el ends here
