;;; kuro-char-width-test.el --- Unit tests for kuro-char-width.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-char-width.el (EA-Ambiguous char-width tables,
;; override application, and glyph-metric probing).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-char-width)

;;; Group 13: EA-Ambiguous char-width — kuro--setup-char-width-table spot checks

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
  "Table of (test-name codepoint expected-width) for char-width spot checks after
`kuro--setup-char-width-table'.  Add new EA-Ambiguous boundary codepoints here.")

(defmacro kuro-char-width-test--def-setup-width (test-name char expected)
  "Define a test asserting CHAR has char-width EXPECTED after `kuro--setup-char-width-table'."
  `(ert-deftest ,test-name ()
     ,(format "U+%04X has char-width %d after kuro--setup-char-width-table." char expected)
     (with-temp-buffer
       (kuro--setup-char-width-table)
       (should (= ,expected (char-width ,char))))))

(kuro-char-width-test--def-setup-width kuro-faces-test--char-width-table-box-drawing-start    #x2500 1)
(kuro-char-width-test--def-setup-width kuro-faces-test--char-width-table-box-drawing-end      #x257F 1)
(kuro-char-width-test--def-setup-width kuro-faces-test--char-width-table-block-elements-start #x2580 1)
(kuro-char-width-test--def-setup-width kuro-faces-test--char-width-table-block-elements-end   #x259F 1)
(kuro-char-width-test--def-setup-width kuro-faces-test--char-width-table-arrows-start         #x2190 1)
(kuro-char-width-test--def-setup-width kuro-faces-test--char-width-table-arrows-end           #x21FF 1)
(kuro-char-width-test--def-setup-width kuro-faces-test--char-width-table-math-operators       #x2200 1)
(kuro-char-width-test--def-setup-width kuro-faces-test--char-width-table-geometric-shapes     #x25A0 1)
(kuro-char-width-test--def-setup-width kuro-faces-test--char-width-table-braille-start        #x2800 1)
(kuro-char-width-test--def-setup-width kuro-faces-test--char-width-table-braille-end          #x28FF 1)

(ert-deftest kuro-faces-test--char-width-table-misc-symbols ()
  "U+2600 (BLACK SUN WITH RAYS) is width 1 after setup.
This codepoint appears in kuro--char-width-2-ranges (emoji) AND
kuro--char-width-1-ranges (EA-Ambiguous); the width-1 pass must win."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2600)))))

(ert-deftest kuro-test-detect-nerd-font-nil ()
  "kuro--detect-nerd-font returns nil or a string without error."
  (let ((result (kuro--detect-nerd-font)))
    (should (or (null result) (stringp result)))))

(ert-deftest kuro-faces-test--char-width-table-is-buffer-local ()
  "kuro--setup-char-width-table makes char-width-table buffer-local."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (local-variable-p 'char-width-table))))

(ert-deftest kuro-faces-test--all-setup-widths-correct ()
  "Every entry in `kuro-char-width-test--setup-width-table' has the expected char-width."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (dolist (entry kuro-char-width-test--setup-width-table)
      (let ((char     (nth 1 entry))
            (expected (nth 2 entry)))
        (should (= expected (char-width char)))))))

