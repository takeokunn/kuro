;;; kuro-navigation.el --- Navigation and hyperlink overlays for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Prompt navigation and focus event handling for the Kuro terminal.
;;
;; Provides `kuro-previous-prompt' and `kuro-next-prompt' commands
;; that jump between shell prompts using OSC 133 semantic marks
;; (prompt-start, prompt-end, command-start, command-end).
;;
;; Also handles focus-in/focus-out events (DEC mode 1004) by sending
;; the appropriate CSI I/O sequences to the PTY.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-ffi-modes)
(require 'kuro-navigation-macros)

(declare-function kuro--get-focus-events "kuro-ffi-modes" ())
(declare-function kuro--send-key "kuro-ffi" (data))

(defvar kuro--initialized nil
  "Forward reference; `defvar-local' in kuro-ffi.el.")

;;; Buffer-local state

(kuro--defvar-permanent-local kuro--prompt-positions nil
  "List of (MARK-TYPE ROW COL EXIT-CODE) for OSC 133 prompt marks.
MARK-TYPE is a string such as \"prompt-start\", \"prompt-end\",
\"command-start\", or \"command-end\".  ROW and COL are 0-based integers.
EXIT-CODE is an integer for command-end marks (from OSC 133;D;N), or nil.
Updated each render cycle by polling `kuro--poll-prompt-marks'.")

(defun kuro--update-prompt-positions (marks positions max-count)
  "Merge OSC 133 prompt mark data into POSITIONS and return the updated list.
MARKS is a list of (MARK-TYPE ROW COL EXIT-CODE) proper lists as returned
by `kuro--poll-prompt-marks'.  POSITIONS is the current accumulated list
of prompt positions (buffer-local `kuro--prompt-positions').
MAX-COUNT is the maximum number of entries to retain (oldest are dropped).

The result is sorted ascending by row number and capped at MAX-COUNT
entries so the list never grows unboundedly across long sessions.
Returns the updated positions list (suitable for direct assignment).

POSITIONS is maintained sorted; MARKS (typically 0–5 new events) is sorted
separately then merged in O(M+N) rather than re-sorting the full combined
list.  Fast path: if MARKS is nil, returns POSITIONS unchanged."
  (if (null marks)
      positions
    (let* ((m (sort (copy-sequence marks) (lambda (a b) (< (cadr a) (cadr b)))))
           (p positions)
           (count 0)
           result)
      (while (< count max-count)
        (cond
         ((and m p)
          (if (< (cadr (car m)) (cadr (car p)))
              (progn (push (car m) result) (setq m (cdr m)))
            (progn (push (car p) result) (setq p (cdr p)))))
         (m (push (car m) result) (setq m (cdr m)))
         (p (push (car p) result) (setq p (cdr p)))
         (t (setq count max-count)))
        (setq count (1+ count)))
      (nreverse result))))

;;; Prompt navigation (OSC 133)

(defsubst kuro--goto-prompt-row (row)
  "Move point to the beginning of ROW (0-based) in the terminal buffer.
Uses (goto-char (point-min)) then (forward-line ROW) to navigate
to the exact buffer position corresponding to grid row ROW."
  (goto-char (point-min))
  (forward-line row))

(defun kuro--find-mark-in-direction (direction type-pred)
  "Return nearest prompt entry matching TYPE-PRED in DIRECTION.
Search `kuro--prompt-positions' around point.
DIRECTION is `previous' (towards the top) or `next' (towards the bottom).
TYPE-PRED is called with each entry and must return non-nil for a match.
Returns the closest matching entry to point, or nil when none is found."
  (let* ((cur      (1- (line-number-at-pos)))
         (row-pred (if (eq direction 'previous)
                       (lambda (e) (< (cadr e) cur))
                     (lambda (e) (> (cadr e) cur))))
         (matches  (seq-filter (lambda (e)
                                 (and (funcall row-pred e)
                                      (funcall type-pred e)))
                               kuro--prompt-positions)))
    (if (eq direction 'previous)
        (car (last matches))
      (car matches))))

(kuro--def-navigator kuro--navigate-to-prompt
  (lambda (e) (equal (car e) "prompt-start"))
  (kuro--goto-prompt-row (cadr target))
  (message "kuro: no %s prompt" (symbol-name direction))
  "Navigate to the nearest prompt-start in DIRECTION (`previous' or `next').")

;;;###autoload
(kuro--def-nav-cmd kuro-previous-prompt kuro--navigate-to-prompt previous
  "Jump to the previous shell prompt (OSC 133 mark).")

;;;###autoload
(kuro--def-nav-cmd kuro-next-prompt kuro--navigate-to-prompt next
  "Jump to the next shell prompt (OSC 133 mark).")

(defun kuro--command-output-region ()
  "Return (BEG . END) buffer positions for the command output enclosing point.
Uses OSC 133 marks: output begins at the `command-start' mark at or before
point and ends just before the next `prompt-start' mark (or buffer end when
the command is the most recent one).  Returns nil when no enclosing
`command-start' mark is found — e.g. when shell integration is absent or
point precedes the first command."
  (let* ((cur     (1- (line-number-at-pos)))
         (cstart  (car (last (seq-filter
                              (lambda (e)
                                (and (equal (car e) "command-start")
                                     (<= (cadr e) cur)))
                              kuro--prompt-positions)))))
    (when cstart
      (let* ((start-row   (cadr cstart))
             (next-prompt (seq-find
                           (lambda (e)
                             (and (equal (car e) "prompt-start")
                                  (> (cadr e) start-row)))
                           kuro--prompt-positions)))
        (cons (save-excursion (kuro--goto-prompt-row start-row) (point))
              (if next-prompt
                  (save-excursion (kuro--goto-prompt-row (cadr next-prompt)) (point))
                (point-max)))))))

;;;###autoload
(defun kuro-copy-command-output ()
  "Copy the output of the shell command at point to the kill ring.
Uses OSC 133 semantic marks: the region spans from the command's
`command-start' mark to the next prompt (or buffer end).  This is the
\"copy last command output\" workflow popularised by iTerm2 — grab a
command's results without manually selecting them.  Requires OSC 133 shell
integration; messages and does nothing when no command output is found at
point."
  (interactive)
  (let ((region (kuro--command-output-region)))
    (if (null region)
        (message "kuro: no command output at point (OSC 133 shell integration required)")
      (kill-ring-save (car region) (cdr region))
      (message "kuro: copied command output (%d chars)"
               (- (cdr region) (car region))))))

;;; Command history (OSC 133 prompt-start → command-end pairing)

(defun kuro--prompt-line-text (row)
  "Return the trimmed buffer text of 0-based ROW in the terminal buffer."
  (save-excursion
    (kuro--goto-prompt-row row)
    (string-trim (buffer-substring-no-properties
                  (line-beginning-position) (line-end-position)))))

(defun kuro--command-history-entries ()
  "Return completed command records from OSC 133 data, oldest first.
Each record is (ROW EXIT TEXT): ROW is the prompt-start row (0-based), EXIT
the integer exit code (or nil when the shell did not report one), and TEXT
the trimmed prompt-line text (prompt plus the typed command).  Commands are
formed by pairing each `prompt-start' mark with the next `command-end'."
  (let ((sorted (sort (copy-sequence kuro--prompt-positions)
                      (lambda (a b) (< (cadr a) (cadr b)))))
        records pend-row)
    (dolist (m sorted)
      (pcase (car m)
        ("prompt-start" (setq pend-row (cadr m)))
        ("command-end"
         (when pend-row
           (push (list pend-row (nth 3 m) (kuro--prompt-line-text pend-row))
                 records)
           (setq pend-row nil)))))
    (nreverse records)))

(defun kuro--command-history-label (exit text)
  "Build a completion label from an EXIT code and prompt TEXT."
  (format "%s %s"
          (cond ((null exit) "·")
                ((= exit 0) "✓")
                (t (format "✗%d" exit)))
          (if (string-empty-p text) "(prompt)" text)))

;;;###autoload
(defun kuro-command-history ()
  "Jump to a past shell command chosen from OSC 133 data.
Each completed command is presented newest-first, annotated with its exit
status (✓ success, ✗N failure, · unknown).  Selecting one moves point to
that command's prompt and recenters.  Requires OSC 133 shell integration;
messages and does nothing when no command history is available."
  (interactive)
  (let ((entries (kuro--command-history-entries)))
    (if (null entries)
        (message "kuro: no command history (OSC 133 shell integration required)")
      ;; Newest-first so `assoc' resolves duplicate commands to the most recent.
      (let* ((cands (mapcar (lambda (e)
                              (pcase-let ((`(,row ,exit ,text) e))
                                (cons (kuro--command-history-label exit text) row)))
                            (nreverse entries)))
             (choice (completing-read "Command: " cands nil t)))
        (when-let* ((row (cdr (assoc choice cands))))
          (kuro--goto-prompt-row row)
          (recenter))))))

