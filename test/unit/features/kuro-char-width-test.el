;;; kuro-char-width-test.el --- Unit tests for kuro-char-width.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-char-width.el (EA-Ambiguous char-width tables,
;; override application, and glyph-metric probing).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'kuro-char-width-test-support)

;;; Group 13: EA-Ambiguous char-width — kuro--setup-char-width-table spot checks

(kuro-char-width-test--deftest-setup-widths)

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

(kuro-char-width-test--deftest-override-ranges)

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


;;; Group 17: kuro-char-width-setup

(ert-deftest kuro-char-width-setup-adds-hook ()
  "`kuro-char-width-setup' adds `kuro--reapply-char-width-in-all-buffers' to `set-language-environment-hook'."
  (let ((set-language-environment-hook nil))
    (kuro-char-width-setup)
    (should (memq #'kuro--reapply-char-width-in-all-buffers
                  set-language-environment-hook))))

(ert-deftest kuro-char-width-setup-is-idempotent ()
  "`kuro-char-width-setup' called twice does not add duplicate hook entries."
  (let ((set-language-environment-hook nil))
    (kuro-char-width-setup)
    (kuro-char-width-setup)
    (should (= 1 (length (memq #'kuro--reapply-char-width-in-all-buffers
                               set-language-environment-hook))))))

;;; kuro--set-fontset-font-both macro structural tests

(ert-deftest kuro-char-width-set-fontset-font-both-expands-to-progn ()
  "`kuro--set-fontset-font-both' expands to a `progn' with two `set-fontset-font' calls."
  (let* ((exp (macroexpand-1
               '(kuro--set-fontset-font-both (#x2580 . #x259F) my-spec)))
         (body (cdr exp)))
    (should (eq (car exp) 'progn))
    (should (= (length body) 2))
    (should (cl-every (lambda (f) (eq (car f) 'set-fontset-font)) body))))

(ert-deftest kuro-char-width-set-fontset-font-both-targets-nil-and-t ()
  "`kuro--set-fontset-font-both' targets nil (current frame) then t (default fontset)."
  (let* ((exp (macroexpand-1
               '(kuro--set-fontset-font-both (#x2190 . #x21FF) my-spec)))
         (first-target  (cadr (car (cdr exp))))
         (second-target (cadr (cadr (cdr exp)))))
    (should (null first-target))
    (should (eq second-target t))))

(provide 'kuro-char-width-test)

;;; kuro-char-width-test.el ends here
