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

;; EA-Ambiguous font assignment and glyph-metric refinement are in kuro-char-width.el.
(declare-function kuro--setup-char-width-table "kuro-char-width" ())
(declare-function kuro--assign-mono-fonts "kuro-char-width" ())
(declare-function kuro--refine-glyph-widths "kuro-char-width" ())

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
    (define-key map (kbd "C-c C-SPC") #'kuro-copy-mode)
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

(kuro--defvar-permanent-local kuro--copy-mode nil
  "Non-nil when Kuro copy mode is active.
In copy mode the PTY keymap parent is detached so standard Emacs
navigation and text-selection commands work in the terminal buffer.")

(defcustom kuro-copy-mode-auto-exit t
  "When non-nil, exit copy mode automatically after M-w (`kill-ring-save').
This streamlines the copy workflow: enter copy mode with C-c C-t,
select a region, press M-w to copy and return to terminal mode."
  :type 'boolean
  :group 'kuro)

(defun kuro--copy-mode-save-and-exit ()
  "Copy the region with `kill-ring-save', optionally exiting copy mode.
When `kuro-copy-mode-auto-exit' is non-nil, also exits copy mode."
  (interactive)
  (call-interactively #'kill-ring-save)
  (when kuro-copy-mode-auto-exit
    (kuro--exit-copy-mode)))

(defun kuro--enter-copy-mode ()
  "Enter Kuro copy mode: suspend PTY input and enable Emacs navigation.
Uses `use-local-map' so only the current buffer is affected; other Kuro
buffers keep their normal terminal keymaps."
  (setq-local kuro--copy-mode t)
  ;; Install a minimal buffer-local keymap: C-c C-t to exit, M-w to
  ;; copy-and-optionally-exit.  No parent → the global keymap applies,
  ;; giving full Emacs navigation.
  (let ((copy-map (make-sparse-keymap)))
    (define-key copy-map [?\C-c ?\C-t] #'kuro-copy-mode)
    (define-key copy-map (kbd "C-c C-SPC") #'kuro-copy-mode)
    (define-key copy-map (kbd "M-w") #'kuro--copy-mode-save-and-exit)
    (use-local-map copy-map))
  (setq mode-name (propertize "Kuro[Copy]" 'face 'font-lock-warning-face))
  (force-mode-line-update)
  (message "Kuro copy mode on (C-c C-t or C-c C-SPC to exit)"))

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
are enabled.  Press C-c C-t or C-c C-SPC again to return to terminal mode."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "kuro-copy-mode: not in a Kuro terminal buffer"))
  (if kuro--copy-mode
      (kuro--exit-copy-mode)
    (kuro--enter-copy-mode)))

(kuro--defvar-permanent-local kuro--last-rows 0
  "Last known terminal row count; used to detect window size changes.")

(kuro--defvar-permanent-local kuro--last-cols 0
  "Last known terminal column count; used to detect window size changes.")


(defun kuro--make-focus-change-fn (prev)
  "Build an `after-focus-change-function' that dispatches kuro focus events.
PREV is the previous handler to chain after kuro's handling.
When PREV is a function it is called at the end; nil is ignored."
  (lambda ()
    (if (frame-focus-state)
        (kuro--handle-focus-in)
      (kuro--handle-focus-out))
    (when (functionp prev) (funcall prev))))

(define-derived-mode kuro-mode fundamental-mode "Kuro"
  "Major mode for Kuro terminal buffers."
  (setq buffer-read-only t)
  (setq-local bidi-display-reordering nil)
  (setq-local bidi-paragraph-direction 'left-to-right)
  (setq-local truncate-lines t)
  (setq-local auto-hscroll-mode nil)
  ;; No header-line by default; kuro--update-scroll-indicator sets it when scrolling.
  (setq-local header-line-format nil)
  ;; Disable syntax highlighting: terminal content is colored via text properties
  ;; from the Rust FFI layer; font-lock and jit-lock add overhead with no benefit.
  (font-lock-mode -1)
  (when (fboundp 'jit-lock-mode)
    (jit-lock-mode -1))
  ;; `font-lock-mode -1' and `jit-lock-mode -1' do not always remove
  ;; `jit-lock-function' from `fontification-functions'.  The stale entry
  ;; causes every redisplay to signal (wrong-type-argument number-or-marker-p nil)
  ;; because `jit-lock-context-unfontify-pos' is nil after partial teardown.
  ;; Nuke the hook entirely — terminal buffers never need fontification.
  (setq-local fontification-functions nil)
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
  ;; Prevent Emacs' native redisplay from scrolling the terminal buffer.
  ;; scroll-margin=0 stops auto-scroll when cursor is near window edges;
  ;; scroll-conservatively=101 (any value >100) prevents recentering on any
  ;; cursor movement; auto-window-vscroll=nil prevents vscroll drift from tall
  ;; image overlays (Sixel/Kitty).  Without these, TUI apps (btop, bottom,
  ;; gping) that place the cursor on the last row trigger Emacs scroll
  ;; heuristics between render cycles, causing visible distortion.
  (setq-local scroll-margin 0)
  (setq-local scroll-conservatively 101)
  (setq-local auto-window-vscroll nil)
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
    (setq-local after-focus-change-function
                (kuro--make-focus-change-fn after-focus-change-function)))
  ;; Resize the PTY whenever the Emacs window size changes.
  (add-hook 'window-size-change-functions #'kuro--window-size-change))

(provide 'kuro)

;;; kuro.el ends here
