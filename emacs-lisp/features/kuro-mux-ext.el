;;; kuro-mux-ext.el --- kuro-mux: pane management, tab-bar, persistence, keymap  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; Extension module for kuro-mux.el.  Loaded automatically by kuro-mux.el.
;; Provides: pane movement between frames, session naming, tab-bar integration,
;; layout persistence, session monitoring, pipe-pane, prefix keymap, and setup.
;; All functions here depend on kuro-mux.el having been loaded first.

;;; Code:

(declare-function kuro-mux--live-sessions      "kuro-mux" ())
(declare-function kuro-mux--session-display-name "kuro-mux" (buf))
(declare-function kuro-mux--register           "kuro-mux" ())
(declare-function kuro-mux--unregister         "kuro-mux" ())
(declare-function kuro-mux-next-layout         "kuro-mux-layout" ())
(declare-function kuro-mux-previous-layout     "kuro-mux-layout" ())
(declare-function kuro-mux-select-layout       "kuro-mux-layout" (layout))
(declare-function kuro-mux-next                "kuro-mux" ())
(declare-function kuro-mux-prev                "kuro-mux" ())
(declare-function kuro-mux-switch-by-name      "kuro-mux" (name))
(declare-function kuro-mux-other-window        "kuro-mux" ())
(declare-function kuro-mux-rotate-panes        "kuro-mux" (&optional backward))
(declare-function kuro-mux-rotate-panes-backward "kuro-mux" ())
(declare-function kuro-mux-last                "kuro-mux" ())
(declare-function kuro-mux-find-window         "kuro-mux" (name))
(declare-function kuro-mux-select-by-index     "kuro-mux" (n))
(declare-function kuro-mux-split-right         "kuro-mux" (&optional command))
(declare-function kuro-mux-split-below         "kuro-mux" (&optional command))
(declare-function kuro-mux-detach              "kuro-mux" ())
(declare-function kuro-mux-zoom                "kuro-mux" ())
(declare-function kuro-mux-kill                "kuro-mux" ())
(declare-function kuro-mux-swap-pane-forward   "kuro-mux" ())
(declare-function kuro-mux-swap-pane-backward  "kuro-mux" ())
(declare-function kuro-mux-resize-pane         "kuro-mux" (direction &optional delta))
(declare-function kuro-mux-install-mode-line       "kuro-mux"      ())
(declare-function kuro-mux--track-window-change    "kuro-mux"      (_frame))
(declare-function kuro--activity-notify            "kuro-activity" (title body))

;; Forward declarations for buffer-local variables defined in kuro-mux.el.
;; kuro-mux-tab-bar-mode is defined later in this file (define-minor-mode at line ~187).
(defvar kuro-mux-tab-bar-mode)
(defvar kuro-mux-monitor-activity-debounce)
(defvar kuro-mux-mode-line-segment)
(defvar kuro-mux--name)
(defvar kuro-mux--command)
(defvar kuro-mux--directory)
(defvar kuro-mux--monitor-activity)
(defvar kuro-mux--monitor-activity-last-notified)
(defvar kuro-mux--monitor-silence-seconds)
(defvar kuro-mux--monitor-silence-timer)
(defvar kuro-mux--pipe-pane-file)
(defvar kuro-shell)


;;;; Pane movement between frames

;;;###autoload
(defun kuro-mux-break-pane ()
  "Move the current kuro buffer to its own dedicated frame (tmux: break-pane).
The buffer remains live.  When the current window is one of several visible
windows, it is removed from the frame after the new frame is created.
When it is the sole window, the buffer is shown in both frames momentarily;
the caller may close the old frame manually."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro buffer"))
  (let* ((buf        (current-buffer))
         (can-delete (> (length (window-list nil 0)) 1))
         (new-frame  (make-frame)))
    (with-selected-frame new-frame
      (switch-to-buffer buf))
    (when can-delete
      (delete-window))))

