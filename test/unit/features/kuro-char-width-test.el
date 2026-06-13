;;; kuro-char-width-test.el --- Unit tests for kuro-char-width.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-char-width.el (EA-Ambiguous char-width tables,
;; override application, and glyph-metric probing).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'kuro-char-width-test-support)

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
;; Macro and table are defined in kuro-char-width-test-support.el

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

(provide 'kuro-char-width-test)

;;; kuro-char-width-test.el ends here