;;; Failed-command navigation (OSC 133 command-end exit codes)

(kuro--def-navigator kuro--navigate-to-failed-command
  (lambda (e)
    (and (equal (car e) "command-end")
         (integerp (nth 3 e))
         (/= (nth 3 e) 0)))
  (progn (kuro--goto-prompt-row (cadr target))
         (message "kuro: failed command (exit %d)" (nth 3 target)))
  (message "kuro: no %s failed command" (symbol-name direction))
  "Move point to the nearest failed command in DIRECTION (`previous'/`next').
A failed command is a `command-end' mark with a non-zero OSC 133 exit code.")

;;;###autoload
(kuro--def-nav-cmd kuro-next-failed-command kuro--navigate-to-failed-command next
  "Jump to the next command that exited with a non-zero status (OSC 133).")

;;;###autoload
(kuro--def-nav-cmd kuro-previous-failed-command kuro--navigate-to-failed-command previous
  "Jump to the previous command that exited with a non-zero status (OSC 133).")

;;; Focus event handlers

(kuro--def-focus-handler kuro--handle-focus-in  "\e[I" "Handle focus-in event; send focus-in sequence to terminal.")
(kuro--def-focus-handler kuro--handle-focus-out "\e[O" "Handle focus-out event; send focus-out sequence to terminal.")

(provide 'kuro-navigation)

;;; kuro-navigation.el ends here