;;;###autoload
(defun kuro-mux-join-pane (name)
  "Pull the named kuro session into the current frame as a vertical split.
NAME is the buffer name of a live kuro session.  The session is pulled
into a new window on the right side of the current window (tmux: join-pane).
Use `kuro-mux-break-pane' to perform the reverse operation."
  (interactive
   (list (completing-read "Join session: "
                          (mapcar #'buffer-name (kuro-mux--live-sessions))
                          nil t)))
  (let ((buf (get-buffer name)))
    (unless (buffer-live-p buf)
      (user-error "Session buffer no longer exists: %s" name))
    (let ((new-win (split-window-right)))
      (set-window-buffer new-win buf)
      (select-window new-win))))


;;;; Session naming

;;;###autoload
(defun kuro-mux-rename (name)
  "Rename the current kuro session to NAME.
Updates the mode-line and the tab-bar tab (when `kuro-mux-tab-bar-mode'
is active).  NAME is shown by `kuro-mux-switch-by-name'."
  (interactive "sSession name: ")
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a kuro buffer"))
  (setq kuro-mux--name (if (string-empty-p name) nil name))
  (when kuro-mux-tab-bar-mode
    (kuro-mux--tab-bar-update))
  (force-mode-line-update)
  (message "kuro-mux: session renamed to %s"
           (or kuro-mux--name (buffer-name))))

(defun kuro-mux--name-lighter ()
  "Return a mode-line string for the current session name.
Returns empty string when no name is set."
  (if kuro-mux--name
      (format " {%s}" kuro-mux--name)
    ""))

;;;###autoload
(defun kuro-mux-send-to-session (name text)
  "Send TEXT to the kuro session named NAME.
Interactively, prompts for a session name (with completion) and for
the text to send.  TEXT is delivered via `kuro--send-paste-or-raw'
in the target buffer, which applies bracketed-paste wrapping when
the session has that terminal mode active.
Signals `user-error' when no session matching NAME is found."
  (interactive
   (list (completing-read "Kuro session: "
                          (mapcar #'kuro-mux--session-display-name
                                  (kuro-mux--live-sessions))
                          nil t)
         (read-string "Send text: ")))
  (let ((target (seq-find (lambda (buf)
                            (string= (kuro-mux--session-display-name buf) name))
                          (kuro-mux--live-sessions))))
    (if target
        (with-current-buffer target
          (kuro--send-paste-or-raw text))
      (user-error "kuro-mux: no session named %s" name))))


;;;; Tab-bar integration

(defun kuro-mux--tab-bar-update ()
  "Rebuild the tab-bar tab list to reflect the current session registry.
Each live kuro session gets one tab named by `kuro-mux--session-display-name'.
Existing non-kuro tabs are preserved at their current positions."
  (when (and (fboundp 'tab-bar-tabs) (fboundp 'tab-bar-select-tab-by-name))
    ;; Ensure tab-bar-mode is on
    (tab-bar-mode 1)
    ;; For each session without a corresponding tab, create one
    (dolist (buf (kuro-mux--live-sessions))
      (let* ((name (kuro-mux--session-display-name buf))
             (existing (seq-find (lambda (tab)
                                   (string= (alist-get 'name tab) name))
                                 (tab-bar-tabs))))
        (unless existing
          (tab-bar-new-tab)
          (with-current-buffer buf
            (switch-to-buffer buf))
          ;; Rename the new tab
          (when (fboundp 'tab-bar-rename-tab)
            (tab-bar-rename-tab name)))))))

(defun kuro-mux--on-session-created ()
  "Hook function: register new session and update tab-bar if enabled."
  (kuro-mux--register)
  (when kuro-mux-tab-bar-mode
    (kuro-mux--tab-bar-update)))

(defun kuro-mux--on-session-killed ()
  "Hook function: unregister session and update tab-bar if enabled."
  (kuro-mux--unregister))

(defconst kuro-mux--lifecycle-hooks
  '((kuro-mode-hook                    . kuro-mux--on-session-created)
    (kill-buffer-hook                  . kuro-mux--on-session-killed)
    (window-selection-change-functions . kuro-mux--track-window-change)
    (kill-emacs-hook                   . kuro-mux--auto-save-on-exit))
  "Hook alist managed by `kuro-mux-tab-bar-mode'.  Each entry is (HOOK . FN).")

(defun kuro-mux--install-hooks ()
  "Install kuro-mux lifecycle hooks."
  (dolist (h kuro-mux--lifecycle-hooks) (add-hook (car h) (cdr h))))

(defun kuro-mux--uninstall-hooks ()
  "Remove kuro-mux lifecycle hooks."
  (dolist (h kuro-mux--lifecycle-hooks) (remove-hook (car h) (cdr h))))

;;;###autoload
(define-minor-mode kuro-mux-tab-bar-mode
  "Global minor mode that syncs kuro sessions with tab-bar tabs.
When enabled, each new kuro session automatically gets a tab-bar tab,
and closing a session removes its tab.  `tab-bar-mode' is activated
automatically when the first kuro tab is created."
  :global t
  :group 'kuro
  (if kuro-mux-tab-bar-mode
      (progn
        (kuro-mux--install-hooks)
        ;; Reflect already-open sessions in tab-bar
        (when (kuro-mux--live-sessions)
          (kuro-mux--tab-bar-update)))
    (kuro-mux--uninstall-hooks)))


;;;; Layout persistence

(defcustom kuro-mux-layout-file
  (expand-file-name "kuro-mux-layout.el" user-emacs-directory)
  "File path for saving and restoring the kuro-mux session layout.
The file is an Emacs Lisp sexp — do not edit by hand."
  :type 'file
  :group 'kuro)

(defcustom kuro-mux-auto-save-layout nil
  "When non-nil, automatically save the kuro session layout when Emacs exits.
`kuro-mux-save-layout' is called from `kill-emacs-hook' when this is set.
The layout is written to `kuro-mux-layout-file' and can be restored with
`kuro-mux-restore-layout' on the next Emacs startup."
  :type 'boolean
  :group 'kuro)

(defun kuro-mux--auto-save-on-exit ()
  "Save the kuro session layout on Emacs exit if auto-save is enabled.
Called from `kill-emacs-hook'.  No-op when `kuro-mux-auto-save-layout' is nil
or when there are no live sessions to persist."
  (when (and kuro-mux-auto-save-layout (kuro-mux--live-sessions))
    (kuro-mux-save-layout)))

;;;; Session monitoring (activity + silence)

(defun kuro-mux--activity-watcher (_beg _end _old-len)
  "Called from `after-change-functions' to detect output in monitored sessions.
Fires a notification when the buffer is not currently visible and at least
`kuro-mux-monitor-activity-debounce' seconds have elapsed since the last one."
  (when (and kuro-mux--monitor-activity
             (not (get-buffer-window (current-buffer) 'visible))
             (> (float-time)
                (+ kuro-mux--monitor-activity-last-notified
                   kuro-mux-monitor-activity-debounce)))
    (setq kuro-mux--monitor-activity-last-notified (float-time))
    (kuro--activity-notify
     (format "Activity: %s" (buffer-name))
     "Session produced output while hidden")))

(defun kuro-mux--silence-watcher (_beg _end _old-len)
  "Called from `after-change-functions' to reset the silence countdown.
Cancels any pending silence timer and schedules a new one for
`kuro-mux--monitor-silence-seconds' seconds in the future."
  (when kuro-mux--monitor-silence-seconds
    (when (timerp kuro-mux--monitor-silence-timer)
      (cancel-timer kuro-mux--monitor-silence-timer))
    (let ((buf (current-buffer))
          (sec kuro-mux--monitor-silence-seconds))
      (setq kuro-mux--monitor-silence-timer
            (run-with-timer sec nil
              (lambda ()
                (when (buffer-live-p buf)
                  (with-current-buffer buf
                    (kuro--activity-notify
                     (format "Silence: %s" (buffer-name))
                     (format "No output for %gs" sec))))))))))

;;;###autoload
(defun kuro-mux-monitor-activity-toggle ()
  "Toggle activity monitoring for the current kuro session.
When enabled, a notification fires via `kuro--activity-notify' the first
time new output arrives while the buffer is not displayed in any visible
frame.  Subsequent notifications are throttled by
`kuro-mux-monitor-activity-debounce'.
Analogous to tmux `:monitor-activity on/off'."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro buffer"))
  (setq kuro-mux--monitor-activity (not kuro-mux--monitor-activity))
  (if kuro-mux--monitor-activity
      (progn
        (add-hook 'after-change-functions #'kuro-mux--activity-watcher nil t)
        (message "kuro-mux: activity monitoring ON for %s" (buffer-name)))
    (remove-hook 'after-change-functions #'kuro-mux--activity-watcher t)
    (message "kuro-mux: activity monitoring OFF for %s" (buffer-name))))

;;;###autoload
(defun kuro-mux-monitor-silence (seconds)
  "Monitor the current kuro session for silence longer than SECONDS.
A notification fires via `kuro--activity-notify' when the session produces
no output for SECONDS consecutive seconds.  The timer is reset on every
new output event.  Pass 0 to disable silence monitoring for this session.
Analogous to tmux `:monitor-silence N'."
  (interactive "nMonitor silence after (seconds, 0=off): ")
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro buffer"))
  (setq kuro-mux--monitor-silence-seconds (and (> seconds 0) seconds))
  (if kuro-mux--monitor-silence-seconds
      (progn
        (add-hook 'after-change-functions #'kuro-mux--silence-watcher nil t)
        (message "kuro-mux: silence monitoring ON (%gs) for %s"
                 seconds (buffer-name)))
    (when (timerp kuro-mux--monitor-silence-timer)
      (cancel-timer kuro-mux--monitor-silence-timer)
      (setq kuro-mux--monitor-silence-timer nil))
    (remove-hook 'after-change-functions #'kuro-mux--silence-watcher t)
    (message "kuro-mux: silence monitoring OFF for %s" (buffer-name))))


;;;; Pipe pane — capture rendered session output to a file

(defun kuro-mux--pipe-pane-watcher (beg end _old-len)
  "Append newly inserted buffer text to `kuro-mux--pipe-pane-file'.
Called from `after-change-functions' when output piping is active."
  (when (and kuro-mux--pipe-pane-file (< beg end))
    (let ((text (buffer-substring-no-properties beg end)))
      (condition-case err
          (write-region text nil kuro-mux--pipe-pane-file t 'silent)
        (error
         (message "kuro-mux pipe-pane error: %s" (error-message-string err))
         (setq kuro-mux--pipe-pane-file nil)
         (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t))))))

(defun kuro-mux-pipe-pane (file)
  "Toggle piping of this session's rendered output to FILE (tmux: pipe-pane).
When output is already being piped, stop it (pass nil interactively).
Otherwise prompt for FILE and start appending rendered text to it.
Bound to `P' in the mux prefix map."
  (interactive
   (if kuro-mux--pipe-pane-file
       (list nil)
     (list (read-file-name "Pipe output to file: "))))
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro buffer"))
  (if (null file)
      (progn
        (setq kuro-mux--pipe-pane-file nil)
        (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t)
        (message "kuro-mux: pipe-pane stopped for %s" (buffer-name)))
    (setq kuro-mux--pipe-pane-file (expand-file-name file))
    (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
    (message "kuro-mux: piping %s → %s" (buffer-name) kuro-mux--pipe-pane-file)))


(provide 'kuro-mux-ext)
;;; kuro-mux-ext.el ends here
