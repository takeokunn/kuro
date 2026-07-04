;;; kuro-char-width-test-cases.el --- Char width test case data  -*- lexical-binding: t; -*-

;;; Code:

(defconst kuro-char-width-test--setup-width-table
  '((kuro-faces-test--char-width-table-box-drawing-start    #x2500 1)
    (kuro-faces-test--char-width-table-box-drawing-end      #x257F 1)
    (kuro-faces-test--char-width-table-block-elements-start #x2580 1)
    (kuro-faces-test--char-width-table-block-elements-end   #x259F 1)
    (kuro-faces-test--char-width-table-arrows-start         #x2190 1)
    (kuro-faces-test--char-width-table-arrows-end           #x21FF 1)
    (kuro-faces-test--char-width-table-math-operators       #x2200 1)
    (kuro-faces-test--char-width-table-geometric-shapes     #x25A0 1)
    (kuro-faces-test--char-width-table-braille-start        #x2800 1)
    (kuro-faces-test--char-width-table-braille-end          #x28FF 1))
  "Table of (test-name codepoint expected-width) for char-width spot checks.")

(defconst kuro-char-width-test--override-range-table
  '((kuro-faces-test--apply-overrides-arrows           "Arrows"           (#x2190 . #x21FF))
    (kuro-faces-test--apply-overrides-math-operators   "Math Operators"   (#x2200 . #x22FF))
    (kuro-faces-test--apply-overrides-misc-technical   "Misc Technical"   (#x2300 . #x23FF))
    (kuro-faces-test--apply-overrides-box-drawing      "Box Drawings"     (#x2500 . #x257F))
    (kuro-faces-test--apply-overrides-block-elements   "Block Elements"   (#x2580 . #x259F))
    (kuro-faces-test--apply-overrides-geometric-shapes "Geometric Shapes" (#x25A0 . #x25FF))
    (kuro-faces-test--apply-overrides-misc-symbols     "Misc Symbols"     (#x2600 . #x26FF))
    (kuro-faces-test--apply-overrides-dingbats         "Dingbats"         (#x2700 . #x27BF))
    (kuro-faces-test--apply-overrides-braille          "Braille"          (#x2800 . #x28FF)))
  "Table of (test-name description range) for `kuro--apply-char-width-overrides'.")

(defconst kuro-char-width-test--noop-in-batch-table
  '((kuro-faces-test--assign-mono-fonts-noop-in-batch    kuro--assign-mono-fonts)
    (kuro-faces-test--refine-glyph-widths-noop-in-batch  kuro--refine-glyph-widths)
    (kuro-faces-test--setup-fontset-noop-in-batch        kuro--setup-fontset)
    (kuro-faces-test--detect-nerd-font-nil-in-batch      kuro--detect-nerd-font))
  "Table of (test-name fn-sym): functions that must return nil in non-graphical (batch) Emacs.")

(defconst kuro-char-width-test--detect-nerd-font-table
  '((kuro-faces-test--detect-nerd-font-prefers-symbols-nerd-font-mono
     ("DejaVu Sans Mono" "Symbols Nerd Font Mono" "SomeOther Nerd Font")
     "Symbols Nerd Font Mono")
    (kuro-faces-test--detect-nerd-font-fallback-to-other-nerd-mono
     ("DejaVu Sans Mono" "Hack Nerd Font Mono")
     "Hack Nerd Font Mono")
    (kuro-faces-test--detect-nerd-font-fallback-to-nerd-font
     ("DejaVu Sans Mono" "Hack Nerd Font")
     "Hack Nerd Font")
    (kuro-faces-test--detect-nerd-font-nil-when-no-nerd-fonts
     ("DejaVu Sans Mono" "Consolas" "Courier New")
     nil))
  "Table: (test-name fonts expected) for kuro--detect-nerd-font priority dispatch.")

(defconst kuro-char-width-test--width-invariant-table
  '(;; Variation Selectors (FE00-FE0F): zero width
    (kuro-faces-test--variation-selector-fe00-is-0  #xFE00  0)
    (kuro-faces-test--variation-selector-fe0f-is-0  #xFE0F  0)
    ;; Nerd Font PUA (E000-F8FF): width 1
    (kuro-faces-test--pua-nerd-e000-is-1            #xE000  1)
    (kuro-faces-test--pua-nerd-f8ff-is-1            #xF8FF  1)
    ;; Supplementary Nerd Font PUA (F0000): width 1
    (kuro-faces-test--supplementary-pua-f0000-is-1  #xF0000 1))
  "Table of (test-name codepoint expected-width) for char-width invariants.")

(defconst kuro-char-width-test--refine-redraw-table
  '((test-kuro-refine-glyph-widths-calls-redraw-when-changed  t   t)
    (test-kuro-refine-glyph-widths-no-redraw-when-unchanged   nil nil))
  "Table: (test-name rescale-result redraw-expected?) for kuro--refine-glyph-widths.")

(provide 'kuro-char-width-test-cases)
;;; kuro-char-width-test-cases.el ends here
