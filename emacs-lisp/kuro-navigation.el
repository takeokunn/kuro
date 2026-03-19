;;; kuro-navigation.el --- Navigation and hyperlink overlays for Kuro -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:
;; Prompt navigation (OSC 133), focus event handling (mode 1004),
;; and OSC 8 hyperlink overlay infrastructure (scaffolding; not yet wired).

;;; Code:

(require 'kuro-ffi)
(require 'kuro-ffi-modes)

(declare-function kuro--get-focus-events "kuro-ffi-modes" ())
(declare-function kuro--send-key "kuro-ffi" (data))

(defvar kuro--initialized nil
  "Forward reference; defvar-local in kuro-ffi.el.")

;;; Buffer-local state

(defvar-local kuro--hyperlink-overlays nil
  "List of active hyperlink overlays in the current kuro buffer.")
(put 'kuro--hyperlink-overlays 'permanent-local t)

(defvar-local kuro--prompt-positions nil
  "List of (MARK-TYPE ROW COL) for OSC 133 prompt marks.
MARK-TYPE is a string such as \"prompt-start\", \"prompt-end\",
\"command-start\", or \"command-end\".  ROW and COL are 0-based integers.
Updated each render cycle by polling `kuro--poll-prompt-marks'.")
(put 'kuro--prompt-positions 'permanent-local t)

(defun kuro--update-prompt-positions (marks positions max-count)
  "Merge OSC 133 MARKS into POSITIONS and return the updated list.
MARKS is a list of (MARK-TYPE ROW COL) proper lists as returned by
`kuro--poll-prompt-marks'.  POSITIONS is the current accumulated list
of prompt positions (buffer-local `kuro--prompt-positions').
MAX-COUNT is the maximum number of entries to retain (oldest are dropped).

The result is sorted ascending by row number and capped at MAX-COUNT
entries so the list never grows unboundedly across long sessions.
Returns the updated positions list (suitable for direct assignment)."
  (dolist (mark marks)
    (push mark positions))
  (seq-take
   (sort positions (lambda (a b) (< (cadr a) (cadr b))))
   max-count))

;;; OSC 8 Hyperlink overlay API — Not yet wired to render cycle
;;
;; OSC 8 hyperlink overlay infrastructure (scaffolding; not yet wired).
;; Missing pieces before wire-up:
;;   1. Rust FFI: expose kuro_core_poll_hyperlink_spans in bridge/events.rs
;;   2. Emacs wrapper: add kuro--poll-hyperlink-spans to kuro-ffi-osc.el
;;   3. Wire-up: call kuro--poll-hyperlink-spans in kuro--poll-osc-events
;;      (kuro-renderer.el) and apply overlays via kuro--apply-hyperlink-overlay.

(defun kuro--clear-all-hyperlink-overlays ()
  "Remove all hyperlink overlays from the current buffer.
Note: Not currently called from the render cycle."
  (dolist (ov kuro--hyperlink-overlays)
    (when (overlay-buffer ov)
      (delete-overlay ov)))
  (setq kuro--hyperlink-overlays nil))

(defun kuro--make-hyperlink-keymap (uri)
  "Return a sparse keymap that opens URI on RET or mouse-1."
  (let ((map (make-sparse-keymap)))
    (define-key map [return]
      (lambda () (interactive) (browse-url uri)))
    (define-key map [mouse-1]
      (lambda (_event) (interactive "e") (browse-url uri)))
    map))

(defun kuro--apply-hyperlink-overlay (start end uri)
  "Create a hyperlink overlay from START to END pointing to URI.
Note: Not currently called from the render cycle."
  (let ((ov (make-overlay start end)))
    (overlay-put ov 'kuro-hyperlink t)
    (overlay-put ov 'help-echo (format "URI: %s\nRET or mouse-1 to open" uri))
    (overlay-put ov 'mouse-face 'highlight)
    (overlay-put ov 'keymap (kuro--make-hyperlink-keymap uri))
    (push ov kuro--hyperlink-overlays)))

;;; Prompt navigation (OSC 133)

(defsubst kuro--goto-prompt-row (row)
  "Move point to the beginning of ROW (0-based) in the terminal buffer.
Uses (goto-char (point-min)) then (forward-line ROW) to navigate
to the exact buffer position corresponding to grid row ROW."
  (goto-char (point-min))
  (forward-line row))

;;;###autoload
(defun kuro-previous-prompt ()
  "Jump to the previous shell prompt (OSC 133 mark)."
  (interactive)
  (let* ((cur-line (1- (line-number-at-pos)))
         (candidates
          (seq-filter (lambda (entry)
                        (and (< (cadr entry) cur-line)
                             (equal (car entry) "prompt-start")))
                      kuro--prompt-positions))
         (target (car (last candidates))))
    (if target
        (kuro--goto-prompt-row (cadr target))
      (message "kuro: no previous prompt"))))

;;;###autoload
(defun kuro-next-prompt ()
  "Jump to the next shell prompt (OSC 133 mark)."
  (interactive)
  (let* ((cur-line (1- (line-number-at-pos)))
         (candidates
          (seq-filter (lambda (entry)
                        (and (> (cadr entry) cur-line)
                             (equal (car entry) "prompt-start")))
                      kuro--prompt-positions))
         (target (car candidates)))
    (if target
        (kuro--goto-prompt-row (cadr target))
      (message "kuro: no next prompt"))))

;;; Focus event handlers

(defun kuro--handle-focus-in ()
  "Handle Emacs focus-in event for terminal focus reporting (mode 1004)."
  (when (and (derived-mode-p 'kuro-mode)
             kuro--initialized
             (kuro--get-focus-events))
    (kuro--send-key "\e[I")))

(defun kuro--handle-focus-out ()
  "Handle Emacs focus-out event for terminal focus reporting (mode 1004)."
  (when (and (derived-mode-p 'kuro-mode)
             kuro--initialized
             (kuro--get-focus-events))
    (kuro--send-key "\e[O")))

(provide 'kuro-navigation)

;;; kuro-navigation.el ends here
