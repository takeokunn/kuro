;;; kuro-config.el --- Entry point for Kuro configuration  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Compatibility entry point for Kuro configuration.
;; User-facing defcustom values live here; runtime validation lives in
;; `kuro-config-logic'.

;;; Code:

(require 'kuro-config-logic)
(require 'kuro-colors)

(defgroup kuro nil
  "Kuro terminal emulator."
  :group 'terminal
  :prefix "kuro-")

(defgroup kuro-display nil
  "Display settings for Kuro terminal emulator."
  :group 'kuro
  :prefix "kuro-")

;;; Color variable enumeration

(defconst kuro--color-defcustom-vars
  '(kuro-color-black     kuro-color-red     kuro-color-green   kuro-color-yellow
    kuro-color-blue      kuro-color-magenta kuro-color-cyan    kuro-color-white
    kuro-color-bright-black   kuro-color-bright-red
    kuro-color-bright-green   kuro-color-bright-yellow
    kuro-color-bright-blue    kuro-color-bright-magenta
    kuro-color-bright-cyan    kuro-color-bright-white)
  "All 16 ANSI color defcustom variables in standard terminal order.
Used by `kuro--validate-config' and any code needing to enumerate all colors.")

;;; Module Binary Path

(defcustom kuro-module-binary-path nil
  "Path to the kuro native module binary (libkuro_core.so / libkuro_core.dylib).
When nil, kuro will auto-detect the binary from standard locations:
1. ~/.local/share/kuro/ (installed via \\[kuro-module-download])
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
  "Default terminal width in columns when window dimensions are unavailable.
Used in `kuro--init' when the COLS argument is nil (e.g., noninteractive mode).
See also `kuro--default-rows'.")

;;; Core Settings

(defcustom kuro-keymap-exceptions
  '("C-c" "C-x" "C-u" "C-g" "C-h" "C-l" "M-x" "M-o" "C-y" "M-y")
  "Keys passed to Emacs instead of the PTY in `kuro-mode'.
Each element is a key description string accepted by `kbd'.
Keys in this list are not bound in the Kuro input keymap and
therefore fall through to the standard Emacs global keymap.

The default list mirrors `vterm-keymap-exceptions' from emacs-libvterm,
covering the Kuro-mode prefix key, standard Emacs prefix keys, and common
editing commands such as `yank', `yank-pop', `universal-argument',
`keyboard-quit', and `execute-extended-command'.

Changes via Customize take effect immediately: the keymap is rebuilt and
propagated to all live Kuro buffers.  If you set this variable directly
with `setq', call `(kuro--build-keymap)' afterwards to rebuild the keymap."
  :type '(repeat string)
  :group 'kuro
  :set #'kuro--set-keymap-exceptions)

(defvaralias 'kuro-default-shell 'kuro-shell
  "Backward-compatibility alias for `kuro-shell'.")

(defcustom kuro-shell (or (getenv "SHELL") "/bin/bash")
  "Shell program to run in the Kuro terminal.
Must be an executable accessible via PATH.
Set to nil to use the system default shell.
Also accessible via the alias `kuro-default-shell' for backward compatibility."
  :type 'string
  :group 'kuro
  :set #'kuro--set-shell)

(defcustom kuro-shell-integration t
  "When non-nil, automatically inject shell integration scripts.
Provides directory tracking, prompt navigation, and title updates."
  :type 'boolean
  :group 'kuro)

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

(defcustom kuro-notifications-enabled t
  "Whether to surface terminal desktop notifications (OSC 9 / OSC 777).
When non-nil, notifications emitted by terminal applications are displayed
via `kuro-notification-function'.  Pending notifications are always drained
from the Rust core regardless of this setting, so they cannot accumulate."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-notification-function 'kuro--default-notify
  "Function that displays a terminal desktop notification.
Called with two arguments: TITLE (a string or nil) and BODY (a string).
The default, `kuro--default-notify', prefers `notifications-notify' (D-Bus)
when available and otherwise falls back to the echo area."
  :type 'function
  :group 'kuro)

;;; Display Settings

(defcustom kuro-frame-rate 120
  "Frame rate for terminal rendering in frames per second.
Must be a positive integer (greater than zero).
Changes take effect immediately by restarting the render loop.
120 fps (≈8 ms between frames) provides smooth, low-latency rendering.
The idle-timer mechanism in kuro--self-insert also triggers an immediate render
after each keypress, so input echo is not limited by this rate."
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

;; Migration guard: `defcustom' uses `defvar' semantics and will not override a
;; variable that is already bound.  Daemons that loaded an older kuro-config.el
;; where the default was `nil' therefore retain `nil' even after reload.
;; Reset to `t' only when the user has not explicitly saved a custom value so
;; that deliberate `nil' customisations are preserved.
(when (and (null kuro-use-binary-ffi)
           (null (get 'kuro-use-binary-ffi 'saved-value)))
  (setq kuro-use-binary-ffi t))

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

(defconst kuro--positive-integer-config-vars
  '(kuro-scrollback-size
    kuro-frame-rate
    kuro-tui-frame-rate)
  "Kuro config variables that must always hold positive integers.")

(defconst kuro--optional-positive-integer-config-vars
  '(kuro-font-size)
  "Kuro config variables that may be nil or a positive integer.")

(provide 'kuro-config)

;;; kuro-config.el ends here
