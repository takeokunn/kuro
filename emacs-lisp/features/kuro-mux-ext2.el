;;; kuro-mux-ext2.el --- kuro-mux: layout persistence, prefix keymap, broadcast, setup  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Continuation of kuro-mux-ext.el (split to keep files under 600 lines).
;; Provides: layout save/restore, prefix keymap, help, clock, broadcast, setup.
;; Loaded by kuro-mux.el after kuro-mux-ext.el; relies on load order for
;; kuro-mux--install-hooks, kuro-mux--live-sessions, and kuro-mux-ext vars.

;;; Code:

(require 'kuro-keymap)
(require 'kuro-mux-monitor)
(require 'cl-lib)

(declare-function kuro-mux--live-sessions      "kuro-mux" ())
(declare-function kuro-mux--for-each-live-session "kuro-mux" (fn &optional exclude))
(declare-function kuro-mux--install-hooks      "kuro-mux-ext" ())
(declare-function kuro-mux--register           "kuro-mux" ())
(declare-function kuro-mux-install-mode-line   "kuro-mux" ())
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
(declare-function kuro-mux-break-pane          "kuro-mux-windows" ())
(declare-function kuro-mux-join-pane           "kuro-mux-windows" ())
(declare-function kuro-mux-rename              "kuro-mux-windows" ())
(declare-function kuro-mux-send-to-session     "kuro-mux-windows" ())
(declare-function kuro-mux-next-layout         "kuro-mux-layout" ())
(declare-function kuro-mux-previous-layout     "kuro-mux-layout" ())
(declare-function kuro-mux-select-layout       "kuro-mux-layout" (layout))
(declare-function kuro-create                  "kuro" (&optional command))
(declare-function kuro--send-paste-or-raw      "kuro" (text))
(declare-function kuro-copy-mode               "kuro" ())
(declare-function kuro-search-forward          "kuro" ())
(declare-function kuro-list-sessions           "kuro" ())

;; Buffer-local variables from kuro-mux.el and kuro-mux-ext.el.
(defvar kuro-mux--name)
(defvar kuro-mux--command)
(defvar kuro-mux--directory)
(defvar kuro-mux-mode-line-segment)


;;;; Layout persistence
;; `kuro-mux-layout-file' and `kuro-mux-auto-save-layout' defcustoms are
;; defined in kuro-mux-ext.el (loaded first), so only forward-declare here.
(defvar kuro-mux-layout-file)
(defvar kuro-mux-auto-save-layout)
(defvar read-eval)
(defvar read-circle)

(defconst kuro-mux--layout-spec-keys '(:name :directory)
  "Allowed keys in a persisted kuro-mux layout session spec.")

(cl-defstruct (kuro-mux--layout-session
               (:constructor kuro-mux--layout-session--create (name directory))
               (:copier nil))
  "Typed, validated mux layout session."
  (name nil :read-only t)
  (directory nil :read-only t))

(defun kuro-mux--session-spec (buf)
  "Return a typed layout session for kuro buffer BUF.
Returns nil if BUF is not a live kuro buffer."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (let ((name (or (kuro-mux--safe-layout-name kuro-mux--name)
                      (kuro-mux--safe-layout-name (buffer-name))
                      (generate-new-buffer-name "*kuro*")))
            (directory (kuro-mux--safe-layout-directory
                        (or kuro-mux--directory default-directory))))
        (kuro-mux--layout-session--create name directory)))))

;;;###autoload
(defun kuro-mux-save-layout ()
  "Save the current kuro session layout to `kuro-mux-layout-file'.
The layout records the name and working directory of each live session.  It
does not persist executable commands or PTY state (scrollback, terminal modes).
Use `kuro-mux-restore-layout' to recreate sessions with the configured default
command after an Emacs restart."
  (interactive)
  (let* ((sessions (kuro-mux--live-sessions))
         (specs    (delq nil (mapcar #'kuro-mux--session-spec sessions)))
         (records  (mapcar #'kuro-mux--layout-session-to-plist specs)))
    (with-temp-file kuro-mux-layout-file
      (insert ";; kuro-mux layout — auto-generated by kuro-mux-save-layout\n")
      (insert ";; Restore with M-x kuro-mux-restore-layout\n")
      (pp `(kuro-mux-layout ,@records) (current-buffer)))
    (message "kuro-mux: layout saved (%d session%s) → %s"
             (length records)
             (if (= (length records) 1) "" "s")
             kuro-mux-layout-file)))

