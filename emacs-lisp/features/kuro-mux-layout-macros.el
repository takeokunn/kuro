;;; kuro-mux-layout-macros.el --- Macros for kuro-mux-layout.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

;;; Commentary:

;; Fixed-layout dispatch helpers for kuro-mux.  The layout names stay data in
;; `kuro-mux-layouts' while the runtime dispatch expands into direct branches.

;;; Code:

(defmacro kuro--dispatch-layout (layout win buffers)
  "Expand LAYOUT into a direct window-layout dispatch.
WIN is the main window and BUFFERS is the visible kuro buffer list."
  `(pcase ,layout
     ("even-horizontal" (kuro-mux--layout-chain ,win (cdr ,buffers) 'right))
     ("even-vertical"   (kuro-mux--layout-chain ,win (cdr ,buffers) 'below))
     ("main-vertical"   (kuro-mux--layout-main ,win (cdr ,buffers) 'right 'below))
     ("main-horizontal" (kuro-mux--layout-main ,win (cdr ,buffers) 'below 'right))
     ("tiled"           (kuro-mux--layout-tiled ,buffers))
     (_ (user-error "Kuro-mux: unknown layout: %s" ,layout))))

(provide 'kuro-mux-layout-macros)

;;; kuro-mux-layout-macros.el ends here
