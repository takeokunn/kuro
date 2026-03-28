;;; kuro-char-width.el --- Character width and glyph metrics for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; Character width tables (EA-Ambiguous, CJK, emoji, PUA, VS) and
;; glyph-metrics probing for correct single-column terminal rendering.
;;
;; # Responsibilities
;;
;; - Buffer-local `char-width-table' matching Rust unicode-width 0.2.2
;; - EA-Ambiguous override enforcement (box drawing, block elements, etc.)
;; - Nerd Font PUA and emoji fontset configuration
;; - Glyph-metric probing and font rescaling for mismatched fallback fonts
;;
;; # Dependencies
;;
;; Depends on `seq' for `seq-find' in fontset detection.

;;; Code:

(require 'seq)

;; Forward declarations for variables used by kuro--refine-glyph-widths
;; to detect line-height changes after font rescaling.
(defvar kuro--initialized nil
  "Forward reference; defvar-local in kuro-ffi.el.")
(defvar kuro--last-rows 0
  "Forward reference; defvar-local in kuro.el.")
(defvar kuro--last-cols 0
  "Forward reference; defvar-local in kuro.el.")
(defvar kuro--resize-pending nil
  "Forward reference; defvar-permanent-local in kuro-ffi.el.")

;;; Character width table — data

(defconst kuro--char-width-2-ranges
  '(;; Emoji: Miscellaneous Symbols and Pictographs, Emoticons, etc.
    (#x1F300 . #x1F64F) (#x1F680 . #x1F6FF)
    (#x1F900 . #x1F9FF) (#x1FA00 . #x1FA6F) (#x1FA70 . #x1FAFF)
    ;; NOTE: #x2600-#x26FF and #x2702-#x27B0 are intentionally omitted here;
    ;; they are East-Asian-Ambiguous and pinned to width 1 below.
    ;; CJK Unified Ideographs (main block + extensions)
    (#x4E00  . #x9FFF)  (#x3400  . #x4DBF)
    (#x20000 . #x2A6DF) (#x2A700 . #x2B73F) (#x2B740 . #x2B81F)
    (#x2B820 . #x2CEAF) (#x2CEB0 . #x2EBEF)
    (#x30000 . #x3134F) (#x31350 . #x323AF)
    ;; CJK Compatibility Ideographs
    (#xF900  . #xFAFF)
    ;; Fullwidth Forms
    (#xFF01  . #xFF60)  (#xFFE0  . #xFFE6)
    ;; Hangul Syllables
    (#xAC00  . #xD7AF)
    ;; CJK Radicals, Kangxi, Bopomofo, Katakana, Hiragana, etc.
    (#x2E80  . #x303E)  (#x3041  . #x3096)  (#x30A1  . #x30FA)
    (#x3105  . #x312F)  (#x31A0  . #x31BF)
    (#x3200  . #x321E)  (#x3220  . #x3247)
    (#x3250  . #x32FE)  (#x3300  . #x33FF))
  "Unicode ranges with display width 2 (emoji, CJK), matching Rust unicode-width 0.2.2.
Used by `kuro--setup-char-width-table' to align Emacs display width with
the terminal grid column count, preventing cursor misalignment for wide chars.")

(defconst kuro--char-width-1-ranges
  '(;; EA-Ambiguous ranges: Rust unicode-width 0.2 and xterm treat these as
    ;; width 1; CJK language environments promote them to width 2.
    ;; Terminal applications (btop, htop, ncurses) assume width 1.
    (#x2190 . #x21FF)    ; Arrows
    (#x2200 . #x22FF)    ; Mathematical Operators
    (#x2300 . #x23FF)    ; Miscellaneous Technical
    (#x2500 . #x257F)    ; Box Drawing — used by ncurses borders
    (#x2580 . #x259F)    ; Block Elements — btop/htop bars
    (#x25A0 . #x25FF)    ; Geometric Shapes — TUI indicators
    (#x2600 . #x26FF)    ; Miscellaneous Symbols
    (#x2700 . #x27BF)    ; Dingbats
    (#x2800 . #x28FF)    ; Braille Patterns — pinned to 1 for safety
    ;; Nerd Font Private Use Area (basic BMP block)
    (#xE000  . #xF8FF)
    ;; Supplementary PUA for Nerd Fonts v3
    (#xF0000 . #xFFFFF))
  "Unicode ranges with display width 1.
Covers East-Asian-Ambiguous ranges (box drawing, block elements, geometric
shapes, misc symbols, etc.) that Rust unicode-width 0.2 and xterm treat as
width 1, plus Nerd Font PUA ranges.")

(defconst kuro--char-width-0-ranges
  '(;; Variation Selectors (VS1-VS16) — zero-width combining chars
    (#xFE00 . #xFE0F))
  "Unicode ranges with display width 0 (zero-width combining characters).
Variation Selectors modify the preceding character's rendering (e.g., VS16
forces emoji presentation) without consuming a grid column themselves.")

;;; Fontset-assignment macro

(defmacro kuro--set-fontset-font-both (range spec)
  "Register SPEC for RANGE in both the current frame and the default fontset.
Both nil (current frame) and t (default template) are updated because
frame creation copies the default fontset — modifying only t would not
update existing frames, and modifying only nil would not affect new frames."
  `(progn
     (set-fontset-font nil ,range ,spec nil 'prepend)
     (set-fontset-font t   ,range ,spec nil 'prepend)))

;;; EA-Ambiguous font assignment and glyph-metric refinement

(defconst kuro--ea-range-probe-table
  '(((#x2190 . #x21FF) . #x2192)    ; Arrows — EA Width A (↑↓←→): probe →
    ((#x2200 . #x22FF) . #x2200)    ; Mathematical Operators — EA Width A (×÷∞√): probe ∀
    ((#x2300 . #x23FF) . #x2302)    ; Miscellaneous Technical — EA Width A: probe ⌂
    ((#x2500 . #x257F) . #x2502)    ; Box Drawing — ncurses borders: probe │
    ((#x2580 . #x259F) . #x2588)    ; Block Elements — btop/htop bars: probe █
    ((#x25A0 . #x25FF) . #x25A0)    ; Geometric Shapes — TUI indicators: probe ■
    ((#x2600 . #x26FF) . #x2605)    ; Miscellaneous Symbols — EA Width A: probe ★
    ((#x2700 . #x27BF) . #x2714)    ; Dingbats — EA Width A: probe ✔
    ((#x2800 . #x28FF) . #x28C0))   ; Braille Patterns — pinned to 1: probe ⣀
  "Canonical table of EA-Ambiguous Unicode ranges with their probe characters.
Each entry is ((range-start . range-end) . probe-char).
The range is forced to display-width 1 in kuro buffers; the probe char is used
by `kuro--refine-glyph-widths' to detect and correct font metrics.
Unifies the old parallel `kuro--char-width-overrides' + `kuro--glyph-probe-chars'.")

(defconst kuro--char-width-overrides
  (mapcar #'car kuro--ea-range-probe-table)
  "Unicode ranges forced to display-width 1 in kuro terminal buffers.
Derived from `kuro--ea-range-probe-table'.  CJK language environments promote
these EA-Ambiguous ranges to width 2, but terminal apps and Rust unicode-width
treat them as width 1.")

(defun kuro--apply-char-width-overrides ()
  "Force all `kuro--char-width-overrides' ranges to width 1 in the current buffer.
Must be called after `char-width-table' is buffer-local."
  (dolist (range kuro--char-width-overrides)
    (set-char-table-range char-width-table range 1)))

(defun kuro--reapply-char-width-in-all-buffers ()
  "Re-apply char-width overrides in all kuro-mode buffers.
Called from `set-language-environment-hook' because
`set-language-environment' replaces buffer-local `char-width-table'."
  (dolist (buf (buffer-list))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (derived-mode-p 'kuro-mode)
          ;; set-language-environment replaced our table — make a fresh copy
          ;; of the (new) global table and re-apply overrides.
          (setq char-width-table (copy-sequence char-width-table))
          (kuro--apply-char-width-overrides))))))

(add-hook 'set-language-environment-hook #'kuro--reapply-char-width-in-all-buffers)

(defun kuro--assign-mono-fonts ()
  "Assign the frame's ASCII (monospace) font to EA-Ambiguous Unicode ranges.
This MUST run synchronously during `kuro-mode' init — before the first
render — so that btop/htop output is already rendered with correct glyph
widths from the very first frame.  If deferred to an idle timer, the timer
may never fire while btop floods the PTY with output.

Modifies BOTH the selected frame's fontset (nil) and the default fontset (t).
Using only `t' was the original bug: `t' modifies the template for future
frames, but existing frames already have their own fontset copy made at
frame creation time.

Uses `prepend' rather than replacing the font list, so if the ASCII font
lacks a glyph for a given codepoint Emacs falls back to the original
\(possibly CJK) font rather than showing a missing-glyph box."
  (when (display-graphic-p)
    (let* ((ascii-font (face-attribute 'default :font nil t))
           (ascii-family (and ascii-font (font-get ascii-font :family))))
      (when ascii-family
        (let ((family-name (if (symbolp ascii-family)
                               (symbol-name ascii-family)
                             ascii-family)))
          (dolist (range kuro--char-width-overrides)
            (condition-case nil
                (kuro--set-fontset-font-both range (font-spec :family family-name))
              (error nil))))))))


(defconst kuro--glyph-extra-probes
  '(#x23FA    ; ⏺ — record symbol (Claude Code status indicator)
    #x25CF    ; ● — black circle (common TUI bullet)
    #x2714    ; ✔ — check mark
    #x276F)   ; ❯ — heavy right-pointing angle quotation mark ornament
  "Individual codepoints to probe for glyph metric correction.
The per-range probing in `kuro--glyph-probe-chars' uses one representative
character per Unicode range, but different characters within the same range
may use different fallback fonts with mismatched metrics.  This list targets
specific high-frequency characters known to cause visual shaking (line-height
fluctuation) or horizontal misalignment in TUI applications.")

(defun kuro--probe-glyph-metrics (probe-char)
  "Return (:font FONT :width W :height H) for PROBE-CHAR, or nil if unavailable.
Uses `internal-char-font' to determine which font Emacs would use for
PROBE-CHAR in the current buffer's window, then reads glyph metrics via
`font-get-glyphs'.  The buffer must be displayed in a window (always true
when called from `kuro--refine-glyph-widths' 0.1s after session start).
Returns nil on any error (non-graphical display, no window, missing font)."
  (condition-case nil
      (when-let* ((win (get-buffer-window (current-buffer) t)))
        (with-selected-window win
          (let* ((char-font (internal-char-font (point-min) probe-char))
                 (font-obj  (and char-font (car char-font)))
                 (probe-str (string probe-char))
                 (glyphs    (and font-obj (font-get-glyphs font-obj 0 1 probe-str)))
                 (glyph     (and glyphs (> (length glyphs) 0) (aref glyphs 0)))
                 (width     (and glyph (aref glyph 4)))
                 (ascent    (and glyph (> (length glyph) 7) (aref glyph 7)))
                 (descent   (and glyph (> (length glyph) 8) (aref glyph 8))))
            (and width (> width 0)
                 (list :font   font-obj
                       :width  width
                       :height (and ascent descent
                                    (+ (abs ascent) (abs descent))))))))
    (error nil)))

(defun kuro--rescale-font-for-glyph (probe-char range cell-width cell-height)
  "Probe PROBE-CHAR and rescale its font if metrics don't match cell dimensions.
RANGE is the fontset range to apply the rescaled font to — either a cons
cell (START . END) for a Unicode range, or a single character for per-char
correction.  CELL-WIDTH and CELL-HEIGHT are the expected pixel dimensions.
Returns non-nil if a rescaling was applied."
  (when-let ((metrics (kuro--probe-glyph-metrics probe-char)))
    (let* ((font-obj     (plist-get metrics :font))
           (glyph-width  (plist-get metrics :width))
           (glyph-height (plist-get metrics :height))
           (width-ratio  (/ (float glyph-width) cell-width))
           (height-ratio (if (and glyph-height (> glyph-height 0)
                                  (> glyph-height cell-height))
                             (/ (float glyph-height) cell-height)
                           1.0))
           (max-ratio    (max width-ratio height-ratio)))
      (when (> max-ratio 1.05)
        (let* ((fname    (font-get font-obj :family))
               (new-size (* (font-get font-obj :size) (/ 1.0 max-ratio)))
               (rescaled (font-spec :family (if (symbolp fname) (symbol-name fname) fname)
                                    :size new-size)))
          (kuro--set-fontset-font-both range rescaled)
          t)))))

(defun kuro--refine-glyph-widths ()
  "Probe actual rendered glyph widths and heights, rescale mismatched fonts.
Called from a short timer after the kuro buffer is displayed in a window,
so `font-at' can determine which font Emacs actually chose for each range.

Two passes:
  1. Per-range: probe one representative character per
     `kuro--char-width-overrides' range (from `kuro--glyph-probe-chars').
     Rescales the range-level font.
  2. Per-character: probe individual high-frequency characters from
     `kuro--glyph-extra-probes' that may use a different fallback font
     than the range-level probe.  Applies a per-codepoint override.

Both passes check width AND height: a fallback font matching cell width
may still have taller ascent+descent, causing line-height fluctuation
\(visible as vertical buffer shaking when the character blinks)."
  (when (display-graphic-p)
    (let* ((cell-width (frame-char-width))
           (cell-height (frame-char-height))
           (did-change nil))
      (when (and cell-width (> cell-width 0) cell-height (> cell-height 0))
        ;; Pass 1: per-range probing — range and probe-char from unified table.
        (dolist (entry kuro--ea-range-probe-table)
          (when (kuro--rescale-font-for-glyph (cdr entry) (car entry) cell-width cell-height)
            (setq did-change t)))
        ;; Pass 2: per-character probing for known-problematic glyphs
        (dolist (char kuro--glyph-extra-probes)
          (when (kuro--rescale-font-for-glyph
                 char (cons char char) cell-width cell-height)
            (setq did-change t)))
        (when did-change
          (redraw-display)
          ;; Font rescaling may change effective line height (e.g. replacing a
          ;; taller fallback font with a shorter one), which changes
          ;; window-body-height without triggering window-size-change-functions
          ;; (pixel size is unchanged).  Record a pending resize so the next
          ;; render cycle sends the corrected dimensions to the PTY.
          (when-let ((win (get-buffer-window (current-buffer) t)))
            (let ((new-rows (window-body-height win))
                  (new-cols (window-body-width win)))
              (when (and (boundp 'kuro--initialized) kuro--initialized
                         (or (/= new-rows kuro--last-rows)
                             (/= new-cols kuro--last-cols)))
                (setq kuro--resize-pending (cons new-rows new-cols))))))))))


;;; Character width table — logic

(defun kuro--setup-char-width-table ()
  "Set buffer-local `char-width-table' matching Rust unicode-width 0.2.2.
Applies `kuro--char-width-2-ranges', `kuro--char-width-1-ranges', and
`kuro--char-width-0-ranges' to a new char-table, then inherits from the
global `char-width-table' for all other codepoints.
This ensures Emacs display width agrees with the terminal grid column count,
preventing cursor misalignment and face-range corruption for wide characters.

The width-1 pass runs last so EA-Ambiguous ranges (box drawing, block
elements, misc symbols, etc.) correctly override width-2 entries that
appear in both `kuro--char-width-2-ranges' and `kuro--char-width-1-ranges'."
  (let ((table (make-char-table nil)))
    (mapc (pcase-lambda (`(,ranges . ,width))
            (dolist (range ranges)
              (set-char-table-range table range width)))
          `((,kuro--char-width-2-ranges . 2)
            (,kuro--char-width-0-ranges . 0)
            (,kuro--char-width-1-ranges . 1)))
    (set-char-table-parent table char-width-table)
    (setq-local char-width-table table)))

;;; Fontset configuration

(defun kuro--detect-nerd-font ()
  "Detect a Nerd Font from the system font list.
Returns the font family name string, preferring \"Symbols Nerd Font Mono\".
Returns nil if no Nerd Font is found."
  (when (display-graphic-p)
    (let ((families (font-family-list)))
      (or (when (member "Symbols Nerd Font Mono" families)
            "Symbols Nerd Font Mono")
          (seq-find (lambda (f) (string-match-p "Nerd Font Mono" f)) families)
          (seq-find (lambda (f) (string-match-p "Nerd Font" f)) families)))))

(defun kuro--setup-fontset ()
  "Configure fontset for emoji and Nerd Font icon display.
Auto-detects available fonts; no-op if no suitable fonts are found.
Only effective in graphical Emacs frames."
  (when (display-graphic-p)
    (when-let ((nerd-font (kuro--detect-nerd-font)))
      (set-fontset-font t '(#xE000 . #xF8FF) nerd-font nil 'prepend)
      (set-fontset-font t '(#xF0000 . #xFFFFF) nerd-font nil 'prepend))
    (let ((emoji-font
           (seq-find
            (lambda (f) (member f (font-family-list)))
            '("Apple Color Emoji" "Noto Color Emoji" "Segoe UI Emoji"))))
      (when emoji-font
        (set-fontset-font t 'emoji emoji-font nil 'prepend)))))

(provide 'kuro-char-width)

;;; kuro-char-width.el ends here