(defun kuro-mux--skip-layout-trivia ()
  "Move point over whitespace and Lisp comments in a layout file."
  (let ((continue t))
    (while continue
      (skip-chars-forward " \t\n\r")
      (if (eq (char-after) ?\;)
          (forward-line 1)
        (setq continue nil)))))

(defun kuro-mux--read-layout-file ()
  "Read and return the layout sexp from `kuro-mux-layout-file'.
Returns nil if the file does not exist, cannot be parsed, uses reader
evaluation, or contains trailing non-comment data."
  (when (file-readable-p kuro-mux-layout-file)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents kuro-mux-layout-file)
          (goto-char (point-min))
          (let ((read-eval nil)
                (read-circle nil))
            (kuro-mux--skip-layout-trivia)
            (let ((layout (read (current-buffer))))
              (kuro-mux--skip-layout-trivia)
              (if (eobp)
                  layout
                (signal 'invalid-read-syntax '("trailing layout data"))))))
      (error nil))))

(defun kuro-mux--proper-list-p (value)
  "Return non-nil when VALUE is a finite proper list."
  (let ((slow value)
        (fast value)
        (ok t))
    (while (and ok (consp fast))
      (setq fast (cdr fast))
      (cond
       ((null fast))
       ((not (consp fast))
        (setq ok nil))
       (t
        (setq fast (cdr fast)
              slow (cdr slow))
        (when (eq slow fast)
          (setq ok nil)))))
    (and ok (null fast))))

(defun kuro-mux--proper-keyword-plist-p (value)
  "Return non-nil when VALUE is a finite proper plist with keyword keys."
  (and (kuro-mux--proper-list-p value)
       (let ((tail value)
             (valid t))
         (while (and valid tail)
           (if (and (keywordp (car tail))
                    (consp (cdr tail)))
               (setq tail (cddr tail))
             (setq valid nil)))
         valid)))

(defun kuro-mux--non-empty-string-p (value)
  "Return non-nil when VALUE is a non-empty string."
  (and (stringp value) (< 0 (length value))))

(defun kuro-mux--string-has-control-character-p (value)
  "Return non-nil when VALUE has an ASCII control character."
  (string-match-p "[[:cntrl:]]" value))

(defun kuro-mux--valid-layout-name-p (value)
  "Return non-nil when VALUE is a valid persisted layout name."
  (and (kuro-mux--non-empty-string-p value)
       (not (kuro-mux--string-has-control-character-p value))))

(defun kuro-mux--valid-layout-directory-p (value)
  "Return non-nil when VALUE is a valid optional layout directory."
  (or (null value)
      (and (kuro-mux--non-empty-string-p value)
           (not (kuro-mux--string-has-control-character-p value))
           (not (file-remote-p value))
           (file-directory-p value))))

(defun kuro-mux--safe-layout-name (value)
  "Return VALUE when it is safe to persist as a layout name."
  (when (kuro-mux--valid-layout-name-p value)
    value))

(defun kuro-mux--safe-layout-directory (value)
  "Return VALUE as a local directory name when it is safe to persist."
  (cond
   ((null value) nil)
   ((kuro-mux--valid-layout-directory-p value)
    (file-name-as-directory value))))

(defun kuro-mux--layout-spec-allowed-keys-p (spec)
  "Return non-nil when SPEC is composed only of persisted layout keys."
  (let ((tail spec)
        (valid t))
    (while (and valid tail)
      (unless (memq (car tail) kuro-mux--layout-spec-keys)
        (setq valid nil))
      (setq tail (cddr tail)))
    valid))

(defun kuro-mux--layout-session-from-plist (spec)
  "Return a typed layout session from persisted SPEC, or nil."
  (when (and (kuro-mux--proper-keyword-plist-p spec)
             (kuro-mux--layout-spec-allowed-keys-p spec)
             (kuro-mux--valid-layout-name-p (plist-get spec :name))
             (kuro-mux--valid-layout-directory-p (plist-get spec :directory)))
    (kuro-mux--layout-session--create
     (plist-get spec :name)
     (kuro-mux--safe-layout-directory (plist-get spec :directory)))))

