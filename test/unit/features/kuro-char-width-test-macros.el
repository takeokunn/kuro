;;; kuro-char-width-test-macros.el --- Char width test macros  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-char-width)
(require 'kuro-char-width-test-cases)

(defmacro kuro-char-width-test--def-setup-width (test-name char expected)
  `(ert-deftest ,test-name ()
     ,(format "U+%04X has char-width %d after kuro--setup-char-width-table." char expected)
     (with-temp-buffer
       (kuro--setup-char-width-table)
       (should (= ,expected (char-width ,char))))))

(defmacro kuro-char-width-test--deftest-setup-widths ()
  `(progn
     ,@(mapcar (lambda (case)
                 (pcase-let ((`(,test-name ,char ,expected) case))
                   `(kuro-char-width-test--def-setup-width ,test-name ,char ,expected)))
               kuro-char-width-test--setup-width-table)))

(defmacro kuro-char-width-test--def-override-range (test-name desc range)
  `(ert-deftest ,test-name ()
     ,(format "kuro--apply-char-width-overrides sets %s to width 1." desc)
     (with-temp-buffer
       (make-local-variable 'char-width-table)
       (setq char-width-table (copy-sequence char-width-table))
       (kuro--apply-char-width-overrides)
       (should (= 1 (char-table-range char-width-table ',range))))))

(defmacro kuro-char-width-test--deftest-override-ranges ()
  `(progn
     ,@(mapcar (lambda (case)
                 (pcase-let ((`(,test-name ,desc ,range) case))
                   `(kuro-char-width-test--def-override-range ,test-name ,desc ,range)))
               kuro-char-width-test--override-range-table)))

(defmacro kuro-char-width-test--def-noop-in-batch (test-name fn-sym)
  `(ert-deftest ,test-name ()
     ,(format "`%s' is a no-op (returns nil) when `display-graphic-p' is nil." fn-sym)
     (should-not (,fn-sym))))

(defmacro kuro-char-width-test--def-detect-nerd-font (test-name fonts expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--detect-nerd-font' with fonts %S -> %S." fonts expected)
     (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
               ((symbol-function 'font-family-list) (lambda () ',fonts)))
       ,(if expected
            `(should (equal (kuro--detect-nerd-font) ,expected))
          `(should-not (kuro--detect-nerd-font))))))

(defmacro kuro-char-width-test--deftest-detect-nerd-fonts ()
  `(progn
     ,@(mapcar (lambda (case)
                 (pcase-let ((`(,test-name ,fonts ,expected) case))
                   `(kuro-char-width-test--def-detect-nerd-font ,test-name ,fonts ,expected)))
               kuro-char-width-test--detect-nerd-font-table)))

(defmacro kuro-char-width-test--def-width-invariant (test-name codepoint expected-width)
  `(ert-deftest ,test-name ()
     ,(format "kuro--setup-char-width-table: char-width #x%X => %d." codepoint expected-width)
     (with-temp-buffer
       (kuro--setup-char-width-table)
       (should (= ,expected-width (char-width ,codepoint))))))

(defmacro kuro-char-width-test--deftest-width-invariants ()
  `(progn
     ,@(mapcar (lambda (case)
                 (pcase-let ((`(,test-name ,codepoint ,expected-width) case))
                   `(kuro-char-width-test--def-width-invariant
                     ,test-name ,codepoint ,expected-width)))
               kuro-char-width-test--width-invariant-table)))

(defmacro kuro-char-width-test--def-refine-redraw (test-name rescale redraw)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--refine-glyph-widths' rescale=%s -> redraw=%s." rescale redraw)
     (let (redraw-called)
       (cl-letf (((symbol-function 'display-graphic-p) (lambda () t))
                 ((symbol-function 'frame-char-width)  (lambda () 8))
                 ((symbol-function 'frame-char-height) (lambda () 16))
                 ((symbol-function 'kuro--rescale-font-for-glyph) (lambda (&rest _) ,rescale))
                 ((symbol-function 'redraw-display) (lambda () (setq redraw-called t))))
         (kuro--refine-glyph-widths)
         ,(if redraw '(should redraw-called) '(should-not redraw-called))))))

(defmacro kuro-char-width-test--deftest-refine-redraws ()
  `(progn
     ,@(mapcar (lambda (case)
                 (pcase-let ((`(,test-name ,rescale ,redraw) case))
                   `(kuro-char-width-test--def-refine-redraw ,test-name ,rescale ,redraw)))
               kuro-char-width-test--refine-redraw-table)))

(provide 'kuro-char-width-test-macros)
;;; kuro-char-width-test-macros.el ends here
