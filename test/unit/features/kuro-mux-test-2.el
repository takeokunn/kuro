;;; kuro-mux-test-2.el --- ERT tests for kuro-mux.el — Groups 15-22  -*-  lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

;;; Group 15 — kuro-mux-detach / kuro-mux-zoom / kuro-mux-kill behaviour

(ert-deftest kuro-mux-test-detach-errors-outside-kuro-mode ()
  "`kuro-mux-detach' signals user-error when not in a kuro buffer."
  (with-temp-buffer
    (should-error (kuro-mux-detach) :type 'user-error)))

(ert-deftest kuro-mux-test-detach-deletes-window-when-multiple ()
  "`kuro-mux-detach' calls `delete-window' when more than one window exists."
  (let ((deleted nil))
    (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
              ((symbol-function 'count-windows)  (lambda () 2))
              ((symbol-function 'delete-window)  (lambda () (setq deleted t))))
      (kuro-mux-detach)
      (should deleted))))

(ert-deftest kuro-mux-test-detach-switches-session-when-single-window ()
  "`kuro-mux-detach' switches to the next session when only one window."
  (let ((switched nil))
    (cl-letf (((symbol-function 'derived-mode-p)      (lambda (&rest _) t))
              ((symbol-function 'count-windows)        (lambda () 1))
              ((symbol-function 'kuro-mux--live-sessions)
               (lambda () (list (current-buffer) (get-buffer-create "*other*"))))
              ((symbol-function 'kuro-mux-next)        (lambda () (setq switched t))))
      (kuro-mux-detach)
      (should switched))))

(ert-deftest kuro-mux-test-zoom-saves-config-on-first-call ()
  "`kuro-mux-zoom' sets `kuro-mux--zoom-config' on the first call."
  (let ((kuro-mux--zoom-config nil)
        (deleted nil))
    (cl-letf (((symbol-function 'current-window-configuration)
               (lambda () 'fake-config))
              ((symbol-function 'delete-other-windows)
               (lambda () (setq deleted t))))
      (kuro-mux-zoom)
      (should (eq kuro-mux--zoom-config 'fake-config))
      (should deleted))))

(ert-deftest kuro-mux-test-zoom-restores-config-on-second-call ()
  "`kuro-mux-zoom' restores the saved config and clears it on the second call."
  (let ((kuro-mux--zoom-config 'saved-config)
        (restored nil))
    (cl-letf (((symbol-function 'set-window-configuration)
               (lambda (cfg) (setq restored cfg))))
      (kuro-mux-zoom)
      (should (eq restored 'saved-config))
      (should (null kuro-mux--zoom-config)))))

(ert-deftest kuro-mux-test-kill-errors-outside-kuro-mode ()
  "`kuro-mux-kill' signals user-error when not in a kuro buffer."
  (with-temp-buffer
    (should-error (kuro-mux-kill) :type 'user-error)))

(ert-deftest kuro-mux-test-kill-without-confirm-kills-buffer ()
  "`kuro-mux-kill' kills the current buffer when confirm is nil."
  (let ((killed nil)
        (kuro-mux-kill-confirm nil))
    (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
              ((symbol-function 'kill-buffer)     (lambda (_) (setq killed t))))
      (kuro-mux-kill)
      (should killed))))

(ert-deftest kuro-mux-test-kill-confirm-defcustom-exists ()
  "`kuro-mux-kill-confirm' is a defined customization variable."
  (should (boundp 'kuro-mux-kill-confirm)))


;;; Group 16 — kuro-mux-clock

(ert-deftest kuro-mux-test-clock-is-interactive ()
  "`kuro-mux-clock' is an interactive command."
  (should (commandp #'kuro-mux-clock)))

(ert-deftest kuro-mux-test-clock-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds t to kuro-mux-clock."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "t")) #'kuro-mux-clock)))

;;; Group 17 — kuro-mux-send-to-session

(ert-deftest kuro-mux-test-send-to-session-is-interactive ()
  "`kuro-mux-send-to-session' is an interactive command."
  (should (commandp #'kuro-mux-send-to-session)))

(ert-deftest kuro-mux-test-send-to-session-errors-on-unknown-name ()
  "`kuro-mux-send-to-session' signals user-error for an unknown session name."
  (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () nil)))
    (should-error (kuro-mux-send-to-session "nonexistent" "hello")
                  :type 'user-error)))

(ert-deftest kuro-mux-test-send-to-session-calls-send-in-target-buffer ()
  "`kuro-mux-send-to-session' calls kuro--send-paste-or-raw in the target buffer."
  (let ((sent-text nil)
        (target-buf (generate-new-buffer "*kuro-mux-test-send-target*")))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                   (lambda () (list target-buf)))
                  ((symbol-function 'kuro-mux--session-display-name)
                   (lambda (buf) (buffer-name buf)))
                  ((symbol-function 'kuro--send-paste-or-raw)
                   (lambda (text) (setq sent-text text))))
          (kuro-mux-send-to-session "*kuro-mux-test-send-target*" "hello\n")
          (should (equal sent-text "hello\n")))
      (kill-buffer target-buf))))

(ert-deftest kuro-mux-test-send-to-session-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds x to kuro-mux-send-to-session."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "x")) #'kuro-mux-send-to-session)))

;;; Group 18 — kuro-mux-select-by-index

(ert-deftest kuro-mux-test-select-by-index-is-interactive ()
  "`kuro-mux-select-by-index' is an interactive command."
  (should (commandp #'kuro-mux-select-by-index)))

(ert-deftest kuro-mux-test-select-by-index-switches-to-first-session ()
  "`kuro-mux-select-by-index' index 1 switches to the oldest session."
  (let ((buf-a (generate-new-buffer "*kuro-idx-test-a*"))
        (buf-b (generate-new-buffer "*kuro-idx-test-b*"))
        (switched-to nil))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                   (lambda () (list buf-a buf-b)))
                  ((symbol-function 'switch-to-buffer)
                   (lambda (buf) (setq switched-to buf))))
          (kuro-mux-select-by-index 1)
          (should (eq switched-to buf-a)))
      (kill-buffer buf-a)
      (kill-buffer buf-b))))

(ert-deftest kuro-mux-test-select-by-index-switches-to-second-session ()
  "`kuro-mux-select-by-index' index 2 switches to the second session."
  (let ((buf-a (generate-new-buffer "*kuro-idx2-test-a*"))
        (buf-b (generate-new-buffer "*kuro-idx2-test-b*"))
        (switched-to nil))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                   (lambda () (list buf-a buf-b)))
                  ((symbol-function 'switch-to-buffer)
                   (lambda (buf) (setq switched-to buf))))
          (kuro-mux-select-by-index 2)
          (should (eq switched-to buf-b)))
      (kill-buffer buf-a)
      (kill-buffer buf-b))))

(ert-deftest kuro-mux-test-select-by-index-errors-when-out-of-range ()
  "`kuro-mux-select-by-index' signals user-error for an out-of-range index."
  (cl-letf (((symbol-function 'kuro-mux--live-sessions)
             (lambda () (list (current-buffer)))))
    (should-error (kuro-mux-select-by-index 5) :type 'user-error)))

(ert-deftest kuro-mux-test-select-by-index-1-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds key 1 to a command (lambda for index 1)."
  (should (commandp (lookup-key kuro-mux-prefix-map (kbd "1")))))

(ert-deftest kuro-mux-test-select-by-index-9-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds key 9 to a command (lambda for index 9)."
  (should (commandp (lookup-key kuro-mux-prefix-map (kbd "9")))))

;;; Group 19 — kuro-mux-broadcast-mode

(ert-deftest kuro-mux-test-broadcast-toggle-is-interactive ()
  "`kuro-mux-broadcast-toggle' is an interactive command."
  (should (commandp #'kuro-mux-broadcast-toggle)))

(ert-deftest kuro-mux-test-broadcast-mode-off-by-default ()
  "`kuro-mux--broadcast-mode' defaults to nil."
  (should (null (default-value 'kuro-mux--broadcast-mode))))

(ert-deftest kuro-mux-test-broadcast-toggle-enables-mode ()
  "`kuro-mux-broadcast-toggle' sets kuro-mux--broadcast-mode to non-nil."
  (let ((kuro-mux--broadcast-mode nil))
    (kuro-mux-broadcast-toggle)
    (should kuro-mux--broadcast-mode)))

(ert-deftest kuro-mux-test-broadcast-toggle-disables-mode ()
  "`kuro-mux-broadcast-toggle' clears kuro-mux--broadcast-mode when already set."
  (let ((kuro-mux--broadcast-mode t))
    (kuro-mux-broadcast-toggle)
    (should-not kuro-mux--broadcast-mode)))

(ert-deftest kuro-mux-test-broadcast-send-noop-when-mode-off ()
  "`kuro-mux--broadcast-send' does not call kuro--send-paste-or-raw when mode is off."
  (let ((kuro-mux--broadcast-mode nil)
        (called nil))
    (cl-letf (((symbol-function 'kuro-mux--live-sessions)
               (lambda () (list (current-buffer))))
              ((symbol-function 'kuro--send-paste-or-raw)
               (lambda (_) (setq called t))))
      (kuro-mux--broadcast-send "hello")
      (should-not called))))

(ert-deftest kuro-mux-test-broadcast-send-replicates-to-other-sessions ()
  "`kuro-mux--broadcast-send' sends text to all sessions except the origin buffer."
  (let* ((buf-b (generate-new-buffer "*kuro-bcast-test-b*"))
         (sent-to nil)
         (kuro-mux--broadcast-mode t)
         (kuro-mux--broadcasting nil))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                   (lambda () (list (current-buffer) buf-b)))
                  ((symbol-function 'kuro--send-paste-or-raw)
                   (lambda (text) (push (cons (current-buffer) text) sent-to))))
          (kuro-mux--broadcast-send "test-input")
          (should (= (length sent-to) 1))
          (should (eq (caar sent-to) buf-b))
          (should (equal (cdar sent-to) "test-input")))
      (kill-buffer buf-b))))

(ert-deftest kuro-mux-test-broadcast-B-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds B to kuro-mux-broadcast-toggle."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "B")) #'kuro-mux-broadcast-toggle)))

;;; Group 20 — kuro-mux-resize-pane + session index + mode-line segment

(ert-deftest kuro-mux-test-resize-pane-is-interactive ()
  "`kuro-mux-resize-pane' is an interactive command."
  (should (commandp #'kuro-mux-resize-pane)))

(ert-deftest kuro-mux-test-resize-pane-up-calls-enlarge-window ()
  "`kuro-mux-resize-pane' up calls enlarge-window with the given delta."
  (let ((called-n nil))
    (cl-letf (((symbol-function 'enlarge-window) (lambda (n) (setq called-n n))))
      (kuro-mux-resize-pane 'up 3)
      (should (= called-n 3)))))

(ert-deftest kuro-mux-test-resize-pane-down-calls-shrink-window ()
  "`kuro-mux-resize-pane' down calls shrink-window with the given delta."
  (let ((called-n nil))
    (cl-letf (((symbol-function 'shrink-window) (lambda (n) (setq called-n n))))
      (kuro-mux-resize-pane 'down 2)
      (should (= called-n 2)))))

(ert-deftest kuro-mux-test-resize-pane-left-calls-shrink-window-horizontally ()
  "`kuro-mux-resize-pane' left calls shrink-window-horizontally."
  (let ((called-n nil))
    (cl-letf (((symbol-function 'shrink-window-horizontally)
               (lambda (n) (setq called-n n))))
      (kuro-mux-resize-pane 'left 5)
      (should (= called-n 5)))))

(ert-deftest kuro-mux-test-resize-pane-right-calls-enlarge-window-horizontally ()
  "`kuro-mux-resize-pane' right calls enlarge-window-horizontally."
  (let ((called-n nil))
    (cl-letf (((symbol-function 'enlarge-window-horizontally)
               (lambda (n) (setq called-n n))))
      (kuro-mux-resize-pane 'right 4)
      (should (= called-n 4)))))

(ert-deftest kuro-mux-test-resize-pane-errors-on-invalid-direction ()
  "`kuro-mux-resize-pane' signals user-error for an unknown direction."
  (should-error (kuro-mux-resize-pane 'diagonal 1) :type 'user-error))

(ert-deftest kuro-mux-test-resize-pane-arrow-up-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds <up> to a command (resize-pane lambda)."
  (should (commandp (lookup-key kuro-mux-prefix-map (kbd "<up>")))))

(ert-deftest kuro-mux-test-session-index-returns-position ()
  "`kuro-mux--session-index' returns 1-indexed position in the sessions list."
  (let ((buf-a (current-buffer))
        (buf-b (generate-new-buffer "*kuro-idx-seg-b*")))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                   (lambda () (list buf-a buf-b))))
          (should (= (kuro-mux--session-index) 1))
          (with-current-buffer buf-b
            (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                       (lambda () (list buf-a buf-b))))
              (should (= (kuro-mux--session-index) 2)))))
      (kill-buffer buf-b))))

(ert-deftest kuro-mux-test-session-index-nil-when-not-registered ()
  "`kuro-mux--session-index' returns nil when buffer is not in session list."
  (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () nil)))
    (should (null (kuro-mux--session-index)))))

(ert-deftest kuro-mux-test-mode-line-segment-shows-index ()
  "`kuro-mux--mode-line-segment' returns \" [N/M]\" for a registered buffer."
  (let ((buf-a (current-buffer))
        (buf-b (generate-new-buffer "*kuro-ml-seg-b*")))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--live-sessions)
                   (lambda () (list buf-a buf-b))))
          (should (equal (kuro-mux--mode-line-segment) " [1/2]")))
      (kill-buffer buf-b))))

(ert-deftest kuro-mux-test-mode-line-segment-empty-when-not-registered ()
  "`kuro-mux--mode-line-segment' returns empty string when not registered."
  (cl-letf (((symbol-function 'kuro-mux--live-sessions) (lambda () nil)))
    (should (equal (kuro-mux--mode-line-segment) ""))))

;;; Group 21 — kuro-mux-swap-pane + mode-line segment installation

(ert-deftest kuro-mux-test-swap-pane-forward-is-interactive ()
  "`kuro-mux-swap-pane-forward' is an interactive command."
  (should (commandp #'kuro-mux-swap-pane-forward)))

(ert-deftest kuro-mux-test-swap-pane-backward-is-interactive ()
  "`kuro-mux-swap-pane-backward' is an interactive command."
  (should (commandp #'kuro-mux-swap-pane-backward)))

(ert-deftest kuro-mux-test-swap-pane-forward-errors-single-window ()
  "`kuro-mux-swap-pane-forward' signals user-error when only one window is visible."
  (cl-letf (((symbol-function 'next-window)
             (lambda (&rest _) (selected-window))))
    (should-error (kuro-mux-swap-pane-forward) :type 'user-error)))

(ert-deftest kuro-mux-test-swap-pane-backward-errors-single-window ()
  "`kuro-mux-swap-pane-backward' signals user-error when only one window is visible."
  (cl-letf (((symbol-function 'previous-window)
             (lambda (&rest _) (selected-window))))
    (should-error (kuro-mux-swap-pane-backward) :type 'user-error)))

(ert-deftest kuro-mux-test-swap-pane-forward-calls-window-swap-states ()
  "`kuro-mux-swap-pane-forward' passes (selected . next) to `window-swap-states'."
  (let* ((win-a (selected-window))
         (win-b (list 'window 'fake))
         swapped-a swapped-b)
    (cl-letf (((symbol-function 'next-window) (lambda (&rest _) win-b))
              ((symbol-function 'window-swap-states)
               (lambda (a b) (setq swapped-a a swapped-b b))))
      (kuro-mux-swap-pane-forward)
      (should (eq swapped-a win-a))
      (should (eq swapped-b win-b)))))

(ert-deftest kuro-mux-test-swap-pane-backward-calls-window-swap-states ()
  "`kuro-mux-swap-pane-backward' passes (selected . prev) to `window-swap-states'."
  (let* ((win-a (selected-window))
         (win-b (list 'window 'fake))
         swapped-a swapped-b)
    (cl-letf (((symbol-function 'previous-window) (lambda (&rest _) win-b))
              ((symbol-function 'window-swap-states)
               (lambda (a b) (setq swapped-a a swapped-b b))))
      (kuro-mux-swap-pane-backward)
      (should (eq swapped-a win-a))
      (should (eq swapped-b win-b)))))

(ert-deftest kuro-mux-test-swap-forward-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds \"}\" to `kuro-mux-swap-pane-forward'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "}"))
              #'kuro-mux-swap-pane-forward)))

(ert-deftest kuro-mux-test-swap-backward-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds \"{\" to `kuro-mux-swap-pane-backward'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "{"))
              #'kuro-mux-swap-pane-backward)))

(ert-deftest kuro-mux-test-mode-line-segment-defcustom-default-t ()
  "`kuro-mux-mode-line-segment' defcustom defaults to t."
  (should (eq kuro-mux-mode-line-segment t)))

(ert-deftest kuro-mux-test-buffer-mode-line-setup-adds-segment ()
  "`kuro-mux--buffer-mode-line-setup' appends the (:eval ...) segment."
  (with-temp-buffer
    (kuro-mux--buffer-mode-line-setup)
    (should (member '(:eval (kuro-mux--mode-line-segment)) mode-line-format))))

(ert-deftest kuro-mux-test-buffer-mode-line-setup-idempotent ()
  "`kuro-mux--buffer-mode-line-setup' does not add duplicates on repeated calls."
  (with-temp-buffer
    (kuro-mux--buffer-mode-line-setup)
    (kuro-mux--buffer-mode-line-setup)
    (should (= 1 (cl-count '(:eval (kuro-mux--mode-line-segment))
                            mode-line-format
                            :test #'equal)))))

;;; Group 22 — kuro-mux-other-window + kuro-mux-last + last-session tracking

(ert-deftest kuro-mux-test-other-window-is-interactive ()
  "`kuro-mux-other-window' is an interactive command."
  (should (commandp #'kuro-mux-other-window)))

(ert-deftest kuro-mux-test-other-window-errors-no-kuro-panes ()
  "`kuro-mux-other-window' signals user-error when no window shows a kuro buffer."
  (cl-letf (((symbol-function 'window-list) (lambda () (list (selected-window))))
            ((symbol-function 'window-buffer) (lambda (_) (current-buffer)))
            ((symbol-function 'derived-mode-p) (lambda (&rest _) nil)))
    (should-error (kuro-mux-other-window) :type 'user-error)))

(ert-deftest kuro-mux-test-other-window-errors-single-pane ()
  "`kuro-mux-other-window' signals user-error when only one kuro window is visible."
  (cl-letf (((symbol-function 'window-list) (lambda () (list (selected-window))))
            ((symbol-function 'window-buffer) (lambda (_) (current-buffer)))
            ((symbol-function 'derived-mode-p) (lambda (&rest _) t)))
    (should-error (kuro-mux-other-window) :type 'user-error)))

(ert-deftest kuro-mux-test-other-window-selects-next-pane ()
  "`kuro-mux-other-window' selects the next window in the kuro-win list."
  (let* ((win-a (selected-window))
         (win-b (list 'window 'b))
         selected-win)
    (cl-letf (((symbol-function 'window-list)   (lambda () (list win-a win-b)))
              ((symbol-function 'window-buffer)  (lambda (_) (current-buffer)))
              ((symbol-function 'derived-mode-p) (lambda (&rest _) t))
              ((symbol-function 'select-window)  (lambda (w) (setq selected-win w))))
      (kuro-mux-other-window)
      (should (eq selected-win win-b)))))

(ert-deftest kuro-mux-test-other-window-wraps-to-first ()
  "`kuro-mux-other-window' wraps to the first kuro window when at the last."
  (let* ((win-a (list 'window 'a))
         (win-b (selected-window))
         selected-win)
    (cl-letf (((symbol-function 'window-list)   (lambda () (list win-a win-b)))
              ((symbol-function 'window-buffer)  (lambda (_) (current-buffer)))
              ((symbol-function 'derived-mode-p) (lambda (&rest _) t))
              ((symbol-function 'select-window)  (lambda (w) (setq selected-win w))))
      (kuro-mux-other-window)
      (should (eq selected-win win-a)))))

(ert-deftest kuro-mux-test-other-window-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds \"o\" to `kuro-mux-other-window'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "o"))
              #'kuro-mux-other-window)))

(ert-deftest kuro-mux-test-last-is-interactive ()
  "`kuro-mux-last' is an interactive command."
  (should (commandp #'kuro-mux-last)))

(ert-deftest kuro-mux-test-last-errors-when-no-previous ()
  "`kuro-mux-last' signals user-error when kuro-mux--last-session is nil."
  (let ((kuro-mux--last-session nil))
    (should-error (kuro-mux-last) :type 'user-error)))

(ert-deftest kuro-mux-test-last-errors-when-session-dead ()
  "`kuro-mux-last' signals user-error and clears last-session when buffer is dead."
  (let* ((dead (generate-new-buffer "*kuro-mux-last-dead*"))
         (kuro-mux--last-session dead))
    (kill-buffer dead)
    (should-error (kuro-mux-last) :type 'user-error)))

(ert-deftest kuro-mux-test-last-switches-to-previous-session ()
  "`kuro-mux-last' calls `switch-to-buffer' with the recorded last session."
  (let* ((target (generate-new-buffer "*kuro-mux-last-target*"))
         (kuro-mux--last-session target)
         switched-to)
    (unwind-protect
        (cl-letf (((symbol-function 'switch-to-buffer)
                   (lambda (buf) (setq switched-to buf))))
          (kuro-mux-last)
          (should (eq switched-to target)))
      (kill-buffer target))))

(ert-deftest kuro-mux-test-last-bound-in-prefix-map ()
  "`kuro-mux-prefix-map' binds \"L\" to `kuro-mux-last'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "L"))
              #'kuro-mux-last)))

(ert-deftest kuro-mux-test-track-installed-by-install-hooks ()
  "`kuro-mux--install-hooks' adds tracker to `window-selection-change-functions'."
  (let ((kuro-mode-hook nil)
        (kill-buffer-hook nil)
        (window-selection-change-functions nil))
    (kuro-mux--install-hooks)
    (should (memq #'kuro-mux--track-window-change
                  window-selection-change-functions))))

(ert-deftest kuro-mux-test-track-removed-by-uninstall-hooks ()
  "`kuro-mux--uninstall-hooks' removes tracker from `window-selection-change-functions'."
  (let ((kuro-mode-hook nil)
        (kill-buffer-hook nil)
        (window-selection-change-functions nil))
    (kuro-mux--install-hooks)
    (kuro-mux--uninstall-hooks)
    (should-not (memq #'kuro-mux--track-window-change
                      window-selection-change-functions))))

(provide 'kuro-mux-test-2)
;;; kuro-mux-test-2.el ends here
