;;; kuro-stream.el --- Smooth streaming output for AI agents in Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides smooth streaming output rendering for AI agent output
;; (Claude Code, aider, etc.) in the Kuro terminal emulator.
;;
;; # Features
;;
;; 1. **Low-latency PTY notification**: A fast idle timer fires immediately
;;    when PTY data arrives, bypassing the normal 60fps polling interval.
;;    This makes streaming text appear token-by-token without batchig delay.
;;
;; 2. **Adaptive frame rate**: When PTY output is flowing (AI streaming),
;;    the render loop automatically increases its poll frequency.  When the
;;    terminal is idle, it returns to the configured `kuro-frame-rate'.
;;
;; 3. **Typewriter animation effect**: Optional character-by-character
;;    display that makes AI output appear to "type itself".  Configurable
;;    speed via `kuro-typewriter-chars-per-second'.
;;
;; 4. **Synchronized output integration**: When the terminal sends
;;    `?2026 h` (Synchronized Output), pending lines are held until `?2026 l`
;;    is received, preventing partial-frame flicker.
;;
;; # Architecture
;;
;; - `kuro--stream-idle-timer': 0-delay idle timer, fires when Emacs is idle.
;;   Calls `kuro--render-cycle' if PTY has pending output.
;; - `kuro--typewriter-queue': Buffer of (row . text) updates waiting to
;;   be displayed character-by-character.
;; - `kuro--typewriter-timer': Fast timer (default 120fps) draining the queue.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-faces)

;; Forward declare to avoid circular dependency with kuro-renderer.el
(declare-function kuro--render-cycle "kuro-renderer" ())

;;; Configuration

