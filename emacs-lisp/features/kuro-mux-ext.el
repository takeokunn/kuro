;;; kuro-mux-ext.el --- kuro-mux: pane management, tab-bar, persistence  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Extension module for kuro-mux.el.  Loaded automatically by kuro-mux.el.
;; Provides: pane movement between frames, session naming, tab-bar integration,
;; layout persistence, prefix keymap, and setup.
;; All functions here depend on kuro-mux.el having been loaded first.

;;; Code:

(declare-function kuro-mux--live-sessions      "kuro-mux" ())
(declare-function kuro-mux--find-session-by-name "kuro-mux" (name))
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
(declare-function kuro-mux-last                "kuro-mux-windows" ())
(declare-function kuro-mux-find-window         "kuro-mux-windows" (name))
(declare-function kuro-mux-select-by-index     "kuro-mux" (n))
(declare-function kuro-mux-split-right         "kuro-mux-windows" (&optional command))
(declare-function kuro-mux-split-below         "kuro-mux-windows" (&optional command))
(declare-function kuro-mux-detach              "kuro-mux-windows" ())
(declare-function kuro-mux-zoom                "kuro-mux-windows" ())
(declare-function kuro-mux-kill                "kuro-mux-windows" ())
(declare-function kuro-mux-swap-pane-forward   "kuro-mux-windows" ())
(declare-function kuro-mux-swap-pane-backward  "kuro-mux-windows" ())
(declare-function kuro-mux-resize-pane         "kuro-mux-windows" (direction &optional delta))
(declare-function kuro--send-paste-or-raw      "kuro-input-paste" (text))
(require 'kuro-config)
(require 'kuro-mux-ext-macros)
(declare-function kuro-mux-install-mode-line       "kuro-mux"      ())
(declare-function kuro-mux--track-window-change    "kuro-mux-windows" (_frame))
(declare-function kuro-mux-save-layout             "kuro-mux-ext2" ())

;; Forward declarations for buffer-local variables defined in kuro-mux.el.
;; kuro-mux-tab-bar-mode is defined later in this file (define-minor-mode at line ~187).
(defvar kuro-mux-tab-bar-mode)
(defvar kuro-mux-mode-line-segment)
(defvar kuro-mux--name)
(defvar kuro-mux--command)
(defvar kuro-mux--directory)


;;;; Pane movement between frames

;;;###autoload
(defun kuro-mux-break-pane ()
  "Move the current kuro buffer to its own dedicated frame (tmux: break-pane).
The buffer remains live.  When the current window is one of several visible
windows, it is removed from the frame after the new frame is created.
When it is the sole window, the buffer is shown in both frames momentarily;
the caller may close the old frame manually."
  (interactive)
  (kuro--with-kuro-mode
   (let* ((buf        (current-buffer))
          (can-delete (> (length (window-list nil 0)) 1))
          (new-frame  (make-frame)))
     (with-selected-frame new-frame
       (switch-to-buffer buf))
     (when can-delete
       (delete-window)))))

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
  (kuro--with-kuro-mode
   (setq kuro-mux--name (if (string-empty-p name) nil name))
   (when kuro-mux-tab-bar-mode
     (kuro-mux--tab-bar-update))
   (force-mode-line-update)
   (message "kuro-mux: session renamed to %s"
            (or kuro-mux--name (buffer-name)))))

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
in the target buffer, which delegates paste encoding to Rust using
the session's current terminal mode.
Signals `user-error' when no session matching NAME is found."
  (interactive
   (list (completing-read "Kuro session: "
                          (mapcar #'kuro-mux--session-display-name
                                  (kuro-mux--live-sessions))
                          nil t)
         (read-string "Send text: ")))
  (let ((target (kuro-mux--find-session-by-name name)))
    (if target
        (with-current-buffer target
          (kuro--send-paste-or-raw text))
      (user-error "Kuro-mux: no session named %s" name))))


;;;; Tab-bar integration

(defun kuro-mux--tab-bar-update ()
  "Make the tab-bar contain one tab for each live kuro session.
Each missing session tab is created and named by
`kuro-mux--session-display-name'."
  (when (fboundp 'tab-bar-tabs)
    ;; Ensure tab-bar-mode is on
    (tab-bar-mode 1)
    ;; For each session without a corresponding tab, create one
    (dolist (buf (kuro-mux--live-sessions))
      (let* ((name (kuro-mux--session-display-name buf))
             (has-tab (kuro-mux--tab-bar-session-tab-p name)))
        (unless has-tab
          (tab-bar-new-tab)
          (with-current-buffer buf
            (switch-to-buffer buf))
          ;; Rename the new tab
          (when (fboundp 'tab-bar-rename-tab)
            (tab-bar-rename-tab name)))))))

(defun kuro-mux--tab-bar-session-tab-p (name)
  "Return non-nil when a tab-bar tab named NAME already exists."
  (seq-find (lambda (tab)
              (string= (alist-get 'name tab) name))
            (tab-bar-tabs)))

(defun kuro-mux--on-session-created ()
  "Hook function: register new session and update tab-bar if enabled."
  (kuro-mux--register)
  (when kuro-mux-tab-bar-mode
    (kuro-mux--tab-bar-update)))

(defun kuro-mux--on-session-killed ()
  "Hook function: unregister session."
  (kuro-mux--unregister))

(eval-and-compile
  (defconst kuro-mux--lifecycle-hooks
    '((kuro-mode-hook                    . kuro-mux--on-session-created)
      (kill-buffer-hook                  . kuro-mux--on-session-killed)
      (window-selection-change-functions . kuro-mux--track-window-change)
      (kill-emacs-hook                   . kuro-mux--auto-save-on-exit))
    "Hook alist managed by `kuro-mux-tab-bar-mode'.  Each entry is (HOOK . FN)."))

(defun kuro-mux--install-hooks ()
  "Install kuro-mux lifecycle hooks."
  (kuro--install-mux-lifecycle-hooks))

(defun kuro-mux--uninstall-hooks ()
  "Remove kuro-mux lifecycle hooks."
  (kuro--uninstall-mux-lifecycle-hooks))

;;;###autoload
(define-minor-mode kuro-mux-tab-bar-mode
  "Global minor mode that syncs kuro sessions with tab-bar tabs.
When enabled, each new kuro session automatically gets a tab-bar tab.
`tab-bar-mode' is activated automatically when the first kuro tab is created."
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

(provide 'kuro-mux-ext)
;;; kuro-mux-ext.el ends here
