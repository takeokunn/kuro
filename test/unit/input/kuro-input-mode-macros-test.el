;;; kuro-input-mode-macros-test.el --- Tests for kuro-input-mode-macros.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the CPS helpers in kuro-input-mode-macros:
;;   `kuro--line-splice'          — substring splice + new-point (no display call)
;;   `kuro--with-line-edit-undo'  — undo push + display continuation

;;; Code:

(require 'kuro-input-mode-test-support)
(require 'kuro-input-mode-macros)


;;; Group 1 — kuro--line-splice: pure state transform (no display side-effect)

(ert-deftest kuro-input-mode-macros-splice-middle-replacement ()
  "`kuro--line-splice' replaces buffer[from..to] with REPLACEMENT."
  (kuro-input-mode-test--with-line "hello world" 5
    (kuro--line-splice 6 11 "emacs" 11)
    (should (string= kuro--line-buffer "hello emacs"))))

(ert-deftest kuro-input-mode-macros-splice-sets-point ()
  "`kuro--line-splice' sets kuro--line-point to NEW-POINT."
  (kuro-input-mode-test--with-line "abcdef" 0
    (kuro--line-splice 2 4 "X" 3)
    (should (= kuro--line-point 3))))

(ert-deftest kuro-input-mode-macros-splice-delete-range ()
  "`kuro--line-splice' with empty REPLACEMENT acts as deletion."
  (kuro-input-mode-test--with-line "abcdef" 6
    (kuro--line-splice 2 4 "" 2)
    (should (string= kuro--line-buffer "abef"))
    (should (= kuro--line-point 2))))

(ert-deftest kuro-input-mode-macros-splice-insert-at-point ()
  "`kuro--line-splice' with FROM=TO inserts without deleting."
  (kuro-input-mode-test--with-line "ac" 1
    (kuro--line-splice 1 1 "b" 2)
    (should (string= kuro--line-buffer "abc"))
    (should (= kuro--line-point 2))))

(ert-deftest kuro-input-mode-macros-splice-prefix ()
  "`kuro--line-splice' starting at 0 replaces the prefix."
  (kuro-input-mode-test--with-line "hello" 5
    (kuro--line-splice 0 3 "HI" 2)
    (should (string= kuro--line-buffer "HIlo"))))

(ert-deftest kuro-input-mode-macros-splice-suffix ()
  "`kuro--line-splice' ending at (length buf) replaces the suffix."
  (kuro-input-mode-test--with-line "hello" 5
    (kuro--line-splice 3 5 "P!" 5)
    (should (string= kuro--line-buffer "helP!"))))

(ert-deftest kuro-input-mode-macros-splice-no-display-call ()
  "`kuro--line-splice' does NOT call `kuro--line-mode-update-display'."
  (kuro-input-mode-test--with-line "hello" 5
    (let ((calls 0))
      (cl-letf (((symbol-function 'kuro--line-mode-update-display)
                 (lambda () (setq calls (1+ calls)))))
        (kuro--line-splice 0 5 "new" 3)
        (should (= calls 0))))))

;;; Group 2 — kuro--line-splice composed inside kuro--with-line-edit-undo

(ert-deftest kuro-input-mode-macros-splice-with-undo-pushes-state ()
  "kuro--with-line-edit-undo + kuro--line-splice saves old state to undo stack."
  (kuro-input-mode-test--with-line "hello" 5
    (kuro--with-line-edit-undo
      (kuro--line-splice 0 5 "world" 5))
    (should (equal (car kuro--line-undo-stack) '("hello" . 5)))))

(ert-deftest kuro-input-mode-macros-splice-with-undo-calls-display ()
  "kuro--with-line-edit-undo calls `kuro--line-mode-update-display' after splice."
  (kuro-input-mode-test--with-line "hello" 5
    (let ((calls 0))
      (cl-letf (((symbol-function 'kuro--line-mode-update-display)
                 (lambda () (setq calls (1+ calls)))))
        (kuro--with-line-edit-undo
          (kuro--line-splice 0 5 "world" 5))
        (should (= calls 1))))))

;;; Group 3 — macro expansion shape tests

(defun kuro-input-mode-macros-test--expand (form)
  "Return a normalized macro expansion for FORM."
  (kuro-input-mode-macros-test--normalize-expansion (macroexpand form)))

(defun kuro-input-mode-macros-test--assert-expansion (name form expected)
  "Assert that FORM expands to EXPECTED, labeling the failure with NAME."
  (ert-info ((format "%s" name))
    (should (equal (kuro-input-mode-macros-test--expand form) expected))))

(ert-deftest kuro-input-mode-macros-test-line-expansion-shapes ()
  "Macro expansion shape tests stay table-driven so new cases stay low-ceremony."
  (let ((cases
         '((apply-word-transform
            (kuro--line-apply-word-transform
             (upcase (substring s start end)))
            (let* ((bounds (kuro--line-word-bounds-forward))
                   (start (car bounds))
                   (end (cdr bounds))
                   (s kuro--line-buffer))
              (when (> end start)
                (kuro--line-splice-with-undo start end
                                             (upcase (substring s start end))
                                             end))))
           (replace-buffer-with-undo
            (kuro--line-replace-buffer-with-undo (concat "a" "b"))
            (let ((replacement (concat "a" "b")))
              (kuro--line-splice-with-undo 0 (length kuro--line-buffer)
                                           replacement
                                           (length replacement))))
           (insert-with-undo
            (kuro--line-insert-with-undo start (concat "a" "b"))
            (let ((pos start)
                  (replacement (concat "a" "b")))
              (kuro--line-splice-with-undo pos pos
                                           replacement
                                           (+ pos (length replacement)))))
           (delete-with-undo
            (kuro--line-delete-with-undo start end)
            (progn
              (kuro--line-undo-push)
              (kuro--line-splice start end "" start)
              (kuro--line-mode-update-display)))
           (replace-range-with-undo
            (kuro--line-replace-range-with-undo start end (concat "a" "b"))
            (let ((from start)
                  (to end)
                  (replacement (concat "a" "b")))
              (kuro--line-splice-with-undo from to
                                           replacement
                                           (+ from (length replacement))))))))
    (dolist (case cases)
      (pcase-let ((`(,name ,form ,expected) case))
        (kuro-input-mode-macros-test--assert-expansion name form expected)))))

(provide 'kuro-input-mode-macros-test)

;;; kuro-input-mode-macros-test.el ends here
