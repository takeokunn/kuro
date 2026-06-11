;;; kuro-copy.el --- Copy mode for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <takeokunn@users.noreply.github.com>

;;; Commentary:

;; Copy mode: suspend PTY input and enable standard Emacs navigation,
;; region selection, isearch, and rectangle operations in the terminal
;; scrollback buffer.  Extracted from kuro.el to keep kuro.el focused
;; on mode definition and lifecycle.

;;; Code:

(require 'cl-lib)
(require 'kuro-config)

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
  (when cancel-rect (rectangle-mark-mode -1))
  (setq kuro--copy-linewise nil)
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
    (user-error "kuro: no region selected — use C-SPC to set mark first"))))

(defun kuro--copy-set-mark ()
  "Set mark at point for char-wise region selection in copy mode (vim v).
Clears any line-wise or rectangle selection so the three modes stay
mutually exclusive."
  (interactive)
  (setq kuro--copy-linewise nil)
  (when (bound-and-true-p rectangle-mark-mode)
    (rectangle-mark-mode -1))
  (set-mark-command nil)
  (message "kuro: mark set — move cursor to select region, then M-w or y to copy"))

(defun kuro--copy-set-mark-line ()
  "Begin a line-wise (whole-line) selection in copy mode (vim: V).
Disables any rectangle selection, moves point to the beginning of the
current line, sets the mark there, and flags the selection line-wise so
\\[kuro--copy-copy-region-and-exit] grabs complete lines including their
trailing newlines."
  (interactive)
  (when (bound-and-true-p rectangle-mark-mode)
    (rectangle-mark-mode -1))
  (setq kuro--copy-linewise t)
  (beginning-of-line)
  (set-mark-command nil)
  (message "kuro: line-wise selection — move by lines, then y/M-w copies whole lines"))

(defun kuro--copy-append-region ()
  "Append the active region to the most recent kill, staying in copy mode (A).
The first use with an empty kill ring copies the region normally; each
later use adds the selection — separated by a newline — to the same
kill-ring entry, so several scattered scrollback fragments can be gathered
into a single paste.  Unlike \\[kuro--copy-copy-region-and-exit], copy mode
stays active so you can keep collecting.  Signals `user-error' when no
region is active."
  (interactive)
  (unless (use-region-p)
    (user-error "kuro: no region selected — use C-SPC or v to set mark first"))
  (let ((text (filter-buffer-substring (region-beginning) (region-end))))
    (if (null kill-ring)
        (kill-new text)
      (kill-append (concat "\n" text) nil))
    (setq kuro--copy-linewise nil)
    (when (bound-and-true-p rectangle-mark-mode)
      (rectangle-mark-mode -1))
    (deactivate-mark)
    (message "kuro: appended %d chars (kill now %d chars)"
             (length text) (length (current-kill 0)))))

(defun kuro--copy-rectangle-toggle ()
  "Toggle rectangle (block) selection in copy mode (tmux: C-v, also R).
Sets the mark at point first when no region is active, so the block has an
anchor, and clears any line-wise selection so the modes stay mutually
exclusive.  With rectangle selection on, the region renders as a column
block and \\[kuro--copy-copy-region-and-exit] copies that block; toggle off
to return to linear selection."
  (interactive)
  (setq kuro--copy-linewise nil)
  (unless (region-active-p)
    (set-mark-command nil))
  (rectangle-mark-mode 'toggle)
  (message (if (bound-and-true-p rectangle-mark-mode)
               "kuro: rectangle (block) selection ON — move, then y/M-w copies the block"
             "kuro: rectangle selection OFF")))


;;;; Window-move commands (data-driven via defmacro)

(defmacro kuro--def-copy-window-move (name arg docstring)
  "Define a copy-mode command that moves point to a window-relative line.
ARG is passed directly to `move-to-window-line'."
  `(defun ,name () ,docstring (interactive) (move-to-window-line ,arg)))

(kuro--def-copy-window-move kuro--copy-move-to-top    0   "Move point to the first visible line in the window (H in vim).")
(kuro--def-copy-window-move kuro--copy-move-to-middle nil "Move point to the middle visible line in the window (M in vim).")
(kuro--def-copy-window-move kuro--copy-move-to-bottom -1  "Move point to the last visible line in the window (L in vim).")


;;;; Search commands (data-driven via defmacro)

(defmacro kuro--def-copy-search (name search-fn fallback-fn wrap-pos docstring)
  "Define a copy-mode search command that repeats the last isearch pattern.
SEARCH-FN is `search-forward' or `search-backward'.
FALLBACK-FN is called interactively when no prior pattern exists.
WRAP-POS is `(point-min)' or `(point-max)' for wrap-around."
  `(defun ,name ()
     ,docstring
     (interactive)
     (let ((s (and (boundp 'isearch-string)
                   (not (string-empty-p isearch-string))
                   isearch-string)))
       (if (not s)
           (call-interactively #',fallback-fn)
         (unless (,search-fn s nil t)
           (goto-char ,wrap-pos)
           (unless (,search-fn s nil t)
             (message "Search failed: %s" s)))))))

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


;;;; Prompt navigation

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

(defun kuro--copy-goto-next-prompt ()
  "Jump to the next shell-prompt overlay in copy mode (vim: }).
Falls back to `forward-paragraph' when no prompt overlays exist."
  (interactive)
  (if-let ((target (kuro--copy-find-prompt :fwd)))
      (goto-char target)
    (forward-paragraph)))

