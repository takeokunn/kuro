;;; kuro-text-size.el --- Kitty OSC 66 text-sizing overlay management  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Renders Kitty text-sizing-protocol (OSC 66) ranges as Emacs overlays.
;; The Rust backend records a per-cell "text size" (overall scale `s', or a
;; fractional `n'/`d' ratio) for cells written inside an
;; `ESC]66;<metadata>;<text>ST' sequence and exposes the collapsed runs as
;; `(ROW START END SCALED-PERMILLE)' ranges, where SCALED-PERMILLE is the
;; effective size multiplier x1000 (2000 = 2x, 500 = half).  This module polls
;; those ranges and applies an overlay with a `:height' face attribute set to
;; the effective multiplier as a float.
;;
;; # Fidelity caveat (honest scope)
;;
;; Emacs scales rendered text only via the face `:height' attribute, which is a
;; per-character font-size multiplier.  It CANNOT make a single glyph occupy an
;; exact NxM terminal-cell block the way Kitty's protocol specifies.  As a
;; consequence:
;;   - The overall scale `s' (and the fractional `n'/`d' ratio) maps directly
;;     to `:height', so a "2x" run is drawn at roughly double the font size.
;;   - The explicit cell-width key `w' (render the text in W cells) is only
;;     APPROXIMATED: we do not stretch/compress horizontally to fill exactly W
;;     cells; the glyph simply takes whatever width the scaled font needs.
;;   - The vertical/horizontal alignment keys `v'/`h' (top/bottom/center) are
;;     NOT honored: Emacs positions the larger glyph on the text baseline of its
;;     line and offers no per-overlay sub-cell alignment control.
;; These approximations are inherent to a font-`:height' display model and are
;; documented here rather than silently dropped.

;;; Code:

(require 'kuro-ffi-osc)

(declare-function kuro--row-position "kuro-render-buffer" (row))

(defvar-local kuro--text-size-overlays nil
  "List of active OSC 66 text-size overlays in this buffer.")

(defconst kuro--text-size-permille-default 1000
  "SCALED-PERMILLE value for a normal-size (1x) cell.
Ranges at or below this carry no visible scaling and are skipped — the Rust
backend already omits unscaled cells, but this guards against degenerate input.")

(defconst kuro--text-size-permille-max 7000
  "Maximum SCALED-PERMILLE accepted (7x, the Kitty protocol scale ceiling).
Ranges above this are treated as out-of-range and ignored, matching the
protocol's `s' range of 1..7.")

(defun kuro--text-size-permille-to-height (permille)
  "Convert SCALED-PERMILLE to an Emacs face `:height' float multiplier, or nil.
Returns nil when PERMILLE is not a usable scale: non-integer, <= the
normal-size value (`kuro--text-size-permille-default'), or above the protocol
ceiling (`kuro--text-size-permille-max').  Otherwise returns PERMILLE/1000.0,
e.g. 2000 => 2.0, 1500 => 1.5, 500 => 0.5.  A half-size run (500) IS returned
because it is a meaningful sub-1x scale even though it is below 1000."
  (when (and (integerp permille)
             (> permille 0)
             (/= permille kuro--text-size-permille-default)
             (<= permille kuro--text-size-permille-max))
    (/ permille 1000.0)))

(defun kuro--clear-text-size-overlays ()
  "Remove all OSC 66 text-size overlays from the current buffer."
  (mapc #'delete-overlay kuro--text-size-overlays)
  (setq kuro--text-size-overlays nil))

(defun kuro--make-text-size-overlay (beg end height)
  "Create a text-size overlay from BEG to END applying face `:height' HEIGHT.
HEIGHT is a float multiplier (see `kuro--text-size-permille-to-height').
The overlay carries an anonymous face so it composes with any underlying
SGR/face ranges already applied to the same columns (overlay `face' is merged
on top of buffer text-properties).  Returns the overlay."
  (let ((ov (make-overlay beg end nil t nil)))
    (overlay-put ov 'face (list :height height))
    (overlay-put ov 'kuro-text-size-height height)
    (push ov kuro--text-size-overlays)
    ov))

(defun kuro--apply-text-size-ranges ()
  "Poll OSC 66 text-size ranges from Rust and apply `:height' overlays.
Each range is (ROW START END SCALED-PERMILLE); START and END are in-row
character offsets.  For every range with a usable scale (per
`kuro--text-size-permille-to-height') an overlay is created with face
`:height' set to the effective multiplier.  Ranges that are empty
\(START >= END), reference a missing row, or whose SCALED-PERMILLE is
out-of-range / unscaled are skipped.  Existing overlays are cleared first so
stale scaling never persists after a redraw."
  (let ((ranges (kuro--poll-text-size-ranges)))
    (when (or ranges kuro--text-size-overlays)
      (kuro--clear-text-size-overlays)
      (dolist (entry ranges)
        (pcase-let ((`(,row ,start ,end ,permille) entry))
          (when-let* ((height (kuro--text-size-permille-to-height permille))
                      ((integerp start))
                      ((integerp end))
                      ((< start end))
                      (row-pos (kuro--row-position row)))
            (kuro--make-text-size-overlay (+ row-pos start)
                                          (+ row-pos end)
                                          height)))))))

(provide 'kuro-text-size)

;;; kuro-text-size.el ends here