(defun kuro-mux--layout-session-to-plist (session)
  "Return persisted plist representation for typed SESSION."
  (unless (kuro-mux--valid-layout-spec-p session)
    (user-error "Kuro-mux: invalid layout session spec"))
  (let ((directory (kuro-mux--layout-session-directory session)))
    (append (list :name (kuro-mux--layout-session-name session))
            (when directory
              (list :directory directory)))))

(defun kuro-mux--valid-layout-spec-p (spec)
  "Return non-nil when SPEC is a safe typed layout session."
  (and (kuro-mux--layout-session-p spec)
       (kuro-mux--valid-layout-name-p (kuro-mux--layout-session-name spec))
       (kuro-mux--valid-layout-directory-p
        (kuro-mux--layout-session-directory spec))))

(defun kuro-mux--restore-session (spec)
  "Recreate a single kuro session from typed layout SPEC.
SPEC must carry a string name and optionally existing directory string.
The configured default command is used for the new session.
Calls `kuro-mux--register' explicitly after creation so the session
appears in the registry even when lifecycle hooks are not installed."
  (unless (kuro-mux--valid-layout-spec-p spec)
    (user-error "Kuro-mux: invalid layout session spec"))
  (let* ((name (kuro-mux--layout-session-name spec))
         (dir  (kuro-mux--layout-session-directory spec))
         (default-directory (or dir default-directory)))
    (kuro-create nil)
    ;; kuro-create switches to the new buffer; annotate and register now
    (when (derived-mode-p 'kuro-mode)
      (setq kuro-mux--command nil)
      (setq kuro-mux--directory (or dir default-directory))
      (setq kuro-mux--name name)
      ;; Ensure registration regardless of whether kuro-mode-hook fired
      (kuro-mux--register))))

;;;###autoload
(defun kuro-mux-restore-layout ()
  "Recreate kuro sessions from the saved layout in `kuro-mux-layout-file'.
Each session is restarted with the configured default command and saved working
directory.  Terminal content (scrollback, history) is not restored — only the
session structure is recreated.
Signals `user-error' if the layout file does not exist."
  (interactive)
  (let ((layout (kuro-mux--read-layout-file)))
    (unless layout
      (user-error "Kuro-mux: no layout file found at %s"
                  kuro-mux-layout-file))
    ;; layout = (kuro-mux-layout (:name N :directory D) ...)
    (unless (and (consp layout)
                 (eq (car layout) 'kuro-mux-layout)
                 (kuro-mux--proper-list-p (cdr layout)))
      (user-error "Kuro-mux: invalid layout file format"))
    (let* ((raw   (cdr layout))
           (specs (kuro-mux--parse-layout-plists raw)))
      (when (and raw (null specs))
        (user-error "Kuro-mux: invalid layout session spec"))
      (dolist (spec specs)
        (kuro-mux--restore-session spec))
      (message "kuro-mux: restored %d session%s from %s"
               (length specs)
               (if (= (length specs) 1) "" "s")
               kuro-mux-layout-file))))

(defun kuro-mux--parse-layout-plists (raw)
  "Parse RAW (the cdr of a kuro-mux-layout sexp) into typed sessions.
RAW is a list of plists as written by `kuro-mux-save-layout' via `pp'.
Each entry must have string :name, may have existing directory string
:directory, and may not contain executable command fields."
  (when (kuro-mux--proper-list-p raw)
    (let ((tail raw)
          (sessions nil)
          (valid t))
      (while (and valid tail)
        (let ((session (kuro-mux--layout-session-from-plist (car tail))))
          (if session
              (progn
                (push session sessions)
                (setq tail (cdr tail)))
            (setq valid nil))))
      (when (and valid sessions)
        (nreverse sessions)))))


