;;; kuro-render-buffer-ext4-test.el --- Tests for cursor-type, row-exists, clear-line-blink  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-render-buffer.el — Groups covering:
;;   kuro--decscusr-to-cursor-type (line 264): pure vector lookup
;;   kuro--ensure-buffer-row-exists (line 228): position cache + buffer mutation
;;   kuro--clear-line-blink-overlays (line 122): fast (row hash) and slow (full scan) paths

;;; Code:

(require 'kuro-render-buffer-test-support)

;;; Group: kuro--decscusr-to-cursor-type

(ert-deftest kuro-render-buffer-decscusr-shape-0-returns-box ()
  "Shape 0 (default block) maps to box."
  (should (eq 'box (kuro--decscusr-to-cursor-type 0))))

(ert-deftest kuro-render-buffer-decscusr-shape-1-returns-box ()
  "Shape 1 (blinking block alias) maps to box."
  (should (eq 'box (kuro--decscusr-to-cursor-type 1))))

(ert-deftest kuro-render-buffer-decscusr-shape-3-returns-hbar ()
  "Shape 3 (blinking underline) maps to hbar."
  (let ((result (kuro--decscusr-to-cursor-type 3)))
    (should (consp result))
    (should (eq (car result) 'hbar))))

(ert-deftest kuro-render-buffer-decscusr-shape-5-returns-bar ()
  "Shape 5 (blinking bar) maps to bar."
  (let ((result (kuro--decscusr-to-cursor-type 5)))
    (should (consp result))
    (should (eq (car result) 'bar))))

(ert-deftest kuro-render-buffer-decscusr-shape-6-returns-bar ()
  "Shape 6 (steady bar) maps to bar."
  (let ((result (kuro--decscusr-to-cursor-type 6)))
    (should (consp result))
    (should (eq (car result) 'bar))))

(ert-deftest kuro-render-buffer-decscusr-negative-shape-falls-back-to-box ()
  "Negative shape falls back to box."
  (should (eq 'box (kuro--decscusr-to-cursor-type -1))))

(ert-deftest kuro-render-buffer-decscusr-out-of-range-falls-back-to-box ()
  "Out-of-range shape (> 6) falls back to box."
  (should (eq 'box (kuro--decscusr-to-cursor-type 7)))
  (should (eq 'box (kuro--decscusr-to-cursor-type 99))))

(ert-deftest kuro-render-buffer-decscusr-non-integer-falls-back-to-box ()
  "Non-integer shape falls back to box."
  (should (eq 'box (kuro--decscusr-to-cursor-type nil)))
  (should (eq 'box (kuro--decscusr-to-cursor-type "3"))))

(ert-deftest kuro-render-buffer-decscusr-all-valid-shapes-non-nil ()
  "All valid shapes 0-6 return non-nil cursor-type values."
  (dotimes (n 7)
    (should (kuro--decscusr-to-cursor-type n))))

;;; Group: kuro--ensure-buffer-row-exists

(ert-deftest kuro-render-buffer-ensure-row-cache-hit-goes-to-char ()
  "kuro--ensure-buffer-row-exists uses cache on hit."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((kuro--row-positions (make-vector 3 nil)))
      (aset kuro--row-positions 0 (point-min))
      (aset kuro--row-positions 1 7)      ; "line1" starts at pos 7
      (aset kuro--row-positions 2 13)
      (kuro--ensure-buffer-row-exists 1)
      (should (= (point) 7)))))

(ert-deftest kuro-render-buffer-ensure-row-cache-miss-forward-line ()
  "kuro--ensure-buffer-row-exists falls back to forward-line on cache miss."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((kuro--row-positions (make-vector 3 nil)))
      ;; No entries cached yet
      (kuro--ensure-buffer-row-exists 1)
      ;; Point should be at the start of line 1 (0-based row 1)
      (let ((line-num (line-number-at-pos)))
        (should (= line-num 2))))))

(ert-deftest kuro-render-buffer-ensure-row-caches-position-on-miss ()
  "kuro--ensure-buffer-row-exists stores the resolved position in the cache."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((kuro--row-positions (make-vector 3 nil)))
      (kuro--ensure-buffer-row-exists 0)
      (should (= (aref kuro--row-positions 0) (point-min))))))

(ert-deftest kuro-render-buffer-ensure-row-inserts-when-past-end ()
  "kuro--ensure-buffer-row-exists inserts newlines when row exceeds buffer length.
After navigation to row 3 (0-indexed), point lands at a position beyond the
original content.  count-lines returns 3 (three \\n chars in the buffer), and
point is at the start of what would be the 4th line (position past last \\n)."
  (kuro-render-buffer-test--with-buffer
    (insert "only-one-line\n")
    (let ((kuro--row-positions nil)
          (original-end (point-max)))
      (kuro--ensure-buffer-row-exists 3)
      ;; Buffer grew: new point-max > original point-max
      (should (> (point-max) original-end))
      ;; At least 3 newlines were inserted so forward-line 3 could succeed
      (should (>= (count-lines (point-min) (point-max)) 3)))))

;;; Group: kuro--clear-line-blink-overlays

(defun kuro-render-buffer-test--make-overlay (buf start end type)
  "Create a blink overlay of TYPE on BUF from START to END."
  (let ((ov (make-overlay start end buf)))
    (overlay-put ov 'kuro-blink-type type)
    ov))

(ert-deftest kuro-render-buffer-clear-line-blink-noop-when-no-blink-overlays ()
  "kuro--clear-line-blink-overlays is a noop when kuro--blink-overlays is nil."
  (with-temp-buffer
    (insert "test line\n")
    (let ((kuro--blink-overlays nil)
          (kuro--blink-overlays-slow nil)
          (kuro--blink-overlays-fast nil)
          (kuro--blink-overlays-by-row nil))
      (goto-char (point-min))
      (kuro--clear-line-blink-overlays (point-min))
      ;; Still nil — no error, no mutation
      (should-not kuro--blink-overlays))))

(ert-deftest kuro-render-buffer-clear-line-blink-fast-path-removes-overlay ()
  "Fast path (via row hash) removes an overlay on the target row."
  (with-temp-buffer
    (insert "row0\nrow1\n")
    (let* ((ov (kuro-render-buffer-test--make-overlay (current-buffer) 1 4 'slow))
           (kuro--blink-overlays (list ov))
           (kuro--blink-overlays-slow (list ov))
           (kuro--blink-overlays-fast nil)
           (kuro--blink-overlays-by-row (let ((h (make-hash-table :test 'eql)))
                                          (puthash 0 (list ov) h) h)))
      (goto-char (point-min))
      (kuro--clear-line-blink-overlays (point-min) 0)
      (should (null kuro--blink-overlays))
      (should (null kuro--blink-overlays-slow)))))

(ert-deftest kuro-render-buffer-clear-line-blink-fast-path-leaves-other-rows ()
  "Fast path removes only the overlay on the target row, not others."
  (with-temp-buffer
    (insert "row0\nrow1\n")
    (let* ((ov0 (kuro-render-buffer-test--make-overlay (current-buffer) 1 4 'slow))
           (ov1 (kuro-render-buffer-test--make-overlay (current-buffer) 6 9 'fast))
           (kuro--blink-overlays (list ov0 ov1))
           (kuro--blink-overlays-slow (list ov0))
           (kuro--blink-overlays-fast (list ov1))
           (kuro--blink-overlays-by-row (let ((h (make-hash-table :test 'eql)))
                                          (puthash 0 (list ov0) h)
                                          (puthash 1 (list ov1) h) h)))
      (goto-char (point-min))
      (kuro--clear-line-blink-overlays (point-min) 0)
      ;; ov0 removed; ov1 on row 1 still there
      (should (equal kuro--blink-overlays (list ov1)))
      (should (equal kuro--blink-overlays-fast (list ov1))))))

(ert-deftest kuro-render-buffer-clear-line-blink-slow-path-removes-overlay ()
  "Slow path (full scan, no row arg) removes an overlay on the line."
  (with-temp-buffer
    (insert "row0\nrow1\n")
    (let* ((ov (kuro-render-buffer-test--make-overlay (current-buffer) 1 4 'fast))
           (kuro--blink-overlays (list ov))
           (kuro--blink-overlays-slow nil)
           (kuro--blink-overlays-fast (list ov))
           (kuro--blink-overlays-by-row nil))
      (goto-char (point-min))
      ;; No row arg → slow path
      (kuro--clear-line-blink-overlays (point-min))
      (should (null kuro--blink-overlays))
      (should (null kuro--blink-overlays-fast)))))

(ert-deftest kuro-render-buffer-clear-line-blink-slow-path-keeps-other-lines ()
  "Slow path preserves overlays on other lines."
  (with-temp-buffer
    (insert "row0\nrow1\n")
    (let* ((ov0 (kuro-render-buffer-test--make-overlay (current-buffer) 1 4 'slow))
           ;; ov1 on line 2 (positions 6-9)
           (ov1 (kuro-render-buffer-test--make-overlay (current-buffer) 6 9 'fast))
           (kuro--blink-overlays (list ov0 ov1))
           (kuro--blink-overlays-slow (list ov0))
           (kuro--blink-overlays-fast (list ov1))
           (kuro--blink-overlays-by-row nil))
      (goto-char (point-min))
      ;; Clear line starting at point-min (line 1)
      (kuro--clear-line-blink-overlays (point-min))
      (should (equal kuro--blink-overlays (list ov1)))
      (should (equal kuro--blink-overlays-fast (list ov1)))
      (should (null kuro--blink-overlays-slow)))))


(provide 'kuro-render-buffer-ext4-test)
;;; kuro-render-buffer-ext4-test.el ends here
