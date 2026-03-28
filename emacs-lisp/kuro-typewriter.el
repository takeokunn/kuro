;;; kuro-typewriter.el --- Typewriter animation effect for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides the typewriter character-by-character animation
;; effect for the Kuro terminal emulator, used to display AI agent
;; streaming output with a smooth "typing" appearance.
;;
;; # Responsibilities
;;
;; - kuro-typewriter-effect and kuro-typewriter-chars-per-second defcustoms
;; - Per-buffer typewriter queue, timer, and state variables
;; - kuro--start-typewriter-timer / kuro--stop-typewriter-timer
;; - kuro--typewriter-enqueue: adds (row . text) items to the queue
;; - kuro--typewriter-tick: drains one character per timer tick
;; - kuro--typewriter-queue-next: advances to next queued row
;; - kuro--typewriter-write-partial: writes partial text to a buffer row
;;
;; # Dependencies
;;
;; Depends on `kuro-ffi' for `kuro--initialized'.

;;; Code:

(require 'kuro-config)
(require 'kuro-ffi)
(require 'kuro-render-buffer)

;;; Configuration (defcustoms live in kuro-config.el)

(defvar kuro-typewriter-effect nil
  "Forward reference; defined in kuro-config.el.")
(defvar kuro-typewriter-chars-per-second nil
  "Forward reference; defined in kuro-config.el.")

;;; Internal state

(kuro--defvar-permanent-local kuro--typewriter-queue nil
  "Queue of (ROW . TEXT) pairs waiting to be displayed by the typewriter effect.
Each entry is a cons cell (row . text) from `kuro--poll-updates-with-faces'.
The typewriter timer drains this queue character-by-character.")

(kuro--defvar-permanent-local kuro--typewriter-timer nil
  "Repeating timer for the typewriter character-drip effect.
Fires at `kuro-typewriter-chars-per-second' Hz when
`kuro-typewriter-effect' is t.")

(kuro--defvar-permanent-local kuro--typewriter-current-row nil
  "Row currently being written by the typewriter effect.")

(kuro--defvar-permanent-local kuro--typewriter-current-text nil
  "Full text for the current typewriter row (not consumed during animation).")

(kuro--defvar-permanent-local kuro--typewriter-written-len 0
  "Number of characters already written for the current typewriter row.")

;;; Typewriter timer

(defun kuro--start-typewriter-timer ()
  "Start the typewriter character-drip timer."
  (when kuro-typewriter-effect
    (kuro--stop-typewriter-timer)
    (let ((buf (current-buffer))
          (interval (/ 1.0 (max 1 kuro-typewriter-chars-per-second))))
      (setq kuro--typewriter-timer
            (run-with-timer interval interval
                            (lambda ()
                              (when (buffer-live-p buf)
                                (with-current-buffer buf
                                  (kuro--typewriter-tick)))))))))

(defun kuro--stop-typewriter-timer ()
  "Stop the typewriter character-drip timer."
  (when (timerp kuro--typewriter-timer)
    (cancel-timer kuro--typewriter-timer)
    (setq kuro--typewriter-timer nil)))

(defun kuro--typewriter-enqueue (row text)
  "Add (ROW . TEXT) to the typewriter queue.
Called from the render cycle when typewriter mode is active."
  (push (cons row text) kuro--typewriter-queue))

(defun kuro--typewriter-tick ()
  "Display one character from the typewriter queue.
Called by `kuro--typewriter-timer' at `kuro-typewriter-chars-per-second' Hz."
  (when kuro--initialized
    ;; If we have a current row in progress, display next character
    (cond
     ((and kuro--typewriter-current-row kuro--typewriter-current-text
           (< kuro--typewriter-written-len
              (length kuro--typewriter-current-text)))
      ;; Write one more character of the current row
      (let* ((row kuro--typewriter-current-row)
             (next-len (1+ kuro--typewriter-written-len)))
        (kuro--typewriter-write-partial
         row (substring kuro--typewriter-current-text 0 next-len))
        (setq kuro--typewriter-written-len next-len)))
     (t
      ;; Try to advance to the next queued row; if none, reset state
      (or (kuro--typewriter-queue-next)
          (setq kuro--typewriter-current-row nil
                kuro--typewriter-current-text nil
                kuro--typewriter-written-len 0))))))

(defun kuro--typewriter-queue-next ()
  "Pop the next item from the typewriter queue and begin writing it.
Returns non-nil if an item was dequeued."
  (when kuro--typewriter-queue
    (let* ((item (pop kuro--typewriter-queue))
           (row (car item))
           (text (cdr item)))
      (setq kuro--typewriter-current-row row
            kuro--typewriter-current-text text
            kuro--typewriter-written-len 0)
      t)))

(defun kuro--typewriter-write-partial (row text)
  "Write partial TEXT to ROW in the buffer (without triggering a full render)."
  (kuro--with-buffer-edit
   (goto-char (point-min))
   (let ((not-moved (forward-line row)))
     (when (= not-moved 0)
       (let ((line-start (point))
             (line-end (line-end-position)))
         (delete-region line-start line-end)
         (insert text))))))

(provide 'kuro-typewriter)

;;; kuro-typewriter.el ends here