(eval-and-compile
  (defconst kuro-mux--prefix-bindings
    '(("n" . kuro-mux-next)
      ("p" . kuro-mux-prev)
      ("s" . kuro-mux-switch-by-name)
      ("L" . kuro-mux-last)
      ("o" . kuro-mux-other-window)
      ("C-o" . kuro-mux-rotate-panes)
      ("M-o" . kuro-mux-rotate-panes-backward)
      ("f" . kuro-mux-find-window)
      ("%" . kuro-mux-split-right)
      ("\"" . kuro-mux-split-below)
      ("c" . kuro-mux-create)
      ("," . kuro-mux-rename)
      ("$" . kuro-mux-rename)
      ("d" . kuro-mux-detach)
      ("z" . kuro-mux-zoom)
      ("&" . kuro-mux-kill)
      ("S" . kuro-mux-save-layout)
      ("R" . kuro-mux-restore-layout)
      ("SPC" . kuro-mux-next-layout)
      ("M-SPC" . kuro-mux-select-layout)
      ("M-{" . kuro-mux-previous-layout)
      ("M-}" . kuro-mux-next-layout)
      ("{" . kuro-mux-swap-pane-backward)
      ("}" . kuro-mux-swap-pane-forward)
      ("!" . kuro-mux-break-pane)
      ("@" . kuro-mux-join-pane)
      ("[" . kuro-copy-mode)
      ("/" . kuro-search-forward)
      ("t" . kuro-mux-clock)
      ("x" . kuro-mux-send-to-session)
      ("B" . kuro-mux-broadcast-toggle)
      ("P" . kuro-mux-pipe-pane)
      ("m" . kuro-mux-monitor-activity-toggle)
      ("M" . kuro-mux-monitor-silence)
      ("w" . kuro-list-sessions)
      ("?" . kuro-mux-help))
    "Static prefix bindings for `kuro-mux-prefix-map'.
Each entry is (KEY . COMMAND), where KEY is a `kbd' string.")

  (defconst kuro-mux--prefix-resize-bindings
    '(("<up>" up 2)
      ("<down>" down 2)
      ("<left>" left 5)
      ("<right>" right 5))
    "Resize bindings for `kuro-mux-prefix-map'.
Each entry is (KEY DIRECTION DELTA).")
  )

(eval-and-compile
  (defun kuro-mux--prefix-resize-command (binding)
    "Return a resize command closure for BINDING.
BINDING is one entry from `kuro-mux--prefix-resize-bindings'."
    (pcase-let ((`(,_key ,direction ,delta) binding))
      (lambda () (interactive) (kuro-mux-resize-pane direction delta)))))

