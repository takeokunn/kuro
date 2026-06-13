;;; kuro-char-width-test-support.el --- Shared helpers for kuro-char-width tests  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-char-width)

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

(provide 'kuro-char-width-test-support)

;;; kuro-char-width-test-support.el ends here
