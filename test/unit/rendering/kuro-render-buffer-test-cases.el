;;; kuro-render-buffer-test-cases.el --- Render-buffer test case data  -*- lexical-binding: t; -*-

;;; Code:

(defconst kuro-render-buffer-test--decscusr-cases
  '((kuro-render-buffer-decscusr-0-is-box
     "DECSCUSR 0 (default) returns box cursor."
     0 box)
    (kuro-render-buffer-decscusr-1-is-box
     "DECSCUSR 1 (blinking block) returns box cursor."
     1 box)
    (kuro-render-buffer-decscusr-2-is-box
     "DECSCUSR 2 (steady block) returns box cursor."
     2 box)
    (kuro-render-buffer-decscusr-3-is-hbar
     "DECSCUSR 3 (blinking underline) returns hbar cursor of height 2."
     3 (hbar . 2))
    (kuro-render-buffer-decscusr-4-is-hbar
     "DECSCUSR 4 (steady underline) returns hbar cursor of height 2."
     4 (hbar . 2))
    (kuro-render-buffer-decscusr-5-is-bar
     "DECSCUSR 5 (blinking bar/I-beam) returns bar cursor of width 2."
     5 (bar . 2))
    (kuro-render-buffer-decscusr-6-is-bar
     "DECSCUSR 6 (steady bar/I-beam) returns bar cursor of width 2."
     6 (bar . 2)))
  "DECSCUSR value to Emacs cursor type cases.")

(defconst kuro-render-buffer-test--decscusr-default-cases
  '((99 box)
    (7 box)
    (-1 box))
  "Unknown DECSCUSR values and their safe fallback cursor types.")

(defconst kuro-render-buffer-test--decscusr-alias-cases
  '((kuro-render-buffer-decscusr-0-and-1-return-same
     "DECSCUSR 0 and 1 are aliases; both return identical cursor types."
     0 1)
    (kuro-render-buffer-decscusr-3-and-4-return-same
     "DECSCUSR 3 and 4 are aliases; both return identical cursor types."
     3 4)
    (kuro-render-buffer-decscusr-5-and-6-return-same
     "DECSCUSR 5 and 6 are aliases; both return identical cursor types."
     5 6))
  "DECSCUSR values that should map to equivalent cursor types.")

(defconst kuro-render-buffer-test--decscusr-shape-kind-cases
  '((kuro-render-buffer-decscusr-shape-0-returns-box
     "Shape 0 (default block) maps to box."
     0 box)
    (kuro-render-buffer-decscusr-shape-1-returns-box
     "Shape 1 (blinking block alias) maps to box."
     1 box)
    (kuro-render-buffer-decscusr-shape-3-returns-hbar
     "Shape 3 (blinking underline) maps to hbar."
     3 hbar)
    (kuro-render-buffer-decscusr-shape-5-returns-bar
     "Shape 5 (blinking bar) maps to bar."
     5 bar)
    (kuro-render-buffer-decscusr-shape-6-returns-bar
     "Shape 6 (steady bar) maps to bar."
     6 bar))
  "DECSCUSR shape-to-kind cursor cases.")

(defconst kuro-render-buffer-test--decscusr-fallback-shape-cases
  '((kuro-render-buffer-decscusr-negative-shape-falls-back-to-box
     "Negative shape falls back to box."
     (-1))
    (kuro-render-buffer-decscusr-out-of-range-falls-back-to-box
     "Out-of-range shape (> 6) falls back to box."
     (7 99))
    (kuro-render-buffer-decscusr-non-integer-falls-back-to-box
     "Non-integer shape falls back to box."
     (nil "3")))
  "Invalid DECSCUSR shape fallback cases.")

(defconst kuro-render-buffer-test--apply-cursor-display-cases
  '((kuro-render-buffer-apply-cursor-display-visible-shape-0
     "Visible cursor with shape 0 sets cursor-type to box."
     t 0 nil box)
    (kuro-render-buffer-apply-cursor-display-visible-shape-3
     "Visible cursor with shape 3 (blinking underline) sets hbar cursor."
     t 3 nil (hbar . 2))
    (kuro-render-buffer-apply-cursor-display-hidden
     "Hidden cursor (DECTCEM off) sets cursor-type to nil."
     nil 0 box nil)
    (kuro-render-buffer-apply-cursor-display-nil-shape-defaults-to-box
     "Nil shape (missing DECSCUSR) defaults to shape 0 (box)."
     t nil nil box))
  "Cursor visibility, shape, and expected `cursor-type' cases.")

(defconst kuro-render-buffer-test--decscusr-cursor-type-vector-cases
  '((kuro-render-buffer-ext2-decscusr-cursor-types-is-vector
     (vectorp kuro--decscusr-cursor-types))
    (kuro-render-buffer-ext2-decscusr-cursor-types-length-7
     (= 7 (length kuro--decscusr-cursor-types)))
    (kuro-render-buffer-ext2-decscusr-cursor-types-index-0-is-box
     (eq 'box (aref kuro--decscusr-cursor-types 0)))
    (kuro-render-buffer-ext2-decscusr-cursor-types-index-3-is-hbar
     (equal '(hbar . 2) (aref kuro--decscusr-cursor-types 3)))
    (kuro-render-buffer-ext2-decscusr-cursor-types-index-5-is-bar
     (equal '(bar . 2) (aref kuro--decscusr-cursor-types 5))))
  "Invariant checks for `kuro--decscusr-cursor-types'.")

(defconst kuro-render-buffer-test--cursor-state-changed-cases
  '((kuro-render-buffer-ext2-cursor-state-changed-p-returns-nil-when-same
     (0 0 t 0) (0 0 t 0) nil)
    (kuro-render-buffer-ext2-cursor-state-changed-p-returns-t-when-row-differs
     (0 0 t 0) (1 0 t 0) t)
    (kuro-render-buffer-ext2-cursor-state-changed-p-returns-t-when-col-differs
     (0 0 t 0) (0 1 t 0) t)
    (kuro-render-buffer-ext2-cursor-state-changed-p-returns-t-when-visible-differs
     (0 0 t 0) (0 0 nil 0) t)
    (kuro-render-buffer-ext2-cursor-state-changed-p-returns-t-when-shape-differs
     (0 0 t 0) (0 0 t 1) t))
  "Cached cursor state, incoming state, and expected change detection result.")

(defconst kuro-render-buffer-test--cache-cursor-state-expansion-cases
  '((kuro-render-buffer-cache-cursor-state-expands-to-setq
     "`kuro--cache-cursor-state' single-step expands to a `setq' form."
     (eq (car exp) 'setq))
    (kuro-render-buffer-cache-cursor-state-first-target-is-cursor-row
     "`kuro--cache-cursor-state' first assignment target is `kuro--last-cursor-row'."
     (eq (cadr exp) 'kuro--last-cursor-row))
    (kuro-render-buffer-cache-cursor-state-sets-all-four-vars
     "`kuro--cache-cursor-state' expansion assigns all four cursor cache variables."
     (and (memq 'kuro--last-cursor-row exp)
          (memq 'kuro--last-cursor-col exp)
          (memq 'kuro--last-cursor-visible exp)
          (memq 'kuro--last-cursor-shape exp))))
  "Structural checks for the `kuro--cache-cursor-state' expansion.")

(provide 'kuro-render-buffer-test-cases)

;;; kuro-render-buffer-test-cases.el ends here
