;;; kuro-renderer.el --- Render loop and buffer management for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file provides the render loop and buffer update functions for Kuro.
;; It manages the Emacs buffer display and updates based on terminal state.

;;; Code:

(require 'kuro-ffi)
(require 'kuro-input)
(require 'kuro-config)

;; Bell functions provided by the Rust dynamic module at runtime.
(declare-function kuro-core-bell-pending  "ext:kuro-core" ())
(declare-function kuro-core-clear-bell   "ext:kuro-core" ())

(defvar-local kuro-timer nil
  "Timer object for the Kuro render loop.
Internal state; do not set directly.
Each Kuro buffer maintains its own independent timer.")
(put 'kuro-timer 'permanent-local t)

(defvar-local kuro--cursor-marker nil
  "Marker for cursor position.")
(put 'kuro--cursor-marker 'permanent-local t)

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

(defvar-local kuro--decckm-frame-count 9
  "Frame counter used for DECCKM/mouse polling backoff (poll every 10 frames).
Initialized to 9 so the first render frame triggers an immediate poll.")
(put 'kuro--decckm-frame-count 'permanent-local t)

(defvar-local kuro--blink-visible-slow t
  "Non-nil when slow-blink text is currently in the visible phase.")
(put 'kuro--blink-visible-slow 'permanent-local t)

(defvar-local kuro--blink-visible-fast t
  "Non-nil when fast-blink text is currently in the visible phase.")
(put 'kuro--blink-visible-fast 'permanent-local t)

;;; Face cache and color support

(defvar kuro--face-cache (make-hash-table :test 'equal)
  "Cache computed faces to avoid recreating them for same attribute combinations.")

(defvar-local kuro--font-remap-cookie nil
  "Cookie returned by `face-remap-add-relative' for font customization.
Stored per-buffer so the remap can be cleanly removed when settings change
or when the buffer is killed.  Internal state; do not set directly.")
(put 'kuro--font-remap-cookie 'permanent-local t)

(defvar kuro--truecolor-available-p nil
  "Cached result of checking TrueColor support.")


;;;###autoload
(defun kuro--check-truecolor ()
  "Check if Emacs supports TrueColor (24-bit colors)."
  (or (display-graphic-p)
      (and (>= (display-color-cells) 16777216)
           (setq kuro--truecolor-available-p t))))

(defun kuro--apply-font-to-buffer (buf)
  "Apply `kuro-font-family' and `kuro-font-size' settings to BUF.
Uses `face-remap-add-relative' to override the default face in the buffer.
Removes any previously installed remap cookie before applying a new one.
This function is a no-op in non-graphical (terminal) Emacs frames."
  (when (display-graphic-p)
    (with-current-buffer buf
      (when kuro--font-remap-cookie
        (face-remap-remove-relative kuro--font-remap-cookie)
        (setq kuro--font-remap-cookie nil))
      (when (or kuro-font-family kuro-font-size)
        (setq kuro--font-remap-cookie
              (apply #'face-remap-add-relative
                     'default
                     (append
                      (when kuro-font-family (list :family kuro-font-family))
                      (when kuro-font-size   (list :height (* 10 kuro-font-size))))))))))

;;; Color conversion functions

(defun kuro--color-to-emacs (color)
  "Convert Rust Color enum value to Emacs color string or nil.
COLOR can be:
  - :default for default color (returns nil)
  - A cons cell (named . color-name) for named colors
  - A cons cell (indexed . index) for 256-color palette
  - A cons cell (rgb . rgb-value) for truecolor (24-bit RGB)"
  (pcase color
    (:default nil)
    ((pred consp)
     (pcase (car color)
       ('named (cdr (assoc (cdr color) kuro--named-colors)))
       ('indexed (kuro--indexed-to-emacs (cdr color)))
       ('rgb (kuro--rgb-to-emacs (cdr color)))))
    (_ nil)))

(defun kuro--indexed-to-emacs (idx)
  "Convert 256-color palette index to Emacs color string."
  (cond
   ((<= idx 15)
    (let* ((names ["black" "red" "green" "yellow"
                   "blue" "magenta" "cyan" "white"
                   "bright-black" "bright-red" "bright-green" "bright-yellow"
                   "bright-blue" "bright-magenta" "bright-cyan" "bright-white"])
           (name (aref names idx)))
      (cdr (assoc name kuro--named-colors))))
   ((<= idx 231)
    (let* ((n (- idx 16))
           (r (* (floor (/ n 36)) 51))
           (g (* (mod (floor (/ n 6)) 6) 51))
           (b (* (mod n 6) 51)))
      (format "#%02x%02x%02x" r g b)))
   ((<= idx 255)
    (let* ((n (- idx 232))
           (v (+ (* n 10) 8)))
      (format "#%02x%02x%02x" v v v)))
   (t nil)))

(defun kuro--rgb-to-emacs (rgb-value)
  "Convert 24-bit RGB value to Emacs color string."
  (let ((r (logand (ash rgb-value -16) #xFF))
        (g (logand (ash rgb-value -8)  #xFF))
        (b (logand rgb-value            #xFF)))
    (format "#%02x%02x%02x" r g b)))

;;; Attribute decoding functions

(defun kuro--decode-attrs (attr-flags)
  "Decode attribute bit flags from Rust core into individual boolean values.
ATTR-FLAGS is a bitmask matching Rust encode_attrs:
  bit 0  (0x001) = bold
  bit 1  (0x002) = dim
  bit 2  (0x004) = italic
  bit 3  (0x008) = underline (any style)
  bit 4  (0x010) = blink-slow
  bit 5  (0x020) = blink-fast
  bit 6  (0x040) = inverse
  bit 7  (0x080) = hidden
  bit 8  (0x100) = strikethrough
  bits 9-11 (0xE00, shift 9) = underline style:
    0 = None, 1 = Straight, 2 = Double, 3 = Curly, 4 = Dotted, 5 = Dashed
Use (/= 0 ...) to produce t/nil booleans — in Elisp, 0 is truthy, only nil is falsy."
  (let ((bold           (/= 0 (logand attr-flags #x01)))
        (dim            (/= 0 (logand attr-flags #x02)))
        (italic         (/= 0 (logand attr-flags #x04)))
        (underline      (/= 0 (logand attr-flags #x08)))
        (blink-slow     (/= 0 (logand attr-flags #x10)))
        (blink-fast     (/= 0 (logand attr-flags #x20)))
        (inverse        (/= 0 (logand attr-flags #x40)))
        (hidden         (/= 0 (logand attr-flags #x80)))
        (strikethrough  (/= 0 (logand attr-flags #x100)))
        ;; Underline style: bits 9-11 (mask 0xE00, shift right 9)
        ;; 0=None, 1=Straight, 2=Double, 3=Curly, 4=Dotted, 5=Dashed
        (underline-style (ash (logand attr-flags #xE00) -9)))
    (list :bold bold
          :italic italic
          :underline underline
          :underline-style underline-style
          :strike-through strikethrough
          :inverse inverse
          :dim dim
          :blink-slow blink-slow
          :blink-fast blink-fast
          :hidden hidden)))

(defun kuro--underline-style-to-face-prop (style underline-color)
  "Convert underline STYLE integer and UNDERLINE-COLOR to an Emacs :underline value.
STYLE is the decoded underline style integer (0-5):
  0 = None (no underline)
  1 = Straight
  2 = Double
  3 = Curly (undercurl / wave)
  4 = Dotted
  5 = Dashed
UNDERLINE-COLOR is an Emacs color string or nil.
Returns the value for the :underline face attribute, or nil for no underline."
  (pcase style
    (0 nil)   ; None
    (1 (if underline-color
           (list :color underline-color :style 'line)
         t))
    (2 (if underline-color
           (list :color underline-color :style 'line)
         ;; Emacs 29+ supports double underline via :style 'double-line
         ;; Fall back to plain underline on older versions
         (if (boundp 'face-underline-style)
             (list :style 'double-line)
           t)))
    (3 (if underline-color
           (list :color underline-color :style 'wave)
         (list :style 'wave)))
    (4 (if underline-color
           (list :color underline-color :style 'dots)
         ;; :style 'dots is Emacs 29+; fall back to plain underline
         (if (boundp 'face-underline-style)
             (list :style 'dots)
           t)))
    (5 (if underline-color
           (list :color underline-color :style 'dashes)
         ;; :style 'dashes is Emacs 29+; fall back to plain underline
         (if (boundp 'face-underline-style)
             (list :style 'dashes)
           t)))
    (_ t)))  ; Unknown style: plain underline

(defun kuro--attrs-to-face-props (attrs)
  "Convert SGR attributes plist to Emacs face property list.
ATTRS is a plist with keys :foreground, :background, :flags, and
optionally :underline-color (an Emacs color string for the underline)."
  (let* ((fg (plist-get attrs :foreground))
         (bg (plist-get attrs :background))
         (fg-color (kuro--color-to-emacs fg))
         (bg-color (kuro--color-to-emacs bg))
         (flags (plist-get attrs :flags))
         (decoded (kuro--decode-attrs (or flags 0)))
         (bold (plist-get decoded :bold))
         (italic (plist-get decoded :italic))
         (underline (plist-get decoded :underline))
         (underline-style (plist-get decoded :underline-style))
         (strikethrough (plist-get decoded :strike-through))
         (inverse (plist-get decoded :inverse))
         (dim (plist-get decoded :dim))
         (underline-color (plist-get attrs :underline-color))
         (weight (cond (bold 'bold) (dim 'light) (t 'normal)))
         (slant (if italic 'italic 'normal))
         ;; Build :underline value: prefer explicit style if underline bit is set
         (underline-val
          (when underline
            (if (and underline-style (> underline-style 0))
                (kuro--underline-style-to-face-prop underline-style underline-color)
              ;; Straight underline (style 0 or no style bits set)
              (if underline-color
                  (list :color underline-color :style 'line)
                t)))))
    (nconc
     (when fg-color (list :foreground fg-color))
     (when bg-color (list :background bg-color))
     (list :weight weight :slant slant)
     (when underline-val (list :underline underline-val))
     (when strikethrough (list :strike-through t))
     (when inverse (list :inverse-video t)))))

;;; Face caching

(defun kuro--make-face (attrs)
  "Create an Emacs face from attribute plist."
  (let ((props (kuro--attrs-to-face-props attrs)))
    (list props)))

(defun kuro--get-cached-face (attrs)
  "Get or create a cached face for given attributes.
ATTRS is a plist containing :foreground, :background, :flags, and
optionally :underline-color."
  (let ((key (list (plist-get attrs :foreground)
                   (plist-get attrs :background)
                   (plist-get attrs :flags)
                   (plist-get attrs :underline-color))))
    (or (gethash key kuro--face-cache)
        (puthash key (kuro--make-face attrs) kuro--face-cache))))

(defun kuro--clear-face-cache ()
  "Clear the face cache to free memory."
  (clrhash kuro--face-cache))

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
  "Remove blink overlays on line ROW and remove them from kuro--blink-overlays."
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
          (let* (;; Decode base64 → raw PNG bytes (unibyte string)
                 (png-data (string-as-unibyte (base64-decode-string b64)))
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

;;; Face application functions

(defun kuro--apply-face-range (start end attrs)
  "Apply a face to a character range with given SGR attributes.
START and END are buffer positions.  ATTRS is a plist with
:foreground, :background, and :flags keys."
  (let ((face (kuro--get-cached-face attrs)))
    (add-text-properties start end `(face ,face))))

(defun kuro--apply-faces (line-num face-ranges)
  "Apply SGR faces to a line based on face ranges from Rust core.
LINE-NUM is the 0-indexed line number.
FACE-RANGES is a list of (START . (END . ATTRS)) where START and END
are column positions (0-indexed) and ATTRS is a plist with SGR attributes."
  (save-excursion
    (goto-char (point-min))
    (forward-line line-num)
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t)
          (line-start (point))
          (line-end (line-end-position)))
      (dolist (face-range face-ranges)
        (let* ((start-col (car face-range))
               (end-col (car (cdr face-range)))
               (attrs (cdr (cdr face-range)))
               (start-pos (min (+ line-start start-col) line-end))
               (end-pos (min (+ line-start end-col) line-end)))
          (when (> end-pos start-pos)
            (kuro--apply-face-range start-pos end-pos attrs)))))))

;;; Prompt navigation (OSC 133)

(defvar-local kuro--prompt-positions nil
  "List of (ROW . MARK-TYPE) for OSC 133 prompt marks.
MARK-TYPE is a symbol such as `prompt-start', `prompt-end',
`command-start', or `command-end'.  Updated each render cycle
by polling `kuro--poll-prompt-marks'.")
(put 'kuro--prompt-positions 'permanent-local t)

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

;;; Hyperlink overlays (OSC 8)

(defvar-local kuro--hyperlink-overlays nil
  "List of active hyperlink overlays in the current kuro buffer.")
(put 'kuro--hyperlink-overlays 'permanent-local t)

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

;;; Render loop

(defun kuro--sanitize-title (title)
  "Sanitize TITLE string from PTY before using as buffer/frame name.
Strips ASCII control characters (U+0000-U+001F, U+007F), null bytes,
and Unicode bidirectional override codepoints (U+202A-U+202E, U+2066-U+2069)
to prevent visual spoofing attacks via malicious OSC title sequences."
  (replace-regexp-in-string
   "[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069\u200f]" "" title))

;;;###autoload
(defun kuro--start-render-loop ()
  "Start the render loop targeting the current buffer."
  (when (timerp kuro-timer)
    (cancel-timer kuro-timer))
  (let ((buf (current-buffer)))
    (setq kuro-timer
          (run-with-timer
           0
           (/ 1.0 kuro-frame-rate)
           (lambda () (when (buffer-live-p buf)
                        (with-current-buffer buf
                          (kuro--render-cycle))))))))

;;;###autoload
(defun kuro--stop-render-loop ()
  "Stop the render loop."
  (when (timerp kuro-timer)
    (cancel-timer kuro-timer)
    (setq kuro-timer nil)))

;;;###autoload
(defun kuro--render-cycle ()
  "Single render cycle: poll updates and update buffer."
  (setq kuro--decckm-frame-count (1+ kuro--decckm-frame-count))
  (when (zerop (mod kuro--decckm-frame-count 10))
    (setq kuro--application-cursor-keys-mode (kuro--get-app-cursor-keys))
    (setq kuro--app-keypad-mode (kuro--get-app-keypad))
    (setq kuro--mouse-mode (kuro--get-mouse-mode))
    (setq kuro--mouse-sgr (kuro--get-mouse-sgr))
    (setq kuro--bracketed-paste-mode (kuro--get-bracketed-paste))
    (setq kuro--keyboard-flags (or (kuro--get-keyboard-flags) 0)))
  (when (kuro-core-bell-pending)
    (ding)
    (kuro-core-clear-bell))
  ;; Advance frame counter and toggle blink states at correct intervals.
  ;; Slow blink (SGR 5): ~0.5 Hz — toggle every 30 frames at 30 fps (1 s per phase).
  ;; Fast blink (SGR 6): ~1.5 Hz — toggle every 10 frames at 30 fps (~0.33 s per phase).
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
        (overlay-put ov 'invisible (not kuro--blink-visible-fast)))))
  ;; Window title update (called every frame; Rust-side dirty flag gates cost)
  (let ((title (kuro--get-and-clear-title)))
    (when (and (stringp title) (not (string-empty-p title)))
      (let ((safe-title (kuro--sanitize-title title)))
        (rename-buffer (format "*kuro: %s*" safe-title) t)
        (let ((win (get-buffer-window (current-buffer) t)))
          (when win
            (set-frame-parameter (window-frame win) 'name safe-title))))))
  ;; Update default-directory from OSC 7 CWD notification
  (let ((cwd (kuro--get-cwd)))
    (when (and cwd (stringp cwd) (not (string-empty-p cwd)))
      (setq default-directory (file-name-as-directory cwd))))
  ;; Process OSC 52 clipboard actions
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
  ;; Collect OSC 133 prompt marks
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
  ;; Process dirty lines: clear per-line blink overlays before rewriting,
  ;; then rebuild faces (including new blink overlays) for each updated line.
  ;; Overlays on lines NOT in this update batch are preserved intact.
  (let ((updates (kuro--poll-updates-with-faces)))
    (when updates
      (dolist (line-update updates)
        (let ((line-data (car line-update))
              (face-ranges (cdr line-update)))
          (let ((row (car line-data))
                (text (cdr line-data)))
            (kuro--clear-line-blink-overlays row)
            (kuro--update-line row text)
            (when face-ranges
              (kuro--apply-faces-from-ffi row face-ranges))))))
    (kuro--update-cursor))
  ;; Poll and render Kitty Graphics image placements
  (let ((image-notifs (kuro--poll-image-notifications)))
    (dolist (notif image-notifs)
      (kuro--render-image-notification notif))))

;;;###autoload
(defun kuro--update-line (row text)
  "Update line at ROW with TEXT."
  (when (and (integerp row) (stringp text))
    ;; Remove any image overlays on this row before rewriting the line text
    (kuro--clear-row-image-overlays row)
    (save-excursion
      (goto-char (point-min))
      (forward-line row)
      (let ((inhibit-read-only t)
            (inhibit-modification-hooks t))
        ;; Delete the entire line INCLUDING its newline to prevent double-\n
        ;; accumulation: (line-end-position) points AT the \n, so 1+ is needed.
        (delete-region (point) (min (1+ (line-end-position)) (point-max)))
        (insert text)
        (insert "\n")))))

;;;###autoload
(defun kuro--update-cursor ()
  "Update cursor position and shape in buffer."
  (unless (> kuro--scroll-offset 0)
    (let ((cursor-pos (kuro--get-cursor)))
      (when cursor-pos
        (let ((row (car cursor-pos))
              (col (cdr cursor-pos)))
          (save-excursion
            (goto-char (point-min))
            (forward-line row)
            ;; Clamp column to line-end to avoid end-of-buffer signal
            (goto-char (min (+ (point) col) (line-end-position)))
            (when kuro--cursor-marker
              (set-marker kuro--cursor-marker (point)))))
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
  "Apply text properties/faces based on UPDATES.
UPDATES should be a list of (LINE-NUM . FACE-RANGES) pairs."
  (dolist (line-update updates)
    (kuro--apply-faces (car line-update) (cdr line-update))))

;;; FFI color decoding functions

(defun kuro--decode-ffi-color (color-enc)
  "Decode FFI color encoding to Emacs color spec.
COLOR-ENC is a u32 value encoding the color:
  - #xFF000000 for default color (sentinel, distinct from true black)
  - Bit 31 set: named color (lower 8 bits = index)
  - Bit 30 set: indexed color (lower 8 bits = index)
  - Otherwise: RGB packed into 24 bits (RRGGBB); 0 = true black Rgb(0,0,0)"
  (cond
   ((= color-enc #xFF000000)
    :default)
   ((/= 0 (logand color-enc #x80000000))
    (let* ((idx (logand color-enc #xFF))
           (names ["black" "red" "green" "yellow"
                   "blue" "magenta" "cyan" "white"
                   "bright-black" "bright-red" "bright-green" "bright-yellow"
                   "bright-blue" "bright-magenta" "bright-cyan" "bright-white"])
           (name (aref names idx)))
      (cons 'named name)))
   ((/= 0 (logand color-enc #x40000000))
    (cons 'indexed (logand color-enc #xFF)))
   (t
    (let ((r (logand (ash color-enc -16) #xFF))
          (g (logand (ash color-enc -8)  #xFF))
          (b (logand color-enc            #xFF)))
      (cons 'rgb (logior (ash r 16) (ash g 8) b))))))

(defun kuro--apply-faces-from-ffi (line-num face-ranges)
  "Apply SGR faces from FFI data to a line.
LINE-NUM is the 0-indexed line number.
FACE-RANGES is a list of (START-COL END-COL FG BG FLAGS) or
(START-COL END-COL FG BG FLAGS UL-COLOR) tuples.
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
               (ul-color-enc (cadr rest))
               (fg (kuro--decode-ffi-color fg-enc))
               (bg (kuro--decode-ffi-color bg-enc))
               ;; Decode underline color: nil means use default (no color override)
               (ul-color (when (and ul-color-enc
                                    (/= ul-color-enc 0)
                                    (/= ul-color-enc #xFF000000))
                           (kuro--rgb-to-emacs
                            (logand ul-color-enc #xFFFFFF))))
               ;; Cap positions at line-end to prevent face bleeding into next line
               (start-pos (min (+ line-start start-col) line-end))
               (end-pos (min (+ line-start end-col) line-end)))
          (when (> end-pos start-pos)
            (kuro--apply-face-range start-pos end-pos
                                    (list :foreground fg
                                          :background bg
                                          :flags flags
                                          :underline-color ul-color))
            ;; Apply blink overlay (fast takes priority over slow)
            (cond
             ((/= 0 (logand flags #x20))
              (kuro--apply-blink-overlay start-pos end-pos 'fast))
             ((/= 0 (logand flags #x10))
              (kuro--apply-blink-overlay start-pos end-pos 'slow)))
            ;; Apply hidden (invisible) as a direct text property
            (when (/= 0 (logand flags #x80))
              (add-text-properties start-pos end-pos '(invisible t)))))))))

(provide 'kuro-renderer)

;;; kuro-renderer.el ends here
