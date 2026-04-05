;;; kuro-char-width-test.el --- Unit tests for kuro-char-width.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-char-width.el (EA-Ambiguous char-width tables,
;; override application, and glyph-metric probing).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-char-width)

;;; Group 13: EA-Ambiguous char-width (kuro--char-width-overrides)

(ert-deftest kuro-faces-test--char-width-table-box-drawing-start ()
  "U+2500 (BOX DRAWINGS LIGHT HORIZONTAL) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2500)))))

(ert-deftest kuro-faces-test--char-width-table-box-drawing-end ()
  "U+257F (BOX DRAWINGS LIGHT UP) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x257F)))))

(ert-deftest kuro-faces-test--char-width-table-block-elements-start ()
  "U+2580 (UPPER HALF BLOCK) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2580)))))

(ert-deftest kuro-faces-test--char-width-table-block-elements-end ()
  "U+259F (QUADRANT UPPER RIGHT AND LOWER LEFT AND LOWER RIGHT) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x259F)))))

(ert-deftest kuro-faces-test--char-width-table-arrows-start ()
  "U+2190 (LEFTWARDS ARROW) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2190)))))

(ert-deftest kuro-faces-test--char-width-table-arrows-end ()
  "U+21FF (last arrow in U+21xx block) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x21FF)))))

(ert-deftest kuro-faces-test--char-width-table-math-operators ()
  "U+2200 (FOR ALL) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2200)))))

(ert-deftest kuro-faces-test--char-width-table-geometric-shapes ()
  "U+25A0 (BLACK SQUARE) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x25A0)))))

(ert-deftest kuro-faces-test--char-width-table-braille-start ()
  "U+2800 (BRAILLE PATTERN BLANK) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2800)))))

(ert-deftest kuro-faces-test--char-width-table-braille-end ()
  "U+28FF (last Braille pattern) is width 1 after setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x28FF)))))

(ert-deftest kuro-faces-test--char-width-table-misc-symbols ()
  "U+2600 (BLACK SUN WITH RAYS) is width 1 after setup.
This codepoint appears in kuro--char-width-2-ranges (emoji) AND
kuro--char-width-1-ranges (EA-Ambiguous); the width-1 pass must win."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #x2600)))))

(ert-deftest kuro-faces-test--char-width-table-is-buffer-local ()
  "kuro--setup-char-width-table makes char-width-table buffer-local."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (local-variable-p 'char-width-table))))

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
          ;; Simulate kuro-mode setup
          (setq major-mode 'kuro-mode)
          (kuro--setup-char-width-table)
          (should (= 1 (char-width #x25A0)))
          ;; Now set-language-environment "Japanese" — this destroys the table
          (set-language-environment "Japanese")
          ;; The hook should have re-applied overrides
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

(ert-deftest kuro-faces-test--apply-overrides-sets-box-drawing-width ()
  "kuro--apply-char-width-overrides forces box-drawing range to width 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2500 . #x257F))))))

(ert-deftest kuro-faces-test--apply-overrides-sets-block-elements-width ()
  "kuro--apply-char-width-overrides forces block-elements range to width 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2580 . #x259F))))))

(ert-deftest kuro-faces-test--apply-overrides-sets-arrows-width ()
  "kuro--apply-char-width-overrides forces arrows range to width 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2190 . #x21FF))))))

(ert-deftest kuro-faces-test--apply-overrides-sets-braille-width ()
  "kuro--apply-char-width-overrides forces braille range to width 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2800 . #x28FF))))))

(ert-deftest kuro-faces-test--apply-overrides-all-ranges-covered ()
  "kuro--apply-char-width-overrides sets every entry in kuro--char-width-overrides to 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (dolist (range kuro--char-width-overrides)
      (should (= 1 (char-table-range char-width-table range))))))

;;; Group 15: Font glyph-width fix structure

(ert-deftest kuro-faces-test--assign-mono-fonts-noop-in-batch ()
  "kuro--assign-mono-fonts is a no-op when display-graphic-p is nil (batch mode)."
  (should-not (kuro--assign-mono-fonts)))

(ert-deftest kuro-faces-test--refine-glyph-widths-noop-in-batch ()
  "kuro--refine-glyph-widths is a no-op when display-graphic-p is nil (batch mode)."
  (should-not (kuro--refine-glyph-widths)))

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
    (should (= 2 (char-width ?\u65E5)))      ; 日 CJK
    ;; Nerd Font PUA: must be 1
    (should (= 1 (char-width ?\xE0B0)))      ; Powerline arrow
    ;; Variation Selector: must be 0
    (should (= 0 (char-width #xFE00)))))

;;; Group 18: kuro--apply-char-width-overrides — each range individually

(ert-deftest kuro-faces-test--apply-overrides-arrows-range ()
  "kuro--apply-char-width-overrides sets Arrows range (#x2190-#x21FF) to 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2190 . #x21FF))))))

(ert-deftest kuro-faces-test--apply-overrides-math-operators-range ()
  "kuro--apply-char-width-overrides sets Math Operators (#x2200-#x22FF) to 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2200 . #x22FF))))))

(ert-deftest kuro-faces-test--apply-overrides-misc-technical-range ()
  "kuro--apply-char-width-overrides sets Misc Technical (#x2300-#x23FF) to 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2300 . #x23FF))))))

(ert-deftest kuro-faces-test--apply-overrides-geometric-shapes-range ()
  "kuro--apply-char-width-overrides sets Geometric Shapes (#x25A0-#x25FF) to 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x25A0 . #x25FF))))))

(ert-deftest kuro-faces-test--apply-overrides-misc-symbols-range ()
  "kuro--apply-char-width-overrides sets Misc Symbols (#x2600-#x26FF) to 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2600 . #x26FF))))))

(ert-deftest kuro-faces-test--apply-overrides-dingbats-range ()
  "kuro--apply-char-width-overrides sets Dingbats (#x2700-#x27BF) to 1."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (should (= 1 (char-table-range char-width-table '(#x2700 . #x27BF))))))

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

(ert-deftest kuro-faces-test--setup-fontset-noop-in-batch ()
  "kuro--setup-fontset is a no-op in non-graphical Emacs (batch mode)."
  ;; display-graphic-p returns nil in batch — entire body must be skipped.
  (should-not (kuro--setup-fontset)))

(ert-deftest kuro-faces-test--detect-nerd-font-nil-in-batch ()
  "kuro--detect-nerd-font returns nil in non-graphical Emacs (batch mode)."
  (should-not (kuro--detect-nerd-font)))

(ert-deftest kuro-faces-test--setup-fontset-no-nerd-font-no-error ()
  "kuro--setup-fontset does not error when no Nerd Font is available."
  ;; Stub display-graphic-p to t and font-family-list to empty list.
  (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
            ((symbol-function 'font-family-list) (lambda () '()))
            ((symbol-function 'set-fontset-font) (lambda (&rest _) nil)))
    (should-not (condition-case err
                    (progn (kuro--setup-fontset) nil)
                  (error err)))))

(ert-deftest kuro-faces-test--detect-nerd-font-prefers-symbols-nerd-font-mono ()
  "kuro--detect-nerd-font returns \"Symbols Nerd Font Mono\" when it is available."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
            ((symbol-function 'font-family-list)
             (lambda ()
               '("DejaVu Sans Mono"
                 "Symbols Nerd Font Mono"
                 "SomeOther Nerd Font"))))
    (should (equal (kuro--detect-nerd-font) "Symbols Nerd Font Mono"))))

(ert-deftest kuro-faces-test--detect-nerd-font-fallback-to-other-nerd-mono ()
  "kuro--detect-nerd-font falls back to any 'Nerd Font Mono' when preferred is absent."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
            ((symbol-function 'font-family-list)
             (lambda ()
               '("DejaVu Sans Mono"
                 "Hack Nerd Font Mono"))))
    (should (equal (kuro--detect-nerd-font) "Hack Nerd Font Mono"))))

(ert-deftest kuro-faces-test--detect-nerd-font-fallback-to-nerd-font ()
  "kuro--detect-nerd-font falls back to 'Nerd Font' (no Mono suffix) as last resort."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
            ((symbol-function 'font-family-list)
             (lambda ()
               '("DejaVu Sans Mono"
                 "Hack Nerd Font"))))
    (should (equal (kuro--detect-nerd-font) "Hack Nerd Font"))))

(ert-deftest kuro-faces-test--detect-nerd-font-nil-when-no-nerd-fonts ()
  "kuro--detect-nerd-font returns nil when no Nerd Font family is present."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
            ((symbol-function 'font-family-list)
             (lambda () '("DejaVu Sans Mono" "Consolas" "Courier New"))))
    (should-not (kuro--detect-nerd-font))))

;;; Group 22: char-width-table data integrity

(ert-deftest kuro-faces-test--variation-selector-is-width-0 ()
  "Variation Selectors (#xFE00-#xFE0F) must be width 0 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 0 (char-width #xFE00)))
    (should (= 0 (char-width #xFE0F)))))

(ert-deftest kuro-faces-test--pua-nerd-font-is-width-1 ()
  "Nerd Font PUA range (#xE000-#xF8FF) must be width 1 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #xE000)))
    (should (= 1 (char-width #xF8FF)))))

(ert-deftest kuro-faces-test--supplementary-pua-is-width-1 ()
  "Supplementary Nerd Font PUA (#xF0000) must be width 1 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width #xF0000)))))

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

(ert-deftest test-kuro-refine-glyph-widths-calls-redraw-when-changed ()
  "kuro--refine-glyph-widths calls redraw-display when any rescale returns t."
  (let (redraw-called)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
              ((symbol-function 'frame-char-width) (lambda () 8))
              ((symbol-function 'frame-char-height) (lambda () 16))
              ((symbol-function 'kuro--rescale-font-for-glyph) (lambda (&rest _) t))
              ((symbol-function 'redraw-display) (lambda () (setq redraw-called t))))
      (kuro--refine-glyph-widths)
      (should redraw-called))))

(ert-deftest test-kuro-refine-glyph-widths-no-redraw-when-unchanged ()
  "kuro--refine-glyph-widths does NOT call redraw-display when no rescale was needed."
  (let (redraw-called)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
              ((symbol-function 'frame-char-width) (lambda () 8))
              ((symbol-function 'frame-char-height) (lambda () 16))
              ((symbol-function 'kuro--rescale-font-for-glyph) (lambda (&rest _) nil))
              ((symbol-function 'redraw-display) (lambda () (setq redraw-called t))))
      (kuro--refine-glyph-widths)
      (should-not redraw-called))))

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

;;; Group 25: kuro--probe-glyph-metrics

(ert-deftest test-kuro-probe-glyph-metrics-nil-in-batch-mode ()
  "kuro--probe-glyph-metrics returns nil when Emacs is in batch/non-graphical mode."
  ;; In batch mode font-at would fail; the condition-case in the function
  ;; catches that and returns nil.
  (should-not (kuro--probe-glyph-metrics ?a)))

(ert-deftest test-kuro-probe-glyph-metrics-nil-when-font-at-nil ()
  "kuro--probe-glyph-metrics returns nil when font-at returns nil."
  (cl-letf (((symbol-function 'font-at) (lambda (&rest _) nil)))
    (should-not (kuro--probe-glyph-metrics ?a))))

;;; Group 26: kuro--assign-mono-fonts error handling

(ert-deftest test-kuro-assign-mono-fonts-swallows-font-spec-error ()
  "kuro--assign-mono-fonts completes without propagating errors from set-fontset-font.
The per-range loop body is wrapped in (condition-case nil ... (error nil));
errors from set-fontset-font must be silently swallowed."
  ;; Build a minimal fake font object that font-get can read :family from.
  (let ((fake-font (font-spec :family "MockFont" :size 12)))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
              ((symbol-function 'face-attribute) (lambda (&rest _) fake-font))
              ((symbol-function 'set-fontset-font)
               (lambda (&rest _) (error "simulated set-fontset-font error"))))
      (should-not (condition-case err
                      (progn (kuro--assign-mono-fonts) nil)
                    (error err))))))

;;; Group 27: kuro--reapply-char-width-in-all-buffers dead buffer safety

(ert-deftest test-kuro-reapply-char-width-skips-dead-buffer ()
  "kuro--reapply-char-width-in-all-buffers completes without error on dead buffers."
  ;; Create a buffer, record it, kill it, then call the function.
  ;; The function uses buffer-live-p, so it should silently skip the dead buffer.
  (let ((dead-buf (generate-new-buffer " *kuro-dead-buf-test*")))
    (with-current-buffer dead-buf
      (setq major-mode 'kuro-mode))
    (kill-buffer dead-buf)
    (should-not (buffer-live-p dead-buf))
    (should-not (condition-case err
                    (progn (kuro--reapply-char-width-in-all-buffers) nil)
                  (error err)))))

;;; Group 28: kuro--setup-char-width-table — width-2 ranges (CJK, Hangul, Fullwidth)

(ert-deftest kuro-char-width-test--cjk-unified-start-is-width-2 ()
  "U+4E00 (first CJK Unified Ideograph) is width 2 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 2 (char-width #x4E00)))))

(ert-deftest kuro-char-width-test--cjk-unified-end-is-width-2 ()
  "U+9FFF (last CJK Unified Ideograph in main block) is width 2 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 2 (char-width #x9FFF)))))

(ert-deftest kuro-char-width-test--hangul-syllable-start-is-width-2 ()
  "U+AC00 (first Hangul Syllable) is width 2 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 2 (char-width #xAC00)))))

(ert-deftest kuro-char-width-test--hangul-syllable-end-is-width-2 ()
  "U+D7AF (last Hangul Syllable) is width 2 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 2 (char-width #xD7AF)))))

(ert-deftest kuro-char-width-test--fullwidth-forms-start-is-width-2 ()
  "U+FF01 (FULLWIDTH EXCLAMATION MARK) is width 2 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 2 (char-width #xFF01)))))

(ert-deftest kuro-char-width-test--fullwidth-forms-end-is-width-2 ()
  "U+FF60 (FULLWIDTH RIGHT WHITE PARENTHESIS) is width 2 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 2 (char-width #xFF60)))))

(ert-deftest kuro-char-width-test--hiragana-start-is-width-2 ()
  "U+3041 (HIRAGANA LETTER SMALL A) is width 2 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 2 (char-width #x3041)))))

(ert-deftest kuro-char-width-test--katakana-start-is-width-2 ()
  "U+30A1 (KATAKANA LETTER SMALL A) is width 2 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 2 (char-width #x30A1)))))

(ert-deftest kuro-char-width-test--table-inherits-parent-for-ascii ()
  "ASCII characters (U+0041 = 'A') must still be width 1 via parent table inheritance."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 1 (char-width ?A)))
    (should (= 1 (char-width ?z)))
    (should (= 1 (char-width ?0)))))

(ert-deftest kuro-char-width-test--apply-overrides-is-idempotent ()
  "Calling kuro--apply-char-width-overrides twice yields the same result as once."
  (with-temp-buffer
    (make-local-variable 'char-width-table)
    (setq char-width-table (copy-sequence char-width-table))
    (kuro--apply-char-width-overrides)
    (kuro--apply-char-width-overrides)
    (dolist (range kuro--char-width-overrides)
      (should (= 1 (char-table-range char-width-table range))))))

;;; Group 29: kuro--setup-char-width-table — width-0 range full boundary

(ert-deftest kuro-char-width-test--variation-selector-mid-range-is-width-0 ()
  "U+FE08 (Variation Selector 9, mid-range) must be width 0 after table setup."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should (= 0 (char-width #xFE08)))))

(ert-deftest kuro-char-width-test--char-outside-variation-selector-range-not-zero ()
  "U+FDF0 (Arabic Ligature, well outside #xFE00-#xFE0F) must not be width 0.
The VS range is strictly #xFE00-#xFE0F; characters before it should be unaffected."
  (with-temp-buffer
    (kuro--setup-char-width-table)
    (should-not (= 0 (char-width #xFDF0)))))

;;; Group 30: kuro--detect-nerd-font — priority ordering edge cases

(ert-deftest kuro-char-width-test--detect-nerd-font-exact-name-wins-over-partial ()
  "kuro--detect-nerd-font prefers 'Symbols Nerd Font Mono' even when another
Nerd Font Mono is listed first in the font-family-list."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
            ((symbol-function 'font-family-list)
             (lambda ()
               '("Hack Nerd Font Mono"
                 "Symbols Nerd Font Mono"
                 "JetBrains Mono Nerd Font"))))
    (should (equal (kuro--detect-nerd-font) "Symbols Nerd Font Mono"))))

(ert-deftest kuro-char-width-test--detect-nerd-font-nerd-mono-wins-over-non-mono ()
  "kuro--detect-nerd-font prefers 'Nerd Font Mono' over bare 'Nerd Font'."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
            ((symbol-function 'font-family-list)
             (lambda ()
               '("Hack Nerd Font"
                 "Hack Nerd Font Mono"))))
    (should (equal (kuro--detect-nerd-font) "Hack Nerd Font Mono"))))

;;; Group 31: kuro--setup-fontset — argument verification

(ert-deftest kuro-char-width-test--setup-fontset-calls-set-fontset-with-nerd-font ()
  "kuro--setup-fontset calls set-fontset-font with the detected Nerd Font name
for both PUA ranges when a Nerd Font is found."
  (let (fontset-calls)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
              ((symbol-function 'font-family-list)
               (lambda () '("Symbols Nerd Font Mono")))
              ((symbol-function 'set-fontset-font)
               (lambda (_target range font &rest _)
                 (push (list range font) fontset-calls))))
      (kuro--setup-fontset)
      ;; Two PUA ranges should have been registered
      (should (>= (length fontset-calls) 2))
      ;; Every registered font name should be the Nerd Font
      (dolist (call fontset-calls)
        (when (stringp (cadr call))
          (should (equal (cadr call) "Symbols Nerd Font Mono")))))))

(ert-deftest kuro-char-width-test--setup-fontset-registers-emoji-font ()
  "kuro--setup-fontset calls set-fontset-font for the emoji symbol set
when an emoji font is found in the font family list."
  (let (emoji-registered)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
              ((symbol-function 'font-family-list)
               (lambda () '("Noto Color Emoji")))
              ((symbol-function 'set-fontset-font)
               (lambda (_target range font &rest _)
                 (when (eq range 'emoji)
                   (setq emoji-registered font)))))
      (kuro--setup-fontset)
      (should (equal emoji-registered "Noto Color Emoji")))))

(ert-deftest kuro-char-width-test--setup-fontset-no-emoji-font-no-error ()
  "kuro--setup-fontset does not error when no emoji font is available."
  (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
            ((symbol-function 'font-family-list) (lambda () '("Symbols Nerd Font Mono")))
            ((symbol-function 'set-fontset-font) (lambda (&rest _) nil)))
    (should-not (condition-case err
                    (progn (kuro--setup-fontset) nil)
                  (error err)))))

;;; Group 32: kuro--refine-glyph-widths — additional guard paths

(ert-deftest kuro-char-width-test--refine-glyph-widths-noop-when-cell-height-zero ()
  "kuro--refine-glyph-widths does nothing when frame-char-height returns 0."
  (let (probe-called)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
              ((symbol-function 'frame-char-width) (lambda () 8))
              ((symbol-function 'frame-char-height) (lambda () 0))
              ((symbol-function 'kuro--rescale-font-for-glyph)
               (lambda (&rest _) (setq probe-called t) nil)))
      (kuro--refine-glyph-widths)
      (should-not probe-called))))

(ert-deftest kuro-char-width-test--refine-glyph-widths-noop-when-cell-width-nil ()
  "kuro--refine-glyph-widths does nothing when frame-char-width returns nil."
  (let (probe-called)
    (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
              ((symbol-function 'frame-char-width) (lambda () nil))
              ((symbol-function 'frame-char-height) (lambda () 16))
              ((symbol-function 'kuro--rescale-font-for-glyph)
               (lambda (&rest _) (setq probe-called t) nil)))
      (kuro--refine-glyph-widths)
      (should-not probe-called))))

;;; Group 33: kuro--rescale-font-for-glyph — height-driven rescale path

(ert-deftest kuro-char-width-test--rescale-font-height-driven-rescale ()
  "kuro--rescale-font-for-glyph rescales when glyph height alone exceeds
the 1.05x threshold (width is within cell but height is too tall)."
  (let (set-fontset-called
        (mock-font (font-spec :family "TallFont" :size 12)))
    (cl-letf (((symbol-function 'kuro--probe-glyph-metrics)
               ;; width = 8 (exact match), height = 20 vs cell-height 16 → ratio 1.25 > 1.05
               (lambda (&rest _)
                 (list :font mock-font :width 8 :height 20)))
              ((symbol-function 'set-fontset-font)
               (lambda (&rest _) (setq set-fontset-called t))))
      (should (kuro--rescale-font-for-glyph ?a '(#x2580 . #x259F) 8 16))
      (should set-fontset-called))))

(ert-deftest kuro-char-width-test--rescale-font-nil-height-uses-width-ratio ()
  "kuro--rescale-font-for-glyph falls back to width-only ratio when height is nil."
  ;; glyph-height nil → height-ratio forced to 1.0; only width-ratio matters
  (let (set-fontset-called
        (mock-font (font-spec :family "WideFont" :size 12)))
    (cl-letf (((symbol-function 'kuro--probe-glyph-metrics)
               (lambda (&rest _)
                 (list :font mock-font :width 16 :height nil)))
              ((symbol-function 'set-fontset-font)
               (lambda (&rest _) (setq set-fontset-called t))))
      ;; width 16 vs cell-width 8 → ratio 2.0 > 1.05 → must rescale
      (should (kuro--rescale-font-for-glyph ?a '(#x2500 . #x257F) 8 16))
      (should set-fontset-called))))

(ert-deftest kuro-char-width-test--rescale-font-symbol-family-converted-to-string ()
  "kuro--rescale-font-for-glyph converts a symbol :family to a string for font-spec."
  ;; font-get can return a symbol for :family; verify no error is signaled.
  (let ((mock-font (font-spec :family "SymbolFamily" :size 12))
        set-fontset-called)
    ;; Patch font-get to return a symbol for :family
    (cl-letf (((symbol-function 'kuro--probe-glyph-metrics)
               (lambda (&rest _)
                 (list :font mock-font :width 16 :height 14)))
              ((symbol-function 'font-get)
               (lambda (font prop)
                 (cond ((eq prop :family) 'SymbolFamily)
                       ((eq prop :size)   12)
                       (t nil))))
              ((symbol-function 'set-fontset-font)
               (lambda (&rest _) (setq set-fontset-called t))))
      (should-not (condition-case err
                      (progn
                        (kuro--rescale-font-for-glyph ?a '(#x2500 . #x257F) 8 16)
                        nil)
                    (error err))))))

;;; Group 34: kuro--glyph-extra-probes membership

(ert-deftest kuro-char-width-test--glyph-extra-probes-contains-record-symbol ()
  "kuro--glyph-extra-probes must contain U+23FA (RECORD symbol)."
  (should (memq #x23FA kuro--glyph-extra-probes)))

(ert-deftest kuro-char-width-test--glyph-extra-probes-contains-black-circle ()
  "kuro--glyph-extra-probes must contain U+25CF (BLACK CIRCLE)."
  (should (memq #x25CF kuro--glyph-extra-probes)))

(ert-deftest kuro-char-width-test--glyph-extra-probes-contains-check-mark ()
  "kuro--glyph-extra-probes must contain U+2714 (HEAVY CHECK MARK)."
  (should (memq #x2714 kuro--glyph-extra-probes)))

(ert-deftest kuro-char-width-test--glyph-extra-probes-contains-angle-ornament ()
  "kuro--glyph-extra-probes must contain U+276F (HEAVY RIGHT-POINTING ANGLE ornament)."
  (should (memq #x276F kuro--glyph-extra-probes)))

(ert-deftest kuro-char-width-test--glyph-extra-probes-length ()
  "kuro--glyph-extra-probes must have exactly 4 entries."
  (should (= 4 (length kuro--glyph-extra-probes))))

;;; Group 35: kuro--set-fontset-font-both macro (non-graphical stubs)

(ert-deftest kuro-char-width-test--set-fontset-font-both-calls-nil-and-t ()
  "kuro--set-fontset-font-both calls set-fontset-font for both nil and t fontsets."
  (let ((calls nil))
    (cl-letf (((symbol-function 'set-fontset-font)
               (lambda (fontset range spec &optional frame add)
                 (push (list fontset range spec add) calls))))
      (kuro--set-fontset-font-both '(#x2500 . #x257F) "test-spec")
      ;; Must produce exactly two calls
      (should (= (length calls) 2))
      ;; One call with nil fontset (current frame)
      (should (cl-some (lambda (c) (null (car c))) calls))
      ;; One call with t fontset (default template)
      (should (cl-some (lambda (c) (eq t (car c))) calls)))))

(ert-deftest kuro-char-width-test--set-fontset-font-both-passes-range ()
  "kuro--set-fontset-font-both passes the given range to both set-fontset-font calls."
  (let ((seen-ranges nil))
    (cl-letf (((symbol-function 'set-fontset-font)
               (lambda (_fontset range _spec &optional _frame _add)
                 (push range seen-ranges))))
      (kuro--set-fontset-font-both '(#xE000 . #xF8FF) "nerd-font")
      (should (= (length seen-ranges) 2))
      (should (cl-every (lambda (r) (equal r '(#xE000 . #xF8FF))) seen-ranges)))))

(ert-deftest kuro-char-width-test--set-fontset-font-both-uses-prepend ()
  "kuro--set-fontset-font-both always uses 'prepend so existing fonts serve as fallback."
  (let ((add-args nil))
    (cl-letf (((symbol-function 'set-fontset-font)
               (lambda (_fontset _range _spec &optional _frame add)
                 (push add add-args))))
      (kuro--set-fontset-font-both '(#x2500 . #x257F) "mono")
      (should (cl-every (lambda (a) (eq a 'prepend)) add-args)))))

(provide 'kuro-char-width-test)

;;; kuro-char-width-test.el ends here
