;;; kuro.el --- Main entry point for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn <takeokunn@users.noreply.github.com>
;; URL: https://github.com/takeokunn/kuro
;; Version: 1.0.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: terminal, tools

;;; Commentary:

;; Kuro is a modern terminal emulator for Emacs using a Rust core and
;; Emacs Lisp UI. It implements the Remote Display Model where all
;; terminal state is managed in Rust and Emacs is purely a display layer.

;; Usage:
;; (require 'kuro)
;; (kuro-create "bash")

;;; Code:

(require 'kuro-module)
(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-faces)
(require 'kuro-overlays)
(require 'kuro-navigation)
(require 'kuro-input)
(require 'kuro-stream)
(require 'kuro-render-buffer)
(require 'kuro-renderer)
(require 'kuro-lifecycle)

;; kuro-send-next-key is defined in kuro-input.el (loaded before kuro.el uses it).
(declare-function kuro-send-next-key "kuro-input" ())
(declare-function kuro--handle-focus-in "kuro-navigation" ())
(declare-function kuro--handle-focus-out "kuro-navigation" ())

(defvar kuro-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Terminal keybindings should pass through
    (define-key map [?\C-c ?\C-c] 'kuro-send-interrupt)
    (define-key map [?\C-c ?\C-z] 'kuro-send-sigstop)
    (define-key map [?\C-c ?\C-\\] 'kuro-send-sigquit)
    ;; Prompt navigation (OSC 133)
    (define-key map [?\C-c ?\C-p] #'kuro-previous-prompt)
    (define-key map [?\C-c ?\C-n] #'kuro-next-prompt)
    ;; Copy mode: suspend PTY input and enable normal Emacs navigation/selection
    (define-key map [?\C-c ?\C-t] #'kuro-copy-mode)
    ;; Send next key directly to PTY, bypassing kuro-keymap-exceptions
    (define-key map [?\C-c ?\C-q] #'kuro-send-next-key)
    map)
  "Keymap for Kuro major mode.")

(defun kuro--window-size-change (frame)
  "Handle window size changes for kuro buffers in FRAME.
Called from `window-size-change-functions'.  For every kuro buffer
whose window dimensions changed, records the new size in
`kuro--resize-pending' so the render cycle can process it
synchronously -- avoiding a race where both this hook and the render
cycle independently call `kuro--resize'."
  (dolist (win (window-list frame))
    (let ((buf (window-buffer win)))
      (when (and (buffer-live-p buf)
                 (with-current-buffer buf (derived-mode-p 'kuro-mode)))
        (with-current-buffer buf
          (let ((new-rows (window-body-height win))
                (new-cols (window-body-width win)))
            (when (and kuro--initialized
                       (or (/= new-rows kuro--last-rows)
                           (/= new-cols kuro--last-cols)))
              ;; Record pending resize; the render cycle will process it
              ;; synchronously, avoiding a race where both paths call kuro--resize.
              (setq kuro--resize-pending (cons new-rows new-cols)))))))))

(defvar-local kuro--copy-mode nil
  "Non-nil when Kuro copy mode is active.
In copy mode the PTY keymap parent is detached so standard Emacs
navigation and text-selection commands work in the terminal buffer.")
(put 'kuro--copy-mode 'permanent-local t)

(defun kuro--enter-copy-mode ()
  "Enter Kuro copy mode: suspend PTY input and enable Emacs navigation.
Uses `use-local-map' so only the current buffer is affected; other Kuro
buffers keep their normal terminal keymaps."
  (setq-local kuro--copy-mode t)
  ;; Install a minimal buffer-local keymap: only C-c C-t to exit.
  ;; No parent → the global keymap applies, giving full Emacs navigation.
  (let ((copy-map (make-sparse-keymap)))
    (define-key copy-map [?\C-c ?\C-t] #'kuro-copy-mode)
    (use-local-map copy-map))
  (setq mode-name "Kuro[Copy]")
  (force-mode-line-update)
  (message "Kuro copy mode on (C-c C-t to exit)"))

(defun kuro--exit-copy-mode ()
  "Exit Kuro copy mode: restore PTY input keymap."
  (setq-local kuro--copy-mode nil)
  ;; Restore the standard kuro-mode-map (includes kuro--keymap as parent).
  (use-local-map kuro-mode-map)
  (setq mode-name "Kuro")
  (force-mode-line-update)
  ;; Re-render so the terminal cursor is restored to its correct position.
  (when (fboundp 'kuro--render-cycle)
    (kuro--render-cycle))
  (message "Kuro copy mode off"))

;;;###autoload
(defun kuro-copy-mode ()
  "Toggle Kuro copy mode.
In copy mode the PTY keymap is suspended and standard Emacs cursor
movement, region selection, and copy commands (M-w, C-w, C-s…) become
available.  The buffer remains read-only; only navigation and selection
are enabled.  Press C-c C-t again to return to terminal mode."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "kuro-copy-mode: not in a Kuro terminal buffer"))
  (if kuro--copy-mode
      (kuro--exit-copy-mode)
    (kuro--enter-copy-mode)))

(defvar-local kuro--last-rows 0
  "Last known terminal row count; used to detect window size changes.")
(put 'kuro--last-rows 'permanent-local t)

(defvar-local kuro--last-cols 0
  "Last known terminal column count; used to detect window size changes.")
(put 'kuro--last-cols 'permanent-local t)

(defun kuro--setup-char-width-table ()
  "Override `char-width-table' to match unicode-width 0.2 / xterm-256color behavior.
In CJK language environments Emacs sets East-Asian-Ambiguous characters
\(block elements, geometric shapes, misc symbols, etc.) to display width 2.
However the Rust unicode-width 0.2 crate — and every standard xterm-256color
terminal — treats those same codepoints as width 1.  Terminal applications
such as btop lay out their UI assuming width 1, so a discrepancy causes
visual corruption \(characters shifted right after each ambiguous glyph).

Braille patterns \(U+2800-U+28FF) are EA-Width Narrow and already 1 in both
environments, but are pinned explicitly as a safety net against unusual
font-fallback rendering."
  (make-local-variable 'char-width-table)
  (setq char-width-table (copy-sequence char-width-table))
  ;; Arrows (U+2190-U+21FF) — EA Width A for many (↑↓←→ used as sort/nav indicators)
  (set-char-table-range char-width-table '(#x2190 . #x21FF) 1)
  ;; Mathematical Operators (U+2200-U+22FF) — EA Width A for many (×, ÷, ∞, √ etc.)
  (set-char-table-range char-width-table '(#x2200 . #x22FF) 1)
  ;; Miscellaneous Technical (U+2300-U+23FF) — EA Width A for some
  (set-char-table-range char-width-table '(#x2300 . #x23FF) 1)
  ;; Box Drawing (U+2500-U+257F) — EA Width N, used by ncurses borders
  (set-char-table-range char-width-table '(#x2500 . #x257F) 1)
  ;; Block Elements (U+2580-U+259F) — EA Width A; used by btop/htop bar graphs
  (set-char-table-range char-width-table '(#x2580 . #x259F) 1)
  ;; Geometric Shapes (U+25A0-U+25FF) — EA Width A for many; used by TUI indicators
  (set-char-table-range char-width-table '(#x25A0 . #x25FF) 1)
  ;; Miscellaneous Symbols (U+2600-U+26FF) — EA Width A for many
  (set-char-table-range char-width-table '(#x2600 . #x26FF) 1)
  ;; Dingbats (U+2700-U+27BF) — EA Width A for many
  (set-char-table-range char-width-table '(#x2700 . #x27BF) 1)
  ;; Braille Patterns (U+2800-U+28FF) — EA Width N; pin to 1 for font-fallback safety
  (set-char-table-range char-width-table '(#x2800 . #x28FF) 1))

(define-derived-mode kuro-mode fundamental-mode "Kuro"
  "Major mode for Kuro terminal buffers."
  (setq buffer-read-only t)
  (setq-local bidi-display-reordering nil)
  (setq-local truncate-lines t)
  ;; Normalise character display widths to match the Rust unicode-width 0.2 crate.
  ;; Must run before the first render so col_to_buf mappings stay consistent.
  (kuro--setup-char-width-table)
  ;; Do NOT enable cursor-intangible-mode: it interferes with set-window-point
  ;; (which we use to track the terminal cursor), causing the visual cursor to
  ;; jump unexpectedly.  vterm and eshell do not use cursor-intangible-mode either.
  (setq-local show-trailing-whitespace nil)
  ;; Disable undo in terminal buffers.  Every render cycle replaces line content
  ;; via delete-region + insert (up to N*2 operations/frame); without this, the
  ;; undo ring grows unboundedly and `undo-boundary' calls inside buffer operations
  ;; add measurable overhead to every redraw tick.
  (buffer-disable-undo)
  ;; Install terminal input keymap as parent so all key presses reach the PTY
  (set-keymap-parent kuro-mode-map kuro--keymap)
  ;; Focus event reporting (mode 1004): forward Emacs focus events to PTY.
  ;; Use after-focus-change-function (Emacs 27+) instead of the obsolete
  ;; focus-in-hook / focus-out-hook hooks.  after-focus-change-function
  ;; is a plain function (not a hook), so we wrap it to preserve any
  ;; existing handler.
  (when (boundp 'after-focus-change-function)
    (let ((prev after-focus-change-function))
      (setq-local after-focus-change-function
                  (lambda ()
                    (if (frame-focus-state)
                        (kuro--handle-focus-in)
                      (kuro--handle-focus-out))
                    (when (functionp prev) (funcall prev)))))
    ;; Remove the obsolete hooks so byte-compiler warnings don't appear.
    ;; This branch is taken on Emacs 27+.
    )
  ;; Resize the PTY whenever the Emacs window size changes.
  (add-hook 'window-size-change-functions #'kuro--window-size-change))

(provide 'kuro)

;;; kuro.el ends here
