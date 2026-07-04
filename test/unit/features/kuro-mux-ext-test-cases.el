;;; kuro-mux-ext-test-cases.el --- Case tables for kuro-mux-ext tests  -*- lexical-binding: t; -*-

;;; Code:

(defconst kuro-mux-ext-test--interactive-command-table
  '((kuro-mux-ext-break-pane-is-interactive kuro-mux-break-pane)
    (kuro-mux-ext-join-pane-is-interactive kuro-mux-join-pane)
    (kuro-mux-ext-rename-is-interactive kuro-mux-rename)
    (kuro-mux-ext-send-to-session-is-interactive kuro-mux-send-to-session)
    (kuro-mux-ext-monitor-activity-toggle-is-interactive kuro-mux-monitor-activity-toggle)
    (kuro-mux-ext-monitor-silence-is-interactive kuro-mux-monitor-silence)
    (kuro-mux-ext-pipe-pane-is-interactive kuro-mux-pipe-pane))
  "Interactive command checks for `kuro-mux-ext'.")

(defconst kuro-mux-ext-test--auto-save-on-exit-table
  '((kuro-mux-ext-auto-save-on-exit-noop-when-disabled nil (x) nil)
    (kuro-mux-ext-auto-save-on-exit-noop-when-no-sessions t nil nil)
    (kuro-mux-ext-auto-save-on-exit-saves-when-enabled-and-sessions t (x) t))
  "Cases for `kuro-mux--auto-save-on-exit'.")

(defconst kuro-mux-ext-test--tab-bar-update-table
  '((kuro-mux-ext-tab-bar-update-creates-tab-for-new-session
     nil
     t
     (tab-bar-tabs tab-bar-rename-tab))
    (kuro-mux-ext-tab-bar-update-skips-existing-tab
     (((name . "test-session")))
     nil
     (tab-bar-tabs)))
  "Cases for `kuro-mux--tab-bar-update' active path.")

(provide 'kuro-mux-ext-test-cases)
;;; kuro-mux-ext-test-cases.el ends here
