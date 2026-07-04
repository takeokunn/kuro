;;; kuro-overlays-macros.el --- Macro helpers for Kuro overlays  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Macro-only helpers for `kuro-overlays.el'.  Moving generated overlay
;; registration logic here keeps the runtime file focused on state and
;; mutation behavior.

;;; Code:

(defmacro kuro--toggle-blink-state (blink-type)
  "Toggle the visibility state variable for BLINK-TYPE and return the new value.
Modifies `kuro--blink-visible-slow' or `kuro--blink-visible-fast' in-place."
  `(if (eq ,blink-type 'slow)
       (setq kuro--blink-visible-slow (not kuro--blink-visible-slow))
     (setq kuro--blink-visible-fast (not kuro--blink-visible-fast))))

(defmacro kuro--register-blink-overlay (ov blink-type row)
  "Register OV with BLINK-TYPE and ROW in blink overlay structures.
Maintains the invariant that every blink overlay simultaneously appears in:
  `kuro--blink-overlays'           -- full list for bulk iteration
  `kuro--blink-overlays-slow/fast' -- typed sub-list for O(1) per-phase toggling
  `kuro--blink-overlays-by-row'    -- row hash for O(1) per-row eviction
Each removal path (`kuro--clear-line-blink-overlays') must mirror this."
  `(progn
     (push ,ov kuro--blink-overlays)
     (if (eq ,blink-type 'slow)
         (push ,ov kuro--blink-overlays-slow)
       (push ,ov kuro--blink-overlays-fast))
     (puthash ,row (cons ,ov (gethash ,row kuro--blink-overlays-by-row))
              kuro--blink-overlays-by-row)))

(provide 'kuro-overlays-macros)

;;; kuro-overlays-macros.el ends here
