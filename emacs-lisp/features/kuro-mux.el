;;; kuro-mux.el --- Lightweight terminal multiplexer for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Provides a lightweight Emacs-native terminal multiplexer built on top
;; of kuro's session model.  It syncs with Emacs' window-configuration
;; and tab-bar-mode so multiple terminal sessions feel like first-class
;; Emacs citizens.
;;
;; # Features
;;
;; Buffer registry and navigation:
;;   `kuro-mux-next'            — cycle to the next live kuro buffer
;;   `kuro-mux-prev'            — cycle to the previous live kuro buffer
;;   `kuro-mux-switch-by-name'  — switch to a session by name (completing-read)
;;
;; Pane splitting:
;;   `kuro-mux-split-right'  — split right, open a new kuro terminal
;;   `kuro-mux-split-below'  — split below, open a new kuro terminal
;;
;; Window management:
;;   `kuro-mux-detach'  — close current window, buffer and PTY remain alive
;;   `kuro-mux-zoom'    — toggle maximizing the current kuro window
;;   `kuro-mux-kill'    — kill the current kuro session (buffer + PTY)
;;
;; Session naming:
;;   `kuro-mux-rename'  — assign a human-readable name shown in the mode-line
;;
;; Tab-bar sync (requires tab-bar-mode):
;;   `kuro-mux-tab-bar-mode'  — global minor mode that auto-creates/removes
;;                               tab-bar tabs to mirror the session registry
;;
;; Layout persistence:
;;   `kuro-mux-save-layout'    — save session names + commands to disk
;;   `kuro-mux-restore-layout' — recreate sessions from a saved layout file
;;
;; # Architecture
;;
;; `kuro-mux--sessions' is a buffer-ordered list of live kuro buffers.
;; It is maintained by hooks installed on `kuro-mode-hook' and
;; `kill-buffer-hook'.  Session order is creation order (newest last).
;;
;; Layout files are plain Emacs Lisp sexp files.  They store the session
;; name, command, and working directory for each session so the layout can
;; be recreated after an Emacs restart (PTY state is not serialized).

;;; Code:

(require 'kuro-config)

(declare-function kuro-create             "kuro-lifecycle"  (&optional command buffer-name))
(declare-function derived-mode-p          "subr"            (&rest modes))
(declare-function kuro-copy-mode          "kuro"            ())
(declare-function kuro-search-forward     "kuro"            ())
(declare-function kuro--send-paste-or-raw "kuro-input-paste" (text))
(declare-function kuro-list-sessions      "kuro-sessions"    ())

(defvar kuro-shell nil "Forward ref; defcustom in kuro-config.el.")


;;;; Registry

(defvar kuro-mux--sessions nil
  "Ordered list of live `kuro-mode' buffers managed by kuro-mux.
Maintained by `kuro-mux--register' and `kuro-mux--unregister'.
Order is creation order (oldest first, newest last).")

(defvar kuro-mux--zoom-config nil
  "Saved window configuration for `kuro-mux-zoom' toggle.
Non-nil when a zoom is in effect; `kuro-mux-zoom' restores this
configuration and clears it.  Stored as a frame-level global because
only one zoomed window configuration exists per frame at a time.")

(kuro--defvar-permanent-local kuro-mux--name nil
  "Human-readable name for this kuro session.
Used in the mode-line lighter and by `kuro-mux-switch-by-name'.
Set via `kuro-mux-rename'.")

(kuro--defvar-permanent-local kuro-mux--command nil
  "Shell command that launched this kuro session.
Stored for layout persistence so the session can be recreated.")

(kuro--defvar-permanent-local kuro-mux--directory nil
  "Working directory at session creation time.
Stored for layout persistence.")

(defvar-local kuro-mux--monitor-activity nil
  "When non-nil, fire notifications when this session produces output off-screen.")

(defvar-local kuro-mux--monitor-activity-last-notified 0
  "Float-time of the last activity notification dispatched for this buffer.")

(defvar-local kuro-mux--monitor-silence-seconds nil
  "Seconds of silence before a silence notification fires, or nil when disabled.")

(defvar-local kuro-mux--monitor-silence-timer nil
  "Active countdown timer for silence monitoring in this buffer, or nil.")

(defvar-local kuro-mux--pipe-pane-file nil
  "Absolute path of the file currently receiving piped output.
Nil when no pipe-pane capture is active for this buffer.")

(defcustom kuro-mux-monitor-activity-debounce 2.0
  "Minimum seconds between activity notifications for a monitored session.
Prevents notification floods when a session produces continuous rapid output."
  :type 'number
  :group 'kuro)

(defun kuro-mux--register ()
  "Add the current buffer to `kuro-mux--sessions' if it is a kuro buffer.
Called from `kuro-mode-hook'."
  (when (derived-mode-p 'kuro-mode)
    (unless (memq (current-buffer) kuro-mux--sessions)
      (setq kuro-mux--sessions
            (append kuro-mux--sessions (list (current-buffer)))))
    (setq kuro-mux--directory default-directory)))

(defun kuro-mux--unregister ()
  "Remove the current buffer from `kuro-mux--sessions'.
Called from `kill-buffer-hook'."
  (setq kuro-mux--sessions
        (delq (current-buffer) kuro-mux--sessions)))

(defun kuro-mux--live-sessions ()
  "Return the list of live kuro-mode buffers, pruning any dead ones."
  (setq kuro-mux--sessions
        (seq-filter #'buffer-live-p kuro-mux--sessions))
  kuro-mux--sessions)

(defun kuro-mux--session-display-name (buf)
  "Return a display name for kuro buffer BUF.
Prefers `kuro-mux--name' when set, falls back to the buffer name."
  (with-current-buffer buf
    (or kuro-mux--name (buffer-name))))


