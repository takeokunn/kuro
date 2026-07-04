;;; kuro-mux-windows.el --- kuro-mux: last session, splitting, window management  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Extension of kuro-mux.el (split to keep files under 500 lines).
;; Provides: last-session tracking, pane splitting, window zoom/detach/kill,
;; pane swap, and pane resize.  Loaded by kuro-mux.el after the core registry
;; and navigation definitions are in place.

;;; Code:

(require 'kuro-config)
(require 'kuro-mux-macros)

(declare-function kuro-mux--live-sessions "kuro-mux" ())
(declare-function kuro-mux-next           "kuro-mux" ())
(declare-function kuro-create             "kuro-lifecycle" (&optional command buffer-name))

(defvar kuro-mux--zoom-config) ; defined in kuro-mux.el


;;;; Last session

(defvar kuro-mux--last-session nil
  "The most recently deselected kuro buffer, for `kuro-mux-last'.
Set by `kuro-mux--track-window-change' via `window-selection-change-functions'.")

(defun kuro-mux--track-window-change (_frame)
  "Record the previously focused kuro buffer after window selection.
Added to `window-selection-change-functions' by `kuro-mux--install-hooks'.
Uses `old-selected-window', which is only valid inside this hook."
  (let ((old (old-selected-window)))
    (when (window-live-p old)
      (let ((buf (window-buffer old)))
        (when (and (with-current-buffer buf (derived-mode-p 'kuro-mode))
                   (not (eq buf (current-buffer))))
          (setq kuro-mux--last-session buf))))))

;;;###autoload
(defun kuro-mux-last ()
  "Switch to the most recently focused kuro session.
Analogous to tmux prefix + L (last window).
Signals `user-error' when there is no recorded previous session or it is dead."
  (interactive)
  (cond
   ((null kuro-mux--last-session)
    (user-error "Kuro-mux: no previous kuro session recorded"))
   ((not (buffer-live-p kuro-mux--last-session))
    (setq kuro-mux--last-session nil)
    (user-error "Kuro-mux: previous session no longer alive"))
   (t
    (switch-to-buffer kuro-mux--last-session))))

;;;###autoload
(defun kuro-mux-find-window (name)
  "Switch to the kuro session named NAME.
Prompts with completion over all live kuro session buffer names.
If the session is visible in a window, selects that window;
otherwise calls `switch-to-buffer'."
  (interactive
   (list (completing-read "Find session: "
                          (mapcar #'buffer-name (kuro-mux--live-sessions))
                          nil t)))
  (let* ((buf (get-buffer name))
         (win (and buf (get-buffer-window buf 'visible))))
    (cond
     ((null buf)
      (user-error "Kuro-mux: no session named %S" name))
     (win
      (select-window win))
     (t
      (switch-to-buffer buf)))))


;;;; Splitting

;;;###autoload (autoload 'kuro-mux-split-right "kuro-mux-windows" nil t)
(kuro--def-mux-split kuro-mux-split-right split-window-right
  "Split the current window to the right and open a new kuro terminal.
COMMAND defaults to `kuro-shell'.")

;;;###autoload (autoload 'kuro-mux-split-below "kuro-mux-windows" nil t)
(kuro--def-mux-split kuro-mux-split-below split-window-below
  "Split the current window below and open a new kuro terminal.
COMMAND defaults to `kuro-shell'.")


;;;; Window management

;;;###autoload
(defun kuro-mux-detach ()
  "Hide the current kuro session without killing it.
If there are multiple windows visible, the current window is deleted and
the kuro buffer continues running in the background.  If there is only
one window, switches to the next registered session instead (wrapping
around).  The kuro buffer and its PTY process are preserved in both
cases."
  (interactive)
  (kuro--with-kuro-mode
   (if (> (count-windows) 1)
       (delete-window)
     (let ((sessions (kuro-mux--live-sessions)))
       (if (> (length sessions) 1)
           (kuro-mux-next)
         (message "kuro-mux: no other sessions to switch to"))))))

;;;###autoload
(defun kuro-mux-zoom ()
  "Toggle maximizing the current window in the frame.
On the first call, saves the current window configuration to
`kuro-mux--zoom-config' and calls `delete-other-windows' so the kuro
buffer fills the frame.  On the second call, restores the saved
configuration (\"zoom off\")."
  (interactive)
  (if kuro-mux--zoom-config
      (progn
        (set-window-configuration kuro-mux--zoom-config)
        (setq kuro-mux--zoom-config nil)
        (message "kuro-mux: zoom off"))
    (setq kuro-mux--zoom-config (current-window-configuration))
    (delete-other-windows)
    (message "kuro-mux: zoomed")))

(defcustom kuro-mux-kill-confirm t
  "When non-nil, `kuro-mux-kill' prompts before killing the buffer."
  :type 'boolean
  :group 'kuro)

;;;###autoload
(defun kuro-mux-kill ()
  "Kill the current kuro session buffer and its PTY process.
When `kuro-mux-kill-confirm' is non-nil, prompts for confirmation first."
  (interactive)
  (kuro--with-kuro-mode
   (when (or (not kuro-mux-kill-confirm)
             (y-or-n-p (format "Kill kuro session %s? " (buffer-name))))
     (kill-buffer (current-buffer)))))

;;;###autoload (autoload 'kuro-mux-swap-pane-forward "kuro-mux-windows" nil t)
(kuro--def-mux-swap kuro-mux-swap-pane-forward next-window
  "Swap the current window's buffer with the next visible window (tmux: `}').")

;;;###autoload (autoload 'kuro-mux-swap-pane-backward "kuro-mux-windows" nil t)
(kuro--def-mux-swap kuro-mux-swap-pane-backward previous-window
  "Swap the current window's buffer with the previous visible window (tmux: `{').")

(defconst kuro--mux-resize-directions
  '((up    . enlarge-window)
    (down  . shrink-window)
    (left  . shrink-window-horizontally)
    (right . enlarge-window-horizontally))
  "Alist mapping resize direction symbols to their `window-resize' functions.")

;;;###autoload
(defun kuro-mux-resize-pane (direction &optional delta)
  "Resize the current window pane in DIRECTION by DELTA lines or columns.
DIRECTION is one of the symbols: up, down, left, right.
`up' / `down' adjust vertical size (rows); `left' / `right' adjust
horizontal size (columns).  DELTA defaults to 1 when nil or omitted.
Analogous to tmux's resize-pane command."
  (interactive
   (list (intern (completing-read
                  "Direction (up/down/left/right): "
                  (mapcar (lambda (e) (symbol-name (car e)))
                          kuro--mux-resize-directions)
                  nil t))
         (if current-prefix-arg
             (prefix-numeric-value current-prefix-arg)
           1)))
  (kuro--mux-resize-dispatch direction (max 1 (or delta 1))))


(provide 'kuro-mux-windows)
;;; kuro-mux-windows.el ends here
