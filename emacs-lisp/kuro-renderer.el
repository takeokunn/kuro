;;; kuro-renderer.el --- Render loop and buffer management for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 0.1.0

;;; Commentary:

;; This file provides the render loop and buffer update functions for Kuro.
;; It manages the Emacs buffer display and updates based on terminal state.

;;; Code:

(require 'kuro-ffi)

;; Bell functions provided by the Rust dynamic module at runtime.
(declare-function kuro-core-bell-pending  "ext:kuro-core" ())
(declare-function kuro-core-clear-bell   "ext:kuro-core" ())

(defcustom kuro-frame-rate 30
  "Frame rate for terminal rendering (frames per second)."
  :type 'integer
  :group 'kuro)

(defcustom kuro-timer nil
  "Timer for render loop.")
(put 'kuro-timer 'permanent-local t)

(defvar kuro--cursor-marker nil
  "Marker for cursor position.")
(put 'kuro--cursor-marker 'permanent-local t)

;;; Face cache and color support

(defvar kuro--face-cache (make-hash-table :test 'equal)
  "Cache computed faces to avoid recreating them for same attribute combinations.")

(defvar kuro--truecolor-available-p nil
  "Cached result of checking TrueColor support.")

(defconst kuro--named-colors
  '(("black" . "#000000")
    ("red" . "#c23621")
    ("green" . "#25bc24")
    ("yellow" . "#adad27")
    ("blue" . "#492ee1")
    ("magenta" . "#d338d3")
    ("cyan" . "#33bbc8")
    ("white" . "#cbcccd")
    ("bright-black" . "#808080")
    ("bright-red" . "#ff0000")
    ("bright-green" . "#00ff00")
    ("bright-yellow" . "#ffff00")
    ("bright-blue" . "#0000ff")
    ("bright-magenta" . "#ff00ff")
    ("bright-cyan" . "#00ffff")
    ("bright-white" . "#ffffff"))
  "Mapping of named ANSI colors to hex strings.")

;;;###autoload
(defun kuro--check-truecolor ()
  "Check if Emacs supports TrueColor (24-bit colors)."
  (or (display-graphic-p)
      (and (>= (display-color-cells) 16777216)
           (setq kuro--truecolor-available-p t))))

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
  (let ((r (logand rgb-value 255))
        (g (logand (ash rgb-value -8) 255))
        (b (logand (ash rgb-value -16) 255)))
    (format "#%02x%02x%02x" r g b)))

;;; Attribute decoding functions

(defun kuro--decode-attrs (attr-flags)
  "Decode attribute bit flags from Rust core into individual boolean values.
ATTR-FLAGS is a bitmask matching Rust encode_attrs:
  bit 0 (0x01) = bold
  bit 1 (0x02) = dim
  bit 2 (0x04) = italic
  bit 3 (0x08) = underline
  bit 4 (0x10) = blink-slow
  bit 5 (0x20) = blink-fast
  bit 6 (0x40) = inverse
  bit 7 (0x80) = hidden
  bit 8 (0x100) = strikethrough
Use (/= 0 ...) to produce t/nil booleans — in Elisp, 0 is truthy, only nil is falsy."
  (let ((bold          (/= 0 (logand attr-flags #x01)))
        (dim           (/= 0 (logand attr-flags #x02)))
        (italic        (/= 0 (logand attr-flags #x04)))
        (underline     (/= 0 (logand attr-flags #x08)))
        (inverse       (/= 0 (logand attr-flags #x40)))
        (strikethrough (/= 0 (logand attr-flags #x100))))
    (list :bold bold
          :italic italic
          :underline underline
          :strike-through strikethrough
          :inverse inverse
          :dim dim)))

(defun kuro--attrs-to-face-props (attrs)
  "Convert SGR attributes plist to Emacs face property list.
ATTRS is a plist with keys :foreground, :background, and :flags."
  (let* ((fg (plist-get attrs :foreground))
         (bg (plist-get attrs :background))
         (fg-color (kuro--color-to-emacs fg))
         (bg-color (kuro--color-to-emacs bg))
         (flags (plist-get attrs :flags))
         (decoded (kuro--decode-attrs (or flags 0)))
         (bold (plist-get decoded :bold))
         (italic (plist-get decoded :italic))
         (underline (plist-get decoded :underline))
         (strikethrough (plist-get decoded :strike-through))
         (inverse (plist-get decoded :inverse))
         (dim (plist-get decoded :dim))
         (weight (cond (bold 'bold) (dim 'light) (t 'normal)))
         (slant (if italic 'italic 'normal)))
    (nconc
     (when fg-color (list :foreground fg-color))
     (when bg-color (list :background bg-color))
     (list :weight weight :slant slant)
     (when underline (list :underline t))
     (when strikethrough (list :strike-through t))
     (when inverse (list :inverse-video t)))))

;;; Face caching

(defun kuro--make-face (attrs)
  "Create an Emacs face from attribute plist."
  (let ((props (kuro--attrs-to-face-props attrs)))
    (list props)))

(defun kuro--get-cached-face (attrs)
  "Get or create a cached face for given attributes.
ATTRS is a plist containing :foreground, :background, and :flags."
  (let ((key (list (plist-get attrs :foreground)
                   (plist-get attrs :background)
                   (plist-get attrs :flags))))
    (or (gethash key kuro--face-cache)
        (puthash key (kuro--make-face attrs) kuro--face-cache))))

(defun kuro--clear-face-cache ()
  "Clear the face cache to free memory."
  (clrhash kuro--face-cache))

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

;;; Render loop

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
  (when (kuro-core-bell-pending)
    (ding)
    (kuro-core-clear-bell))
  (let ((updates (kuro--poll-updates-with-faces)))
    (when updates
      (dolist (line-update updates)
        (let ((line-data (car line-update))
              (face-ranges (cdr line-update)))
          (let ((row (car line-data))
                (text (cdr line-data)))
            (kuro--update-line row text)
            (when face-ranges
              (kuro--apply-faces-from-ffi row face-ranges))))))
    (kuro--update-cursor)))

;;;###autoload
(defun kuro--update-line (row text)
  "Update line at ROW with TEXT."
  (when (and (integerp row) (stringp text))
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
  "Update cursor position in buffer."
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
            (set-marker kuro--cursor-marker (point))))))))

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
  - 0 for default color
  - Bit 31 set: named color (lower 8 bits = index)
  - Bit 30 set: indexed color (lower 8 bits = index)
  - Otherwise: RGB packed into 24 bits (RRGGBB)"
  (cond
   ((= color-enc 0)
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
    (let ((r (logand color-enc #xFF))
          (g (logand (ash color-enc -8) #xFF))
          (b (logand (ash color-enc -16) #xFF)))
      (cons 'rgb (logior r (ash g 8) (ash b 16)))))))

(defun kuro--apply-faces-from-ffi (line-num face-ranges)
  "Apply SGR faces from FFI data to a line.
LINE-NUM is the 0-indexed line number.
FACE-RANGES is a list of (START-COL END-COL FG BG FLAGS) tuples."
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
               (flags (car (cddddr range)))
               (fg (kuro--decode-ffi-color fg-enc))
               (bg (kuro--decode-ffi-color bg-enc))
               ;; Cap positions at line-end to prevent face bleeding into next line
               (start-pos (min (+ line-start start-col) line-end))
               (end-pos (min (+ line-start end-col) line-end)))
          (when (> end-pos start-pos)
            (kuro--apply-face-range start-pos end-pos
                                    (list :foreground fg
                                          :background bg
                                          :flags flags))))))))

(provide 'kuro-renderer)

;;; kuro-renderer.el ends here
