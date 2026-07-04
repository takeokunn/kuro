;;; kuro-mux-layout.el --- Preset window-layout engine for kuro-mux  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Preset tmux-style layout arrangements for kuro-mux sessions.
;; Loaded automatically by kuro-mux.el.  Provides `kuro-mux-select-layout',
;; `kuro-mux-next-layout', and `kuro-mux-previous-layout'.

;;; Code:

(declare-function derived-mode-p "subr" (&rest modes))

(require 'kuro-mux-layout-macros)

(defconst kuro-mux--layout-handlers
  (list
   (cons "even-horizontal"
         (lambda (win bufs) (kuro-mux--layout-chain win (cdr bufs) 'right)))
   (cons "even-vertical"
         (lambda (win bufs) (kuro-mux--layout-chain win (cdr bufs) 'below)))
   (cons "main-vertical"
         (lambda (win bufs) (kuro-mux--layout-main  win (cdr bufs) 'right 'below)))
   (cons "main-horizontal"
         (lambda (win bufs) (kuro-mux--layout-main  win (cdr bufs) 'below 'right)))
   (cons "tiled"
         (lambda (_win bufs) (kuro-mux--layout-tiled bufs))))
  "Alist mapping layout name string to handler function (WIN BUFS).")

(defconst kuro-mux-layouts
  (mapcar #'car kuro-mux--layout-handlers)
  "Preset layout names recognized by `kuro-mux-select-layout'.
Derived from `kuro-mux--layout-handlers'; adding a layout there automatically
extends this list.  Modeled on tmux's five built-in layouts.")


;;;; Internal helpers

(defun kuro-mux--visible-session-buffers ()
  "Return distinct kuro buffers shown in the selected frame, top-left first.
A buffer displayed in multiple windows appears only once.  Window order
follows `window-list', which is top-to-bottom then left-to-right."
  (let ((seen nil))
    (dolist (w (window-list nil 'no-minibuf))
      (let ((buf (window-buffer w)))
        (when (and (buffer-live-p buf)
                   (with-current-buffer buf (derived-mode-p 'kuro-mode))
                   (not (memq buf seen)))
          (push buf seen))))
    (nreverse seen)))

(defun kuro-mux--layout-chain (window buffers side)
  "Show each buffer in BUFFERS in a new window split from WINDOW toward SIDE.
WINDOW already shows the preceding buffer.  Each split is threaded from the
newly created window so panes appear in BUFFERS order along SIDE
\(`right' for horizontal rows, `below' for vertical stacks)."
  (let ((cur window))
    (dolist (buf buffers)
      (setq cur (split-window cur nil side))
      (set-window-buffer cur buf))))

(defun kuro-mux--layout-main (main-win buffers main-side sub-side)
  "Build a main pane plus a stack of the remaining BUFFERS.
MAIN-WIN shows the main buffer.  MAIN-SIDE splits off the secondary area
\(`right' for main-vertical, `below' for main-horizontal); SUB-SIDE divides
that area among BUFFERS."
  (when buffers
    (let ((area (split-window main-win nil main-side)))
      (set-window-buffer area (car buffers))
      (kuro-mux--layout-chain area (cdr buffers) sub-side))))

(defun kuro-mux--fill-band (band buffers start cols)
  "Fill BAND window with up to COLS buffers from BUFFERS starting at index START.
Returns the index after the last buffer placed."
  (let ((col    band)
        (in-row (min cols (- (length buffers) start)))
        (idx    start))
    (set-window-buffer col (nth idx buffers))
    (setq idx (1+ idx))
    (dotimes (_ (1- in-row))
      (setq col (split-window col nil 'right))
      (set-window-buffer col (nth idx buffers))
      (setq idx (1+ idx)))
    idx))

(defun kuro-mux--layout-tiled (buffers)
  "Arrange all BUFFERS in an approximately square grid, row-major.
The selected frame must already be a single window.  Rows = ceil(sqrt N);
columns are filled left-to-right within each row."
  (let* ((n     (length buffers))
         (rows  (ceiling (sqrt n)))
         (cols  (ceiling (/ (float n) rows)))
         (cur   (selected-window))
         (bands (list cur)))
    (dotimes (_ (1- rows))
      (setq cur (split-window cur nil 'below))
      (push cur bands))
    (let ((idx 0))
      (dolist (band (nreverse bands))
        (when (< idx n)
          (setq idx (kuro-mux--fill-band band buffers idx cols)))))))


;;;; Public commands

;;;###autoload
(defun kuro-mux-select-layout (layout)
  "Rearrange visible kuro panes in the selected frame per LAYOUT.
LAYOUT is one of the strings in `kuro-mux-layouts':
  even-horizontal  panes side by side, equal width
  even-vertical    panes stacked, equal height
  main-vertical    one large pane on the left, the rest stacked on the right
  main-horizontal  one large pane on top, the rest in a row below
  tiled            panes in an approximately square grid
The first visible kuro buffer becomes the main pane for the main-*
layouts.  All visible kuro buffers are gathered first, the frame is
collapsed to one window, then re-split.  Analogous to tmux select-layout."
  (interactive (list (completing-read "Layout: " kuro-mux-layouts nil t)))
  (unless (member layout kuro-mux-layouts)
    (user-error "Kuro-mux: unknown layout: %s" layout))
  (let ((buffers (kuro-mux--visible-session-buffers)))
    (when (length< buffers 1)
      (user-error "Kuro-mux: no visible kuro panes to lay out"))
    (delete-other-windows)
    (let ((win (selected-window)))
      (set-window-buffer win (car buffers))
      (kuro--dispatch-layout layout win buffers))
    (balance-windows)
    ;; Record the applied layout on the frame so `kuro-mux-next-layout' /
    ;; `kuro-mux-previous-layout' can cycle relative to it.
    (set-frame-parameter nil 'kuro-mux-current-layout layout)
    (message "kuro-mux: layout %s (%d pane%s)"
             layout (length buffers) (if (= (length buffers) 1) "" "s"))))

(defun kuro-mux--cycle-layout (step)
  "Apply the layout STEP positions from the frame's current one.
STEP is +1 (next) or -1 (previous); the index wraps modulo the list length.
When no layout has been applied yet, +1 selects the first layout and -1
the last.  Delegates to `kuro-mux-select-layout' which re-splits and
records the new current layout."
  (let* ((cur  (frame-parameter nil 'kuro-mux-current-layout))
         (idx  (and cur (seq-position kuro-mux-layouts cur)))
         (n    (length kuro-mux-layouts))
         (next (if idx
                   (mod (+ idx step) n)
                 (if (> step 0) 0 (1- n)))))
    (kuro-mux-select-layout (nth next kuro-mux-layouts))))

;;;###autoload
(defun kuro-mux-next-layout ()
  "Switch to the next preset layout in `kuro-mux-layouts' (tmux: prefix Space).
Cycles forward through the five presets, wrapping around.  The first
invocation on a fresh frame applies the first layout."
  (interactive)
  (kuro-mux--cycle-layout 1))

;;;###autoload
(defun kuro-mux-previous-layout ()
  "Switch to the previous preset layout in `kuro-mux-layouts'.
Cycles backward through the five presets, wrapping around.  The first
invocation on a fresh frame applies the last layout."
  (interactive)
  (kuro-mux--cycle-layout -1))

(provide 'kuro-mux-layout)

;;; kuro-mux-layout.el ends here
