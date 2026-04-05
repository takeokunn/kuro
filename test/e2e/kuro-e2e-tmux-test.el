;;; kuro-e2e-tmux-test.el --- E2E tests for tmux integration -*- lexical-binding: t -*-

;;; Commentary:
;; End-to-end tests for tmux nested terminal integration.
;; Uses slow-timeout (30s) for all tmux lifecycle waits.
;; Design policy: NO standalone sleep-for calls.
;; All waiting is done via condition-based polling.

;;; Code:

(require 'ert)
(require 'kuro-e2e-helpers)

(ert-deftest kuro-e2e-tmux-launches ()
  "Tmux starts successfully and renders a status bar."
  :expected-result kuro-e2e--expected-result
  (skip-unless (executable-find "tmux"))
  (kuro-e2e--with-terminal
   (unwind-protect
       (progn
         (kuro--send-key
          "tmux -L kuro-e2e-test -f /dev/null new-session -s kuro-test -d && tmux -L kuro-e2e-test attach -t kuro-test")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-tmux buf)))
     (shell-command "tmux -L kuro-e2e-test kill-server 2>/dev/null"))))

(ert-deftest kuro-e2e-tmux-pane-split ()
  "Horizontal then vertical pane split produces 3 panes."
  :expected-result kuro-e2e--expected-result
  (skip-unless (executable-find "tmux"))
  (kuro-e2e--with-terminal
   (unwind-protect
       (progn
         ;; Start tmux and wait for status bar
         (kuro--send-key
          "tmux -L kuro-e2e-test -f /dev/null new-session -s kuro-test -d && tmux -L kuro-e2e-test attach -t kuro-test")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-tmux buf))
         ;; Horizontal split → wait for 2 panes
         (kuro--send-key "tmux split-window -h -t kuro-test")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-tmux-pane 2))
         (kuro-e2e--render-idle buf)
         ;; Vertical split → wait for 3 panes
         (kuro--send-key "tmux split-window -v -t kuro-test")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-tmux-pane 3))
         ;; Extra confirmation via tmux command output in the terminal
         (kuro--send-key
          "tmux list-panes -t kuro-test | wc -l | xargs printf 'KURO_PANE_COUNT_%s'")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-text buf "KURO_PANE_COUNT_3")))
     (shell-command "tmux -L kuro-e2e-test kill-server 2>/dev/null"))))

(ert-deftest kuro-e2e-tmux-pane-navigate ()
  "select-pane changes the active pane and input reaches the correct pane."
  :expected-result kuro-e2e--expected-result
  (skip-unless (executable-find "tmux"))
  (kuro-e2e--with-terminal
   (unwind-protect
       (progn
         ;; Start tmux
         (kuro--send-key
          "tmux -L kuro-e2e-test -f /dev/null new-session -s kuro-test -d && tmux -L kuro-e2e-test attach -t kuro-test")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-tmux buf))
         ;; Split horizontally → wait for 2 panes
         (kuro--send-key "tmux split-window -h -t kuro-test")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-tmux-pane 2))
         ;; Navigate to pane 0
         (kuro--send-key "tmux select-pane -t kuro-test:.0")
         (kuro--send-key "\r")
         (kuro-e2e--render-idle buf)
         ;; Verify active pane index via tmux display-message
         (kuro--send-key
          "tmux display-message -p 'KURO_PANE_IDX_#{pane_index}'")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-text buf "KURO_PANE_IDX_0"))
         ;; Type in active pane to confirm input routing
         (kuro--send-key "echo PANE_NAVIGATE_OK")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-text buf "PANE_NAVIGATE_OK")))
     (shell-command "tmux -L kuro-e2e-test kill-server 2>/dev/null"))))

(ert-deftest kuro-e2e-tmux-window-management ()
  "New-window and select-window navigate between tmux windows correctly."
  :expected-result kuro-e2e--expected-result
  (skip-unless (executable-find "tmux"))
  (kuro-e2e--with-terminal
   (unwind-protect
       (progn
         ;; Start tmux
         (kuro--send-key
          "tmux -L kuro-e2e-test -f /dev/null new-session -s kuro-test -d && tmux -L kuro-e2e-test attach -t kuro-test")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-tmux buf))
         ;; Open a new window
         (kuro--send-key "tmux new-window -t kuro-test")
         (kuro--send-key "\r")
         (kuro-e2e--render-idle buf)
         ;; Verify 2 windows via tmux command output
         (kuro--send-key
          "tmux list-windows -t kuro-test | wc -l | xargs printf 'KURO_WIN_COUNT_%s'")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-text buf "KURO_WIN_COUNT_2"))
         ;; Navigate back to window 0
         (kuro--send-key "tmux select-window -t kuro-test:0")
         (kuro--send-key "\r")
         (kuro-e2e--render-idle buf)
         ;; Confirm input reaches window 0
         (kuro--send-key "echo WINDOW_NAVIGATE_OK")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-text buf "WINDOW_NAVIGATE_OK")))
     (shell-command "tmux -L kuro-e2e-test kill-server 2>/dev/null"))))

(ert-deftest kuro-e2e-tmux-session-cleanup ()
  "kill-session terminates tmux and returns control to the underlying shell."
  :expected-result kuro-e2e--expected-result
  (skip-unless (executable-find "tmux"))
  (kuro-e2e--with-terminal
   (unwind-protect
       (progn
         ;; Start tmux
         (kuro--send-key
          "tmux -L kuro-e2e-test -f /dev/null new-session -s kuro-test -d && tmux -L kuro-e2e-test attach -t kuro-test")
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-tmux buf))
         ;; Kill the session from within tmux
         (kuro--send-key "tmux kill-session -t kuro-test")
         (kuro--send-key "\r")
         ;; Wait for the tmux server process to fully exit
         (kuro-e2e--wait-for-tmux-dead)
         (kuro-e2e--render-idle buf)
         ;; Confirm the underlying shell is still alive via ready marker
         (kuro--send-key (concat "echo " kuro-e2e--ready-marker))
         (kuro--send-key "\r")
         (should (kuro-e2e--wait-for-text buf kuro-e2e--ready-marker kuro-e2e--slow-timeout)))
     (shell-command "tmux -L kuro-e2e-test kill-server 2>/dev/null"))))

(provide 'kuro-e2e-tmux-test)

;;; kuro-e2e-tmux-test.el ends here
