;;; kuro-render-buffer-ext3-test.el --- Unit tests for kuro-render-buffer.el (part 3)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Continuation of kuro-render-buffer-test.el (Groups 8–14).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-render-buffer)

;;; Helpers

(defmacro kuro-render-buffer-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with render-buffer state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized nil)
           (kuro--scroll-offset 0)
           (kuro--last-rows 24)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           (kuro--blink-overlays-by-row nil)
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

(defun kuro-render-buffer-test--line-count (buf)
  "Return the number of lines in BUF."
  (with-current-buffer buf
    (count-lines (point-min) (point-max))))

(defmacro kuro-render-buffer-test--capture-face-calls (calls-var &rest body)
  "Run BODY while recording `kuro--apply-ffi-face-at' calls in CALLS-VAR."
  (declare (indent 1))
  `(let ((,calls-var nil))
     (cl-letf (((symbol-function 'kuro--apply-ffi-face-at)
                (lambda (s e fg bg fl _ul)
                  (push (list s e fg bg fl) ,calls-var))))
       ,@body)))

;;; Group 8: kuro--anchor-window-at-pos

(ert-deftest kuro-render-buffer-anchor-window-sets-window-point ()
  "`kuro--anchor-window-at-pos' moves the window point to target-pos."
  (kuro-render-buffer-test--with-buffer
    (insert "row0\nrow1\nrow2\n")
    (let* ((win (selected-window)))
      (set-window-buffer win (current-buffer))
      (kuro--anchor-window-at-pos win 6)
      (should (= (window-point win) 6)))))

;;; Group 9: kuro--clear-line-blink-overlays

(ert-deftest kuro-render-buffer-clear-blink-overlays-noop-when-no-overlays ()
  "kuro--clear-line-blink-overlays is a no-op when kuro--blink-overlays is nil."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (should-not (condition-case err
                    (progn (kuro--clear-line-blink-overlays (point-min)) nil)
                  (error err)))))

(ert-deftest kuro-render-buffer-clear-blink-overlays-removes-in-range ()
  "Overlays within the current line are deleted and removed from the list."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    (let ((ov (make-overlay 1 5)))
      (setq kuro--blink-overlays (list ov))
      (goto-char (point-min))
      (kuro--clear-line-blink-overlays 1)
      (should (null (overlay-buffer ov)))
      (should (null kuro--blink-overlays)))))

(ert-deftest kuro-render-buffer-clear-blink-overlays-preserves-out-of-range ()
  "Overlays outside the current line are retained."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    ;; Overlay on second line (positions 7–11); clear from line-start=1 (first line).
    (let ((ov (make-overlay 7 11)))
      (setq kuro--blink-overlays (list ov))
      (goto-char (point-min))
      (kuro--clear-line-blink-overlays 1)
      (should (= (length kuro--blink-overlays) 1))
      (should (eq (car kuro--blink-overlays) ov)))))

;;; Group 10: kuro--apply-face-ranges

(ert-deftest kuro-render-buffer-apply-face-ranges-noop-when-nil ()
  "kuro--apply-face-ranges with nil face-ranges does nothing."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (should-not (condition-case err
                    (progn (kuro--apply-face-ranges nil 1 6) nil)
                  (error err)))))

