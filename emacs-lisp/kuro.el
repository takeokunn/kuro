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

(defconst kuro--char-width-overrides
  '((#x2190 . #x21FF)    ; Arrows — EA Width A (↑↓←→ sort/nav indicators)
    (#x2200 . #x22FF)    ; Mathematical Operators — EA Width A (×÷∞√)
    (#x2300 . #x23FF)    ; Miscellaneous Technical — EA Width A
    (#x2500 . #x257F)    ; Box Drawing — used by ncurses borders
    (#x2580 . #x259F)    ; Block Elements — EA Width A (btop/htop bars)
    (#x25A0 . #x25FF)    ; Geometric Shapes — EA Width A (■● TUI indicators)
    (#x2600 . #x26FF)    ; Miscellaneous Symbols — EA Width A
    (#x2700 . #x27BF)    ; Dingbats — EA Width A
    (#x2800 . #x28FF))   ; Braille Patterns — pin to 1 for safety
  "Unicode ranges forced to display-width 1 in kuro terminal buffers.
These ranges are East-Asian-Ambiguous (or pinned for safety).  CJK language
environments set them to width 2, but terminal applications and the Rust
unicode-width crate treat them as width 1.")

(defun kuro--apply-char-width-overrides ()
  "Force all `kuro--char-width-overrides' ranges to width 1 in the current buffer.
Must be called after `char-width-table' is buffer-local."
  (dolist (range kuro--char-width-overrides)
    (set-char-table-range char-width-table range 1)))

(defun kuro--setup-char-width-table ()
  "Override `char-width-table' to match unicode-width 0.2 / xterm behavior.
In CJK language environments Emacs sets East-Asian-Ambiguous characters
\(block elements, geometric shapes, misc symbols, etc.) to display width 2.
However the Rust unicode-width 0.2 crate — and every standard xterm-256color
terminal — treats those same codepoints as width 1.  Terminal applications
such as btop lay out their UI assuming width 1, so a discrepancy causes
visual corruption \(characters shifted right after each ambiguous glyph).

IMPORTANT: `set-language-environment' replaces the buffer-local
`char-width-table' with a fresh copy even if the variable was already
buffer-local.  We therefore also install a hook on
`set-language-environment-hook' that re-applies the overrides in all
live kuro buffers."
  (make-local-variable 'char-width-table)
  (setq char-width-table (copy-sequence char-width-table))
  (kuro--apply-char-width-overrides))

(defun kuro--reapply-char-width-in-all-buffers ()
  "Re-apply char-width overrides in all kuro-mode buffers.
Called from `set-language-environment-hook' because
`set-language-environment' replaces buffer-local `char-width-table'."
  (dolist (buf (buffer-list))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (eq major-mode 'kuro-mode)
          ;; set-language-environment replaced our table — make a fresh copy
          ;; of the (new) global table and re-apply overrides.
          (setq char-width-table (copy-sequence char-width-table))
          (kuro--apply-char-width-overrides))))))

(add-hook 'set-language-environment-hook #'kuro--reapply-char-width-in-all-buffers)

(defun kuro--assign-mono-fonts ()
  "Assign the frame's ASCII (monospace) font to EA-Ambiguous Unicode ranges.
This MUST run synchronously during `kuro-mode' init — before the first
render — so that btop/htop output is already rendered with correct glyph
widths from the very first frame.  If deferred to an idle timer, the timer
may never fire while btop floods the PTY with output.

Modifies BOTH the selected frame's fontset (nil) and the default fontset (t).
Using only `t' was the original bug: `t' modifies the template for future
frames, but existing frames already have their own fontset copy made at
frame creation time.

Uses `prepend' rather than replacing the font list, so if the ASCII font
lacks a glyph for a given codepoint Emacs falls back to the original
\(possibly CJK) font rather than showing a missing-glyph box."
  (when (display-graphic-p)
    (let* ((ascii-font (face-attribute 'default :font nil t))
           (ascii-family (and ascii-font (font-get ascii-font :family))))
      (when ascii-family
        (let ((family-name (if (symbolp ascii-family)
                               (symbol-name ascii-family)
                             ascii-family)))
          (dolist (range kuro--char-width-overrides)
            (condition-case nil
                (let ((spec (font-spec :family family-name)))
                  (set-fontset-font nil range spec nil 'prepend)
                  (set-fontset-font t   range spec nil 'prepend))
              (error nil))))))))

(defconst kuro--glyph-probe-chars
  '((#x2190 . #x2192)    ; Arrows: →
    (#x2200 . #x2200)    ; Math Operators: ∀
    (#x2300 . #x2302)    ; Misc Technical: ⌂
    (#x2500 . #x2502)    ; Box Drawing: │
    (#x2580 . #x2588)    ; Block Elements: █
    (#x25A0 . #x25A0)    ; Geometric Shapes: ■
    (#x2600 . #x2605)    ; Misc Symbols: ★
    (#x2700 . #x2714)    ; Dingbats: ✔
    (#x2800 . #x28C0))   ; Braille Patterns: ⣀
  "Alist mapping range-start to a probe character for glyph width detection.
Each probe character is a representative glyph from the corresponding
`kuro--char-width-overrides' range.")

(defun kuro--refine-glyph-widths ()
  "Probe actual rendered glyph widths and rescale fonts that are too wide.
Called from a short timer after the kuro buffer is displayed in a window,
so `font-at' can determine which font Emacs actually chose for each range.

If `kuro--assign-mono-fonts' already assigned a font that renders at the
correct cell width, this function is a no-op for that range.  Otherwise it
rescales the active font so each glyph is exactly `frame-char-width' pixels."
  (when (display-graphic-p)
    (let* ((cell-width (frame-char-width))
           (did-change nil))
      (when (and cell-width (> cell-width 0))
        (dolist (entry kuro--char-width-overrides)
          (let* ((range-start (car entry))
                 (probe-assoc (assq range-start kuro--glyph-probe-chars))
                 (probe-char (and probe-assoc (cdr probe-assoc))))
            (when probe-char
              (condition-case nil
                  (let* ((probe-str (string probe-char))
                         (font-obj (with-temp-buffer
                                     (insert probe-str)
                                     (font-at 0)))
                         (glyphs (and font-obj
                                      (font-get-glyphs font-obj 0 1 probe-str)))
                         (glyph-width (and glyphs (> (length glyphs) 0)
                                           (aref (aref glyphs 0) 4))))
                    (when (and glyph-width (> glyph-width 0)
                               (/= glyph-width cell-width))
                      (let* ((fname (font-get font-obj :family))
                             (fsize (font-get font-obj :size))
                             (new-size (* fsize (/ (float cell-width) glyph-width)))
                             (rescaled (font-spec
                                        :family (if (symbolp fname)
                                                    (symbol-name fname)
                                                  fname)
                                        :size new-size)))
                        (set-fontset-font nil entry rescaled)
                        (set-fontset-font t   entry rescaled)
                        (setq did-change t))))
                (error nil)))))
        (when did-change
          (redraw-display))))))


(define-derived-mode kuro-mode fundamental-mode "Kuro"
  "Major mode for Kuro terminal buffers."
  (setq buffer-read-only t)
  (setq-local bidi-display-reordering nil)
  (setq-local truncate-lines t)
  (setq-local auto-hscroll-mode nil)
  ;; Normalise character display widths to match the Rust unicode-width 0.2 crate.
  ;; Must run before the first render so col_to_buf mappings stay consistent.
  (kuro--setup-char-width-table)
  ;; Assign the ASCII monospace font to EA-Ambiguous Unicode ranges.  Runs
  ;; synchronously so the first render already uses correct glyph widths.
  ;; `set-fontset-font' does not require the buffer to be displayed.
  (kuro--assign-mono-fonts)
  ;; Deferred refinement: probe actual glyph pixel widths and rescale any
  ;; font that still renders wider than one cell.  Uses a regular timer
  ;; (not idle timer) so it fires even when btop floods the PTY.
  (run-with-timer 0.1 nil #'kuro--refine-glyph-widths)
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