(defvar kuro-mux-prefix-map
  (let ((map (make-sparse-keymap)))
    (kuro--define-key-bindings map kuro-mux--prefix-bindings
                               (lambda (binding) (kbd (car binding)))
                               #'cdr)
    (dotimes (i 9)
      (let ((n (1+ i)))
        (define-key map (kbd (number-to-string n))
          (lambda () (interactive) (kuro-mux-select-by-index n)))))
    (kuro--define-key-bindings map kuro-mux--prefix-resize-bindings
                               (lambda (binding) (kbd (car binding)))
                               #'kuro-mux--prefix-resize-command)
    map)
  "Prefix keymap for kuro-mux multiplexer commands.
Bound under `kuro-mux-prefix-key' by `kuro-mux-install-keys'.
Static bindings are driven by `kuro-mux--prefix-bindings'; numeric and
resize bindings are installed procedurally because they close over
runtime values.")

(defcustom kuro-mux-prefix-key "C-c m"
  "Key sequence under which `kuro-mux-prefix-map' is bound.
The value is a `kbd' string used by `kuro-mux-install-keys'.  The default
coexists with the existing terminal-control bindings because the prefix ends
with a plain letter rather than another control character.  Changing this
after `kuro-mux-install-keys' has run requires re-running it."
  :type 'string
  :group 'kuro)

;;;###autoload
(defun kuro-mux-create (&optional command)
  "Create a new kuro session in the current window.
COMMAND defaults to `kuro-shell'.  Provided as a mux-prefix-friendly
wrapper around `kuro-create' so the prefix map has a `c' (create)
binding analogous to tmux."
  (interactive)
  (kuro-create (or command kuro-shell)))

;;;###autoload
(defun kuro-mux-install-keys (&optional keymap)
  "Bind `kuro-mux-prefix-map' under `kuro-mux-prefix-key' in KEYMAP.
KEYMAP defaults to `kuro-mode-map' so the multiplexer prefix is available
in every kuro terminal buffer.  Call this once after loading kuro, e.g.
from `kuro-mux-setup' or your init file.  Returns the keymap modified."
  (let ((map (or keymap (and (boundp 'kuro-mode-map) kuro-mode-map))))
    (unless (keymapp map)
      (user-error "Kuro-mux-install-keys: no valid keymap to bind into"))
    (define-key map (kbd kuro-mux-prefix-key) kuro-mux-prefix-map)
    map))


;;;; Help

(defun kuro-mux--help-insert ()
  "Insert the standard `kuro-mux-help' content into the current buffer."
  (insert (format "kuro-mux prefix key: %s\n\n" kuro-mux-prefix-key))
  (insert "Available commands:\n\n")
  (insert (substitute-command-keys "\\{kuro-mux-prefix-map}")))

;;;###autoload
(defun kuro-mux-help ()
  "Show a help buffer listing all kuro-mux prefix keymap bindings.
Displays the formatted contents of `kuro-mux-prefix-map' and the
configured `kuro-mux-prefix-key' via `with-help-window'."
  (interactive)
  (with-help-window "*kuro-mux help*"
    (kuro-mux--help-insert)))

;;;###autoload
(defun kuro-mux-clock ()
  "Display the current time in the echo area.
Analogous to tmux's clock mode (prefix + t)."
  (interactive)
  (message "kuro-mux: %s" (format-time-string "%H:%M:%S")))


;;;; Broadcast (synchronized panes)

(defvar kuro-mux--broadcast-mode nil
  "When non-nil, PTY input is replicated to all live kuro sessions.
Toggle interactively with `kuro-mux-broadcast-toggle' (prefix key + B).
Analogous to tmux's `:setw synchronize-panes on'.")

(defvar kuro-mux--broadcasting nil
  "Non-nil while `kuro-mux--broadcast-send' is iterating sessions.
Prevents re-entrant advice calls from causing infinite recursion when
broadcasting triggers another `kuro--send-paste-or-raw' in a target buffer.")

(defun kuro-mux--broadcast-send (text)
  "Replicate TEXT to all live kuro sessions except the current buffer.
Installed as :after advice on `kuro--send-paste-or-raw'.  Has no effect
when `kuro-mux--broadcast-mode' is nil or a broadcast is already in
progress (`kuro-mux--broadcasting' non-nil)."
  (when (and kuro-mux--broadcast-mode (not kuro-mux--broadcasting))
    (let ((kuro-mux--broadcasting t)
          (origin (current-buffer)))
      (kuro-mux--for-each-live-session
       (lambda (buf)
         (with-current-buffer buf
           (kuro--send-paste-or-raw text)))
       origin))))

;;;###autoload
(defun kuro-mux-broadcast-toggle ()
  "Toggle broadcast mode: replicate PTY input to all live kuro sessions.
When enabled, every keystroke sent to any kuro buffer is mirrored to all
other live kuro sessions — useful for running the same command on multiple
servers simultaneously.  Analogous to tmux `:setw synchronize-panes'."
  (interactive)
  (setq kuro-mux--broadcast-mode (not kuro-mux--broadcast-mode))
  (message "kuro-mux broadcast: %s"
           (if kuro-mux--broadcast-mode "ON — input shared across all sessions"
             "OFF")))

;; Install relay at load time; the guard inside kuro-mux--broadcast-send
;; ensures it is a no-op (two variable reads) unless broadcast mode is on.
(advice-add 'kuro--send-paste-or-raw :after #'kuro-mux--broadcast-send)


;;;; Setup

(defcustom kuro-mux-install-prefix-keys t
  "When non-nil, `kuro-mux-setup' installs the mux prefix keymap.
Binds `kuro-mux-prefix-map' under `kuro-mux-prefix-key' in `kuro-mode-map'.
Set to nil if you prefer to bind multiplexer commands manually."
  :type 'boolean
  :group 'kuro)

(defun kuro-mux-setup ()
  "Activate kuro-mux: install lifecycle hooks and (optionally) prefix keys.
Call this once in your init file after loading kuro.
Installs the tmux-style prefix keymap when `kuro-mux-install-prefix-keys'
is non-nil.  With `kuro-mux-tab-bar-mode' enabled, also syncs sessions to
tab-bar tabs."
  (kuro-mux--install-hooks)
  (when (and kuro-mux-install-prefix-keys
             (boundp 'kuro-mode-map)
             (keymapp kuro-mode-map))
    (kuro-mux-install-keys))
  (when kuro-mux-mode-line-segment
    (kuro-mux-install-mode-line)))


(provide 'kuro-mux-ext2)
;;; kuro-mux-ext2.el ends here
