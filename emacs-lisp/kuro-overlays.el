;;; kuro-overlays.el --- Overlay management for Kuro terminal emulator  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides overlay management for the Kuro terminal emulator.
;; It handles blink text overlays, Kitty Graphics image overlays,
;; OSC 8 hyperlink overlays, OSC 133 prompt navigation, and focus events.
;;
;; # Responsibilities
;;
;; - Blink overlay creation and visibility toggling (SGR 5/6)
;; - Kitty Graphics Protocol image overlay rendering
;; - OSC 8 hyperlink overlay creation and key bindings
;; - OSC 133 prompt mark navigation (previous/next prompt)
;; - Focus event reporting to PTY (mode 1004)
;;
;; # Dependencies
;;
;; Depends on `kuro-ffi' for `kuro--get-image' and `kuro--send-key'.
;; Depends on `kuro-faces' for `kuro--apply-face-range' (FFI face application).

;;; Code:

(require 'kuro-ffi)
(require 'kuro-faces)

;;; Buffer-local state

(defvar-local kuro--blink-overlays nil
  "List of active blink overlays in the current kuro buffer.")
(put 'kuro--blink-overlays 'permanent-local t)

(defvar-local kuro--image-overlays nil
  "List of image display overlays in the current kuro buffer.
Each overlay has a `kuro-image' property and a `display' image spec.")
(put 'kuro--image-overlays 'permanent-local t)

(defvar-local kuro--blink-frame-count 0
  "Frame counter used for blink animation timing.")
(put 'kuro--blink-frame-count 'permanent-local t)

(defvar-local kuro--blink-visible-slow t
  "Non-nil when slow-blink text is currently in the visible phase.")
(put 'kuro--blink-visible-slow 'permanent-local t)

(defvar-local kuro--blink-visible-fast t
  "Non-nil when fast-blink text is currently in the visible phase.")
(put 'kuro--blink-visible-fast 'permanent-local t)

(defvar-local kuro--hyperlink-overlays nil
  "List of active hyperlink overlays in the current kuro buffer.")
(put 'kuro--hyperlink-overlays 'permanent-local t)

(defvar-local kuro--prompt-positions nil
  "List of (ROW . MARK-TYPE) for OSC 133 prompt marks.
MARK-TYPE is a symbol such as `prompt-start', `prompt-end',
`command-start', or `command-end'.  Updated each render cycle
by polling `kuro--poll-prompt-marks'.")
(put 'kuro--prompt-positions 'permanent-local t)

;;; Blink overlays

(defun kuro--apply-blink-overlay (start end blink-type)
  "Create a blink overlay covering buffer positions START to END.
BLINK-TYPE is the symbol `slow' or `fast', controlling which blink
visibility state variable is consulted."
  (let* ((visible (if (eq blink-type 'slow)
                      kuro--blink-visible-slow
                    kuro--blink-visible-fast))
         (ov (make-overlay start end)))
    (overlay-put ov 'kuro-blink t)
    (overlay-put ov 'kuro-blink-type blink-type)
    (overlay-put ov 'invisible (not visible))
    (push ov kuro--blink-overlays)))

(defun kuro--clear-line-blink-overlays (row)
  "Remove blink overlays on line ROW and remove them from `kuro--blink-overlays'."
  (save-excursion
    (goto-char (point-min))
    (forward-line row)
    (let ((line-start (point))
          (line-end (1+ (line-end-position)))
          (remaining nil))
      (dolist (ov kuro--blink-overlays)
        (if (and (overlay-buffer ov)
                 (>= (overlay-start ov) line-start)
                 (<= (overlay-end ov) line-end))
            (delete-overlay ov)
          (push ov remaining)))
      (setq kuro--blink-overlays (nreverse remaining)))))

(defun kuro--tick-blink-overlays ()
  "Advance the blink frame counter and toggle overlay visibility at correct intervals.
Slow blink (SGR 5): ~0.5 Hz — toggle every 30 frames at 30 fps (1 s per phase).
Fast blink (SGR 6): ~1.5 Hz — toggle every 10 frames at 30 fps (~0.33 s per phase).
Called once per render cycle from `kuro--render-cycle'."
  (setq kuro--blink-frame-count (1+ kuro--blink-frame-count))
  (when (zerop (mod kuro--blink-frame-count 30))
    (setq kuro--blink-visible-slow (not kuro--blink-visible-slow))
    (dolist (ov kuro--blink-overlays)
      (when (and (overlay-buffer ov)
                 (eq (overlay-get ov 'kuro-blink-type) 'slow))
        (overlay-put ov 'invisible (not kuro--blink-visible-slow)))))
  (when (zerop (mod kuro--blink-frame-count 10))
    (setq kuro--blink-visible-fast (not kuro--blink-visible-fast))
    (dolist (ov kuro--blink-overlays)
      (when (and (overlay-buffer ov)
                 (eq (overlay-get ov 'kuro-blink-type) 'fast))
        (overlay-put ov 'invisible (not kuro--blink-visible-fast))))))

;;; Image overlays (Kitty Graphics Protocol)

(defun kuro--clear-all-image-overlays ()
  "Remove all Kitty Graphics image overlays from the current buffer."
  (dolist (ov kuro--image-overlays)
    (when (overlay-buffer ov)
      (delete-overlay ov)))
  (setq kuro--image-overlays nil))

(defun kuro--clear-row-image-overlays (row)
  "Remove image overlays that start on ROW."
  (save-excursion
    (goto-char (point-min))
    (forward-line row)
    (let ((line-start (point))
          (line-end (1+ (line-end-position)))
          (remaining nil))
      (dolist (ov kuro--image-overlays)
        (if (and (overlay-buffer ov)
                 (>= (overlay-start ov) line-start)
                 (< (overlay-start ov) line-end))
            (delete-overlay ov)
          (push ov remaining)))
      (setq kuro--image-overlays (nreverse remaining)))))

(defun kuro--render-image-notification (notif)
  "Render a single Kitty Graphics image placement NOTIF in the terminal buffer.
NOTIF is a list of the form (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT).
Creates an overlay with a `display' image property at the correct grid position."
  (let* ((image-id   (nth 0 notif))
         (row        (nth 1 notif))
         (col        (nth 2 notif))
         (cell-width (max 1 (nth 3 notif)))
         (b64        (kuro--get-image image-id)))
    (when (and b64 (stringp b64) (not (string-empty-p b64)))
      (condition-case err
          (let* (                 ;; Decode base64 → raw PNG bytes (binary string)
                 (png-data (encode-coding-string (base64-decode-string b64) 'binary))
                 ;; Build Emacs image object
                 (img      (create-image png-data 'png t))
                 ;; Locate buffer position for (row, col)
                 ;; Use forward-char rather than (+ line-pos col) so wide characters
                 ;; (which occupy 2 terminal columns but 1 buffer position) are handled correctly.
                 (start    (save-excursion
                             (goto-char (point-min))
                             (forward-line row)
                             (forward-char col)
                             (point)))
                 ;; Span cell-width characters so the image occludes the right cells
                 (end      (+ start cell-width)))
            (when (and img (< start (point-max)))
              (let ((ov (make-overlay start (min end (point-max)))))
                (overlay-put ov 'kuro-image    t)
                (overlay-put ov 'display       img)
                (overlay-put ov 'evaporate     t)  ; auto-delete if region deleted
                (push ov kuro--image-overlays))))
        (error
         (message "kuro: image render error for id %d: %s" image-id err))))))

;;; Hyperlink overlays (OSC 8)

(defun kuro--clear-all-hyperlink-overlays ()
  "Remove all hyperlink overlays from the current buffer."
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
  "Create a hyperlink overlay from START to END pointing to URI."
  (let ((ov (make-overlay start end)))
    (overlay-put ov 'kuro-hyperlink t)
    (overlay-put ov 'help-echo (format "URI: %s\nRET or mouse-1 to open" uri))
    (overlay-put ov 'mouse-face 'highlight)
    (overlay-put ov 'keymap (kuro--make-hyperlink-keymap uri))
    (push ov kuro--hyperlink-overlays)))

;;; Prompt navigation (OSC 133)

(defun kuro-previous-prompt ()
  "Jump to the previous shell prompt (OSC 133 mark)."
  (interactive)
  (let* ((cur-line (1- (line-number-at-pos)))
         (candidates
          (seq-filter (lambda (entry)
                        (and (< (car entry) cur-line)
                             (eq (cdr entry) 'prompt-start)))
                      kuro--prompt-positions))
         (target (car (last candidates))))
    (if target
        (progn
          (goto-char (point-min))
          (forward-line (car target)))
      (message "kuro: no previous prompt"))))

(defun kuro-next-prompt ()
  "Jump to the next shell prompt (OSC 133 mark)."
  (interactive)
  (let* ((cur-line (1- (line-number-at-pos)))
         (candidates
          (seq-filter (lambda (entry)
                        (and (> (car entry) cur-line)
                             (eq (cdr entry) 'prompt-start)))
                      kuro--prompt-positions))
         (target (car candidates)))
    (if target
        (progn
          (goto-char (point-min))
          (forward-line (car target)))
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

;;; FFI face application with blink and hidden support

(defun kuro--apply-faces-from-ffi (line-num face-ranges)
  "Apply SGR faces from FFI data to LINE-NUM.
LINE-NUM is the 0-indexed line number.
FACE-RANGES is a list of (START-COL END-COL FG BG FLAGS) or
\(START-COL END-COL FG BG FLAGS UL-COLOR) tuples.
The optional 6th element UL-COLOR is an encoded underline color (u32, same
encoding as FG/BG) or 0/#xFF000000 for default (no underline color)."
  (save-excursion
    (goto-char (point-min))
    (forward-line line-num)
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t)
          (line-start (point))
          (line-end (line-end-position)))
      (dolist (range face-ranges)
        (let* ((start-col (car range))
               (end-col (cadr range))
               (fg-enc (caddr range))
               (bg-enc (cadddr range))
               (rest (cddddr range))
               (flags (or (car rest) 0))
               (ul-color-enc (cadr rest)))
          ;; Fast path: skip face application when this range is completely
          ;; default-styled (no color, no attributes).  In a typical shell
          ;; session the majority of cells are unstyled; skipping them
          ;; reduces add-text-properties calls by 60-80% on plain output.
          (unless (and (= fg-enc #xFF000000)
                       (= bg-enc #xFF000000)
                       (= flags 0)
                       (or (null ul-color-enc)
                           (= ul-color-enc 0)
                           (= ul-color-enc #xFF000000)))
            (let* ((fg (kuro--decode-ffi-color fg-enc))
                   (bg (kuro--decode-ffi-color bg-enc))
                   (ul-color (when (and ul-color-enc
                                        (/= ul-color-enc 0)
                                        (/= ul-color-enc #xFF000000))
                               (kuro--rgb-to-emacs
                                (logand ul-color-enc #xFFFFFF))))
                   (start-pos (min (+ line-start start-col) line-end))
                   (end-pos (min (+ line-start end-col) line-end)))
              (when (> end-pos start-pos)
                (kuro--apply-face-range start-pos end-pos
                                        (list :foreground fg
                                              :background bg
                                              :flags flags
                                              :underline-color ul-color))
                (cond
                 ((/= 0 (logand flags #x20))
                  (kuro--apply-blink-overlay start-pos end-pos 'fast))
                 ((/= 0 (logand flags #x10))
                  (kuro--apply-blink-overlay start-pos end-pos 'slow)))
                (when (/= 0 (logand flags #x80))
                  (add-text-properties start-pos end-pos '(invisible t)))))))))))

(provide 'kuro-overlays)

;;; kuro-overlays.el ends here
