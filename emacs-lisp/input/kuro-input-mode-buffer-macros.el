;;; kuro-input-mode-buffer-macros.el --- Buffer mutation forms for kuro-input-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Inline line-buffer mutation helpers for Kuro line mode.  Keep these forms
;; separate from `kuro-input-mode-macros' so CPS/display helpers and buffer
;; splicing stay in distinct modules.

;;; Code:

;; Forward declarations for buffer-local state defined in kuro-input-mode.el.
(defvar kuro--line-buffer)
(defvar kuro--line-point)

;; Declare the undo and display continuations so byte compilation of this file
;; does not warn before the dependent modules are loaded.
(declare-function kuro--line-undo-push "kuro-input-mode-line-state" ())
(declare-function kuro--line-mode-update-display "kuro-input-mode-line-display" ())

(defmacro kuro--line-splice (from to replacement new-point)
  "Replace text between FROM and TO with REPLACEMENT and set point to NEW-POINT.
Does not call `kuro--line-mode-update-display'; compose with
`kuro--line-splice-with-undo' to get the undo and display continuations."
  (declare (indent 0))
  `(setq kuro--line-buffer
         (concat (substring kuro--line-buffer 0 ,from)
                 ,replacement
                 (substring kuro--line-buffer ,to))
         kuro--line-point ,new-point))

(defmacro kuro--line-splice-with-undo (from to replacement new-point)
  "Push undo state and splice the line buffer from FROM to TO with REPLACEMENT.
Then move point to NEW-POINT and refresh display."
  (declare (indent 0))
  `(progn
     (kuro--line-undo-push)
     (kuro--line-splice ,from ,to ,replacement ,new-point)
     (kuro--line-mode-update-display)))

(defmacro kuro--line-replace-buffer-with-undo (replacement-form)
  "Replace the whole line buffer with REPLACEMENT-FORM and move point to the end."
  (declare (indent 0))
  `(let ((replacement ,replacement-form))
     (kuro--line-splice-with-undo 0 (length kuro--line-buffer)
                                  replacement (length replacement))))

(defmacro kuro--line-insert-with-undo (from replacement-form)
  "Insert REPLACEMENT-FORM at FROM, then move point after the inserted text."
  (declare (indent 1))
  `(let ((pos ,from)
         (replacement ,replacement-form))
     (kuro--line-splice-with-undo pos pos
                                  replacement (+ pos (length replacement)))))

(defmacro kuro--line-delete-with-undo (from to)
  "Delete buffer text from FROM to TO and keep point at FROM."
  (declare (indent 0))
  `(kuro--line-splice-with-undo ,from ,to "" ,from))

(defmacro kuro--line-replace-range-with-undo (from to replacement-form)
  "Replace buffer text from FROM to TO with REPLACEMENT-FORM.
Move point to the end of it."
  (declare (indent 0))
  `(let ((from ,from)
         (to ,to)
         (replacement ,replacement-form))
     (kuro--line-splice-with-undo from to
                                  replacement (+ from (length replacement)))))

(provide 'kuro-input-mode-buffer-macros)

;;; kuro-input-mode-buffer-macros.el ends here
