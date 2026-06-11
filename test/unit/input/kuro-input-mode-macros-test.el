;;; kuro-input-mode-macros-test.el --- Tests for kuro-input-mode-macros.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the CPS helpers in kuro-input-mode-macros:
;;   `kuro--line-set-buffer'  — whole-buffer replacement + point-at-end + display
;;   `kuro--line-splice'      — substring splice + new-point (no display call)

;;; Code:

(require 'kuro-input-mode-test-support)
(require 'kuro-input-mode-macros)


;;; Group 1 — kuro--line-set-buffer: state mutations

(ert-deftest kuro-input-mode-macros-set-buffer-replaces-content ()
  "`kuro--line-set-buffer' replaces kuro--line-buffer with TEXT."
  (kuro-input-mode-test--with-line "hello" 5
    (kuro--line-set-buffer "world")
    (should (string= kuro--line-buffer "world"))))

(ert-deftest kuro-input-mode-macros-set-buffer-point-at-end ()
  "`kuro--line-set-buffer' sets kuro--line-point to (length TEXT)."
  (kuro-input-mode-test--with-line "hello" 0
    (kuro--line-set-buffer "abc")
    (should (= kuro--line-point 3))))

(ert-deftest kuro-input-mode-macros-set-buffer-empty-string ()
  "`kuro--line-set-buffer' on empty string leaves point at 0."
  (kuro-input-mode-test--with-line "hello" 5
    (kuro--line-set-buffer "")
    (should (string= kuro--line-buffer ""))
    (should (= kuro--line-point 0))))

(ert-deftest kuro-input-mode-macros-set-buffer-calls-display ()
  "`kuro--line-set-buffer' calls `kuro--line-mode-update-display'."
  (kuro-input-mode-test--with-line "hello" 5
    (let ((calls 0))
      (cl-letf (((symbol-function 'kuro--line-mode-update-display)
                 (lambda () (setq calls (1+ calls)))))
        (kuro--line-set-buffer "new")
        (should (= calls 1))))))

(ert-deftest kuro-input-mode-macros-set-buffer-unicode ()
  "`kuro--line-set-buffer' point equals character length for multibyte strings."
  (kuro-input-mode-test--with-line "" 0
    (kuro--line-set-buffer "あいう")
    (should (= kuro--line-point 3))
    (should (string= kuro--line-buffer "あいう"))))


;;; Group 2 — kuro--line-splice: pure state transform (no display side-effect)

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


;;; Group 3 — kuro--line-splice composed inside kuro--with-line-edit-undo

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

(provide 'kuro-input-mode-macros-test)

;;; kuro-input-mode-macros-test.el ends here