;;;; Navigation

(defun kuro-mux--next-buffer (buf sessions)
  "Return the buffer after BUF in SESSIONS, wrapping around."
  (let ((rest (cdr (memq buf sessions))))
    (or (car rest) (car sessions))))

(defun kuro-mux--prev-buffer (buf sessions)
  "Return the buffer before BUF in SESSIONS, wrapping around."
  (kuro-mux--next-buffer buf (reverse sessions)))

(defmacro kuro--def-mux-nav (name nav-fn docstring)
  "Define a kuro-mux session cycle command.
NAV-FN is called with (current-buffer sessions) to pick the target buffer."
  `(defun ,name ()
     ,docstring
     (interactive)
     (let ((sessions (kuro-mux--live-sessions)))
       (cond
        ((null sessions)       (message "kuro-mux: no active sessions"))
        ((null (cdr sessions)) (switch-to-buffer (car sessions)))
        (t                     (switch-to-buffer
                                (,nav-fn (current-buffer) sessions)))))))

;;;###autoload
(kuro--def-mux-nav kuro-mux-next kuro-mux--next-buffer
  "Switch to the next live kuro buffer in creation order, wrapping around.")

;;;###autoload
(kuro--def-mux-nav kuro-mux-prev kuro-mux--prev-buffer
  "Switch to the previous live kuro buffer in creation order, wrapping around.")

;;;###autoload
(defun kuro-mux-switch-by-name (name)
  "Switch to the kuro session named NAME.
With prefix argument or when called interactively, use `completing-read'."
  (interactive
   (list (completing-read
          "Kuro session: "
          (mapcar #'kuro-mux--session-display-name
                  (kuro-mux--live-sessions))
          nil t)))
  (let ((target (seq-find
                 (lambda (buf)
                   (string= (kuro-mux--session-display-name buf) name))
                 (kuro-mux--live-sessions))))
    (if target
        (switch-to-buffer target)
      (message "kuro-mux: no session named %s" name))))

(defun kuro-mux--session-index ()
  "Return the 1-indexed position of the current buffer in the session registry.
Returns nil when the current buffer is not registered with kuro-mux."
  (when-let ((pos (seq-position (kuro-mux--live-sessions) (current-buffer))))
    (1+ pos)))

(defun kuro-mux--mode-line-segment ()
  "Return a mode-line string showing the current session's index as [N/M].
Returns an empty string when the buffer is not in the kuro-mux registry."
  (if-let ((idx   (kuro-mux--session-index))
           (total (length (kuro-mux--live-sessions))))
      (format " [%d/%d]" idx total)
    ""))

