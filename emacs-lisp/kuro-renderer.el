;;; kuro-renderer.el --- Render loop and buffer management for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides the render loop and buffer update functions for Kuro.
;; It manages the Emacs buffer display and updates based on terminal state.
;;
;; # Responsibilities
;;
;; - Timer-based render loop lifecycle (start/stop)
;; - Per-frame render cycle: dirty line updates, cursor, title, CWD,
;;   clipboard (OSC 52), prompt marks (OSC 133), Kitty Graphics images
;; - Cursor position and shape updates
;; - Window title sanitization
;;
;; # Architecture
;;
;; Color conversion and face caching are in `kuro-faces'.
;; Overlay management (blink, image, hyperlink) is in `kuro-overlays'.
;; Input handling is in `kuro-input'.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-input)
(require 'kuro-config)
(require 'kuro-faces)
(require 'kuro-overlays)
(require 'kuro-stream)

;; Bell functions provided by the Rust dynamic module at runtime.
(declare-function kuro-core-bell-pending  "ext:kuro-core" ())
(declare-function kuro-core-clear-bell   "ext:kuro-core" ())

;;; Buffer-local render state

(defvar-local kuro-timer nil
  "Timer object for the Kuro render loop.
Internal state; do not set directly.
Each Kuro buffer maintains its own independent timer.")
(put 'kuro-timer 'permanent-local t)

(defvar-local kuro--cursor-marker nil
  "Marker for cursor position.")
(put 'kuro--cursor-marker 'permanent-local t)

(defvar-local kuro--decckm-frame-count 9
  "Frame counter used for DECCKM/mouse polling backoff (poll every 10 frames).
Initialized to 9 so the first render frame triggers an immediate poll.")
(put 'kuro--decckm-frame-count 'permanent-local t)

;;; Render loop lifecycle

;;;###autoload
(defun kuro--start-render-loop ()
  "Start the render loop targeting the current buffer.
Also starts the low-latency streaming idle timer when
`kuro-streaming-latency-mode' is non-nil."
  (when (timerp kuro-timer)
    (cancel-timer kuro-timer))
  (let ((buf (current-buffer)))
    (setq kuro-timer
          (run-with-timer
           0
           (/ 1.0 kuro-frame-rate)
           (lambda () (when (buffer-live-p buf)
                         (with-current-buffer buf
                           (kuro--render-cycle)))))))
  ;; Start the zero-delay idle timer for streaming latency reduction
  (kuro--start-stream-idle-timer))

;;;###autoload
(defun kuro--stop-render-loop ()
  "Stop the render loop and streaming idle timer."
  (when (timerp kuro-timer)
    (cancel-timer kuro-timer)
    (setq kuro-timer nil))
  (kuro--stop-stream-idle-timer))

;;; Utility functions

(defun kuro--sanitize-title (title)
  "Sanitize TITLE string from PTY before using as buffer/frame name.
Strips ASCII control characters (U+0000-U+001F, U+007F), null bytes,
and Unicode bidirectional override codepoints (U+202A-U+202E, U+2066-U+2069)
to prevent visual spoofing attacks via malicious OSC title sequences."
  (replace-regexp-in-string
   "[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069\u200f]" "" title))

;;; Render cycle

