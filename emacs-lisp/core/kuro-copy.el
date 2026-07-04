;;; kuro-copy.el --- Copy mode for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Copy mode: suspend PTY input and enable standard Emacs navigation,
;; region selection, isearch, and rectangle operations in the terminal
;; scrollback buffer.  Extracted from kuro.el to keep kuro.el focused
;; on mode definition and lifecycle.

;;; Code:

(require 'cl-lib)
(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-copy-macros)

;; kuro-mode-map is defined in kuro.el (required before kuro-copy.el).
(defvar kuro-mode-map)

(declare-function rectangle-mark-mode "rect" (&optional arg))


;;;; Buffer-local state

(kuro--defvar-permanent-local kuro--copy-mode nil
  "Non-nil when Kuro copy mode is active.
In copy mode the PTY keymap parent is detached so standard Emacs
navigation and text-selection commands work in the terminal buffer.")

(kuro--defvar-permanent-local kuro--copy-mode-saved-window-start nil
  "Window start position at the time copy mode was entered.
Saved by `kuro--enter-copy-mode' for potential restoration.
Only set when the buffer is displayed in a live window.")

(kuro--defvar-permanent-local kuro--copy-linewise nil
  "Non-nil when copy-mode selection is line-wise (vim V).
When set, `kuro--copy-copy-region-and-exit' snaps the region to whole
lines — including trailing newlines — before copying.  Mutually exclusive
with `rectangle-mark-mode' (block selection); each selection command
clears the other.")


;;;; Customization

(defcustom kuro-copy-mode-auto-exit t
  "When non-nil, exit copy mode automatically after \\[kill-ring-save].
This streamlines the copy workflow: enter copy mode, select a region,
call `kill-ring-save' to copy and return to terminal mode."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-copy-mode-hl-line t
  "When non-nil, highlight the current line while copy mode is active.
Enables `hl-line-mode' on entry and disables it on exit so the pager
cursor position is always visually obvious during scrollback browsing."
  :type 'boolean
  :group 'kuro)


;;;; Selection helpers

(defun kuro--copy-clear-selection-state (&optional cancel-rect)
  "Clear copy selection state.
When CANCEL-RECT is non-nil, also cancel `rectangle-mark-mode'."
  (when cancel-rect
    (rectangle-mark-mode -1))
  (setq kuro--copy-linewise nil))

(defun kuro--copy-begin-selection (&optional linewise)
  "Start a fresh copy-mode selection.
When LINEWISE is non-nil, snap point to the beginning of the current
line and mark the selection as line-wise."
  (kuro--copy-clear-selection-state (bound-and-true-p rectangle-mark-mode))
  (when linewise
    (setq kuro--copy-linewise t)
    (beginning-of-line))
  (set-mark-command nil))

(defun kuro--copy-clear-selection-and-deactivate ()
  "Clear copy selection state and deactivate the active mark."
  (kuro--copy-clear-selection-state (bound-and-true-p rectangle-mark-mode))
  (deactivate-mark))

(defun kuro--copy-mode-save-and-exit ()
  "Copy the region with `kill-ring-save', optionally exiting copy mode.
When `kuro-copy-mode-auto-exit' is non-nil, also exits copy mode."
  (interactive)
  (call-interactively #'kill-ring-save)
  (when kuro-copy-mode-auto-exit
    (kuro--exit-copy-mode)))

(defun kuro--copy-finalize (&optional cancel-rect)
  "Clean up selection state and exit copy mode.
When CANCEL-RECT is non-nil, also cancel `rectangle-mark-mode'."
  (kuro--copy-clear-selection-state cancel-rect)
  (kuro-copy-mode))

(defun kuro--copy-copy-region-and-exit ()
  "Copy the active region to the kill ring and exit copy mode.
The selection mode determines what is grabbed:
  block (`rectangle-mark-mode') — the column block, rows joined by newlines;
  line-wise (`kuro--copy-linewise', vim V) — whole lines including their
    trailing newlines;
  char-wise (default) — the exact linear region.
In every mode the text lands on the normal kill ring, so it can be yanked
into the shell or any buffer.  Signals `user-error' when no region is
active."
  (interactive)
  (cond
   ((bound-and-true-p rectangle-mark-mode)
    ;; Non-nil third arg routes through `region-extract-function' for the block.
    (kill-ring-save (region-beginning) (region-end) t)
    (kuro--copy-finalize t)
    (message "Copied rectangle block"))
   ((and kuro--copy-linewise (use-region-p))
    (let ((beg (save-excursion (goto-char (region-beginning)) (line-beginning-position)))
          (end (save-excursion (goto-char (region-end))
                               (min (point-max) (1+ (line-end-position))))))
      (kill-ring-save beg end)
      (kuro--copy-finalize)
      (message "Copied %d line(s)" (count-lines beg end))))
   ((use-region-p)
    (let ((beg (region-beginning))
          (end (region-end)))
      (kill-ring-save beg end)
      (kuro--copy-finalize)
      (message "Copied %d characters" (- end beg))))
   (t
    (user-error "Kuro: no region selected — use C-SPC to set mark first"))))

(defun kuro--copy-set-mark ()
  "Set mark at point for char-wise region selection in copy mode (vim v).
Clears any line-wise or rectangle selection so the three modes stay
mutually exclusive."
  (interactive)
  (kuro--copy-begin-selection)
  (message "kuro: mark set — move cursor to select region, then M-w or y to copy"))

(defun kuro--copy-set-mark-line ()
  "Begin a line-wise (whole-line) selection in copy mode (vim: V).
Disables any rectangle selection, moves point to the beginning of the
current line, sets the mark there, and flags the selection line-wise so
\\[kuro--copy-copy-region-and-exit] grabs complete lines including their
trailing newlines."
  (interactive)
  (kuro--copy-begin-selection t)
  (message "kuro: line-wise selection — move by lines, then y/M-w copies whole lines"))

(defun kuro--copy-append-region ()
  "Append the active region to the most recent kill, staying in copy mode (A).
The first use with an empty kill ring copies the region normally; each
later use adds the selection — separated by a newline — to the same
`kill-ring' entry, so several scattered scrollback fragments can be gathered
into a single paste.  Unlike \\[kuro--copy-copy-region-and-exit], copy mode
stays active so you can keep collecting.  Signals `user-error' when no
region is active."
  (interactive)
  (unless (use-region-p)
    (user-error "Kuro: no region selected — use C-SPC or v to set mark first"))
  (let ((text (filter-buffer-substring (region-beginning) (region-end))))
    (if (null kill-ring)
        (kill-new text)
      (kill-append (concat "\n" text) nil))
    (kuro--copy-clear-selection-and-deactivate)
    (message "kuro: appended %d chars (kill now %d chars)"
             (length text) (length (current-kill 0)))))

(defun kuro--copy-rectangle-toggle ()
  "Toggle rectangle (block) selection in copy mode.
Sets the mark at point first when no region is active, so the block has an
anchor, and clears any line-wise selection so the modes stay mutually
exclusive.  With rectangle selection on, the region renders as a column
block and \\[kuro--copy-copy-region-and-exit] copies that block; toggle off
to return to linear selection."
  (interactive)
  (kuro--copy-clear-selection-state)
  (unless (region-active-p)
    (set-mark-command nil))
  (rectangle-mark-mode 'toggle)
  (message (if (bound-and-true-p rectangle-mark-mode)
               "kuro: rectangle (block) selection ON — move, then y/M-w copies the block"
             "kuro: rectangle selection OFF")))

(kuro--def-copy-window-move kuro--copy-move-to-top    0   "Move point to the first visible line in the window (H in vim).")
(kuro--def-copy-window-move kuro--copy-move-to-middle nil "Move point to the middle visible line in the window (M in vim).")
(kuro--def-copy-window-move kuro--copy-move-to-bottom -1  "Move point to the last visible line in the window (L in vim).")


(kuro--def-copy-search kuro--copy-search-next
  search-forward isearch-forward (point-min)
  "Jump to the next occurrence of the last isearch pattern (vim: n).")

(kuro--def-copy-search kuro--copy-search-prev
  search-backward isearch-backward (point-max)
  "Jump to the previous occurrence of the last isearch pattern (vim: N).")

(defun kuro--copy-search-word-forward ()
  "Search forward for the word at point in copy-mode (vim: *).
Sets `isearch-string' to the word token so `n'/`N' can repeat it."
  (interactive)
  (let ((word (thing-at-point 'word t)))
    (if (null word)
        (message "No word at point")
      (setq isearch-string word
            isearch-regexp nil)
      (forward-word 1)
      (kuro--copy-search-next))))

(defun kuro--prompt-overlay-positions ()
  "Return sorted buffer positions carrying a `kuro-prompt-status' overlay.
Used by copy-mode prompt navigation to enumerate shell-prompt marks set
by the OSC 133 annotation system."
  (let (positions)
    (dolist (ov (overlays-in (point-min) (point-max)))
      (when (overlay-get ov 'kuro-prompt-status)
        (push (overlay-start ov) positions)))
    (sort (delete-dups positions) #'<)))

(defun kuro--copy-find-prompt (direction)
  "Return the next prompt position in DIRECTION (:fwd or :bwd) from point, or nil."
  (let ((pos   (point))
        (marks (kuro--prompt-overlay-positions)))
    (if (eq direction :fwd)
        (cl-find-if (lambda (p) (> p pos)) marks)
      (cl-find-if (lambda (p) (< p pos)) (reverse marks)))))

(kuro--def-copy-goto-prompt kuro--copy-goto-next-prompt :fwd forward-paragraph
  "Jump to the next shell-prompt overlay in copy mode (vim: }).
Falls back to `forward-paragraph' when no prompt overlays exist.")

(kuro--def-copy-goto-prompt kuro--copy-goto-prev-prompt :bwd backward-paragraph
  "Jump to the previous shell-prompt overlay in copy mode (vim: {).
Falls back to `backward-paragraph' when no prompt overlays exist.")

(defconst kuro--copy-mode-bindings
  '(([?\C-c ?\C-t] . kuro-copy-mode)
    ("C-c C-SPC" . kuro-copy-mode)
    ("M-w" . kuro--copy-copy-region-and-exit)
    ("y" . kuro--copy-copy-region-and-exit)
    ("v" . kuro--copy-set-mark)
    ("V" . kuro--copy-set-mark-line)
    ("A" . kuro--copy-append-region)
    ("C-v" . kuro--copy-rectangle-toggle)
    ("R" . kuro--copy-rectangle-toggle)
    ("C-s" . isearch-forward)
    ("C-r" . isearch-backward)
    ("M-s o" . occur)
    ("j" . scroll-up-line)
    ("k" . scroll-down-line)
    ("g" . beginning-of-buffer)
    ("G" . end-of-buffer)
    ("b" . scroll-down-command)
    ("f" . scroll-up-command)
    ("SPC" . scroll-up-command)
    ("q" . kuro-copy-mode)
    ("h" . backward-char)
    ("l" . forward-char)
    ("w" . forward-word)
    ("e" . forward-word)
    ("B" . backward-word)
    ("0" . beginning-of-line)
    ("$" . end-of-line)
    ("H" . kuro--copy-move-to-top)
    ("M" . kuro--copy-move-to-middle)
    ("L" . kuro--copy-move-to-bottom)
    ("n" . kuro--copy-search-next)
    ("N" . kuro--copy-search-prev)
    ("*" . kuro--copy-search-word-forward)
    ("{" . kuro--copy-goto-prev-prompt)
    ("}" . kuro--copy-goto-next-prompt))
  "Key bindings installed in `kuro--copy-mode-map'.")

(defvar kuro--copy-mode-map
  (let ((map (make-sparse-keymap)))
    (kuro--define-copy-mode-bindings map kuro--copy-mode-bindings)
    map)
  "Sparse keymap active during Kuro copy mode.
Built once at load time; installed per-buffer by `kuro--enter-copy-mode'.")


;;;; Mode entry / exit (CPS: every path ends with mode-line refresh)

(defun kuro--enter-copy-mode ()
  "Enter Kuro copy mode: suspend PTY input and enable Emacs navigation.
Uses `use-local-map' so only the current buffer is affected; other Kuro
buffers keep their normal terminal keymaps.
Saves the current window start in `kuro--copy-mode-saved-window-start'."
  (setq-local kuro--copy-mode t)
  ;; Save the window start so callers can interrogate the entry position.
  (setq kuro--copy-mode-saved-window-start
        (when-let* ((win (get-buffer-window (current-buffer))))
          (window-start win)))
  (use-local-map kuro--copy-mode-map)
  (unless transient-mark-mode
    (setq-local transient-mark-mode t))
  (when kuro-copy-mode-hl-line
    (hl-line-mode 1))
  (setq mode-name (propertize "Kuro[Copy]" 'face 'font-lock-warning-face))
  (force-mode-line-update)
  (message "Kuro copy mode on — j/k:scroll  h/l/w/e:move  g/G:top/btm  {/}:prompts  C-s/C-r:search  n/N/*:repeat  v:mark  V:line  C-v:rect  A:append  M-w:copy  q:exit"))

(defun kuro--exit-copy-mode ()
  "Exit Kuro copy mode: restore PTY input keymap."
  (setq-local kuro--copy-mode nil)
  ;; Restore the standard kuro-mode-map (includes kuro--keymap as parent).
  (use-local-map kuro-mode-map)
  ;; Clear any lingering rectangle / line-wise selection so it cannot leak
  ;; into terminal mode.
  (kuro--copy-clear-selection-state (bound-and-true-p rectangle-mark-mode))
  (hl-line-mode -1)
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
movement, region selection, and copy commands (\\[kill-ring-save],
\\[kill-region], \\[isearch-forward]…) become available.
The buffer remains read-only; only navigation and selection
are enabled.  Call \\[kuro-copy-mode] again to return to terminal mode."
  (interactive)
  (kuro--with-kuro-mode
   (if kuro--copy-mode
       (kuro--exit-copy-mode)
     (kuro--enter-copy-mode))))

;;;###autoload
(kuro--def-copy-search-enter kuro-search-forward isearch-forward
  "Enter copy mode and search forward through terminal output.
If not already in copy mode, enters it automatically so the PTY keymap
is suspended and Emacs isearch bindings apply to the scrollback buffer.
Bound to \\[kuro-search-forward] to avoid stealing raw C-s (XOFF) from
the PTY.  Use `kuro-copy-mode' first if you prefer a manual workflow.")

;;;###autoload
(kuro--def-copy-search-enter kuro-search-backward isearch-backward
  "Enter copy mode and search backward through terminal output.
If not already in copy mode, enters it automatically.  Searches from
point toward the beginning of the buffer (oldest scrollback).")

;;;###autoload
(defun kuro-occur (regexp)
  "Show all lines in terminal output matching REGEXP in an *Occur* buffer.
Enters copy mode automatically if needed.  Results appear in a separate
*Occur* buffer with clickable links back to the matched lines; the
terminal buffer itself is never modified (it remains read-only)."
  (interactive "sSearch terminal output (regexp): ")
  (kuro--with-kuro-mode
   (unless kuro--copy-mode
     (kuro--enter-copy-mode))
   (occur regexp)))

(provide 'kuro-copy)

;;; kuro-copy.el ends here
