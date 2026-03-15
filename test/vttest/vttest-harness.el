;;; vttest-harness.el --- VTtest-style harness for Kuro -*- lexical-binding: t; -*-

;; This harness runs vttest-style sequences WITHOUT spawning a real PTY.
;; It directly feeds escape sequences to the Rust parser and checks the
;; resulting grid state. This avoids the session-killing PTY issues.

;; Usage:
;;   1. Build kuro: make build
;;   2. Start Emacs: emacs -Q --batch -L emacs-lisp -L test/vttest -f vttest-harness.el
;;   3. Run tests: M-x ert-run-tests-batch vttest-
(require 'ert)

;;; Helper functions using dynamic module test FFI
(defun vttest--make-grid (rows cols)
  "Create a fresh grid for testing."
  (kuro-core-test-create rows cols))

(defun vttest--destroy-grid ()
  "Destroy test terminal."
  (kuro-core-test-destroy))

(defun vttest--feed-bytes (bytes)
  "Feed BYTES to the parser."
  (kuro-core-test-feed bytes))

(defun vttest--get-cell (row col)
  "Get cell at ROW,COL."
  (kuro-core-test-get-cell row col))

(defun vttest--get-cursor ()
  "Get cursor position as (ROW . COL)."
  (kuro-core-test-get-cursor))

(defun vttest--get-line (row)
  "Get line content at ROW."
  (kuro-core-test-get-line row))

(defun vttest--get-size ()
  "Get terminal size as (ROWS . COLS)."
  (kuro-core-test-get-size))

(defun vttest--get-scroll-region ()
  "Get scroll region as (TOP . BOTTOM)."
  (kuro-core-test-get-scroll-region))

(defun vttest--resize (rows cols)
  "Resize terminal to ROWS x COLS."
  (kuro-core-test-resize rows cols))

;;; VT100 Tests (derived from vttest)

(defmacro vttest--deftest (name description &rest body)
  "Define a vttest-style test."
  `(ert-deftest ,(intern (format "vttest-%s" name)) ()
     ,description
     (unwind-protect
         (progn
           (vttest--make-grid 24 80)
           ,@body)
       (vttest--destroy-grid))))

;; Test 1: Cursor movement (CUU/CUD/CUF/CUB)
(vttest--deftest cursor-up "Test CUU (Cursor Up)"
  (vttest--feed-bytes "\033[5;10H")  ; Move to row 5, col 10 (1-indexed)
  (vttest--feed-bytes "\033[2A")      ; Up 2 rows
  (let ((cursor (vttest--get-cursor)))
    (should (equal cursor '(3 . 9)))))  ; Row 3 (0-indexed), col 9 (0-indexed)

(vttest--deftest cursor-down "Test CUD (Cursor Down)"
  (vttest--feed-bytes "\033[5;10H")
  (vttest--feed-bytes "\033[3B")
  (let ((cursor (vttest--get-cursor)))
    (should (equal cursor '(8 . 9)))))

(vttest--deftest cursor-forward "Test CUF (Cursor Forward)"
  (vttest--feed-bytes "\033[1;1H")
  (vttest--feed-bytes "\033[5C")
  (let ((cursor (vttest--get-cursor)))
    (should (equal cursor '(0 . 5)))))

(vttest--deftest cursor-back "Test CUB (Cursor Back)"
  (vttest--feed-bytes "\033[1;20H")
  (vttest--feed-bytes "\033[10D")
  (let ((cursor (vttest--get-cursor)))
    (should (equal cursor '(0 . 9)))))

;; Test 2: CUP (Cursor Position)
(vttest--deftest cursor-position "Test CUP (Cursor Position)"
  (vttest--feed-bytes "\033[10;40H")
  (let ((cursor (vttest--get-cursor)))
    (should (equal cursor '(9 . 39)))))

;; Test 3: Terminal size
(vttest--deftest terminal-size "Test terminal size"
  (let ((size (vttest--get-size)))
    (should (equal size '(24 . 80)))))

;; Test 4: Tab stops
(vttest--deftest tab-default "Test default tab stops"
  (vttest--feed-bytes "\033[1;1H")
  (vttest--feed-bytes "\t")
  (let ((cursor (vttest--get-cursor)))
    ;; Default tab stop at column 9 (0-indexed: 8)
    (should (= (cdr cursor) 8))))

;; Test 5: Save/Restore Cursor (DECSC/DECRC)
(vttest--deftest save-restore-cursor "Test DECSC/DECRC"
  (vttest--feed-bytes "\033[10;20H")
  (vttest--feed-bytes "\0337")  ; Save cursor (ESC 7)
  (vttest--feed-bytes "\033[1;1H")
  (vttest--feed-bytes "\0338")  ; Restore cursor (ESC 8)
  (let ((cursor (vttest--get-cursor)))
    (should (equal cursor '(9 . 19)))))

;; Test 6: Line content
(vttest--deftest line-content "Test line content retrieval"
  (vttest--feed-bytes "Hello World")
  (let ((line (vttest--get-line 0)))
    (should (string= line "Hello World"))))

;; Test 7: Carriage return handling
(vttest--deftest carriage-return "Test carriage return moves cursor"
  (vttest--feed-bytes "Line1\r\nLine2")
  (let ((cursor (vttest--get-cursor)))
    (should (equal cursor '(2 . 0)))))

(provide 'vttest-harness)