(defun kuro--copy-goto-prev-prompt ()
  "Jump to the previous shell-prompt overlay in copy mode (vim: {).
Falls back to `backward-paragraph' when no prompt overlays exist."
  (interactive)
  (if-let ((target (kuro--copy-find-prompt :bwd)))
      (goto-char target)
    (backward-paragraph)))


;;;; Keymap

(defvar kuro--copy-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Exit / toggle
    (define-key map [?\C-c ?\C-t]     #'kuro-copy-mode)
    (define-key map (kbd "C-c C-SPC") #'kuro-copy-mode)
    ;; Copy and exit
    (define-key map (kbd "M-w") #'kuro--copy-copy-region-and-exit)
    (define-key map (kbd "y")   #'kuro--copy-copy-region-and-exit)
    ;; Selection modes
    (define-key map (kbd "v")   #'kuro--copy-set-mark)
    (define-key map (kbd "V")   #'kuro--copy-set-mark-line)
    (define-key map (kbd "A")   #'kuro--copy-append-region)
    (define-key map (kbd "C-v") #'kuro--copy-rectangle-toggle)
    (define-key map (kbd "R")   #'kuro--copy-rectangle-toggle)
    ;; Search
    (define-key map (kbd "C-s") #'isearch-forward)
    (define-key map (kbd "C-r") #'isearch-backward)
    (define-key map (kbd "M-s o") #'occur)
    ;; Pager navigation
    (define-key map (kbd "j")   #'scroll-up-line)
    (define-key map (kbd "k")   #'scroll-down-line)
    (define-key map (kbd "g")   #'beginning-of-buffer)
    (define-key map (kbd "G")   #'end-of-buffer)
    (define-key map (kbd "b")   #'scroll-down-command)
    (define-key map (kbd "f")   #'scroll-up-command)
    (define-key map (kbd "SPC") #'scroll-up-command)
    (define-key map (kbd "q")   #'kuro-copy-mode)
    ;; Vim character motions
    (define-key map (kbd "h")   #'backward-char)
    (define-key map (kbd "l")   #'forward-char)
    (define-key map (kbd "w")   #'forward-word)
    (define-key map (kbd "e")   #'forward-word)
    (define-key map (kbd "B")   #'backward-word)
    ;; Absolute line position
    (define-key map (kbd "0")   #'beginning-of-line)
    (define-key map (kbd "$")   #'end-of-line)
    ;; Window position
    (define-key map (kbd "H")   #'kuro--copy-move-to-top)
    (define-key map (kbd "M")   #'kuro--copy-move-to-middle)
    (define-key map (kbd "L")   #'kuro--copy-move-to-bottom)
    ;; Search repeat
    (define-key map (kbd "n")   #'kuro--copy-search-next)
    (define-key map (kbd "N")   #'kuro--copy-search-prev)
    (define-key map (kbd "*")   #'kuro--copy-search-word-forward)
    ;; Prompt navigation
    (define-key map (kbd "{")   #'kuro--copy-goto-prev-prompt)
    (define-key map (kbd "}")   #'kuro--copy-goto-next-prompt)
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
        (when-let ((win (get-buffer-window (current-buffer))))
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
  (when (bound-and-true-p rectangle-mark-mode)
    (rectangle-mark-mode -1))
  (setq-local kuro--copy-linewise nil)
  (hl-line-mode -1)
  (setq mode-name "Kuro")
  (force-mode-line-update)
  ;; Re-render so the terminal cursor is restored to its correct position.
  (when (fboundp 'kuro--render-cycle)
    (kuro--render-cycle))
  (message "Kuro copy mode off"))


;;;; Public commands

;;;###autoload
(defun kuro-copy-mode ()
  "Toggle Kuro copy mode.
In copy mode the PTY keymap is suspended and standard Emacs cursor
movement, region selection, and copy commands (\\[kill-ring-save],
\\[kill-region], \\[isearch-forward]…) become available.
The buffer remains read-only; only navigation and selection
are enabled.  Call \\[kuro-copy-mode] again to return to terminal mode."
  (interactive)
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Kuro-copy-mode: not in a Kuro terminal buffer"))
  (if kuro--copy-mode
      (kuro--exit-copy-mode)
    (kuro--enter-copy-mode)))

(defmacro kuro--def-copy-search-enter (name search-fn docstring)
  "Define a command that enters copy mode (if needed) then calls SEARCH-FN."
  `(defun ,name ()
     ,docstring
     (interactive)
     (unless (derived-mode-p 'kuro-mode)
       (user-error "Not in a Kuro terminal buffer"))
     (unless kuro--copy-mode
       (kuro--enter-copy-mode))
     (,search-fn)))

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
  (unless (derived-mode-p 'kuro-mode)
    (user-error "Not in a Kuro terminal buffer"))
  (unless kuro--copy-mode
    (kuro--enter-copy-mode))
  (occur regexp))

(provide 'kuro-copy)

;;; kuro-copy.el ends here
