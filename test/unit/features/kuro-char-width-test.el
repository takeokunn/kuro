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

(provide 'kuro-char-width-test)

;;; kuro-char-width-test.el ends here
