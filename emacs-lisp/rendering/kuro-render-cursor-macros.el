;;; kuro-render-cursor-macros.el --- Macros for kuro-render-cursor.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Cursor cache update macro extracted from kuro-render-cursor.el.

;;; Code:

(defmacro kuro--cache-cursor-state (row col visible shape)
  "Store ROW, COL, VISIBLE, SHAPE into the per-buffer cursor cache variables."
  `(setq kuro--last-cursor-row     ,row
         kuro--last-cursor-col     ,col
         kuro--last-cursor-visible ,visible
         kuro--last-cursor-shape   ,shape))

(provide 'kuro-render-cursor-macros)

;;; kuro-render-cursor-macros.el ends here
