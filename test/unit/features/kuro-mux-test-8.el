;;; kuro-mux-test-8.el --- Unit tests for kuro-mux-ext2.el binding tables  -*- lexical-binding: t; -*-

;;; Commentary:
;; Groups 37-38: data-invariant tests for kuro-mux--prefix-bindings and
;; kuro-mux--prefix-resize-bindings, plus a table-driven binding coverage
;; test that verifies every entry is correctly installed in kuro-mux-prefix-map.

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)


;;; Group 37 — kuro-mux--prefix-bindings table invariants

(ert-deftest kuro-mux-test-prefix-bindings-is-non-empty ()
  "`kuro-mux--prefix-bindings' is a non-empty alist."
  (should (consp kuro-mux--prefix-bindings)))

(ert-deftest kuro-mux-test-prefix-bindings-all-keys-are-strings ()
  "Every key in `kuro-mux--prefix-bindings' is a non-empty string."
  (dolist (entry kuro-mux--prefix-bindings)
    (should (stringp (car entry)))
    (should (> (length (car entry)) 0))))

(ert-deftest kuro-mux-test-prefix-bindings-all-values-are-symbols ()
  "Every value in `kuro-mux--prefix-bindings' is a symbol."
  (dolist (entry kuro-mux--prefix-bindings)
    (should (symbolp (cdr entry)))))

(ert-deftest kuro-mux-test-prefix-bindings-all-installed-in-map ()
  "Every entry in `kuro-mux--prefix-bindings' is correctly installed in the map."
  (dolist (entry kuro-mux--prefix-bindings)
    (let ((key (car entry))
          (fn  (cdr entry)))
      (should (eq (lookup-key kuro-mux-prefix-map (kbd key)) fn)))))

(ert-deftest kuro-mux-test-prefix-bindings-count ()
  "`kuro-mux--prefix-bindings' has at least 30 entries."
  (should (>= (length kuro-mux--prefix-bindings) 30)))


;;; Group 38 — kuro-mux--prefix-resize-bindings table invariants

(ert-deftest kuro-mux-test-prefix-resize-bindings-has-four-entries ()
  "`kuro-mux--prefix-resize-bindings' has exactly 4 arrow entries."
  (should (= (length kuro-mux--prefix-resize-bindings) 4)))

(ert-deftest kuro-mux-test-prefix-resize-bindings-all-entries-have-three-elements ()
  "Every resize binding entry has exactly 3 elements (key dir delta)."
  (dolist (entry kuro-mux--prefix-resize-bindings)
    (should (= (length entry) 3))))

(ert-deftest kuro-mux-test-prefix-resize-bindings-all-keys-are-strings ()
  "Every resize binding key is a non-empty string."
  (dolist (entry kuro-mux--prefix-resize-bindings)
    (should (stringp (car entry)))
    (should (> (length (car entry)) 0))))

(ert-deftest kuro-mux-test-prefix-resize-bindings-covers-all-directions ()
  "`kuro-mux--prefix-resize-bindings' covers all four arrow directions."
  (let ((dirs (mapcar #'cadr kuro-mux--prefix-resize-bindings)))
    (should (memq 'up    dirs))
    (should (memq 'down  dirs))
    (should (memq 'left  dirs))
    (should (memq 'right dirs))))

(ert-deftest kuro-mux-test-prefix-resize-bindings-all-deltas-positive ()
  "Every resize binding delta is a positive integer."
  (dolist (entry kuro-mux--prefix-resize-bindings)
    (let ((delta (caddr entry)))
      (should (integerp delta))
      (should (> delta 0)))))

(provide 'kuro-mux-test-8)
;;; kuro-mux-test-8.el ends here
