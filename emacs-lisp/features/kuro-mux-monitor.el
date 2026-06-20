;;; kuro-mux-monitor.el --- kuro-mux: session monitoring and pipe-pane  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; Companion module for kuro-mux.el.  Loaded after kuro-mux-ext.el.
;; Provides session activity/silence watchers and pipe-pane capture.

;;; Code:

(require 'kuro-config)
(require 'kuro-activity)

;; Buffer-local state for monitoring and pipe-pane capture.
(defcustom kuro-mux-monitor-activity-debounce 2.0
  "Minimum seconds between activity notifications for a monitored session.
Prevents notification floods when a session produces continuous rapid output."
  :type 'number
  :group 'kuro)
(defvar-local kuro-mux--monitor-activity nil)
(defvar-local kuro-mux--monitor-activity-last-notified 0)
(defvar-local kuro-mux--monitor-silence-seconds nil)
(defvar-local kuro-mux--monitor-silence-timer nil)
(defvar-local kuro-mux--pipe-pane-file nil)

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
  (kuro--with-kuro-mode
   (setq kuro-mux--monitor-activity (not kuro-mux--monitor-activity))
   (if kuro-mux--monitor-activity
       (progn
         (add-hook 'after-change-functions #'kuro-mux--activity-watcher nil t)
         (message "kuro-mux: activity monitoring ON for %s" (buffer-name)))
     (remove-hook 'after-change-functions #'kuro-mux--activity-watcher t)
     (message "kuro-mux: activity monitoring OFF for %s" (buffer-name)))))

;;;###autoload
(defun kuro-mux-monitor-silence (seconds)
  "Monitor the current kuro session for silence longer than SECONDS.
A notification fires via `kuro--activity-notify' when the session produces
no output for SECONDS consecutive seconds.  The timer is reset on every
new output event.  Pass 0 to disable silence monitoring for this session.
Analogous to tmux `:monitor-silence N'."
  (interactive "nMonitor silence after (seconds, 0=off): ")
  (kuro--with-kuro-mode
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
     (message "kuro-mux: silence monitoring OFF for %s" (buffer-name)))))


;;;; Pipe pane - capture rendered session output to a file

(defun kuro-mux--pipe-pane-watcher (beg end _old-len)
  "Append buffer text from BEG to END to `kuro-mux--pipe-pane-file'.
Called from `after-change-functions' when output piping is active."
  (when (and kuro-mux--pipe-pane-file (< beg end))
    (let ((text (buffer-substring-no-properties beg end)))
      (condition-case err
          (write-region text nil kuro-mux--pipe-pane-file t 'silent)
        (error
         (message "kuro-mux pipe-pane error: %s" (error-message-string err))
         (setq kuro-mux--pipe-pane-file nil)
         (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t))))))

;;;###autoload
(defun kuro-mux-pipe-pane (file)
  "Toggle piping of this session's rendered output to FILE (tmux: pipe-pane).
When output is already being piped, stop it (pass nil interactively).
Otherwise prompt for FILE and start appending rendered text to it.
Bound to `P' in the mux prefix map."
  (interactive
   (if kuro-mux--pipe-pane-file
       (list nil)
     (list (read-file-name "Pipe output to file: "))))
  (kuro--with-kuro-mode
   (if (null file)
       (progn
         (setq kuro-mux--pipe-pane-file nil)
         (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t)
         (message "kuro-mux: pipe-pane stopped for %s" (buffer-name)))
     (setq kuro-mux--pipe-pane-file (expand-file-name file))
     (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
     (message "kuro-mux: piping %s -> %s" (buffer-name) kuro-mux--pipe-pane-file))))

(provide 'kuro-mux-monitor)
;;; kuro-mux-monitor.el ends here
