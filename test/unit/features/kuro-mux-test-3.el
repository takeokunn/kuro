;;; kuro-mux-test-3.el --- ERT tests for kuro-mux.el — Groups 23-29  -*-  lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

;;; Group 23 — kuro-mux-find-window

(ert-deftest kuro-mux-test-find-window-is-interactive ()
  "`kuro-mux-find-window' is an interactive command."
  (should (commandp #'kuro-mux-find-window)))

(ert-deftest kuro-mux-test-find-window-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds f to kuro-mux-find-window."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "f"))
              #'kuro-mux-find-window)))

(ert-deftest kuro-mux-test-find-window-selects-visible-window ()
  "`kuro-mux-find-window' calls `select-window' when the buffer is visible."
  (let* ((fake-win (list 'window 'fake))
         selected-win)
    (cl-letf (((symbol-function 'get-buffer)
               (lambda (_) (current-buffer)))
              ((symbol-function 'get-buffer-window)
               (lambda (_buf _flag) fake-win))
              ((symbol-function 'select-window)
               (lambda (w) (setq selected-win w)))
              ((symbol-function 'switch-to-buffer)
               (lambda (_) (error "switch-to-buffer must not be called"))))
      (kuro-mux-find-window "*kuro-test*")
      (should (eq selected-win fake-win)))))

(ert-deftest kuro-mux-test-find-window-switches-when-not-visible ()
  "`kuro-mux-find-window' calls `switch-to-buffer' when buffer exists but is not visible."
  (let (switched-to)
    (cl-letf (((symbol-function 'get-buffer)
               (lambda (_) (current-buffer)))
              ((symbol-function 'get-buffer-window)
               (lambda (_buf _flag) nil))
              ((symbol-function 'select-window)
               (lambda (_) (error "select-window must not be called")))
              ((symbol-function 'switch-to-buffer)
               (lambda (buf) (setq switched-to buf))))
      (kuro-mux-find-window "*kuro-test*")
      (should (eq switched-to (current-buffer))))))

(ert-deftest kuro-mux-test-find-window-errors-on-missing-buffer ()
  "`kuro-mux-find-window' signals user-error when `get-buffer' returns nil."
  (cl-letf (((symbol-function 'get-buffer) (lambda (_) nil)))
    (should-error (kuro-mux-find-window "nonexistent") :type 'user-error)))

(ert-deftest kuro-mux-test-find-window-uses-live-sessions-for-completion ()
  "The `completing-read' candidates come from `kuro-mux--live-sessions'."
  (let ((candidates :unset))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt cands &rest _) (setq candidates cands) ""))
              ((symbol-function 'kuro-mux--live-sessions)
               (lambda () (list (current-buffer))))
              ((symbol-function 'get-buffer) (lambda (_) nil)))
      (ignore-errors (call-interactively #'kuro-mux-find-window))
      (should (listp candidates)))))

;;; Group 24 — kuro-mux-auto-save-layout + kill-emacs-hook integration

(ert-deftest kuro-mux-test-auto-save-layout-default-is-nil ()
  "`kuro-mux-auto-save-layout' defaults to nil."
  (should (null (default-value 'kuro-mux-auto-save-layout))))

(ert-deftest kuro-mux-test-install-hooks-adds-kill-emacs-hook ()
  "`kuro-mux--install-hooks' adds `kuro-mux--auto-save-on-exit' to `kill-emacs-hook'."
  (let ((kill-emacs-hook nil))
    (kuro-mux--install-hooks)
    (should (memq #'kuro-mux--auto-save-on-exit kill-emacs-hook))
    (kuro-mux--uninstall-hooks)))

(ert-deftest kuro-mux-test-uninstall-hooks-removes-kill-emacs-hook ()
  "`kuro-mux--uninstall-hooks' removes `kuro-mux--auto-save-on-exit' from `kill-emacs-hook'."
  (let ((kill-emacs-hook (list #'kuro-mux--auto-save-on-exit)))
    (kuro-mux--uninstall-hooks)
    (should (null (memq #'kuro-mux--auto-save-on-exit kill-emacs-hook)))))

(ert-deftest kuro-mux-test-auto-save-on-exit-noop-when-disabled ()
  "`kuro-mux--auto-save-on-exit' does not call `kuro-mux-save-layout' when auto-save is nil."
  (let ((kuro-mux-auto-save-layout nil)
        (saved nil))
    (cl-letf (((symbol-function 'kuro-mux-save-layout)
               (lambda () (setq saved t)))
              ((symbol-function 'kuro-mux--live-sessions)
               (lambda () (list (current-buffer)))))
      (kuro-mux--auto-save-on-exit)
      (should (null saved)))))

(ert-deftest kuro-mux-test-auto-save-on-exit-saves-when-enabled ()
  "`kuro-mux--auto-save-on-exit' calls `kuro-mux-save-layout' when auto-save is t."
  (let ((kuro-mux-auto-save-layout t)
        (saved nil))
    (cl-letf (((symbol-function 'kuro-mux-save-layout)
               (lambda () (setq saved t)))
              ((symbol-function 'kuro-mux--live-sessions)
               (lambda () (list (current-buffer)))))
      (kuro-mux--auto-save-on-exit)
      (should saved))))

(ert-deftest kuro-mux-test-auto-save-on-exit-noop-when-no-sessions ()
  "`kuro-mux--auto-save-on-exit' skips save when no live sessions exist."
  (let ((kuro-mux-auto-save-layout t)
        (saved nil))
    (cl-letf (((symbol-function 'kuro-mux-save-layout)
               (lambda () (setq saved t)))
              ((symbol-function 'kuro-mux--live-sessions)
               (lambda () nil)))
      (kuro-mux--auto-save-on-exit)
      (should (null saved)))))

;;; Group 25 — kuro-mux-break-pane + kuro-mux-join-pane

(ert-deftest kuro-mux-test-break-pane-rejects-non-kuro-buffer ()
  "`kuro-mux-break-pane' signals user-error when not in a kuro buffer."
  (with-temp-buffer
    (should-error (kuro-mux-break-pane) :type 'user-error)))

(ert-deftest kuro-mux-test-break-pane-creates-new-frame ()
  "`kuro-mux-break-pane' calls `make-frame' to create a new frame."
  (with-temp-buffer
    (kuro-mode)
    (let ((frame-made nil))
      (cl-letf (((symbol-function 'make-frame)
                 (lambda (&optional _params) (setq frame-made t) (selected-frame)))
                ((symbol-function 'window-list)
                 (lambda (&rest _) '(win1)))
                ((symbol-function 'delete-window)
                 (lambda (&optional _) nil)))
        (kuro-mux-break-pane)
        (should frame-made)))))

(ert-deftest kuro-mux-test-break-pane-deletes-window-when-multiple ()
  "`kuro-mux-break-pane' deletes the source window when multiple windows exist."
  (with-temp-buffer
    (kuro-mode)
    (let ((window-deleted nil))
      (cl-letf (((symbol-function 'make-frame)
                 (lambda (&optional _params) (selected-frame)))
                ((symbol-function 'window-list)
                 (lambda (&rest _) '(win1 win2)))
                ((symbol-function 'delete-window)
                 (lambda (&optional _) (setq window-deleted t))))
        (kuro-mux-break-pane)
        (should window-deleted)))))

(ert-deftest kuro-mux-test-break-pane-no-delete-when-sole-window ()
  "`kuro-mux-break-pane' does not delete window when it is the only one."
  (with-temp-buffer
    (kuro-mode)
    (let ((window-deleted nil))
      (cl-letf (((symbol-function 'make-frame)
                 (lambda (&optional _params) (selected-frame)))
                ((symbol-function 'window-list)
                 (lambda (&rest _) '(win1)))
                ((symbol-function 'delete-window)
                 (lambda (&optional _) (setq window-deleted t))))
        (kuro-mux-break-pane)
        (should (null window-deleted))))))

(ert-deftest kuro-mux-test-break-pane-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `!' to `kuro-mux-break-pane'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "!")) #'kuro-mux-break-pane)))

(ert-deftest kuro-mux-test-join-pane-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `@' to `kuro-mux-join-pane'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "@")) #'kuro-mux-join-pane)))

(ert-deftest kuro-mux-test-join-pane-dead-buffer-signals-error ()
  "`kuro-mux-join-pane' signals user-error when the named buffer is dead."
  (should-error (kuro-mux-join-pane " *nonexistent-kuro-99*") :type 'user-error))

(ert-deftest kuro-mux-test-join-pane-splits-and-selects ()
  "`kuro-mux-join-pane' splits the window right and selects the new window."
  (with-temp-buffer
    (kuro-mode)
    (let ((the-buf (current-buffer))
          (split-called nil)
          (selected-buf nil))
      (cl-letf (((symbol-function 'split-window-right)
                 (lambda () (setq split-called t) (selected-window)))
                ((symbol-function 'set-window-buffer)
                 (lambda (_win buf) (setq selected-buf buf)))
                ((symbol-function 'select-window)
                 (lambda (_w) nil)))
        (kuro-mux-join-pane (buffer-name the-buf))
        (should split-called)
        (should (eq selected-buf the-buf))))))

;;; Group 26 — kuro-mux-monitor-activity-toggle + kuro-mux-monitor-silence

(ert-deftest kuro-mux-test-monitor-activity-default-nil ()
  "`kuro-mux--monitor-activity' starts as nil in a fresh kuro buffer."
  (with-temp-buffer
    (kuro-mode)
    (should (null kuro-mux--monitor-activity))))

(ert-deftest kuro-mux-test-monitor-activity-toggle-rejects-non-kuro ()
  "`kuro-mux-monitor-activity-toggle' signals user-error outside kuro-mode."
  (with-temp-buffer
    (should-error (kuro-mux-monitor-activity-toggle) :type 'user-error)))

(ert-deftest kuro-mux-test-monitor-activity-toggle-enables ()
  "`kuro-mux-monitor-activity-toggle' sets `kuro-mux--monitor-activity' to t."
  (with-temp-buffer
    (kuro-mode)
    (kuro-mux-monitor-activity-toggle)
    (should kuro-mux--monitor-activity)))

(ert-deftest kuro-mux-test-monitor-activity-toggle-adds-hook ()
  "`kuro-mux-monitor-activity-toggle' adds watcher to `after-change-functions'."
  (with-temp-buffer
    (kuro-mode)
    (kuro-mux-monitor-activity-toggle)
    (should (memq #'kuro-mux--activity-watcher after-change-functions))
    ;; cleanup
    (kuro-mux-monitor-activity-toggle)))

(ert-deftest kuro-mux-test-monitor-activity-toggle-disables ()
  "`kuro-mux-monitor-activity-toggle' toggles back to nil on second call."
  (with-temp-buffer
    (kuro-mode)
    (kuro-mux-monitor-activity-toggle)
    (kuro-mux-monitor-activity-toggle)
    (should (null kuro-mux--monitor-activity))))

(ert-deftest kuro-mux-test-monitor-activity-toggle-removes-hook ()
  "`kuro-mux-monitor-activity-toggle' removes watcher from `after-change-functions' on disable."
  (with-temp-buffer
    (kuro-mode)
    (kuro-mux-monitor-activity-toggle)
    (kuro-mux-monitor-activity-toggle)
    (should (null (memq #'kuro-mux--activity-watcher after-change-functions)))))

(ert-deftest kuro-mux-test-activity-watcher-noop-when-disabled ()
  "`kuro-mux--activity-watcher' does not notify when monitoring is off."
  (with-temp-buffer
    (kuro-mode)
    (let ((notified nil))
      (cl-letf (((symbol-function 'kuro--activity-notify)
                 (lambda (_title _body) (setq notified t)))
                ((symbol-function 'get-buffer-window)
                 (lambda (_buf _vis) nil)))
        (kuro-mux--activity-watcher 1 2 0)
        (should (null notified))))))

(ert-deftest kuro-mux-test-activity-watcher-notifies-background ()
  "`kuro-mux--activity-watcher' fires when monitoring on and buffer is not visible."
  (with-temp-buffer
    (kuro-mode)
    (setq kuro-mux--monitor-activity t)
    (setq kuro-mux--monitor-activity-last-notified 0)
    (let ((notified nil))
      (cl-letf (((symbol-function 'kuro--activity-notify)
                 (lambda (_title _body) (setq notified t)))
                ((symbol-function 'get-buffer-window)
                 (lambda (_buf _vis) nil)))
        (kuro-mux--activity-watcher 1 2 0)
        (should notified)))))

(ert-deftest kuro-mux-test-activity-watcher-skips-visible-buffer ()
  "`kuro-mux--activity-watcher' does not notify when buffer is visible."
  (with-temp-buffer
    (kuro-mode)
    (setq kuro-mux--monitor-activity t)
    (setq kuro-mux--monitor-activity-last-notified 0)
    (let ((notified nil))
      (cl-letf (((symbol-function 'kuro--activity-notify)
                 (lambda (_title _body) (setq notified t)))
                ((symbol-function 'get-buffer-window)
                 (lambda (_buf _vis) (selected-window))))
        (kuro-mux--activity-watcher 1 2 0)
        (should (null notified))))))

(ert-deftest kuro-mux-test-monitor-silence-rejects-non-kuro ()
  "`kuro-mux-monitor-silence' signals user-error outside kuro-mode."
  (with-temp-buffer
    (should-error (kuro-mux-monitor-silence 30) :type 'user-error)))

(ert-deftest kuro-mux-test-monitor-silence-sets-seconds ()
  "`kuro-mux-monitor-silence' sets `kuro-mux--monitor-silence-seconds' to N."
  (with-temp-buffer
    (kuro-mode)
    (cl-letf (((symbol-function 'run-with-timer) (lambda (&rest _) nil)))
      (kuro-mux-monitor-silence 30)
      (should (= kuro-mux--monitor-silence-seconds 30))
      (kuro-mux-monitor-silence 0))))

(ert-deftest kuro-mux-test-monitor-silence-zero-disables ()
  "`kuro-mux-monitor-silence' with 0 disables monitoring."
  (with-temp-buffer
    (kuro-mode)
    (setq kuro-mux--monitor-silence-seconds 30)
    (kuro-mux-monitor-silence 0)
    (should (null kuro-mux--monitor-silence-seconds))))

(ert-deftest kuro-mux-test-monitor-activity-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `m' to `kuro-mux-monitor-activity-toggle'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "m"))
              #'kuro-mux-monitor-activity-toggle)))

(ert-deftest kuro-mux-test-monitor-silence-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `M' to `kuro-mux-monitor-silence'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "M"))
              #'kuro-mux-monitor-silence)))

(ert-deftest kuro-mux-test-choose-window-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `w' to `kuro-list-sessions'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "w"))
              #'kuro-list-sessions)))

;;; Group 27 — kuro-mux-select-layout (tmux preset layouts)

(ert-deftest kuro-mux-test-layouts-constant ()
  "`kuro-mux-layouts' lists the five tmux preset layout names."
  (should (equal kuro-mux-layouts
                 '("even-horizontal" "even-vertical"
                   "main-vertical" "main-horizontal" "tiled"))))

(ert-deftest kuro-mux-test-select-layout-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `M-SPC' to the `kuro-mux-select-layout' picker.
`SPC' itself cycles to the next layout (tmux parity); see Group 28."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "M-SPC"))
              #'kuro-mux-select-layout)))

(ert-deftest kuro-mux-test-select-layout-rejects-unknown ()
  "`kuro-mux-select-layout' signals user-error for an unrecognized layout."
  (should-error (kuro-mux-select-layout "spiral") :type 'user-error))

(ert-deftest kuro-mux-test-visible-session-buffers-filters-kuro ()
  "`kuro-mux--visible-session-buffers' returns only kuro-mode buffers, deduped."
  (let ((kuro-buf (get-buffer-create "*mux-vis-kuro*"))
        (plain    (get-buffer-create "*mux-vis-plain*")))
    (unwind-protect
        (progn
          (with-current-buffer kuro-buf (kuro-mode))
          (cl-letf (((symbol-function 'window-list)
                     (lambda (&rest _) '(w1 w2 w3)))
                    ((symbol-function 'window-buffer)
                     (lambda (w) (pcase w
                                   ('w1 kuro-buf)
                                   ('w2 plain)
                                   ('w3 kuro-buf)))))
            (should (equal (kuro-mux--visible-session-buffers)
                           (list kuro-buf)))))
      (kill-buffer kuro-buf)
      (kill-buffer plain))))

(ert-deftest kuro-mux-test-select-layout-no-panes-errors ()
  "`kuro-mux-select-layout' signals user-error when no kuro panes are visible."
  (cl-letf (((symbol-function 'kuro-mux--visible-session-buffers)
             (lambda () nil)))
    (should-error (kuro-mux-select-layout "tiled") :type 'user-error)))

(ert-deftest kuro-mux-test-select-layout-even-horizontal-chains-splits ()
  "even-horizontal splits to the `right' once per non-main buffer."
  (let ((b1 (get-buffer-create "*mux-eh1*"))
        (b2 (get-buffer-create "*mux-eh2*"))
        (b3 (get-buffer-create "*mux-eh3*"))
        (split-sides nil))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--visible-session-buffers)
                   (lambda () (list b1 b2 b3)))
                  ((symbol-function 'delete-other-windows) (lambda () nil))
                  ((symbol-function 'set-window-buffer) (lambda (&rest _) nil))
                  ((symbol-function 'balance-windows) (lambda (&rest _) nil))
                  ((symbol-function 'split-window)
                   (lambda (_win _size side) (push side split-sides) 'newwin)))
          (kuro-mux-select-layout "even-horizontal")
          ;; Two non-main buffers → two splits, both toward `right'.
          (should (equal split-sides '(right right))))
      (kill-buffer b1) (kill-buffer b2) (kill-buffer b3))))

(ert-deftest kuro-mux-test-select-layout-even-vertical-uses-below ()
  "even-vertical splits toward `below'."
  (let ((b1 (get-buffer-create "*mux-ev1*"))
        (b2 (get-buffer-create "*mux-ev2*"))
        (split-sides nil))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--visible-session-buffers)
                   (lambda () (list b1 b2)))
                  ((symbol-function 'delete-other-windows) (lambda () nil))
                  ((symbol-function 'set-window-buffer) (lambda (&rest _) nil))
                  ((symbol-function 'balance-windows) (lambda (&rest _) nil))
                  ((symbol-function 'split-window)
                   (lambda (_win _size side) (push side split-sides) 'newwin)))
          (kuro-mux-select-layout "even-vertical")
          (should (equal split-sides '(below))))
      (kill-buffer b1) (kill-buffer b2))))

(ert-deftest kuro-mux-test-select-layout-main-vertical-splits ()
  "main-vertical splits the main area `right' then stacks the rest `below'."
  (let ((b1 (get-buffer-create "*mux-mv1*"))
        (b2 (get-buffer-create "*mux-mv2*"))
        (b3 (get-buffer-create "*mux-mv3*"))
        (split-sides nil))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--visible-session-buffers)
                   (lambda () (list b1 b2 b3)))
                  ((symbol-function 'delete-other-windows) (lambda () nil))
                  ((symbol-function 'set-window-buffer) (lambda (&rest _) nil))
                  ((symbol-function 'balance-windows) (lambda (&rest _) nil))
                  ((symbol-function 'split-window)
                   (lambda (_win _size side) (push side split-sides) 'newwin)))
          (kuro-mux-select-layout "main-vertical")
          ;; First split carves the secondary area (right); remaining buffer
          ;; (b3) stacks below within it.
          (should (equal (nreverse split-sides) '(right below))))
      (kill-buffer b1) (kill-buffer b2) (kill-buffer b3))))

(ert-deftest kuro-mux-test-select-layout-single-pane-no-splits ()
  "With one visible pane, no splits occur and the layout still applies."
  (let ((b1 (get-buffer-create "*mux-sp1*"))
        (split-count 0))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--visible-session-buffers)
                   (lambda () (list b1)))
                  ((symbol-function 'delete-other-windows) (lambda () nil))
                  ((symbol-function 'set-window-buffer) (lambda (&rest _) nil))
                  ((symbol-function 'balance-windows) (lambda (&rest _) nil))
                  ((symbol-function 'split-window)
                   (lambda (&rest _) (setq split-count (1+ split-count)) 'w)))
          (kuro-mux-select-layout "even-horizontal")
          (should (= split-count 0)))
      (kill-buffer b1))))

;;; Group 28 — kuro-mux-next-layout / kuro-mux-previous-layout (cycling)

(ert-deftest kuro-mux-test-next-layout-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `SPC' to `kuro-mux-next-layout' (tmux parity)."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "SPC"))
              #'kuro-mux-next-layout)))

(ert-deftest kuro-mux-test-prev-layout-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `M-{' to `kuro-mux-previous-layout'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "M-{"))
              #'kuro-mux-previous-layout)))

(ert-deftest kuro-mux-test-next-layout-from-unset-picks-first ()
  "`kuro-mux-next-layout' on a fresh frame applies the first preset."
  (set-frame-parameter nil 'kuro-mux-current-layout nil)
  (let ((applied nil))
    (cl-letf (((symbol-function 'kuro-mux-select-layout)
               (lambda (layout) (setq applied layout))))
      (kuro-mux-next-layout)
      (should (equal applied "even-horizontal")))))

(ert-deftest kuro-mux-test-prev-layout-from-unset-picks-last ()
  "`kuro-mux-previous-layout' on a fresh frame applies the last preset."
  (set-frame-parameter nil 'kuro-mux-current-layout nil)
  (let ((applied nil))
    (cl-letf (((symbol-function 'kuro-mux-select-layout)
               (lambda (layout) (setq applied layout))))
      (kuro-mux-previous-layout)
      (should (equal applied "tiled")))))

(ert-deftest kuro-mux-test-next-layout-advances-one ()
  "`kuro-mux-next-layout' moves to the layout one position forward."
  (set-frame-parameter nil 'kuro-mux-current-layout "even-vertical")
  (let ((applied nil))
    (cl-letf (((symbol-function 'kuro-mux-select-layout)
               (lambda (layout) (setq applied layout))))
      (kuro-mux-next-layout)
      ;; even-vertical (idx 1) → main-vertical (idx 2)
      (should (equal applied "main-vertical")))))

(ert-deftest kuro-mux-test-next-layout-wraps-around ()
  "`kuro-mux-next-layout' wraps from the last preset back to the first."
  (set-frame-parameter nil 'kuro-mux-current-layout "tiled")
  (let ((applied nil))
    (cl-letf (((symbol-function 'kuro-mux-select-layout)
               (lambda (layout) (setq applied layout))))
      (kuro-mux-next-layout)
      (should (equal applied "even-horizontal")))))

(ert-deftest kuro-mux-test-prev-layout-wraps-around ()
  "`kuro-mux-previous-layout' wraps from the first preset to the last."
  (set-frame-parameter nil 'kuro-mux-current-layout "even-horizontal")
  (let ((applied nil))
    (cl-letf (((symbol-function 'kuro-mux-select-layout)
               (lambda (layout) (setq applied layout))))
      (kuro-mux-previous-layout)
      (should (equal applied "tiled")))))

(ert-deftest kuro-mux-test-select-layout-records-frame-param ()
  "`kuro-mux-select-layout' stores the applied layout on the frame."
  (let ((b1 (get-buffer-create "*mux-rec1*")))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--visible-session-buffers)
                   (lambda () (list b1)))
                  ((symbol-function 'delete-other-windows) (lambda () nil))
                  ((symbol-function 'set-window-buffer) (lambda (&rest _) nil))
                  ((symbol-function 'balance-windows) (lambda (&rest _) nil))
                  ((symbol-function 'split-window) (lambda (&rest _) 'w)))
          (set-frame-parameter nil 'kuro-mux-current-layout nil)
          (kuro-mux-select-layout "main-horizontal")
          (should (equal (frame-parameter nil 'kuro-mux-current-layout)
                         "main-horizontal")))
      (kill-buffer b1)
      (set-frame-parameter nil 'kuro-mux-current-layout nil))))

;;; Group 29 — kuro-mux-rotate-panes (tmux rotate-window)

(ert-deftest kuro-mux-test-rotate-panes-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `C-o' to `kuro-mux-rotate-panes'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "C-o"))
              #'kuro-mux-rotate-panes)))

(ert-deftest kuro-mux-test-rotate-backward-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `M-o' to `kuro-mux-rotate-panes-backward'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "M-o"))
              #'kuro-mux-rotate-panes-backward)))

(ert-deftest kuro-mux-test-rotate-panes-needs-two ()
  "`kuro-mux-rotate-panes' signals user-error with fewer than two panes."
  (cl-letf (((symbol-function 'kuro-mux--visible-windows)
             (lambda () '(w1))))
    (should-error (kuro-mux-rotate-panes) :type 'user-error)))

(ert-deftest kuro-mux-test-rotate-panes-forward-mapping ()
  "Forward rotation: each window takes the previous window's buffer; w1 wraps."
  (let ((assignments nil))
    (cl-letf (((symbol-function 'kuro-mux--visible-windows)
               (lambda () '(w1 w2 w3)))
              ((symbol-function 'window-buffer)
               (lambda (w) (pcase w ('w1 'A) ('w2 'B) ('w3 'C))))
              ((symbol-function 'set-window-buffer)
               (lambda (win buf) (push (cons win buf) assignments)))
              ((symbol-function 'select-window) #'ignore))
      (kuro-mux-rotate-panes)
      (should (equal (nreverse assignments)
                     '((w1 . C) (w2 . A) (w3 . B)))))))

(ert-deftest kuro-mux-test-rotate-panes-backward-mapping ()
  "Backward rotation: each window takes the next window's buffer; w1 takes w2's."
  (let ((assignments nil))
    (cl-letf (((symbol-function 'kuro-mux--visible-windows)
               (lambda () '(w1 w2 w3)))
              ((symbol-function 'window-buffer)
               (lambda (w) (pcase w ('w1 'A) ('w2 'B) ('w3 'C))))
              ((symbol-function 'set-window-buffer)
               (lambda (win buf) (push (cons win buf) assignments)))
              ((symbol-function 'select-window) #'ignore))
      (kuro-mux-rotate-panes t)
      (should (equal (nreverse assignments)
                     '((w1 . B) (w2 . C) (w3 . A)))))))

(ert-deftest kuro-mux-test-rotate-backward-command-delegates ()
  "`kuro-mux-rotate-panes-backward' calls `kuro-mux-rotate-panes' with t."
  (let ((arg 'unset))
    (cl-letf (((symbol-function 'kuro-mux-rotate-panes)
               (lambda (&optional b) (setq arg b))))
      (kuro-mux-rotate-panes-backward)
      (should (eq arg t)))))

(ert-deftest kuro-mux-test-visible-windows-filters-kuro ()
  "`kuro-mux--visible-windows' returns only windows showing kuro buffers."
  (let ((kuro-buf (get-buffer-create "*mux-vw-kuro*"))
        (plain    (get-buffer-create "*mux-vw-plain*")))
    (unwind-protect
        (progn
          (with-current-buffer kuro-buf (kuro-mode))
          (cl-letf (((symbol-function 'window-list)
                     (lambda (&rest _) '(w1 w2)))
                    ((symbol-function 'window-buffer)
                     (lambda (w) (pcase w ('w1 kuro-buf) ('w2 plain)))))
            (should (equal (kuro-mux--visible-windows) '(w1)))))
      (kill-buffer kuro-buf)
      (kill-buffer plain))))

(provide 'kuro-mux-test)

(provide 'kuro-mux-test-3)
;;; kuro-mux-test-3.el ends here
