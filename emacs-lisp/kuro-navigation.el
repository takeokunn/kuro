;;; kuro-navigation.el --- Navigation and hyperlink overlays for Kuro -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:
;; Prompt navigation (OSC 133) and focus event handling (mode 1004).

;;; Code:

(require 'kuro-ffi)
(require 'kuro-ffi-modes)

(declare-function kuro--get-focus-events "kuro-ffi-modes" ())
(declare-function kuro--send-key "kuro-ffi" (data))

(defvar kuro--initialized nil
  "Forward reference; defvar-local in kuro-ffi.el.")

;;; Buffer-local state

(kuro--defvar-permanent-local kuro--prompt-positions nil
  "List of (MARK-TYPE ROW COL) for OSC 133 prompt marks.
MARK-TYPE is a string such as \"prompt-start\", \"prompt-end\",
\"command-start\", or \"command-end\".  ROW and COL are 0-based integers.
Updated each render cycle by polling `kuro--poll-prompt-marks'.")

(defun kuro--update-prompt-positions (marks positions max-count)
  "Merge OSC 133 MARKS into POSITIONS and return the updated list.
MARKS is a list of (MARK-TYPE ROW COL) proper lists as returned by
`kuro--poll-prompt-marks'.  POSITIONS is the current accumulated list
of prompt positions (buffer-local `kuro--prompt-positions').
MAX-COUNT is the maximum number of entries to retain (oldest are dropped).

The result is sorted ascending by row number and capped at MAX-COUNT
entries so the list never grows unboundedly across long sessions.
Returns the updated positions list (suitable for direct assignment)."
  (seq-take
   (sort (append marks positions) (lambda (a b) (< (cadr a) (cadr b))))
   max-count))

;;; Prompt navigation (OSC 133)

(defsubst kuro--goto-prompt-row (row)
  "Move point to the beginning of ROW (0-based) in the terminal buffer.
Uses (goto-char (point-min)) then (forward-line ROW) to navigate
to the exact buffer position corresponding to grid row ROW."
  (goto-char (point-min))
  (forward-line row))

(defun kuro--navigate-to-prompt (direction)
  "Navigate to the nearest prompt-start in DIRECTION (`previous' or `next')."
  (let* ((cur-line   (1- (line-number-at-pos)))
         (row-pred   (if (eq direction 'previous)
                         (lambda (e) (< (cadr e) cur-line))
                       (lambda (e) (> (cadr e) cur-line))))
         (candidates (seq-filter (lambda (e)
                                   (and (funcall row-pred e)
                                        (equal (car e) "prompt-start")))
                                 kuro--prompt-positions))
         (target     (if (eq direction 'previous)
                         (car (last candidates))
                       (car candidates))))
    (if target
        (kuro--goto-prompt-row (cadr target))
      (message "kuro: no %s prompt" (symbol-name direction)))))

;;;###autoload
(defun kuro-previous-prompt ()
  "Jump to the previous shell prompt (OSC 133 mark)."
  (interactive)
  (kuro--navigate-to-prompt 'previous))

;;;###autoload
(defun kuro-next-prompt ()
  "Jump to the next shell prompt (OSC 133 mark)."
  (interactive)
  (kuro--navigate-to-prompt 'next))

;;; Focus event handlers

(defmacro kuro--with-focus-guard (&rest body)
  "Execute BODY only when in an active kuro buffer with focus-events mode enabled."
  `(when (and (derived-mode-p 'kuro-mode)
              kuro--initialized
              (kuro--get-focus-events))
     ,@body))

(defmacro kuro--def-focus-handler (name sequence doc)
  "Define a focus event handler NAME that sends SEQUENCE."
  `(defun ,name ()
     ,doc
     (kuro--with-focus-guard
      (kuro--send-key ,sequence))))

(kuro--def-focus-handler kuro--handle-focus-in  "\e[I" "Handle focus-in event; send focus-in sequence to terminal.")
(kuro--def-focus-handler kuro--handle-focus-out "\e[O" "Handle focus-out event; send focus-out sequence to terminal.")

(provide 'kuro-navigation)

;;; kuro-navigation.el ends here
