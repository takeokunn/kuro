;;; kuro-mux-monitor.el --- kuro-mux: session monitoring and pipe-pane  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; Companion module for kuro-mux.el.  Loaded after kuro-mux-ext.el.
;; Provides session activity/silence watchers and pipe-pane capture.

;;; Code:

(require 'kuro-config)
(require 'kuro-activity)
(require 'cl-lib)
(require 'subr-x)

;; Buffer-local state for monitoring and pipe-pane capture.
(defcustom kuro-mux-monitor-activity-debounce 2.0
  "Minimum seconds between activity notifications for a monitored session.
Prevents notification floods when a session produces continuous rapid output."
  :type 'number
  :group 'kuro)

(defcustom kuro-mux-pipe-pane-directory
  (expand-file-name "kuro-pipe-pane/" user-emacs-directory)
  "Local private directory used for `kuro-mux-pipe-pane' captures.
Pipe-pane output is untrusted terminal text, so capture files are restricted to
direct child files of this directory."
  :type 'directory
  :group 'kuro)

(defvar-local kuro-mux--monitor-activity nil)
(defvar-local kuro-mux--monitor-activity-last-notified 0)
(defvar-local kuro-mux--monitor-silence-seconds nil)
(defvar-local kuro-mux--monitor-silence-timer nil)
(defvar-local kuro-mux--pipe-pane-file nil
  "Active pipe-pane capture target object, or nil when disabled.")

(cl-defstruct (kuro-mux--pipe-pane-target
               (:constructor kuro-mux--pipe-pane-target-create
                             (&key path device inode))
               (:copier nil))
  "Stable identity of an active pipe-pane capture file."
  path
  device
  inode)

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
         (message "Kuro-mux: activity monitoring ON for %s" (buffer-name)))
     (remove-hook 'after-change-functions #'kuro-mux--activity-watcher t)
     (message "Kuro-mux: activity monitoring OFF for %s" (buffer-name)))))

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
         (message "Kuro-mux: silence monitoring ON (%gs) for %s"
                  seconds (buffer-name)))
     (when (timerp kuro-mux--monitor-silence-timer)
       (cancel-timer kuro-mux--monitor-silence-timer)
       (setq kuro-mux--monitor-silence-timer nil))
     (remove-hook 'after-change-functions #'kuro-mux--silence-watcher t)
     (message "Kuro-mux: silence monitoring OFF for %s" (buffer-name)))))


;;;; Pipe pane - capture rendered session output to a file

(defun kuro-mux--pipe-pane-directory-path ()
  "Return the expanded configured pipe-pane directory path."
  (file-name-as-directory
   (expand-file-name kuro-mux-pipe-pane-directory)))