(ert-deftest kuro-render-buffer-apply-face-ranges-calls-apply-ffi-face ()
  "kuro--apply-face-ranges calls kuro--apply-ffi-face-at for each valid range."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (kuro-render-buffer-test--capture-face-calls calls
      ;; Stride-6 flat vector: [start end fg bg flags ul] — range [0 3 1 0 0 0]
      ;; start-pos = min(1+0,6) = 1, end-pos = min(1+3,6) = 4
      (kuro--apply-face-ranges (vector 0 3 1 0 0 0) 1 6)
      (should (= (length calls) 1))
      (should (equal (car calls) '(1 4 1 0 0))))))

(ert-deftest kuro-render-buffer-apply-face-ranges-skips-zero-width ()
  "kuro--apply-face-ranges skips ranges where start-pos >= end-pos."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (kuro-render-buffer-test--capture-face-calls calls
      ;; Stride-6: start-buf=3 end-buf=3 → start-pos=end-pos → no call
      (kuro--apply-face-ranges (vector 3 3 1 0 0 0) 1 6)
      (should (null calls)))))

(ert-deftest kuro-render-buffer-apply-face-ranges-clamps-to-line-end ()
  "kuro--apply-face-ranges clamps start-pos and end-pos to line-end."
  (kuro-render-buffer-test--with-buffer
    (insert "ab\n")
    ;; line-start=1, line-end=3 ("ab" occupies positions 1-2, newline at 3)
    (kuro-render-buffer-test--capture-face-calls calls
      ;; Stride-6: range [0 99 1 0 0 0] — end-pos = min(1+99, 3) = 3
      (kuro--apply-face-ranges (vector 0 99 1 0 0 0) 1 3)
      (should (= (length calls) 1))
      (should (= (nth 1 (car calls)) 3)))))

(ert-deftest kuro-render-buffer-apply-face-ranges-multi-range-all-called ()
  "kuro--apply-face-ranges calls kuro--apply-ffi-face-at once per valid range."
  (kuro-render-buffer-test--with-buffer
    (insert "hello world\n")
    ;; line-start=1, line-end=12 ("hello world" = 11 chars)
    (kuro-render-buffer-test--capture-face-calls calls
      ;; Stride-6: three ranges flat [s0 e0 fg0 bg0 f0 ul0 s1 ...]
      (kuro--apply-face-ranges (vector 0 3 1 0 0 0   ; "hel"
                                       4 6 2 0 0 0   ; "o "
                                       7 10 3 0 0 0) ; "wor"
                               1 12)
      (should (= (length calls) 3))
      ;; calls pushed in reverse order; verify each call's fg-enc
      (should (equal (mapcar (lambda (c) (nth 2 c)) (reverse calls))
                     '(1 2 3))))))

;;; Group 11: kuro--scroll-lines

(ert-deftest kuro-render-buffer-scroll-lines-up-removes-top-line ()
  "kuro--scroll-lines \\='up removes the first line from the buffer."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'up 1 3))
    (goto-char (point-min))
    (should (looking-at "line1\n"))))

(ert-deftest kuro-render-buffer-scroll-lines-up-appends-blank-line ()
  "kuro--scroll-lines \\='up appends a blank line at the bottom."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'up 1 3))
    (goto-char (point-max))
    (forward-line -1)
    (should (looking-at "\n"))))

(ert-deftest kuro-render-buffer-scroll-lines-up-preserves-line-count ()
  "kuro--scroll-lines \\='up keeps total line count unchanged."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (let ((count-before (count-lines (point-min) (point-max)))
          (inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'up 1 3)
      (should (= (count-lines (point-min) (point-max)) count-before)))))

(ert-deftest kuro-render-buffer-scroll-lines-down-prepends-blank-line ()
  "kuro--scroll-lines \\='down prepends a blank line at the top."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'down 1 3))
    (goto-char (point-min))
    (should (looking-at "\n"))))

(ert-deftest kuro-render-buffer-scroll-lines-down-shifts-content-down ()
  "kuro--scroll-lines \\='down shifts content down: original line0 becomes line1."
  (kuro-render-buffer-test--with-buffer
    (insert "first\nsecond\nthird\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'down 1 3))
    (goto-char (point-min))
    (should (looking-at "\n"))
    (forward-line 1)
    (should (looking-at "first\n"))))

(ert-deftest kuro-render-buffer-scroll-lines-down-removes-last-line ()
  "kuro--scroll-lines \\='down removes the last buffer line."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'down 1 3))
    ;; "line2" must no longer be present
    (should-not (save-excursion
                  (goto-char (point-min))
                  (search-forward "line2" nil t)))))

(ert-deftest kuro-render-buffer-apply-buffer-scroll-delegates-up ()
  "kuro--apply-buffer-scroll with up>0 delegates to kuro--scroll-lines \\='up."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--scroll-lines)
                 (lambda (dir n lr) (push (list dir n lr) calls))))
        (kuro--apply-buffer-scroll 2 0)
        (should (= (length calls) 1))
        (should (equal (car calls) (list 'up 2 kuro--last-rows)))))))

(ert-deftest kuro-render-buffer-apply-buffer-scroll-delegates-down ()
  "kuro--apply-buffer-scroll with down>0 delegates to kuro--scroll-lines \\='down."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--scroll-lines)
                 (lambda (dir n lr) (push (list dir n lr) calls))))
        (kuro--apply-buffer-scroll 0 2)
        (should (= (length calls) 1))
        (should (equal (car calls) (list 'down 2 kuro--last-rows)))))))

(ert-deftest kuro-render-buffer-apply-buffer-scroll-zero-skips-scroll-lines ()
  "kuro--apply-buffer-scroll with up=0 down=0 never calls kuro--scroll-lines."
  (kuro-render-buffer-test--with-buffer
    (insert "x\ny\nz\n")
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--scroll-lines)
                 (lambda (dir n lr) (push (list dir n lr) calls))))
        (kuro--apply-buffer-scroll 0 0)
        (should (null calls))))))

;;; Group 12: kuro--clear-row-overlays

(ert-deftest kuro-render-buffer-clear-row-overlays-removes-blink-on-row ()
  "kuro--clear-row-overlays removes blink overlays on the target row."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    ;; Overlay on row 0 (positions 1–5)
    (let ((ov (make-overlay 1 5)))
      (setq kuro--blink-overlays (list ov))
      ;; Position point at row 0 (as kuro--ensure-buffer-row-exists would)
      (goto-char (point-min))
      (forward-line 0)
      (kuro--clear-row-overlays 0)
      (should (null (overlay-buffer ov)))
      (should (null kuro--blink-overlays)))))

(ert-deftest kuro-render-buffer-clear-row-overlays-keeps-overlays-on-other-rows ()
  "kuro--clear-row-overlays does not touch overlays on other rows."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    ;; Overlay on row 1 (positions 7–11); clear row 0
    (let ((ov (make-overlay 7 11)))
      (setq kuro--blink-overlays (list ov))
      ;; Position point at row 0
      (goto-char (point-min))
      (forward-line 0)
      (kuro--clear-row-overlays 0)
      ;; Overlay on row 1 must be untouched
      (should (= (length kuro--blink-overlays) 1))
      (should (eq (car kuro--blink-overlays) ov)))))

;;; Group 13: kuro--store-col-to-buf

(ert-deftest kuro-render-buffer-store-col-to-buf-stores-vector ()
  "kuro--store-col-to-buf stores a non-empty vector in the hash table."
  (kuro-render-buffer-test--with-buffer
    (let ((mapping [0 1 2]))
      (kuro--store-col-to-buf 3 mapping)
      (should (equal (gethash 3 kuro--col-to-buf-map) mapping)))))

(ert-deftest kuro-render-buffer-store-col-to-buf-removes-nil ()
  "kuro--store-col-to-buf removes existing entry when given nil."
  (kuro-render-buffer-test--with-buffer
    ;; Pre-populate row 2 with a mapping
    (puthash 2 [0 1] kuro--col-to-buf-map)
    (should (gethash 2 kuro--col-to-buf-map))
    (kuro--store-col-to-buf 2 nil)
    (should (null (gethash 2 kuro--col-to-buf-map)))))

(ert-deftest kuro-render-buffer-store-col-to-buf-removes-empty-vector ()
  "kuro--store-col-to-buf removes an existing entry when given an empty vector.
An empty vector is functionally equivalent to absent (identity fallback),
so storing it would waste hash table space without any semantic benefit."
  (kuro-render-buffer-test--with-buffer
    ;; Pre-populate so we can confirm the remhash actually fires.
     (puthash 5 [1 2 3] kuro--col-to-buf-map)
     (kuro--store-col-to-buf 5 [])
     (should (null (gethash 5 kuro--col-to-buf-map)))))

(ert-deftest kuro-render-buffer-update-row-position-cache-after-line-change-updates-next-row ()
  "Length changes update row+1 exactly and propagate delta to later rows.
Row+1 is set to (1+ new-line-end).  Rows +2 and beyond are adjusted by
(new-len - old-len) so they remain valid without a forward-line traversal."
  (kuro-render-buffer-test--with-buffer
    (setq kuro--row-positions [10 20 30 40 50])
    ;; row=1, old-len=3, new-len=5 → delta=+2, new-line-end=99
    (kuro--update-row-position-cache-after-line-change 1 3 5 99)
    ;; row 2 = (1+ 99) = 100; row 3 = 40+2 = 42; row 4 = 50+2 = 52.
    (should (equal kuro--row-positions [10 20 100 42 52]))))

(ert-deftest kuro-render-buffer-update-row-position-cache-after-line-change-skips-equal-length ()
  "Equal lengths leave the cached row positions untouched."
  (kuro-render-buffer-test--with-buffer
    (setq kuro--row-positions [10 20 30])
    (kuro--update-row-position-cache-after-line-change 1 4 4 99)
    (should (equal kuro--row-positions [10 20 30]))))

;;; Group 14: kuro--with-buffer-edit

(ert-deftest kuro-render-buffer-with-buffer-edit-sets-inhibit-read-only ()
  "`kuro--with-buffer-edit' binds `inhibit-read-only' to t inside its body."
  (kuro-render-buffer-test--with-buffer
    (let (captured)
      (kuro--with-buffer-edit
        (setq captured inhibit-read-only))
      (should (eq captured t)))))

(ert-deftest kuro-render-buffer-with-buffer-edit-sets-inhibit-modification-hooks ()
  "`kuro--with-buffer-edit' binds `inhibit-modification-hooks' to t inside its body."
  (kuro-render-buffer-test--with-buffer
    (let (captured)
      (kuro--with-buffer-edit
        (setq captured inhibit-modification-hooks))
      (should (eq captured t)))))

(ert-deftest kuro-render-buffer-with-buffer-edit-restores-inhibit-read-only ()
  "`kuro--with-buffer-edit' restores `inhibit-read-only' to its prior value on exit."
  (kuro-render-buffer-test--with-buffer
    (let ((inhibit-read-only nil))
      (kuro--with-buffer-edit
        (ignore))
      (should (eq inhibit-read-only nil)))))

(ert-deftest kuro-render-buffer-with-buffer-edit-restores-inhibit-modification-hooks ()
  "`kuro--with-buffer-edit' restores `inhibit-modification-hooks' to its prior value on exit."
  (kuro-render-buffer-test--with-buffer
    (let ((inhibit-modification-hooks nil))
      (kuro--with-buffer-edit
        (ignore))
      (should (eq inhibit-modification-hooks nil)))))

(ert-deftest kuro-render-buffer-with-buffer-edit-restores-point ()
  "`kuro--with-buffer-edit' restores point to its pre-body value on exit."
  (kuro-render-buffer-test--with-buffer
    (insert "abc\ndef\n")
    (goto-char (point-min))
    (let ((pos-before (point)))
      (kuro--with-buffer-edit
        (goto-char (point-max)))
      (should (= (point) pos-before)))))

(ert-deftest kuro-render-buffer-with-buffer-edit-allows-buffer-modification ()
  "`kuro--with-buffer-edit' permits inserting into a read-only buffer."
  (kuro-render-buffer-test--with-buffer
    (setq buffer-read-only t)
    (kuro--with-buffer-edit
      (insert "x"))
    (should (string-match-p "x" (buffer-string)))))

(provide 'kuro-render-buffer-ext3-test)

;;; kuro-render-buffer-ext3-test.el ends here
