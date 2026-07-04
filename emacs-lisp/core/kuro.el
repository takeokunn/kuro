;;; kuro.el --- Main entry point for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <takeokunn@users.noreply.github.com>
;; URL: https://github.com/takeokunn/kuro
;; Version: 1.0.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: terminals, tools

;;; Commentary:

;; Kuro is a modern terminal emulator for Emacs using a Rust core and
;; Emacs Lisp UI.  It implements the Remote Display Model where all
;; terminal state is managed in Rust and Emacs is purely a display layer.

;; Usage:
;; (require 'kuro)
;; (kuro-create "bash")

;;; Code:

;; Add subdirectories to load-path so that (require 'kuro-xxx) works
;; regardless of which subdirectory the file lives in.  This is only
;; needed in the source tree layout; installed packages place the .el
;; files flat into a single directory, in which case the subdirs do
;; not exist and the dolist body is skipped entirely.
(let ((base (file-name-directory
             (directory-file-name
              (file-name-directory (or load-file-name buffer-file-name
                                      (locate-library "kuro")))))))
  (dolist (subdir '("core" "rendering" "input" "ffi" "faces" "features"))
    (when (file-directory-p (expand-file-name subdir base))
      (add-to-list 'load-path (expand-file-name subdir base) t))))

(require 'kuro-module)
(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-faces)
(require 'kuro-keymap)
(require 'kuro-scrollback)
(require 'kuro-overlays)
(require 'kuro-navigation)
(require 'kuro-input)
;; kuro-input-mode is required AFTER kuro-mode-map is defined below, because
;; kuro-input-mode.el references kuro-mode-map and must not shadow its defvar.
(require 'kuro-stream)
(require 'kuro-render-buffer)
(require 'kuro-renderer)
(require 'kuro-lifecycle)

;; kuro-send-next-key is defined in kuro-input-encode.el (loaded via kuro-input).
(declare-function kuro-send-next-key    "kuro-input-encode" ())
(declare-function kuro--handle-focus-in  "kuro-navigation" ())
(declare-function kuro--handle-focus-out "kuro-navigation" ())

;; Input mode commands are in kuro-input-mode.el.
(declare-function kuro-cycle-input-mode  "kuro-input-mode" ())
(declare-function kuro--input-mode-lighter "kuro-input-mode" ())
(declare-function kuro--progress-mode-line "kuro-poll-modes" ())

;; EA-Ambiguous font assignment and glyph-metric refinement are in kuro-char-width.el.
(declare-function kuro--setup-char-width-table "kuro-char-width" ())
(declare-function kuro--assign-mono-fonts "kuro-char-width" ())
(declare-function kuro--refine-glyph-widths "kuro-char-width" ())
(declare-function kuro-char-width-setup "kuro-char-width" ())

;; Color palette table is rebuilt lazily on first kuro-mode entry; defined in kuro-colors.el.
(declare-function kuro--rebuild-named-colors "kuro-colors" ())

(defvar kuro-mode-map
  (kuro--define-keymap
    ("C-c C-c" . kuro-send-interrupt)
    ("C-c C-z" . kuro-send-sigstop)
    ("C-c C-\\" . kuro-send-sigquit)
    ("C-c C-p" . kuro-previous-prompt)
    ("C-c C-n" . kuro-next-prompt)
    ("C-c C-o" . kuro-copy-command-output)
    ("C-c C-M-n" . kuro-next-failed-command)
    ("C-c C-M-p" . kuro-previous-failed-command)
    ("C-c C-r" . kuro-command-history)
    ("C-c C-t" . kuro-copy-mode)
    ("C-c C-SPC" . kuro-copy-mode)
    ("C-c C-q" . kuro-send-next-key)
    ("C-c C-i" . kuro-cycle-input-mode)
    ("C-c C-s" . kuro-search-forward)
    ("C-c C-e" . kuro-edit-scrollback))
  "Keymap for Kuro major mode.")

;; Load kuro-input-mode here — AFTER kuro-mode-map is defined — so the
;; (defvar kuro-mode-map) forward declaration in kuro-input-mode.el does
;; not shadow the real initialization above.
(require 'kuro-input-mode)
(require 'kuro-copy)

(defun kuro--window-size-change (frame)
  "Handle window size change for kuro buffers in FRAME.
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

;;;###autoload
(define-derived-mode kuro-mode fundamental-mode "Kuro"
  "Major mode for Kuro terminal buffers."
  ;; Install global hooks/state lazily — keeps load-time side-effect-free
  ;; for users who require kuro from init.el but defer launching a
  ;; terminal until later.  Both helpers are idempotent.
  (kuro-char-width-setup)
  (kuro--rebuild-named-colors)
  ;; Show current input mode in the mode line: [C]=char [S]=semi-char [L]=line
  (setq-local mode-name
              '("Kuro" (:eval (kuro--input-mode-lighter))))
  ;; Surface the ConEmu OSC 9;4 progress indicator (e.g. " ⏳50% ") in the
  ;; mode-line process slot; nil when no foreground task reports progress.
  (setq-local mode-line-process '(:eval (kuro--progress-mode-line)))
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