(defun kuro-mux--pipe-pane-path-mode (path)
  "Return PATH's permission bits masked to 0777."
  (let ((mode (file-modes path)))
    (unless mode
      (user-error "Kuro-mux pipe-pane path has no file mode: %s" path))
    (logand mode #o777)))

(defun kuro-mux--pipe-pane-existing-safe-directory ()
  "Return the existing local private pipe-pane directory.
Unlike `kuro-mux--pipe-pane-safe-directory', this never creates or repairs the
directory.  It is used while piping is active so captures fail closed if the
capture directory disappears or its permissions drift."
  (let ((dir (kuro-mux--pipe-pane-directory-path)))
    (when (file-remote-p dir)
      (user-error "Kuro-mux pipe-pane directory must be local: %s" dir))
    (when (file-symlink-p (directory-file-name dir))
      (user-error "Kuro-mux pipe-pane directory must not be a symlink: %s" dir))
    (unless (file-exists-p dir)
      (user-error "Kuro-mux pipe-pane directory no longer exists: %s" dir))
    (unless (file-directory-p dir)
      (user-error "Kuro-mux pipe-pane directory is not a directory: %s" dir))
    (unless (= (kuro-mux--pipe-pane-path-mode dir) #o700)
      (user-error "Kuro-mux pipe-pane directory mode must be 0700: %s" dir))
    (file-name-as-directory (file-truename dir))))

(defun kuro-mux--pipe-pane-safe-directory ()
  "Return the local private pipe-pane directory, creating it if needed."
  (let ((dir (kuro-mux--pipe-pane-directory-path)))
    (when (file-remote-p dir)
      (user-error "Kuro-mux pipe-pane directory must be local: %s" dir))
    (when (and (file-exists-p dir)
               (not (file-directory-p dir)))
      (user-error "Kuro-mux pipe-pane directory is not a directory: %s" dir))
    (when (file-symlink-p (directory-file-name dir))
      (user-error "Kuro-mux pipe-pane directory must not be a symlink: %s" dir))
    (make-directory dir t)
    (set-file-modes dir #o700)
    (kuro-mux--pipe-pane-existing-safe-directory)))

(defun kuro-mux--pipe-pane-validate-filename (file)
  "Return a safe basename for pipe-pane FILE.
Only short ASCII filenames are accepted; directories and traversal are refused."
  (unless (and (stringp file) (not (string-empty-p file)))
    (user-error "Kuro-mux pipe-pane file must be a non-empty string"))
  (when (file-remote-p file)
    (user-error "Kuro-mux pipe-pane file must be local: %s" file))
  (let ((name (file-name-nondirectory (directory-file-name file))))
    (unless (and (stringp name)
                 (not (string-empty-p name))
                 (<= (length name) 128)
                 (string-match-p "\\`[A-Za-z0-9._-]+\\'" name)
                 (not (member name '("." ".."))))
      (user-error "Kuro-mux pipe-pane file must be a safe ASCII filename: %s" file))
    name))

(defun kuro-mux--pipe-pane-file-in-directory-p (file dir basename)
  "Return non-nil when FILE names BASENAME directly inside DIR."
  (string= (expand-file-name file)
           (expand-file-name basename dir)))

(defun kuro-mux--pipe-pane-single-link-p (file)
  "Return non-nil when FILE has exactly one filesystem link."
  (= (file-nlinks file) 1))

(defun kuro-mux--pipe-pane-file-attributes (file)
  "Return FILE attributes with integer inode/device fields."
  (or (file-attributes file 'integer)
      (user-error "Kuro-mux pipe-pane file no longer exists: %s" file)))

(defun kuro-mux--pipe-pane-target-from-attributes (file attributes)
  "Return a pipe-pane target for FILE using ATTRIBUTES."
  (let ((device (file-attribute-device-number attributes))
        (inode (file-attribute-inode-number attributes)))
    (unless (and (integerp device) (integerp inode))
      (user-error "Kuro-mux pipe-pane file identity is unavailable: %s" file))
    (kuro-mux--pipe-pane-target-create
     :path file
     :device device
     :inode inode)))

(defun kuro-mux--pipe-pane-validate-existing-regular-file
    (file &optional require-private-mode)
  "Return FILE attributes if FILE is an acceptable capture file.
When REQUIRE-PRIVATE-MODE is non-nil, FILE must already have mode 0600."
  (when (file-remote-p file)
    (user-error "Kuro-mux pipe-pane file must be local: %s" file))
  (when (file-symlink-p file)
    (user-error "Kuro-mux pipe-pane file must not be a symlink: %s" file))
  (unless (file-exists-p file)
    (user-error "Kuro-mux pipe-pane file no longer exists: %s" file))
  (unless (file-regular-p file)
    (user-error "Kuro-mux pipe-pane file must be a regular file: %s" file))
  (unless (kuro-mux--pipe-pane-single-link-p file)
    (user-error "Kuro-mux pipe-pane file must not be a hard link: %s" file))
  (unless (file-writable-p file)
    (user-error "Kuro-mux pipe-pane file is not writable: %s" file))
  (when (and require-private-mode
             (/= (kuro-mux--pipe-pane-path-mode file) #o600))
    (user-error "Kuro-mux pipe-pane file mode must be 0600: %s" file))
  (kuro-mux--pipe-pane-file-attributes file))

(defun kuro-mux--pipe-pane-ensure-regular-file (file)
  "Ensure FILE is a local writable regular file and return its target object."
  (when (file-remote-p file)
    (user-error "Kuro-mux pipe-pane file must be local: %s" file))
  (when (file-symlink-p file)
    (user-error "Kuro-mux pipe-pane file must not be a symlink: %s" file))
  (if (file-exists-p file)
      (kuro-mux--pipe-pane-validate-existing-regular-file file)
    (write-region "" nil file nil 'silent nil 'excl))
  (set-file-modes file #o600)
  (kuro-mux--pipe-pane-target-from-attributes
   file
   (kuro-mux--pipe-pane-validate-existing-regular-file file t)))

(defun kuro-mux--pipe-pane-prepare-file (file)
  "Validate FILE and return its stable pipe-pane target object."
  (let* ((dir (kuro-mux--pipe-pane-safe-directory))
         (basename (kuro-mux--pipe-pane-validate-filename file))
         (candidate (expand-file-name file dir))
         (target (expand-file-name basename dir)))
    (when (and (not (file-name-absolute-p file))
               (not (string= file basename)))
      (user-error "Kuro-mux pipe-pane file must not include directories: %s" file))
    (unless (kuro-mux--pipe-pane-file-in-directory-p candidate dir basename)
      (user-error "Kuro-mux pipe-pane file must be directly under %s: %s"
                  dir file))
    (kuro-mux--pipe-pane-ensure-regular-file target)))

(defun kuro-mux--pipe-pane-validate-active-file (target)
  "Validate active pipe-pane TARGET before each append and return its path."
  (unless (and (kuro-mux--pipe-pane-target-p target)
               (stringp (kuro-mux--pipe-pane-target-path target))
               (integerp (kuro-mux--pipe-pane-target-device target))
               (integerp (kuro-mux--pipe-pane-target-inode target)))
    (user-error "Kuro-mux pipe-pane active target is corrupt"))
  (let* ((file (kuro-mux--pipe-pane-target-path target))
         (dir (kuro-mux--pipe-pane-existing-safe-directory))
         (basename (kuro-mux--pipe-pane-validate-filename file)))
    (unless (kuro-mux--pipe-pane-file-in-directory-p file dir basename)
      (user-error "Kuro-mux pipe-pane active file escaped capture directory: %s"
                  file))
    (let* ((attributes
            (kuro-mux--pipe-pane-validate-existing-regular-file file t))
           (current
            (kuro-mux--pipe-pane-target-from-attributes file attributes)))
      (unless (and (= (kuro-mux--pipe-pane-target-device target)
                      (kuro-mux--pipe-pane-target-device current))
                   (= (kuro-mux--pipe-pane-target-inode target)
                      (kuro-mux--pipe-pane-target-inode current)))
        (user-error "Kuro-mux pipe-pane active file identity changed: %s" file)))
    file))

(defun kuro-mux--pipe-pane-watcher (beg end _old-len)
  "Append buffer text from BEG to END to `kuro-mux--pipe-pane-file'.
Called from `after-change-functions' when output piping is active."
  (when (and kuro-mux--pipe-pane-file (< beg end))
    (let ((text (buffer-substring-no-properties beg end)))
      (condition-case err
          (write-region text nil
                        (kuro-mux--pipe-pane-validate-active-file
                         kuro-mux--pipe-pane-file)
                        t 'silent)
        (error
         (message "Kuro-mux pipe-pane error: %s" (error-message-string err))
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
     (list (read-file-name "Pipe output to file: "
                           (kuro-mux--pipe-pane-safe-directory)))))
  (kuro--with-kuro-mode
   (if (null file)
       (progn
         (setq kuro-mux--pipe-pane-file nil)
         (remove-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher t)
         (message "Kuro-mux: pipe-pane stopped for %s" (buffer-name)))
     (setq kuro-mux--pipe-pane-file (kuro-mux--pipe-pane-prepare-file file))
     (add-hook 'after-change-functions #'kuro-mux--pipe-pane-watcher nil t)
     (message "Kuro-mux: piping %s -> %s"
              (buffer-name)
              (kuro-mux--pipe-pane-target-path kuro-mux--pipe-pane-file)))))

(provide 'kuro-mux-monitor)
;;; kuro-mux-monitor.el ends here
