;;; kuro-render-buffer-ext2-test.el --- Render buffer tests: anchor, face-ranges, store  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-render-buffer.el — Groups 8-14, 29.
;; Groups 1-9, 21-26 are in kuro-render-buffer-test.el.
;; Groups 15-20, 27-28 are in kuro-render-buffer-ext-test.el.
;; Helper macros (kuro-render-buffer-test--with-buffer, etc.) are in
;; kuro-render-buffer-test.el which loads before this file alphabetically.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-render-buffer-test-support)

;;; Group 8: kuro--anchor-window-at-pos (from updates file)

(ert-deftest kuro-render-buffer-anchor-window-sets-window-point ()
  "`kuro--anchor-window-at-pos' moves the window point to target-pos."
  (kuro-render-buffer-test--with-buffer
    (insert "row0\nrow1\nrow2\n")
    (let* ((win (selected-window)))
      (set-window-buffer win (current-buffer))
      (kuro--anchor-window-at-pos win 6)
      (should (= (window-point win) 6)))))

;;; Group 9: kuro--clear-line-blink-overlays (from updates file)

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

;;; Group 11: kuro--scroll-lines (from updates file)

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

(defmacro kuro-render-buffer-test--def-apply-scroll-delegate (test-name up-n down-n expected-dir expected-n)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--apply-buffer-scroll' (up=%d down=%d) delegates with dir=%s n=%d." up-n down-n expected-dir expected-n)
     (kuro-render-buffer-test--with-buffer
       (insert "line0\nline1\nline2\n")
       (let ((calls nil))
         (cl-letf (((symbol-function 'kuro--scroll-lines)
                    (lambda (dir n lr) (push (list dir n lr) calls))))
           (kuro--apply-buffer-scroll ,up-n ,down-n)
           (should (= (length calls) 1))
           (should (equal (car calls) (list ',expected-dir ,expected-n kuro--last-rows))))))))

(kuro-render-buffer-test--def-apply-scroll-delegate kuro-render-buffer-apply-buffer-scroll-delegates-up   2 0 up   2)
(kuro-render-buffer-test--def-apply-scroll-delegate kuro-render-buffer-apply-buffer-scroll-delegates-down 0 2 down 2)

(ert-deftest kuro-render-buffer-apply-buffer-scroll-zero-skips-scroll-lines ()
  "kuro--apply-buffer-scroll with up=0 down=0 never calls kuro--scroll-lines."
  (kuro-render-buffer-test--with-buffer
    (insert "x\ny\nz\n")
    (let ((calls nil))
      (cl-letf (((symbol-function 'kuro--scroll-lines)
                 (lambda (dir n lr) (push (list dir n lr) calls))))
        (kuro--apply-buffer-scroll 0 0)
        (should (null calls))))))

;;; Group 12: kuro--clear-row-overlays (from updates file)

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

;;; Group 13: kuro--store-col-to-buf (from updates file)

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
  "kuro--store-col-to-buf removes an existing entry when given an empty vector."
  (kuro-render-buffer-test--with-buffer
    ;; Pre-populate so we can confirm the remhash actually fires.
     (puthash 5 [1 2 3] kuro--col-to-buf-map)
     (kuro--store-col-to-buf 5 [])
     (should (null (gethash 5 kuro--col-to-buf-map)))))

(ert-deftest kuro-render-buffer-update-row-position-cache-after-line-change-updates-next-row ()
  "Length changes update row+1 exactly and propagate delta to later rows."
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

;;; Group 14: kuro--with-buffer-edit (from updates file)

(defmacro kuro-render-buffer-test--def-buffer-edit-sets (test-name var)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--with-buffer-edit' binds `%s' to t inside its body." var)
     (kuro-render-buffer-test--with-buffer
       (let (captured)
         (kuro--with-buffer-edit (setq captured ,var))
         (should (eq captured t))))))

(defmacro kuro-render-buffer-test--def-buffer-edit-restores (test-name var)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--with-buffer-edit' restores `%s' to its prior value on exit." var)
     (kuro-render-buffer-test--with-buffer
       (let ((,var nil))
         (kuro--with-buffer-edit (ignore))
         (should (eq ,var nil))))))

(kuro-render-buffer-test--def-buffer-edit-sets     kuro-render-buffer-with-buffer-edit-sets-inhibit-read-only               inhibit-read-only)
(kuro-render-buffer-test--def-buffer-edit-sets     kuro-render-buffer-with-buffer-edit-sets-inhibit-modification-hooks      inhibit-modification-hooks)
(kuro-render-buffer-test--def-buffer-edit-restores kuro-render-buffer-with-buffer-edit-restores-inhibit-read-only            inhibit-read-only)
(kuro-render-buffer-test--def-buffer-edit-restores kuro-render-buffer-with-buffer-edit-restores-inhibit-modification-hooks  inhibit-modification-hooks)

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

;;; Group 29: kuro--resolve-window, kuro--ensure-cursor-marker, kuro--cursor-fallback-pos

(ert-deftest kuro-render-buffer-resolve-window-returns-cached-when-live ()
  "`kuro--resolve-window' returns `kuro--cached-window' without calling get-buffer-window."
  (kuro-render-buffer-test--with-buffer
    (let* ((win (selected-window))
           (calls 0))
      (setq kuro--cached-window win)
      (cl-letf (((symbol-function 'get-buffer-window)
                 (lambda (&rest _) (cl-incf calls) nil)))
        (should (eq (kuro--resolve-window) win))
        (should (= calls 0))))))

(ert-deftest kuro-render-buffer-resolve-window-refreshes-stale-cache ()
  "`kuro--resolve-window' calls get-buffer-window and caches when cached window is dead."
  (kuro-render-buffer-test--with-buffer
    (let ((fake-win (selected-window)))
      (setq kuro--cached-window nil)
      (cl-letf (((symbol-function 'get-buffer-window)
                 (lambda (&rest _) fake-win)))
        (should (eq (kuro--resolve-window) fake-win))
        ;; Cache must be updated.
        (should (eq kuro--cached-window fake-win))))))

(ert-deftest kuro-render-buffer-ensure-cursor-marker-creates-on-nil ()
  "`kuro--ensure-cursor-marker' allocates a new marker when none exists."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (setq kuro--cursor-marker nil)
    (kuro--ensure-cursor-marker 3)
    (should (markerp kuro--cursor-marker))
    (should (= (marker-position kuro--cursor-marker) 3))))

(ert-deftest kuro-render-buffer-ensure-cursor-marker-updates-existing ()
  "`kuro--ensure-cursor-marker' moves an existing marker to the new position."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (setq kuro--cursor-marker (copy-marker 1))
    (kuro--ensure-cursor-marker 4)
    (should (= (marker-position kuro--cursor-marker) 4))))

(ert-deftest kuro-render-buffer-cursor-fallback-pos-uses-marker ()
  "`kuro--cursor-fallback-pos' returns marker position when marker is set."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (setq kuro--cursor-marker (copy-marker 3))
    (let ((calls 0))
      (cl-letf (((symbol-function 'kuro--grid-col-to-buffer-pos)
                 (lambda (_r _c) (cl-incf calls) 99)))
        (should (= (kuro--cursor-fallback-pos 0 0) 3))
        (should (= calls 0))))))

(ert-deftest kuro-render-buffer-cursor-fallback-pos-computes-without-marker ()
  "`kuro--cursor-fallback-pos' calls kuro--grid-col-to-buffer-pos when no marker."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (setq kuro--cursor-marker nil)
    (cl-letf (((symbol-function 'kuro--grid-col-to-buffer-pos)
               (lambda (_r _c) 7)))
      (should (= (kuro--cursor-fallback-pos 0 2) 7)))))

;;; Group 30 — kuro--grid-col-to-buffer-pos

(ert-deftest kuro-render-buffer-grid-col-ascii-no-mapping-slow-path ()
  "`kuro--grid-col-to-buffer-pos' returns (row-start + col) for ASCII with no col-to-buf entry."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    ;; No col-to-buf entry → identity mapping; no row-positions → slow path
    (setq kuro--row-positions nil)
    ;; Row 0, col 3 → position 4 (1-based: "hell" → pos 4 = after 'l')
    (should (= (kuro--grid-col-to-buffer-pos 0 3) 4))))

(ert-deftest kuro-render-buffer-grid-col-ascii-second-row-slow-path ()
  "`kuro--grid-col-to-buffer-pos' navigates to the correct row via forward-line."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    (setq kuro--row-positions nil)
    ;; Row 1, col 2 → "wo" on second line → position 9 (point-min=1, "hello\n"=6 chars, "wo"=2)
    (should (= (kuro--grid-col-to-buffer-pos 1 2) 9))))

(ert-deftest kuro-render-buffer-grid-col-ascii-fast-path-matches-slow ()
  "`kuro--grid-col-to-buffer-pos' fast and slow paths give the same result."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    (let ((slow-result (progn (setq kuro--row-positions nil)
                              (kuro--grid-col-to-buffer-pos 1 2))))
      ;; Enable fast path: row-positions vector with row 1 pointing to start of "world"
      (setq kuro--row-positions (make-vector 2 nil))
      (aset kuro--row-positions 0 1)    ; row 0 starts at position 1
      (aset kuro--row-positions 1 7)    ; row 1 starts at position 7 ("hello\n" = 6 chars)
      (should (= (kuro--grid-col-to-buffer-pos 1 2) slow-result)))))

(ert-deftest kuro-render-buffer-grid-col-with-mapping-uses-offset ()
  "`kuro--grid-col-to-buffer-pos' uses the col-to-buf mapping when available."
  (kuro-render-buffer-test--with-buffer
    ;; Simulate a line with a CJK wide char: "Aあ" — 'A' is col 0, 'あ' occupies cols 1+2
    ;; but only 2 buffer chars. col-to-buf: col 0 → offset 0, col 1 → offset 1, col 2 → offset 1
    (insert "Aあ\n")  ; 'A' + 'あ' (wide)
    (setq kuro--row-positions nil)
    (let ((row-map (make-vector 3 0)))
      (aset row-map 0 0)  ; col 0 → buf offset 0 ('A')
      (aset row-map 1 1)  ; col 1 → buf offset 1 ('あ')
      (aset row-map 2 1)  ; col 2 → buf offset 1 (wide placeholder → same char)
      (puthash 0 row-map kuro--col-to-buf-map))
    ;; col 2 → offset 1, row 0 starts at position 1 → buffer pos 2
    (should (= (kuro--grid-col-to-buffer-pos 0 2) 2))))

(ert-deftest kuro-render-buffer-grid-col-mapping-too-short-falls-back ()
  "`kuro--grid-col-to-buffer-pos' falls back to col when col exceeds the mapping length."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (setq kuro--row-positions nil)
    ;; Mapping only covers cols 0-2, col 4 is beyond it → identity (col=4)
    (let ((row-map (make-vector 3 0)))
      (aset row-map 0 0) (aset row-map 1 1) (aset row-map 2 2)
      (puthash 0 row-map kuro--col-to-buf-map))
    ;; col 4 → identity buf-offset 4; row 0 starts at pos 1 → buf pos 5
    (should (= (kuro--grid-col-to-buffer-pos 0 4) 5))))

(ert-deftest kuro-render-buffer-grid-col-row-beyond-end-returns-max ()
  "`kuro--grid-col-to-buffer-pos' returns point-max when row exceeds buffer lines."
  (kuro-render-buffer-test--with-buffer
    (insert "only-one-line\n")
    (setq kuro--row-positions nil)
    ;; Row 5 doesn't exist — forward-line returns >0, goto-char point-max
    (let ((pos (kuro--grid-col-to-buffer-pos 5 0)))
      (should (<= pos (point-max))))))

(provide 'kuro-render-buffer-ext2-test)

;;; kuro-render-buffer-ext2-test.el ends here
