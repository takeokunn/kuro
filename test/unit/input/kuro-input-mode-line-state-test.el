;;; kuro-input-mode-line-state-test.el --- Tests for kuro-input-mode-line-state.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the stateful helpers in kuro-input-mode-line-state:
;;   `kuro--line-set-buffer'  — whole-buffer replacement + point-at-end + display
;;   `kuro--line-reset-state'  — transient state reset
;;   `kuro--line-undo-push'    — undo stack growth and cap

;;; Code:

(require 'kuro-input-mode-test-support)
(require 'kuro-input-mode-line-state)


;;; Group 1 — kuro--line-set-buffer: state mutations

(ert-deftest kuro-input-mode-line-state-set-buffer-replaces-content ()
  "`kuro--line-set-buffer' replaces kuro--line-buffer with TEXT."
  (kuro-input-mode-test--with-line "hello" 5
    (kuro--line-set-buffer "world")
    (should (string= kuro--line-buffer "world"))))

(ert-deftest kuro-input-mode-line-state-set-buffer-point-at-end ()
  "`kuro--line-set-buffer' sets kuro--line-point to (length TEXT)."
  (kuro-input-mode-test--with-line "hello" 0
    (kuro--line-set-buffer "abc")
    (should (= kuro--line-point 3))))

(ert-deftest kuro-input-mode-line-state-set-buffer-empty-string ()
  "`kuro--line-set-buffer' on empty string leaves point at 0."
  (kuro-input-mode-test--with-line "hello" 5
    (kuro--line-set-buffer "")
    (should (string= kuro--line-buffer ""))
    (should (= kuro--line-point 0))))

(ert-deftest kuro-input-mode-line-state-set-buffer-calls-display ()
  "`kuro--line-set-buffer' calls `kuro--line-mode-update-display'."
  (kuro-input-mode-test--with-line "hello" 5
    (let ((calls 0))
      (cl-letf (((symbol-function 'kuro--line-mode-update-display)
                 (lambda () (setq calls (1+ calls)))))
        (kuro--line-set-buffer "new")
        (should (= calls 1))))))

(ert-deftest kuro-input-mode-line-state-set-buffer-unicode ()
  "`kuro--line-set-buffer' point equals character length for multibyte strings."
  (kuro-input-mode-test--with-line "" 0
    (kuro--line-set-buffer "あいう")
    (should (= kuro--line-point 3))
    (should (string= kuro--line-buffer "あいう"))))


;;; Group 2 — kuro--line-reset-state

(ert-deftest kuro-input-mode-line-state-reset-state-clears-transients ()
  "`kuro--line-reset-state' restores transient line state to defaults."
  (kuro-input-mode-test--with-line "hello" 3
    (setq kuro--line-history-idx 7
          kuro--line-history-stash "stash"
          kuro--line-undo-stack '((old . 1))
          kuro--line-yank-length 2
          kuro--line-yank-last-arg-idx 4
          kuro--line-yank-last-arg-len 6)
    (kuro--line-reset-state)
    (should (string= kuro--line-buffer ""))
    (should (= kuro--line-point 0))
    (should (= kuro--line-history-idx -1))
    (should (string= kuro--line-history-stash ""))
    (should (null kuro--line-undo-stack))
    (should (= kuro--line-yank-length 0))
    (should (= kuro--line-yank-last-arg-idx -1))
    (should (= kuro--line-yank-last-arg-len 0))))


;;; Group 3 — kuro--line-undo-push

(ert-deftest kuro-input-mode-line-state-undo-push-grows-stack ()
  "`kuro--line-undo-push' pushes current (buffer . point) onto the undo stack."
  (kuro-input-mode-test--with-buffer
    (setq kuro--line-buffer "hello" kuro--line-point 3 kuro--line-undo-stack nil)
    (kuro--line-undo-push)
    (should (= (length kuro--line-undo-stack) 1))
    (should (equal (car kuro--line-undo-stack) '("hello" . 3)))))

(ert-deftest kuro-input-mode-line-state-undo-push-caps-at-max-depth ()
  "`kuro--line-undo-push' trims the stack to `kuro--line-undo-max-depth'."
  (kuro-input-mode-test--with-buffer
    (let ((kuro--line-undo-max-depth 2))
      (setq kuro--line-undo-stack nil)
      (setq kuro--line-buffer "a" kuro--line-point 1) (kuro--line-undo-push)
      (setq kuro--line-buffer "b" kuro--line-point 1) (kuro--line-undo-push)
      (setq kuro--line-buffer "c" kuro--line-point 1) (kuro--line-undo-push)
      (should (= (length kuro--line-undo-stack) 2)))))


(provide 'kuro-input-mode-line-state-test)

;;; kuro-input-mode-line-state-test.el ends here