;;;###autoload
(defun kuro--render-cycle ()
  "Single render cycle: poll updates and update buffer."
  ;; --- Window size sync ---
  ;; Process any pending resize from `kuro--window-size-change'.
  ;; The hook sets `kuro--resize-pending' to (NEW-ROWS . NEW-COLS); the render
  ;; cycle is the single authority that calls `kuro--resize' and adjusts the
  ;; buffer, eliminating the previous race where both paths could resize.
  (when kuro--resize-pending
    (let ((new-rows (car kuro--resize-pending))
          (new-cols (cdr kuro--resize-pending)))
      (setq kuro--resize-pending nil)
      (when (and kuro--initialized (> new-rows 0) (> new-cols 0))
        (setq kuro--last-rows new-rows
              kuro--last-cols new-cols)
        (kuro--resize new-rows new-cols)
        ;; Adjust buffer line count to match new rows
        (let ((inhibit-read-only t)
              (current-rows (count-lines (point-min) (point-max))))
          (cond
           ((< current-rows new-rows)
            (save-excursion
              (goto-char (point-max))
              (dotimes (_ (- new-rows current-rows))
                (insert "\n"))))
           ((> current-rows new-rows)
            (save-excursion
              (goto-char (point-max))
              (dotimes (_ (- current-rows new-rows))
                (when (> (point) (point-min))
                  (forward-line -1)
                  (delete-region (line-end-position) (point-max)))))))))))
  ;; --- Mode polling (tiered cadence using kuro--decckm-frame-count) ---
  ;; Every 10 frames: mode queries + cursor shape + some OSC polls
  ;; Every 30 frames: rare OSC events (palette, default colors)
  ;; This reduces unconditional per-frame Mutex acquisitions from ~11 to ~5.
  (setq kuro--decckm-frame-count (1+ kuro--decckm-frame-count))
  (when (zerop (mod kuro--decckm-frame-count 10))
    ;; Terminal mode queries (changes are rare; 167ms lag is imperceptible)
    (setq kuro--application-cursor-keys-mode (kuro--get-app-cursor-keys))
    (setq kuro--app-keypad-mode (kuro--get-app-keypad))
    (setq kuro--mouse-mode (kuro--get-mouse-mode))
    (setq kuro--mouse-sgr (kuro--get-mouse-sgr))
    (setq kuro--mouse-pixel-mode (kuro--get-mouse-pixel))
    (setq kuro--bracketed-paste-mode (kuro--get-bracketed-paste))
    (setq kuro--keyboard-flags (or (kuro--get-keyboard-flags) 0))
    ;; Cursor shape (DECSCUSR): shape changes are rare application events
    ;; (vim entering/exiting insert mode, etc.); 167ms lag is imperceptible.
    ;; kuro--get-cursor-visible and kuro--get-cursor-shape are still called
    ;; every frame inside kuro--update-cursor — this only caches the values
    ;; used outside that path.  kuro--update-cursor remains unchanged.
    )
  (when (zerop (mod kuro--decckm-frame-count 10))
    ;; OSC polls at 10-frame cadence (167ms): user-triggered or shell-rate events
    (let ((cwd (kuro--get-cwd)))
      (when (and cwd (stringp cwd) (not (string-empty-p cwd)))
        (setq default-directory (file-name-as-directory cwd))))
    ;; Clipboard (OSC 52): user-triggered; 167ms lag acceptable (yes-or-no-p blocks anyway)
    (let ((actions (kuro--poll-clipboard-actions)))
      (dolist (action actions)
        (pcase (car action)
          ('write
           (pcase kuro-clipboard-policy
             ((or 'write-only 'allow)
              (kill-new (cdr action))
              (message "kuro: clipboard updated from terminal"))
             ('prompt
              (when (yes-or-no-p
                     (format "kuro: terminal wants to set clipboard (%d chars). Allow? "
                             (length (cdr action))))
                (kill-new (cdr action))))))
          ('query
           (pcase kuro-clipboard-policy
             ('allow
              (let ((text (condition-case nil (current-kill 0 t) (error ""))))
                (kuro--send-key
                 (format "\e]52;c;%s\a"
                         (base64-encode-string (or text "") t)))))
             ('prompt
              (when (yes-or-no-p "kuro: terminal wants to read clipboard. Allow? ")
                (let ((text (condition-case nil (current-kill 0 t) (error ""))))
                  (kuro--send-key
                   (format "\e]52;c;%s\a"
                           (base64-encode-string (or text "") t)))))))))))
    ;; Prompt marks (OSC 133): arrive with shell prompts; 167ms lag acceptable
    (let ((marks (kuro--poll-prompt-marks)))
      (when marks
        (dolist (mark marks)
          (push mark kuro--prompt-positions))
        (setq kuro--prompt-positions
              (seq-take
               (sort kuro--prompt-positions
                     (lambda (a b) (< (car a) (car b))))
               1000))))
    ;; Kitty Graphics image notifications: low-frequency async events
    (let ((image-notifs (kuro--poll-image-notifications)))
      (dolist (notif image-notifs)
        (kuro--render-image-notification notif))))
  (when (zerop (mod kuro--decckm-frame-count 30))
    ;; OSC 4/10/11/12: palette and default color changes occur at
    ;; user-action timescale (theme switch, startup); 500ms lag is invisible.
    (kuro--apply-palette-updates)
    (kuro--apply-default-colors))
  ;; --- Bell ---
  (when (kuro-core-bell-pending)
    (ding)
    (kuro-core-clear-bell))
  ;; --- Blink overlays ---
  (kuro--tick-blink-overlays)
  ;; --- Window title (OSC 2) ---
  (let ((title (kuro--get-and-clear-title)))
    (when (and (stringp title) (not (string-empty-p title)))
      (let ((safe-title (kuro--sanitize-title title)))
        (rename-buffer (format "*kuro: %s*" safe-title) t)
        (let ((win (get-buffer-window (current-buffer) t)))
          (when win
            (set-frame-parameter (window-frame win) 'name safe-title))))))
  ;; --- CWD (OSC 7) ---
  (let ((cwd (kuro--get-cwd)))
    (when (and cwd (stringp cwd) (not (string-empty-p cwd)))
      (setq default-directory (file-name-as-directory cwd))))
  ;; --- Clipboard (OSC 52) ---
  (let ((actions (kuro--poll-clipboard-actions)))
    (dolist (action actions)
      (pcase (car action)
        ('write
         (pcase kuro-clipboard-policy
           ((or 'write-only 'allow)
            (kill-new (cdr action))
            (message "kuro: clipboard updated from terminal"))
           ('prompt
            (when (yes-or-no-p
                   (format "kuro: terminal wants to set clipboard (%d chars). Allow? "
                           (length (cdr action))))
              (kill-new (cdr action))))))
        ('query
         (pcase kuro-clipboard-policy
           ('allow
            (let ((text (condition-case nil (current-kill 0 t) (error ""))))
              (kuro--send-key
               (format "\e]52;c;%s\a"
                       (base64-encode-string (or text "") t)))))
           ('prompt
            (when (yes-or-no-p "kuro: terminal wants to read clipboard. Allow? ")
              (let ((text (condition-case nil (current-kill 0 t) (error ""))))
                (kuro--send-key
                 (format "\e]52;c;%s\a"
                         (base64-encode-string (or text "") t)))))))))))
  ;; --- Prompt marks (OSC 133) ---
  (let ((marks (kuro--poll-prompt-marks)))
    (when marks
      (dolist (mark marks)
        (push mark kuro--prompt-positions))
      ;; Keep list sorted by row, bounded to last 1000 entries
      (setq kuro--prompt-positions
            (seq-take
             (sort kuro--prompt-positions
                   (lambda (a b) (< (car a) (car b))))
             1000))))
  ;; --- Dirty line updates ---
  ;; Clear per-line blink overlays before rewriting, then rebuild faces
  ;; (including new blink overlays) for each updated line.
  ;; Overlays on lines NOT in this update batch are preserved intact.
  ;;
  ;; FFI data structure (per line):
  ;;   (((row . text) . face-list) . col-to-buf-vector)
  ;; col-to-buf-vector maps grid column index → buffer char offset.
  ;; Face ranges use buffer offsets (not grid column indices).
  (let ((updates (kuro--poll-updates-with-faces)))
    (when updates
      (dolist (line-update updates)
        ;; line-update = (((row . text) . face-list) . col-to-buf-vector)
        (let* ((line-and-faces (car line-update))
               (col-to-buf    (cdr line-update))
               (line-data     (car line-and-faces))
               (face-ranges   (cdr line-and-faces))
               (row           (car line-data))
               (text          (cdr line-data)))
          ;; Save col→buf mapping for cursor placement.
          ;; We store per-row so kuro--update-cursor can look up the correct
          ;; row's mapping instead of only seeing the last dirty line's vector.
          (when (vectorp col-to-buf)
            (puthash row col-to-buf kuro--col-to-buf-map))
          (kuro--clear-line-blink-overlays row)
          (kuro--update-line row text)
          (when face-ranges
            (kuro--apply-faces-from-ffi row face-ranges)))))
    (kuro--update-cursor))
  ;; Evict stale col-to-buf entries outside terminal row range.
  ;; Guard kuro--last-rows > 0 to avoid spurious eviction before first resize.
  ;; 2x hysteresis: tolerate up to twice the current row count before evicting.
  (when (and (> kuro--last-rows 0)
             (> (hash-table-count kuro--col-to-buf-map) (* 2 kuro--last-rows)))
    (let ((max-row kuro--last-rows))
      (let (stale-keys)
        (maphash (lambda (k _v)
                   (when (>= k max-row)
                     (push k stale-keys)))
                 kuro--col-to-buf-map)
        (dolist (k stale-keys)
          (remhash k kuro--col-to-buf-map)))))
  ;; --- Kitty Graphics image placements ---
  (let ((image-notifs (kuro--poll-image-notifications)))
    (dolist (notif image-notifs)
      (kuro--render-image-notification notif)))
  ;; --- OSC 4 palette updates ---
  (kuro--apply-palette-updates)
  ;; --- OSC 10/11/12 default color changes ---
  (kuro--apply-default-colors))

;;; Buffer update functions

;;;###autoload
(defun kuro--update-line (row text)
  "Update line at ROW with TEXT."
  (when (and (integerp row) (stringp text))
    ;; Remove any image overlays on this row before rewriting the line text
    (kuro--clear-row-image-overlays row)
    (save-excursion
      (goto-char (point-min))
      (let ((not-moved (forward-line row)))
        (let ((inhibit-read-only t)
              (inhibit-modification-hooks t))
          ;; If forward-line couldn't reach ROW (buffer has fewer lines than
          ;; the terminal), append blank lines until we reach the target row.
          (when (> not-moved 0)
            (goto-char (point-max))
            ;; Ensure there is a newline at end before appending more lines
            (unless (and (> (point-max) (point-min))
                         (= (char-before) ?\n))
              (insert "\n"))
            (dotimes (_ not-moved)
              (insert "\n"))
            ;; Now navigate to the correct position
            (goto-char (point-min))
            (forward-line row))
          ;; Replace the entire content of this line (excluding trailing newline)
          (let ((line-start (point))
                (line-end (line-end-position)))
            ;; Delete only the content (not the trailing newline)
            (delete-region line-start line-end)
            (insert text)))))))

;;;###autoload
(defun kuro--update-cursor ()
  "Update cursor position and shape in buffer."
  (unless (> kuro--scroll-offset 0)
    (let ((cursor-pos (kuro--get-cursor)))
      (when cursor-pos
        (let* ((row (car cursor-pos))
               (col (cdr cursor-pos))
               ;; Convert grid column to buffer char offset using col_to_buf mapping.
               ;; col_to_buf[col] gives the buffer offset for cursor column col.
               ;; For pure ASCII lines, col == buf-offset; for CJK lines, col > buf-offset
               ;; because wide placeholder cells are skipped in the buffer.
               ;; We look up the per-row mapping from kuro--col-to-buf-map (a hash table
               ;; keyed by row number) so each row's mapping is independent.
               ;; If the vector is shorter than col (e.g. cursor past last content),
               ;; fall back to col (works for trailing spaces which are pure ASCII).
               (row-col-to-buf (gethash row kuro--col-to-buf-map))
               (buf-offset
                (if (and row-col-to-buf
                         (< col (length row-col-to-buf)))
                    (aref row-col-to-buf col)
                  col))
               (target-pos
                (save-excursion
                  (goto-char (point-min))
                  (forward-line row)
                  (let ((line-start (point))
                        (line-end (line-end-position)))
                    (goto-char (min (+ line-start buf-offset) line-end)))
                  (point))))
          (when kuro--cursor-marker
            (set-marker kuro--cursor-marker target-pos))
          ;; Keep the window anchored at point-min so the terminal viewport (rows 0..N-1)
          ;; always fills the Emacs window from top to bottom.  Without this, Emacs scrolls
          ;; automatically to keep `point' visible using its own heuristics — when a full-
          ;; screen app (vim, htop, …) moves the cursor to the last row, Emacs would scroll
          ;; the window down, hiding the top rows and showing only the bottom half of the
          ;; terminal content.  vterm avoids this by always calling set-window-start first.
          ;;
          ;; Do NOT anchor when the user is scrolled into the scrollback buffer —
          ;; the guard `unless (> kuro--scroll-offset 0)' at the top of this function
          ;; already prevents us from reaching here during scrollback, but be explicit.
          (let ((win (get-buffer-window (current-buffer) t)))
            (when win
              ;; Anchor display at point-min on every frame so full-screen apps
              ;; (htop, vim, …) fill the whole window.  set-window-start is called
              ;; without a NOFORCE argument (nil, the default) so Emacs honours
              ;; point-min as the window start.  It is called BEFORE set-window-point
              ;; so that point is placed within the already-anchored viewport; this
              ;; combination prevents Emacs from scrolling to keep the cursor visible
              ;; when a full-screen app moves it to the last row.
              ;; set-window-start MUST come before set-window-point.
              (unless (= (window-start win) (point-min))
                (set-window-start win (point-min)))
              (unless (= (window-point win) target-pos)
                (set-window-point win target-pos)))))
        (if (kuro--get-cursor-visible)
            ;; Apply cursor shape from terminal DECSCUSR (CSI Ps SP q)
            (let ((shape (or (kuro--get-cursor-shape) 0)))
              (setq-local cursor-type
                          (pcase shape
                            (0 'box)          ; default blinking block
                            (1 'box)          ; blinking block
                            (2 'box)          ; steady block
                            (3 '(hbar . 2))   ; blinking underline
                            (4 '(hbar . 2))   ; steady underline
                            (5 '(bar . 2))    ; blinking bar (I-beam)
                            (6 '(bar . 2))    ; steady bar (I-beam)
                            (_ 'box))))
          (setq-local cursor-type nil))))))

;;;###autoload
(defun kuro--apply-faces-simple (updates)
  "Apply text properties/faces based on UPDATES using the plist API.
UPDATES should be a list of (LINE-NUM . FACE-RANGES) pairs."
  (dolist (line-update updates)
    (kuro--apply-faces (car line-update) (cdr line-update))))

(provide 'kuro-renderer)

;;; kuro-renderer.el ends here