(defcustom kuro-streaming-latency-mode t
  "When non-nil, enable low-latency mode for AI agent streaming output.
In this mode, a zero-delay idle timer fires an immediate render cycle
whenever the PTY has pending data, giving token-by-token responsiveness
without waiting for the next 60fps frame tick."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-typewriter-effect nil
  "When non-nil, display new terminal output character-by-character.
This creates a smooth \"typing\" animation for AI agent output.
Set `kuro-typewriter-chars-per-second' to control the display speed."
  :type 'boolean
  :group 'kuro)

(defcustom kuro-typewriter-chars-per-second 120
  "Number of characters to display per second in typewriter mode.
Higher values look faster; lower values are more dramatic.
Only effective when `kuro-typewriter-effect' is non-nil."
  :type 'natnum
  :group 'kuro)

;;; Internal state

(defvar-local kuro--stream-idle-timer nil
  "One-shot idle timer for low-latency PTY output detection.
Fires when Emacs is idle and PTY has pending data.
Set to nil when streaming latency mode is disabled.")
(put 'kuro--stream-idle-timer 'permanent-local t)

(defvar-local kuro--typewriter-queue nil
  "Queue of (ROW . TEXT) pairs waiting to be displayed by the typewriter effect.
Each entry is a cons cell (row . text) from `kuro--poll-updates-with-faces'.
The typewriter timer drains this queue character-by-character.")
(put 'kuro--typewriter-queue 'permanent-local t)

(defvar-local kuro--typewriter-timer nil
  "Repeating timer for the typewriter character-drip effect.
Fires at `kuro-typewriter-chars-per-second' Hz when `kuro-typewriter-effect' is t.")
(put 'kuro--typewriter-timer 'permanent-local t)

(defvar-local kuro--typewriter-current-row nil
  "Row currently being written by the typewriter effect.")
(put 'kuro--typewriter-current-row 'permanent-local t)

(defvar-local kuro--typewriter-current-text nil
  "Remaining text to write for the current typewriter row.")
(put 'kuro--typewriter-current-text 'permanent-local t)

(defvar-local kuro--typewriter-written-len 0
  "Number of characters already written for the current typewriter row.")
(put 'kuro--typewriter-written-len 'permanent-local t)

(defvar-local kuro--stream-output-active nil
  "Non-nil when PTY output has been flowing recently (streaming state).
Used to detect AI agent activity and apply appropriate rendering strategy.")
(put 'kuro--stream-output-active 'permanent-local t)

(defvar-local kuro--stream-idle-count 0
  "Counter of consecutive idle render cycles with no PTY output.
When this reaches `kuro--stream-idle-threshold', streaming mode is deactivated.")
(put 'kuro--stream-idle-count 'permanent-local t)

(defvar-local kuro--stream-last-render-time 0.0
  "Float-time of last render triggered by the streaming idle timer.
Used to rate-limit idle renders to at most `kuro-frame-rate' times/second.")
(put 'kuro--stream-last-render-time 'permanent-local t)

(defvar-local kuro--stream-min-interval nil
  "Minimum seconds between idle-timer render cycles, derived from `kuro-frame-rate'.
Computed lazily: nil means unset, will be computed on first idle render.")
(put 'kuro--stream-min-interval 'permanent-local t)

(defconst kuro--stream-idle-threshold 10
  "Number of empty render cycles before exiting active streaming mode.")

;;; Low-latency idle timer

;;;###autoload
(defun kuro--start-stream-idle-timer ()
  "Start the zero-delay idle timer for low-latency streaming output.
When `kuro-streaming-latency-mode' is non-nil, this fires a render
cycle immediately whenever Emacs becomes idle and PTY has data."
  (when kuro-streaming-latency-mode
    (when (timerp kuro--stream-idle-timer)
      (cancel-timer kuro--stream-idle-timer)
      (setq kuro--stream-idle-timer nil))
    (let ((buf (current-buffer)))
      (setq kuro--stream-idle-timer
            (run-with-idle-timer
             0 t                           ; repeat=t: fire every time Emacs is idle
             (lambda ()
               (when (and (buffer-live-p buf)
                          kuro-streaming-latency-mode)
                 (with-current-buffer buf
                   (when (and kuro--initialized
                              (kuro--has-pending-output))
                     (kuro--render-cycle))))))))))

;;;###autoload
(defun kuro--stop-stream-idle-timer ()
  "Stop the streaming idle timer."
  (when (timerp kuro--stream-idle-timer)
    (cancel-timer kuro--stream-idle-timer)
    (setq kuro--stream-idle-timer nil)))

;;; Typewriter effect

;;;###autoload
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

;;;###autoload
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
           (not (string-empty-p kuro--typewriter-current-text)))
      ;; Write one more character of the current row
      (let* ((row kuro--typewriter-current-row)
             (full-text (concat
                         (make-string kuro--typewriter-written-len ? )
                         kuro--typewriter-current-text))
             (next-len (1+ kuro--typewriter-written-len)))
        (kuro--typewriter-write-partial row (substring full-text 0 next-len))
        (setq kuro--typewriter-written-len next-len)
        (setq kuro--typewriter-current-text
              (if (> (length kuro--typewriter-current-text) 1)
                  (substring kuro--typewriter-current-text 1)
                ""))))
     ((kuro--typewriter-queue-next))  ; advance to next queued row
     (t
      ;; Queue empty: reset state
      (setq kuro--typewriter-current-row nil
            kuro--typewriter-current-text nil
            kuro--typewriter-written-len 0)))))

(defun kuro--typewriter-queue-next ()
  "Pop the next item from the typewriter queue and begin writing it.
Returns non-nil if an item was dequeued."
  (when kuro--typewriter-queue
    (let* ((item (car (last kuro--typewriter-queue)))
           (row (car item))
           (text (cdr item)))
      (setq kuro--typewriter-queue (butlast kuro--typewriter-queue))
      (setq kuro--typewriter-current-row row
            kuro--typewriter-current-text text
            kuro--typewriter-written-len 0)
      t)))

(defun kuro--typewriter-write-partial (row text)
  "Write partial TEXT to ROW in the buffer (without triggering a full render)."
  (save-excursion
    (goto-char (point-min))
    (let ((not-moved (forward-line row)))
      (when (= not-moved 0)
        (let ((inhibit-read-only t)
              (inhibit-modification-hooks t))
          (let ((line-start (point))
                (line-end (line-end-position)))
            (delete-region line-start line-end)
            (insert text)))))))

;;; Streaming mode detection

(defun kuro--stream-mark-active ()
  "Mark the terminal as actively streaming output."
  (setq kuro--stream-output-active t
        kuro--stream-idle-count 0))

(defun kuro--stream-check-idle ()
  "Increment idle counter and deactivate streaming mode if threshold reached."
  (when kuro--stream-output-active
    (setq kuro--stream-idle-count (1+ kuro--stream-idle-count))
    (when (>= kuro--stream-idle-count kuro--stream-idle-threshold)
      (setq kuro--stream-output-active nil
            kuro--stream-idle-count 0))))

;;; Default color application (OSC 10/11/12)

(defun kuro--apply-default-colors ()
  "Apply OSC 10/11/12 default terminal colors to the current kuro buffer.
Reads pending color changes from the Rust core and sets buffer-local
`default' face overrides so the terminal background/foreground match
what the running application requested."
  (when kuro--initialized
    (let ((colors (kuro--get-default-colors)))
      (when colors
        (let* ((fg-enc (car colors))
               (bg-enc (cadr colors))
               ;; cursor-enc = (caddr colors) -- future use
               (fg (kuro--decode-ffi-color fg-enc))
               (bg (kuro--decode-ffi-color bg-enc))
               (fg-str (kuro--color-to-emacs fg))
               (bg-str (kuro--color-to-emacs bg)))
          ;; Apply as buffer-local face remapping
          (when (and (display-graphic-p) (or fg-str bg-str))
            (apply #'face-remap-add-relative
                   'default
                   (append
                    (when fg-str (list :foreground fg-str))
                    (when bg-str (list :background bg-str))))))))))

;;; Palette application (OSC 4)

(defun kuro--apply-palette-updates ()
  "Apply OSC 4 palette overrides from the Rust core.
Updates `kuro--named-colors' entries for indices 0-15 if overridden."
  (when kuro--initialized
    (let ((updates (kuro--get-palette-updates)))
      (dolist (entry updates)
        (let* ((idx  (nth 0 entry))
               (r    (nth 1 entry))
               (g    (nth 2 entry))
               (b    (nth 3 entry))
               (hex  (format "#%02x%02x%02x" r g b))
               (names ["black" "red" "green" "yellow"
                       "blue" "magenta" "cyan" "white"
                       "bright-black" "bright-red" "bright-green" "bright-yellow"
                       "bright-blue" "bright-magenta" "bright-cyan" "bright-white"]))
          ;; Update named-colors for indices 0-15
          (when (< idx 16)
            (let ((name (aref names idx)))
              (setf (alist-get name kuro--named-colors nil nil #'string=) hex)
              ;; Clear face cache since colors changed
              (kuro--clear-face-cache))))))))

(provide 'kuro-stream)

;;; kuro-stream.el ends here