(ert-deftest kuro-faces-test--char-width-table-cjk-override ()
  "In Japanese language environment, EA-Ambiguous chars must still be width 1."
  (let ((orig-env current-language-environment))
    (unwind-protect
        (progn
          (set-language-environment "Japanese")
          (with-temp-buffer
            ;; Before setup: CJK env makes these width 2
            (should (= 2 (char-width #x25A0)))  ; ■
            (should (= 2 (char-width #x2502)))  ; │
            (should (= 2 (char-width #x2500)))  ; ─
            ;; After setup: must be 1
            (kuro--setup-char-width-table)
            (should (= 1 (char-width #x25A0)))
            (should (= 1 (char-width #x2502)))
            (should (= 1 (char-width #x2500)))
            (should (= 1 (char-width #x2588)))  ; █
            (should (= 1 (char-width #x2192)))  ; →
            (should (= 1 (char-width #x28C0))))) ; ⣀
      (set-language-environment orig-env))))

(ert-deftest kuro-faces-test--char-width-survives-set-language-environment ()
  "char-width overrides must survive `set-language-environment' via hook."
  (let ((orig-env current-language-environment))
    (unwind-protect
        (with-temp-buffer
          ;; Simulate kuro-mode setup: buffer-local table + global hook
          (setq major-mode 'kuro-mode)
          (kuro--setup-char-width-table)
          (kuro-char-width-setup)
          (should (= 1 (char-width #x25A0)))
          ;; set-language-environment replaces char-width-table globally;
          ;; the hook must re-apply overrides in all kuro-mode buffers.
          (set-language-environment "Japanese")
          (should (= 1 (char-width #x25A0)))
          (should (= 1 (char-width #x2502)))
          (should (= 1 (char-width #x2500))))
      (set-language-environment orig-env))))

(ert-deftest kuro-faces-test--string-width-btop-line ()
  "A 120-char btop line must have string-width 120 after char-width-table setup."
  (let ((orig-env current-language-environment))
    (unwind-protect
        (progn
          (set-language-environment "Japanese")
          (with-temp-buffer
            (kuro--setup-char-width-table)
            (let ((btop-line (concat "│  23%                    │"
                                     " Used: 19% ■■■■■  701 GiB "
                                     "││   87580 Google C /Applications/"
                                     "Google  take   856M ⣀⣀⣀⣀⣀  1.5  │")))
              (should (= (length btop-line) 120))
              (should (= (string-width btop-line) 120)))))
      (set-language-environment orig-env))))

;;; Group 14: kuro--apply-char-width-overrides

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
  "Table of (test-name description range) for `kuro--apply-char-width-overrides'.
Mirrors the 9 entries in `kuro--ea-range-probe-table'.  All ranges must map to width 1.")

(defmacro kuro-char-width-test--def-override-range (test-name desc range)
  "Define a test that `kuro--apply-char-width-overrides' sets RANGE to width 1."
  `(ert-deftest ,test-name ()
     ,(format "kuro--apply-char-width-overrides sets %s to width 1." desc)
     (with-temp-buffer
       (make-local-variable 'char-width-table)
       (setq char-width-table (copy-sequence char-width-table))
       (kuro--apply-char-width-overrides)
       (should (= 1 (char-table-range char-width-table ',range))))))

(kuro-char-width-test--def-override-range kuro-faces-test--apply-overrides-arrows           "Arrows"           (#x2190 . #x21FF))
(kuro-char-width-test--def-override-range kuro-faces-test--apply-overrides-math-operators   "Math Operators"   (#x2200 . #x22FF))
(kuro-char-width-test--def-override-range kuro-faces-test--apply-overrides-misc-technical   "Misc Technical"   (#x2300 . #x23FF))
(kuro-char-width-test--def-override-range kuro-faces-test--apply-overrides-box-drawing      "Box Drawings"     (#x2500 . #x257F))
(kuro-char-width-test--def-override-range kuro-faces-test--apply-overrides-block-elements   "Block Elements"   (#x2580 . #x259F))
(kuro-char-width-test--def-override-range kuro-faces-test--apply-overrides-geometric-shapes "Geometric Shapes" (#x25A0 . #x25FF))
(kuro-char-width-test--def-override-range kuro-faces-test--apply-overrides-misc-symbols     "Misc Symbols"     (#x2600 . #x26FF))
(kuro-char-width-test--def-override-range kuro-faces-test--apply-overrides-dingbats         "Dingbats"         (#x2700 . #x27BF))
(kuro-char-width-test--def-override-range kuro-faces-test--apply-overrides-braille          "Braille"          (#x2800 . #x28FF))

(ert-deftest kuro-faces-test--apply-overrides-all-ranges-covered ()
  "kuro--apply-char-width-overrides sets every entry in kuro--char-width-overrides to 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (dolist (range kuro--char-width-overrides)
      (should (= 1 (char-table-range char-width-table range))))))

;;; Group 15: Font glyph-width fix structure — noop-in-batch cross-group table

(defconst kuro-char-width-test--noop-in-batch-table
  '((kuro-faces-test--assign-mono-fonts-noop-in-batch    kuro--assign-mono-fonts)
    (kuro-faces-test--refine-glyph-widths-noop-in-batch  kuro--refine-glyph-widths)
    (kuro-faces-test--setup-fontset-noop-in-batch        kuro--setup-fontset)
    (kuro-faces-test--detect-nerd-font-nil-in-batch      kuro--detect-nerd-font))
  "Table of (test-name fn-sym): functions that must return nil in non-graphical (batch) Emacs.")

(defmacro kuro-char-width-test--def-noop-in-batch (test-name fn-sym)
  `(ert-deftest ,test-name ()
     ,(format "`%s' is a no-op (returns nil) when `display-graphic-p' is nil." fn-sym)
     (should-not (,fn-sym))))

(kuro-char-width-test--def-noop-in-batch kuro-faces-test--assign-mono-fonts-noop-in-batch   kuro--assign-mono-fonts)
(kuro-char-width-test--def-noop-in-batch kuro-faces-test--refine-glyph-widths-noop-in-batch kuro--refine-glyph-widths)

(ert-deftest kuro-char-width-test--all-noop-in-batch-correct ()
  "Invariant: all listed functions return nil when display-graphic-p is nil (batch mode)."
  (dolist (entry kuro-char-width-test--noop-in-batch-table)
    (pcase-let ((`(,_name ,fn-sym) entry))
      (should-not (funcall fn-sym)))))

(ert-deftest kuro-faces-test--ea-range-probe-table-structure ()
  "kuro--ea-range-probe-table has 9 entries, each with a range cons and probe char."
  (should (= (length kuro--ea-range-probe-table) 9))
  (dolist (entry kuro--ea-range-probe-table)
    (should (consp (car entry)))          ; range is (start . end)
    (should (integerp (caar entry)))      ; range-start is integer
    (should (integerp (cdar entry)))      ; range-end is integer
    (should (integerp (cdr entry))))      ; probe-char is integer
  ;; Derived kuro--char-width-overrides matches the table's ranges.
  (should (= (length kuro--char-width-overrides) 9))
  (let ((table-ranges (mapcar #'car kuro--ea-range-probe-table)))
    (should (member '(#x2500 . #x257F) table-ranges))
    (should (member '(#x2580 . #x259F) table-ranges))
    (should (member '(#x25A0 . #x25FF) table-ranges))))

;;; Group 16: kuro--probe-glyph-metrics

(ert-deftest kuro-faces-test--probe-glyph-metrics-nil-in-batch ()
  "kuro--probe-glyph-metrics returns nil in non-graphical (batch) Emacs."
  (should-not (kuro--probe-glyph-metrics ?a)))

(ert-deftest kuro-faces-test--probe-glyph-metrics-nil-on-error ()
  "kuro--probe-glyph-metrics returns nil when font-at signals an error."
  (cl-letf (((symbol-function 'font-at)
             (lambda (&rest _) (error "simulated font-at error"))))
    (should-not (kuro--probe-glyph-metrics ?a))))

;;; Group 17: Merged char-width — EA-Ambiguous AND emoji in one table

(ert-deftest kuro-faces-test--setup-handles-ea-ambiguous-and-emoji ()
  "Unified kuro--setup-char-width-table covers both EA-Ambiguous (width 1)
and emoji (width 2) ranges correctly.  The width-1 pass runs last so
EA-Ambiguous codepoints that also appear in the emoji block are pinned to 1."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    ;; EA-Ambiguous: must be 1
    (should (= 1 (char-width #x2500)))   ; ─ Box Drawing
    (should (= 1 (char-width #x2580)))   ; ▀ Block Elements
    (should (= 1 (char-width #x25A0)))   ; ■ Geometric Shapes
    (should (= 1 (char-width #x2600)))   ; ☀ Misc Symbols (also in emoji block)
    (should (= 1 (char-width #x2702)))   ; ✂ Dingbats (also in emoji block)
    (should (= 1 (char-width #x2800)))   ; ⠀ Braille
    ;; Emoji: must be 2
    (should (= 2 (char-width ?\U0001F525)))  ; 🔥
    (should (= 2 (char-width ?日)))      ; 日 CJK
    ;; Nerd Font PUA: must be 1
    (should (= 1 (char-width ?\xE0B0)))      ; Powerline arrow
    ;; Variation Selector: must be 0
    (should (= 0 (char-width #xFE00)))))

;;; Group 19: kuro--reapply-char-width-in-all-buffers

(ert-deftest kuro-faces-test--reapply-in-all-buffers-fixes-kuro-mode-buffer ()
  "kuro--reapply-char-width-in-all-buffers re-applies overrides in kuro-mode buffers."
  (let ((orig-env current-language-environment)
        (test-buf (get-buffer-create " *kuro-reapply-test*")))
    (unwind-protect
        (progn
          (with-current-buffer test-buf
            (setq major-mode 'kuro-mode)
            (kuro--setup-char-width-table)
            ;; Verify table is set up
            (should (= 1 (char-width #x2500))))
          ;; Simulate language environment change destroying the table
          (set-language-environment "Japanese")
          ;; After hook fires (called by set-language-environment),
          ;; overrides should have been re-applied
          (with-current-buffer test-buf
            (should (= 1 (char-width #x2500)))
            (should (= 1 (char-width #x2580)))))
      (kill-buffer test-buf)
      (set-language-environment orig-env))))

(ert-deftest kuro-faces-test--reapply-in-all-buffers-skips-non-kuro-buffers ()
  "kuro--reapply-char-width-in-all-buffers does not touch non-kuro-mode buffers."
  ;; Just verify it runs without error on buffers with other major modes.
  (with-temp-buffer
    (setq major-mode 'text-mode)
    ;; Should not signal any error
    (should-not (condition-case err
                    (progn (kuro--reapply-char-width-in-all-buffers) nil)
                  (error err)))))

;;; Group 20: kuro--assign-mono-fonts fallback

(ert-deftest kuro-faces-test--assign-mono-fonts-no-ascii-font ()
  "kuro--assign-mono-fonts is a no-op when face-attribute returns nil family."
  ;; In batch mode display-graphic-p is nil, so this is always a no-op.
  ;; Test verifies no error is signaled.
  (should-not (kuro--assign-mono-fonts)))

;;; Group 21: kuro--setup-fontset nerd-font fallback

(kuro-char-width-test--def-noop-in-batch kuro-faces-test--setup-fontset-noop-in-batch   kuro--setup-fontset)
(kuro-char-width-test--def-noop-in-batch kuro-faces-test--detect-nerd-font-nil-in-batch kuro--detect-nerd-font)

(ert-deftest kuro-faces-test--setup-fontset-no-nerd-font-no-error ()
  "kuro--setup-fontset does not error when no Nerd Font is available."
  ;; Stub display-graphic-p to t and font-family-list to empty list.
  (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
            ((symbol-function 'font-family-list) (lambda () '()))
            ((symbol-function 'set-fontset-font) (lambda (&rest _) nil)))
    (should-not (condition-case err
                    (progn (kuro--setup-fontset) nil)
                  (error err)))))

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

(defmacro kuro-char-width-test--def-detect-nerd-font (test-name fonts expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--detect-nerd-font' with fonts %S → %S." fonts expected)
     (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
               ((symbol-function 'font-family-list) (lambda () ',fonts)))
       ,(if expected
            `(should (equal (kuro--detect-nerd-font) ,expected))
          `(should-not (kuro--detect-nerd-font))))))

(kuro-char-width-test--def-detect-nerd-font
 kuro-faces-test--detect-nerd-font-prefers-symbols-nerd-font-mono
 ("DejaVu Sans Mono" "Symbols Nerd Font Mono" "SomeOther Nerd Font")
 "Symbols Nerd Font Mono")
(kuro-char-width-test--def-detect-nerd-font
 kuro-faces-test--detect-nerd-font-fallback-to-other-nerd-mono
 ("DejaVu Sans Mono" "Hack Nerd Font Mono")
 "Hack Nerd Font Mono")
(kuro-char-width-test--def-detect-nerd-font
 kuro-faces-test--detect-nerd-font-fallback-to-nerd-font
 ("DejaVu Sans Mono" "Hack Nerd Font")
 "Hack Nerd Font")
(kuro-char-width-test--def-detect-nerd-font
 kuro-faces-test--detect-nerd-font-nil-when-no-nerd-fonts
 ("DejaVu Sans Mono" "Consolas" "Courier New")
 nil)

(ert-deftest kuro-char-width-test--all-detect-nerd-font-cases-correct ()
  "Invariant: every detect-nerd-font table entry returns the expected result."
  (dolist (entry kuro-char-width-test--detect-nerd-font-table)
    (pcase-let ((`(,_name ,fonts ,expected) entry))
      (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
                ((symbol-function 'font-family-list) (lambda () fonts)))
        (if expected
            (should (equal (kuro--detect-nerd-font) expected))
          (should-not (kuro--detect-nerd-font)))))))

;;; Group 22: char-width-table data integrity

(defconst kuro-char-width-test--width-invariant-table
  '(;; Variation Selectors (FE00-FE0F): zero width
    (kuro-faces-test--variation-selector-fe00-is-0  #xFE00  0)
    (kuro-faces-test--variation-selector-fe0f-is-0  #xFE0F  0)
    ;; Nerd Font PUA (E000-F8FF): width 1
    (kuro-faces-test--pua-nerd-e000-is-1            #xE000  1)
    (kuro-faces-test--pua-nerd-f8ff-is-1            #xF8FF  1)
    ;; Supplementary Nerd Font PUA (F0000): width 1
    (kuro-faces-test--supplementary-pua-f0000-is-1  #xF0000 1))
  "Table of (test-name codepoint expected-width) for kuro--setup-char-width-table invariants.")

(defmacro kuro-char-width-test--def-width-invariant (test-name codepoint expected-width)
  `(ert-deftest ,test-name ()
     ,(format "kuro--setup-char-width-table: char-width #x%X => %d." codepoint expected-width)
     (with-temp-buffer
       (kuro--setup-char-width-table)
       (should (= ,expected-width (char-width ,codepoint))))))

(kuro-char-width-test--def-width-invariant kuro-faces-test--variation-selector-fe00-is-0  #xFE00  0)
(kuro-char-width-test--def-width-invariant kuro-faces-test--variation-selector-fe0f-is-0  #xFE0F  0)
(kuro-char-width-test--def-width-invariant kuro-faces-test--pua-nerd-e000-is-1            #xE000  1)
(kuro-char-width-test--def-width-invariant kuro-faces-test--pua-nerd-f8ff-is-1            #xF8FF  1)
(kuro-char-width-test--def-width-invariant kuro-faces-test--supplementary-pua-f0000-is-1  #xF0000 1)

(ert-deftest kuro-char-width-test--all-width-invariants-correct ()
  "Every entry in `kuro-char-width-test--width-invariant-table' has the expected char-width."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (dolist (entry kuro-char-width-test--width-invariant-table)
      (pcase-let ((`(,_name ,cp ,expected) entry))
        (should (= expected (char-width cp)))))))

;;; Group 23: kuro--refine-glyph-widths

(ert-deftest test-kuro-refine-glyph-widths-noop-when-not-graphical ()
  "kuro--refine-glyph-widths returns nil without probing when display-graphic-p is nil."
  (let (probe-called)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () nil))
              ((symbol-function 'kuro--probe-glyph-metrics)
               (lambda (&rest _) (setq probe-called t) nil)))
      (should-not (kuro--refine-glyph-widths))
      (should-not probe-called))))

(ert-deftest test-kuro-refine-glyph-widths-noop-when-cell-width-zero ()
  "kuro--refine-glyph-widths does nothing when frame-char-width returns 0."
  (let (probe-called)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
              ((symbol-function 'frame-char-width) (lambda () 0))
              ((symbol-function 'frame-char-height) (lambda () 16))
              ((symbol-function 'kuro--probe-glyph-metrics)
               (lambda (&rest _) (setq probe-called t) nil)))
      (kuro--refine-glyph-widths)
      (should-not probe-called))))

(defconst kuro-char-width-test--refine-redraw-table
  '((test-kuro-refine-glyph-widths-calls-redraw-when-changed  t   t)
    (test-kuro-refine-glyph-widths-no-redraw-when-unchanged   nil nil))
  "Table: (test-name rescale-result redraw-expected?) for kuro--refine-glyph-widths redraw dispatch.")

(defmacro kuro-char-width-test--def-refine-redraw (test-name rescale redraw)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--refine-glyph-widths' rescale=%s → redraw=%s." rescale redraw)
     (let (redraw-called)
       (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
                 ((symbol-function 'frame-char-width)  (lambda () 8))
                 ((symbol-function 'frame-char-height) (lambda () 16))
                 ((symbol-function 'kuro--rescale-font-for-glyph) (lambda (&rest _) ,rescale))
                 ((symbol-function 'redraw-display) (lambda () (setq redraw-called t))))
         (kuro--refine-glyph-widths)
         ,(if redraw '(should redraw-called) '(should-not redraw-called))))))

(kuro-char-width-test--def-refine-redraw
 test-kuro-refine-glyph-widths-calls-redraw-when-changed t t)
(kuro-char-width-test--def-refine-redraw
 test-kuro-refine-glyph-widths-no-redraw-when-unchanged nil nil)

(ert-deftest kuro-char-width-test--all-refine-redraw-cases-correct ()
  "Invariant: every refine-redraw table entry produces the expected redraw behavior."
  (dolist (entry kuro-char-width-test--refine-redraw-table)
    (pcase-let ((`(,_name ,rescale ,redraw) entry))
      (let (redraw-called)
        (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
                  ((symbol-function 'frame-char-width)  (lambda () 8))
                  ((symbol-function 'frame-char-height) (lambda () 16))
                  ((symbol-function 'kuro--rescale-font-for-glyph) (lambda (&rest _) rescale))
                  ((symbol-function 'redraw-display) (lambda () (setq redraw-called t))))
          (kuro--refine-glyph-widths)
          (if redraw (should redraw-called) (should-not redraw-called)))))))

(ert-deftest test-kuro-refine-glyph-widths-iterates-both-passes ()
  "kuro--refine-glyph-widths calls kuro--rescale-font-for-glyph for both passes."
  (let (called-chars)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
              ((symbol-function 'frame-char-width) (lambda () 8))
              ((symbol-function 'frame-char-height) (lambda () 16))
              ((symbol-function 'kuro--rescale-font-for-glyph)
               (lambda (probe-char _range _cw _ch)
                 (push probe-char called-chars)
                 nil))
              ((symbol-function 'redraw-display) (lambda () nil)))
      (kuro--refine-glyph-widths)
      ;; Pass 1: one probe char per kuro--ea-range-probe-table entry
      (dolist (entry kuro--ea-range-probe-table)
        (should (memq (cdr entry) called-chars)))
      ;; Pass 2: each char in kuro--glyph-extra-probes
      (dolist (c kuro--glyph-extra-probes)
        (should (memq c called-chars))))))

;;; Group 24: kuro--rescale-font-for-glyph

(ert-deftest test-kuro-rescale-font-nil-metrics-returns-nil ()
  "kuro--rescale-font-for-glyph returns nil when kuro--probe-glyph-metrics returns nil."
  (cl-letf (((symbol-function 'kuro--probe-glyph-metrics) (lambda (&rest _) nil)))
    (should-not (kuro--rescale-font-for-glyph ?a '(#x2500 . #x257F) 8 16))))

(ert-deftest test-kuro-rescale-font-exact-match-returns-nil ()
  "kuro--rescale-font-for-glyph returns nil when glyph metrics match cell size."
  ;; width-ratio = 8/8 = 1.0 <= 1.05 threshold, height within cell too
  (let ((mock-font (font-spec :family "MockFont" :size 12)))
    (cl-letf (((symbol-function 'kuro--probe-glyph-metrics)
               (lambda (&rest _)
                 (list :font mock-font :width 8 :height 14)))
              ((symbol-function 'set-fontset-font) (lambda (&rest _) nil)))
      (should-not (kuro--rescale-font-for-glyph ?a '(#x2500 . #x257F) 8 16)))))

(ert-deftest test-kuro-rescale-font-exceeds-threshold-calls-set-fontset ()
  "kuro--rescale-font-for-glyph calls set-fontset-font and returns t when ratio > 1.05."
  ;; glyph-width=16, cell-width=8 → width-ratio=2.0 >> 1.05
  (let ((set-fontset-called 0)
        (mock-font (font-spec :family "MockFont" :size 12)))
    (cl-letf (((symbol-function 'kuro--probe-glyph-metrics)
               (lambda (&rest _)
                 (list :font mock-font :width 16 :height 14)))
              ((symbol-function 'set-fontset-font)
               (lambda (&rest _) (setq set-fontset-called (1+ set-fontset-called)))))
      (should (kuro--rescale-font-for-glyph ?a '(#x2500 . #x257F) 8 16))
      ;; Called twice: once for nil (current frame) and once for t (default fontset)
      (should (= 2 set-fontset-called)))))

(provide 'kuro-char-width-test)
;;; kuro-char-width-test.el ends here