(defcustom kuro-mux-mode-line-segment t
  "When non-nil, `kuro-mux-setup' appends a session-index segment to the mode-line.
The segment shows \" [N/M]\" in each kuro buffer where N is the 1-indexed
session slot and M is the total number of live sessions."
  :type 'boolean
  :group 'kuro)

(defun kuro-mux--buffer-mode-line-setup ()
  "Append the kuro-mux session-index segment to this buffer's mode-line-format.
Idempotent: repeated calls do not add duplicate segments."
  (make-local-variable 'mode-line-format)
  (let ((seg '(:eval (kuro-mux--mode-line-segment))))
    (unless (member seg mode-line-format)
      (setq mode-line-format (append mode-line-format (list seg))))))

(defun kuro-mux-install-mode-line ()
  "Install the kuro-mux mode-line segment into all current and future kuro buffers.
Adds `kuro-mux--buffer-mode-line-setup' to `kuro-mode-hook' and calls it
immediately on every already-live kuro session."
  (add-hook 'kuro-mode-hook #'kuro-mux--buffer-mode-line-setup)
  (dolist (buf (kuro-mux--live-sessions))
    (with-current-buffer buf
      (kuro-mux--buffer-mode-line-setup))))

;;;###autoload
(defun kuro-mux-other-window ()
  "Switch focus to the next visible window displaying a kuro buffer.
Cycles through windows on the selected frame that show a kuro-mode buffer,
in `next-window' order.  Analogous to tmux prefix + o (next pane)."
  (interactive)
  (let* ((kuro-wins (kuro-mux--visible-windows))
         (next (cadr (memq (selected-window) kuro-wins))))
    (cond
     ((length< kuro-wins 1)
      (user-error "kuro-mux: no visible kuro panes"))
     ((length< kuro-wins 2)
      (user-error "kuro-mux: only one visible kuro pane"))
     (t
      (select-window (or next (car kuro-wins)))))))

(defun kuro-mux--visible-windows ()
  "Return the live windows on the selected frame that show a kuro buffer.
Order follows `window-list' (top-to-bottom, then left-to-right)."
  (seq-filter
   (lambda (w)
     (with-current-buffer (window-buffer w)
       (derived-mode-p 'kuro-mode)))
   (window-list nil 'no-minibuf)))

;;;###autoload
(defun kuro-mux-rotate-panes (&optional backward)
  "Rotate kuro buffers through the visible window positions (tmux: C-o).
Window geometry stays fixed; each window adopts a neighbour's buffer,
cycling around so no buffer is lost.  Forward rotation shifts every buffer
to the next window (the last wraps to the first); with BACKWARD non-nil —
or any prefix argument — it rotates the other way.  Signals `user-error'
when fewer than two kuro panes are visible."
  (interactive "P")
  (let* ((wins (kuro-mux--visible-windows))
         (n    (length wins)))
    (when (< n 2)
      (user-error "kuro-mux: need at least two visible kuro panes to rotate"))
    (let* ((bufs (mapcar #'window-buffer wins))
           ;; Forward = right-shift the buffer list onto the windows:
           ;; window[i] shows what window[i-1] showed, window[0] takes the last.
           (rot  (if backward
                     (append (cdr bufs) (list (car bufs)))
                   (cons (car (last bufs)) (butlast bufs))))
           (ws wins)
           (bs rot))
      (while ws
        (set-window-buffer (car ws) (car bs))
        (setq ws (cdr ws) bs (cdr bs)))
      (select-window (car wins)))))

;;;###autoload
(defun kuro-mux-rotate-panes-backward ()
  "Rotate kuro buffers through window positions in reverse (tmux: M-o).
Equivalent to `kuro-mux-rotate-panes' with a prefix argument."
  (interactive)
  (kuro-mux-rotate-panes t))

;;;###autoload
(defun kuro-mux-select-by-index (n)
  "Switch to the Nth kuro session (1-indexed).
Sessions are ordered by `kuro-mux--live-sessions' (creation order, oldest
first).  Index 1 is the oldest session; 0 selects the tenth.  Signals
`user-error' when N is out of range."
  (interactive "nKuro session index: ")
  (let* ((idx      (if (= n 0) 9 (1- n)))
         (sessions (kuro-mux--live-sessions))
         (target   (nth idx sessions)))
    (if target
        (switch-to-buffer target)
      (user-error "kuro-mux: no session at index %d (have %d)"
                  (if (= n 0) 10 n)
                  (length sessions)))))


(require 'kuro-mux-windows)
(require 'kuro-mux-layout)
(require 'kuro-mux-ext)
(require 'kuro-mux-ext2)

(provide 'kuro-mux)
;;; kuro-mux.el ends here
