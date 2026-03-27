;;; kuro-config.el --- User configuration for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Central configuration module for the Kuro terminal emulator.
;; All user-facing defcustom variables are defined here.
;;
;; This file has no dependencies on other kuro modules and must be
;; loaded before kuro-renderer.el.

;;; Code:

(require 'kuro-colors)

;;; Customization Groups

(defgroup kuro nil
  "Kuro terminal emulator."
  :group 'terminal
  :prefix "kuro-")

(defgroup kuro-display nil
  "Display settings for Kuro terminal emulator."
  :group 'kuro
  :prefix "kuro-")

;;; Internal buffer iterator

(defun kuro--kuro-buffers ()
  "Return a list of all live Kuro terminal buffers."
  (when (fboundp 'kuro-mode)
    (let (result)
      (dolist (buf (buffer-list))
        (when (and (buffer-live-p buf)
                   (with-current-buffer buf
                     (derived-mode-p 'kuro-mode)))
          (push buf result)))
      (nreverse result))))

;;; Validation Primitives

(defsubst kuro--positive-integer-p (val)
  "Return non-nil if VAL is a positive integer (> 0)."
  (and (integerp val) (> val 0)))

(defmacro kuro--broadcast-to-buffers (fn &rest args)
  "When FN is bound, call (FN ARGS...) in every live kuro-mode buffer."
  `(when (fboundp ',fn)
     (dolist (buf (kuro--kuro-buffers))
       (with-current-buffer buf
         (,fn ,@args)))))

(defmacro kuro--check-positive-integer (var errors)
  "Push an error string onto ERRORS if VAR is not a positive integer."
  `(unless (kuro--positive-integer-p ,var)
     (push (format "%s: must be a positive integer, got: %s" ',var ,var) ,errors)))

(defmacro kuro--def-positive-int-setter (name err-msg doc &rest body)
  "Define a defcustom :set handler NAME for a positive-integer setting.
ERR-MSG is the user-error format string (receives VALUE as %s argument).
DOC is the function docstring.
Validates VALUE, sets SYMBOL via `set-default', then evaluates BODY.
SYMBOL and VALUE are bound within BODY."
  (declare (indent 3) (doc-string 3))
  `(defun ,name (symbol value)
     ,doc
     (unless (kuro--positive-integer-p value)
       (user-error ,err-msg value))
     (set-default symbol value)
     ,@body))

;;; :set handler functions

(defun kuro--set-shell (symbol value)
  "Validate and set SYMBOL to VALUE for `kuro-shell'."
  (unless (or (null value) (string-empty-p value) (executable-find value))
    (user-error "kuro: shell executable not found: %s" value))
  (set-default symbol value))

(kuro--def-positive-int-setter kuro--set-scrollback-size
    "kuro: scrollback-size must be a positive integer, got: %s"
    "Set SYMBOL to VALUE and propagate to all live Kuro buffers."
  (kuro--broadcast-to-buffers kuro--set-scrollback-max-lines value))

(kuro--def-positive-int-setter kuro--set-frame-rate
    "kuro: frame-rate must be a positive integer, got: %s"
    "Set SYMBOL to VALUE and restart render loops in all active Kuro buffers."
  (when (and (fboundp 'kuro--stop-render-loop)
             (fboundp 'kuro--start-render-loop))
    (dolist (buf (kuro--kuro-buffers))
      (with-current-buffer buf
        (kuro--stop-render-loop)
        (kuro--start-render-loop)))))

(kuro--def-positive-int-setter kuro--set-tui-frame-rate
    "kuro: tui-frame-rate must be a positive integer, got: %s"
    "Set SYMBOL to VALUE and switch render timer in active TUI-mode Kuro buffers."
  (when (fboundp 'kuro--switch-render-timer)
    (dolist (buf (kuro--kuro-buffers))
      (with-current-buffer buf
        (when (bound-and-true-p kuro--tui-mode-active)
          (kuro--switch-render-timer value))))))

(defun kuro--set-font (symbol value)
  "Set SYMBOL to VALUE and apply font remap to all active Kuro buffers."
  (set-default symbol value)
  (kuro--broadcast-to-buffers kuro--apply-font-to-buffer buf))

(defun kuro--set-input-echo-delay (symbol value)
  "Validate and set SYMBOL to VALUE for `kuro-input-echo-delay'.
VALUE must be a non-negative number."
  (unless (numberp value)
    (user-error "kuro-input-echo-delay must be a number"))
  (when (< value 0)
    (user-error "kuro-input-echo-delay must be non-negative"))
  (set-default symbol value))

;;; Module Binary Path

(defcustom kuro-module-binary-path nil
  "Path to the kuro native module binary (libkuro_core.so / libkuro_core.dylib).
When nil, kuro will auto-detect the binary from standard locations:
1. ~/.local/share/kuro/ (installed via `make install')
2. The directory adjacent to this file's location (development checkout)

Set this if the binary is installed in a non-standard location."
  :type '(choice (const :tag "Auto-detect" nil)
                 (file :tag "Custom path"))
  :group 'kuro)

;;; Terminal dimension defaults

(defconst kuro--default-rows 24
  "Default terminal height in rows used when window dimensions are unavailable.
Used in `kuro--init' when the ROWS argument is nil (e.g., noninteractive mode).
See also `kuro--default-cols'.")

(defconst kuro--default-cols 80
  "Default terminal width in columns used when window dimensions are unavailable.
Used in `kuro--init' when the COLS argument is nil (e.g., noninteractive mode).
See also `kuro--default-rows'.")

;;; Core Settings

(defcustom kuro-keymap-exceptions
  '("C-c" "C-x" "C-u" "C-g" "C-h" "C-l" "M-x" "M-o" "C-y" "M-y")
  "Keys passed to Emacs instead of the PTY in `kuro-mode'.
Each element is a key description string accepted by `kbd', e.g. \"M-x\"
or \"C-g\".  Keys in this list are not bound in the Kuro input keymap and
therefore fall through to the standard Emacs global keymap.

The default list mirrors `vterm-keymap-exceptions' from emacs-libvterm:
  C-c  prefix key for Kuro commands (C-c C-c = SIGINT, C-c C-t = copy-mode)
  C-x  Emacs prefix (C-x C-f, C-x b, etc.)
  C-u  Emacs universal-argument
  C-g  Emacs keyboard-quit / abort
  C-h  Emacs help prefix
  C-l  recenter-top-bottom (use C-l in shell via `kuro-send-next-key')
  M-x  execute-extended-command
  M-o  other-window / face prefix
  C-y  yank (with bracketed-paste support via `kuro--yank')
  M-y  yank-pop

Changes do NOT take effect automatically.  After modifying this variable
you must call `(kuro--build-keymap)' to rebuild the keymap; the next Kuro
buffer you open will then use the updated binding set."
  :type '(repeat string)
  :group 'kuro)

(defcustom kuro-shell (or (getenv "SHELL") "/bin/bash")
  "Shell program to run in the Kuro terminal.
Must be an executable accessible via PATH.
Set to nil to use the system default shell.
Also accessible via the alias `kuro-default-shell' for backward compatibility."
  :type 'string
  :group 'kuro
  :set #'kuro--set-shell)

(defvaralias 'kuro-default-shell 'kuro-shell
  "Backward-compatibility alias for `kuro-shell'.")

(defcustom kuro-scrollback-size 10000
  "Maximum number of lines retained in the scrollback buffer.
Must be a positive integer (greater than zero).
Changes take effect immediately in all running Kuro buffers."
  :type '(integer :tag "Positive integer (> 0)")
  :group 'kuro
  :set #'kuro--set-scrollback-size)

;;; Security Settings

(defcustom kuro-clipboard-policy 'write-only
  "Security policy for OSC 52 clipboard access.
`write-only' allows terminal apps to set the clipboard but not read it.
`allow' permits both read and write access.
`prompt' asks for confirmation on each clipboard access."
  :type '(choice (const :tag "Write only (safest)" write-only)
                 (const :tag "Allow read and write" allow)
                 (const :tag "Prompt for each access" prompt))
  :group 'kuro)

;;; Display Settings

(defcustom kuro-frame-rate 120
  "Frame rate for terminal rendering in frames per second.
Must be a positive integer (greater than zero).
Changes take effect immediately by restarting the render loop.
120 fps (≈8 ms between frames) provides smooth, low-latency rendering.
The idle-timer mechanism in kuro--self-insert also triggers an
immediate render after each keypress, so input echo is not limited by this rate."
  :type '(integer :tag "Positive integer (> 0)")
  :group 'kuro-display
  :set #'kuro--set-frame-rate)

(defcustom kuro-tui-frame-rate 5
  "Frame rate used when a full-screen TUI app is detected.
When the renderer detects that a TUI application (cmatrix, htop, vim, etc.)
is running — identified by >= `kuro--tui-dirty-threshold' of terminal rows
being dirty for several consecutive frames — it switches the render timer
to this lower rate.  This reduces CPU usage significantly during sustained
full-screen redraws.  The normal `kuro-frame-rate' is restored immediately
when the TUI app exits."
  :type '(integer :tag "Positive integer (> 0)")
  :group 'kuro-display
  :set #'kuro--set-tui-frame-rate)

(defcustom kuro-streaming-latency-mode t
  "When non-nil, enable low-latency mode for AI agent streaming output.
In this mode, a zero-delay idle timer fires an immediate render cycle
whenever the PTY has pending data, giving token-by-token responsiveness
without waiting for the next 120fps frame tick."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-kill-buffer-on-exit t
  "When non-nil, automatically kill the buffer when the shell process exits.
Set to nil to keep the buffer open for reviewing output after exit."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-typewriter-effect nil
  "When non-nil, display new terminal output character-by-character.
This creates a smooth \"typing\" animation for AI agent output.
Set `kuro-typewriter-chars-per-second' to control the display speed."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-use-binary-ffi t
  "When non-nil, use the binary FFI protocol for polling terminal updates.
In binary mode the native module returns a flat vector of byte values instead
of nested Lisp cons cells, shifting cons allocation from the FFI layer to the
Elisp decoder.  Enable this when `kuro-debug-perf' output shows the FFI
allocation phase dominating per-frame time.  The visual output is identical
to the default cons-cell protocol.
Requires kuro native module >= 1.1."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-typewriter-chars-per-second 120
  "Number of characters to display per second in typewriter mode.
Higher values look faster; lower values are more dramatic.
Only effective when `kuro-typewriter-effect' is non-nil."
  :type 'natnum
  :group 'kuro)

(defcustom kuro-input-echo-delay 0.01
  "Seconds to wait after a keypress before polling for the PTY echo response.
The PTY reader thread needs a short window to receive the shell's echo and
deposit it in the crossbeam channel before the Emacs side polls.  A 0 s
delay is too aggressive on most systems: the idle timer fires before the
reader thread wakes from its blocking read call, resulting in an empty poll
and no cursor movement until the next 120 fps periodic tick (~8 ms later).

10 ms (0.01 s) comfortably covers the PTY kernel round-trip on both macOS
and Linux without adding perceptible latency to keystroke echo."
  :type 'float
  :group 'kuro
  :set #'kuro--set-input-echo-delay)

(defcustom kuro-font-family nil
  "Font family for Kuro terminal buffers.
nil means inherit from the default face.
Only effective in graphical Emacs frames; has no effect in terminal frames."
  :type '(choice (const :tag "Inherit from default face" nil)
                 (string :tag "Font family name (e.g. \"Iosevka\")"))
  :group 'kuro-display
  :set #'kuro--set-font)

(defcustom kuro-font-size nil
  "Font size in points for Kuro terminal buffers.
nil means inherit from the default face.
Only effective in graphical Emacs frames; has no effect in terminal frames.
The value is converted to Emacs face :height units (* 10 value)."
  :type '(choice (const :tag "Inherit from default face" nil)
                 (natnum :tag "Size in points (e.g. 14)"))
  :group 'kuro-display
  :set #'kuro--set-font)

;;; Validation

(defun kuro--validate-config ()
  "Validate all Kuro configuration settings.
Returns a list of error description strings.
An empty list indicates that all settings are valid."
  (let ((errors nil))
    (unless (or (null kuro-shell)
                (string-empty-p kuro-shell)
                (executable-find kuro-shell))
      (push (format "kuro-shell: executable not found: %s" kuro-shell) errors))
    (kuro--check-positive-integer kuro-scrollback-size errors)
    (kuro--check-positive-integer kuro-frame-rate errors)
    (kuro--check-positive-integer kuro-tui-frame-rate errors)
    (when kuro-font-size
      (kuro--check-positive-integer kuro-font-size errors))
    (dolist (color-var '(kuro-color-black
                         kuro-color-red
                         kuro-color-green
                         kuro-color-yellow
                         kuro-color-blue
                         kuro-color-magenta
                         kuro-color-cyan
                         kuro-color-white
                         kuro-color-bright-black
                         kuro-color-bright-red
                         kuro-color-bright-green
                         kuro-color-bright-yellow
                         kuro-color-bright-blue
                         kuro-color-bright-magenta
                         kuro-color-bright-cyan
                         kuro-color-bright-white))
      (let ((val (symbol-value color-var)))
        (unless (and (stringp val)
                     (string-match-p "^#[0-9a-fA-F]\\{6\\}$" val))
          (push (format "%s: must be a 6-digit hex string like #rrggbb, got: %s"
                        color-var val)
                errors))))
    (nreverse errors)))

;;;###autoload
(defun kuro-validate-config ()
  "Check Kuro configuration and report any validation errors.
Displays results in the echo area."
  (interactive)
  (let ((errors (kuro--validate-config)))
    (if errors
        (message "Kuro configuration errors (%d):\n%s"
                 (length errors)
                 (mapconcat #'identity errors "\n"))
      (message "Kuro: all configuration settings are valid."))))

;; Initialize the color table from current defcustom values at load time.
(kuro--rebuild-named-colors)

(provide 'kuro-config)

;;; kuro-config.el ends here
