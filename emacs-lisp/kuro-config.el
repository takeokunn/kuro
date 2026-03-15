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

;;; Customization Groups

(defgroup kuro nil
  "Kuro terminal emulator."
  :group 'terminal
  :prefix "kuro-")

(defgroup kuro-display nil
  "Display settings for Kuro terminal emulator."
  :group 'kuro
  :prefix "kuro-")

(defgroup kuro-colors nil
  "ANSI color palette for Kuro terminal emulator."
  :group 'kuro
  :prefix "kuro-color-")

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

;;; Internal Color Table
;; Defined before the :set handlers so that kuro--set-color can safely
;; call kuro--rebuild-named-colors even if custom-set-variables fires
;; a :set handler before the file has fully loaded.

(defvar kuro--named-colors nil
  "Internal alist mapping ANSI color names to hex color strings.
Rebuilt automatically from `kuro-color-*' defcustom values by
`kuro--rebuild-named-colors'.  Do not set this variable directly.")

(defun kuro--rebuild-named-colors ()
  "Rebuild `kuro--named-colors' from `kuro-color-*' defcustom values.
Called at file load and by each color `defcustom' `:set' handler.
Skips rebuild silently if any color variable is not yet bound (e.g.
during `defcustom' initialization before all 16 colors are defined)."
  (when (boundp 'kuro-color-bright-white)
    (setq kuro--named-colors
          (list (cons "black"          kuro-color-black)
                (cons "red"            kuro-color-red)
                (cons "green"          kuro-color-green)
                (cons "yellow"         kuro-color-yellow)
                (cons "blue"           kuro-color-blue)
                (cons "magenta"        kuro-color-magenta)
                (cons "cyan"           kuro-color-cyan)
                (cons "white"          kuro-color-white)
                (cons "bright-black"   kuro-color-bright-black)
                (cons "bright-red"     kuro-color-bright-red)
                (cons "bright-green"   kuro-color-bright-green)
                (cons "bright-yellow"  kuro-color-bright-yellow)
                (cons "bright-blue"    kuro-color-bright-blue)
                (cons "bright-magenta" kuro-color-bright-magenta)
                (cons "bright-cyan"    kuro-color-bright-cyan)
                (cons "bright-white"   kuro-color-bright-white)))))

;;; :set handler functions

(defun kuro--set-shell (symbol value)
  "Validate and set SYMBOL to VALUE for `kuro-shell'."
  (unless (or (null value) (string-empty-p value) (executable-find value))
    (user-error "kuro: shell executable not found: %s" value))
  (set-default symbol value))

(defun kuro--set-scrollback-size (symbol value)
  "Set SYMBOL to VALUE and propagate to all live Kuro buffers."
  (unless (and (integerp value) (> value 0))
    (user-error "kuro: scrollback-size must be a positive integer, got: %s" value))
  (set-default symbol value)
  (when (fboundp 'kuro--set-scrollback-max-lines)
    (dolist (buf (kuro--kuro-buffers))
      (with-current-buffer buf
        (kuro--set-scrollback-max-lines value)))))

(defun kuro--set-frame-rate (symbol value)
  "Set SYMBOL to VALUE and restart render loops in all active Kuro buffers."
  (unless (and (integerp value) (> value 0))
    (user-error "kuro: frame-rate must be a positive integer, got: %s" value))
  (set-default symbol value)
  (when (and (fboundp 'kuro--stop-render-loop)
             (fboundp 'kuro--start-render-loop))
    (dolist (buf (kuro--kuro-buffers))
      (with-current-buffer buf
        (kuro--stop-render-loop)
        (kuro--start-render-loop)))))

(defun kuro--set-font (symbol value)
  "Set SYMBOL to VALUE and apply font remap to all active Kuro buffers."
  (set-default symbol value)
  (when (fboundp 'kuro--apply-font-to-buffer)
    (dolist (buf (kuro--kuro-buffers))
      (kuro--apply-font-to-buffer buf))))

(defun kuro--set-color (symbol value)
  "Set SYMBOL to VALUE, rebuild color table, and clear face cache."
  (unless (and (stringp value)
               (string-match-p "^#[0-9a-fA-F]\\{6\\}$" value))
    (user-error "kuro: color must be a 6-digit hex string like #rrggbb, got: %s" value))
  (set-default symbol value)
  (kuro--rebuild-named-colors)
  (when (fboundp 'kuro--clear-face-cache)
    (kuro--clear-face-cache)))

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

;;; Core Settings

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

(defcustom kuro-frame-rate 60
  "Frame rate for terminal rendering in frames per second.
Must be a positive integer (greater than zero).
Changes take effect immediately by restarting the render loop.
60 fps (≈16 ms between frames) matches modern terminal emulators such as kitty
and wezterm.  The idle-timer mechanism in kuro--self-insert also triggers an
immediate render after each keypress, so input echo is not limited by this rate."
  :type '(integer :tag "Positive integer (> 0)")
  :group 'kuro-display
  :set #'kuro--set-frame-rate)

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

;;; ANSI Color Palette

(defcustom kuro-color-black "#000000"
  "Color for ANSI black (palette index 0).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-red "#c23621"
  "Color for ANSI red (palette index 1).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-green "#25bc24"
  "Color for ANSI green (palette index 2).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-yellow "#adad27"
  "Color for ANSI yellow (palette index 3).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-blue "#492ee1"
  "Color for ANSI blue (palette index 4).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-magenta "#d338d3"
  "Color for ANSI magenta (palette index 5).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-cyan "#33bbc8"
  "Color for ANSI cyan (palette index 6).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-white "#cbcccd"
  "Color for ANSI white (palette index 7).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-black "#808080"
  "Color for ANSI bright black / dark gray (palette index 8).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-red "#ff0000"
  "Color for ANSI bright red (palette index 9).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-green "#00ff00"
  "Color for ANSI bright green (palette index 10).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-yellow "#ffff00"
  "Color for ANSI bright yellow (palette index 11).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-blue "#0000ff"
  "Color for ANSI bright blue (palette index 12).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-magenta "#ff00ff"
  "Color for ANSI bright magenta (palette index 13).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-cyan "#00ffff"
  "Color for ANSI bright cyan (palette index 14).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

(defcustom kuro-color-bright-white "#ffffff"
  "Color for ANSI bright white (palette index 15).  Value must be a 6-digit hex string, e.g. #rrggbb."
  :type 'color
  :group 'kuro-colors
  :set #'kuro--set-color)

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
    (unless (and (integerp kuro-scrollback-size) (> kuro-scrollback-size 0))
      (push (format "kuro-scrollback-size: must be a positive integer, got: %s"
                    kuro-scrollback-size)
            errors))
    (unless (and (integerp kuro-frame-rate) (> kuro-frame-rate 0))
      (push (format "kuro-frame-rate: must be a positive integer, got: %s"
                    kuro-frame-rate)
            errors))
    (when kuro-font-size
      (unless (and (integerp kuro-font-size) (> kuro-font-size 0))
        (push (format "kuro-font-size: must be a positive integer or nil, got: %s"
                      kuro-font-size)
              errors)))
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
