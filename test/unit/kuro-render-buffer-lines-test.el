;;; kuro-render-buffer-ext-test.el --- Unit tests for kuro-render-buffer.el (part 2)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-render-buffer.el (buffer update helpers), part 2.
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Covered (Groups 15–20, 27):
;;   - kuro--update-line-full: basic row update, nil-text no-op, face ranges applied
;;   - kuro--update-cursor: visible/hidden cursor, position update, cache skip
;;   - kuro--scroll-lines: zero-count no-op and multi-step
;;   - kuro--apply-buffer-scroll: col-to-buf-map clearing
;;   - kuro--store-col-to-buf: nil-with-non-integer-row guard and overwrite
;;   - kuro--clear-line-blink-overlays: dead-overlay handling
;;   - kuro--anchor-window-at-pos: vscroll/hscroll reset, window-start, invalid pos
;;
;; Groups 21–26 are in kuro-render-buffer-ext2-test.el.

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

;;; Group 15: kuro--update-line-full

(ert-deftest kuro-render-buffer-update-line-full-replaces-text ()
  "kuro--update-line-full replaces the text on the target row."
  (kuro-render-buffer-test--with-buffer
    (insert "original\n")
    (cl-letf (((symbol-function 'kuro--apply-ffi-face-at) #'ignore)
              ((symbol-function 'kuro--clear-row-image-overlays) #'ignore))
      (kuro--update-line-full 0 "replaced" nil nil))
    (goto-char (point-min))
    (should (looking-at "replaced\n"))))

(ert-deftest kuro-render-buffer-update-line-full-nil-text-is-noop ()
  "kuro--update-line-full with nil text does not modify the buffer."
  (kuro-render-buffer-test--with-buffer
    (insert "keep\n")
    (kuro--update-line-full 0 nil nil nil)
    (goto-char (point-min))
    (should (looking-at "keep\n"))))

(ert-deftest kuro-render-buffer-update-line-full-applies-face-ranges ()
  "kuro--update-line-full calls kuro--apply-ffi-face-at for each face range."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (let ((face-calls 0))
      (cl-letf (((symbol-function 'kuro--apply-ffi-face-at)
                 (lambda (_s _e _fg _bg _fl _ul) (cl-incf face-calls)))
                ((symbol-function 'kuro--clear-row-image-overlays) #'ignore))
        ;; A single face range in stride-6 flat format: [start end fg bg flags ul]
        (kuro--update-line-full 0 "hello" (vector 0 5 0 0 0 0) nil))
      (should (= face-calls 1)))))

(ert-deftest kuro-render-buffer-update-line-full-stores-col-to-buf ()
  "kuro--update-line-full stores the col-to-buf vector in kuro--col-to-buf-map."
  (kuro-render-buffer-test--with-buffer
    (insert "abc\n")
    (let ((vec (vector 0 1 2)))
      (cl-letf (((symbol-function 'kuro--apply-ffi-face-at) #'ignore)
                ((symbol-function 'kuro--clear-row-image-overlays) #'ignore))
        (kuro--update-line-full 0 "abc" nil vec))
      (should (equal (gethash 0 kuro--col-to-buf-map) vec)))))

(ert-deftest kuro-render-buffer-update-line-full-non-integer-row-is-noop ()
  "kuro--update-line-full with a non-integer row does not modify the buffer."
  (kuro-render-buffer-test--with-buffer
    (insert "keep\n")
    (kuro--update-line-full nil "replaced" nil nil)
    (goto-char (point-min))
    (should (looking-at "keep\n"))))

;;; Group 16: kuro--update-cursor

(defmacro kuro-render-buffer-cursor-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with cursor-update state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--scroll-offset 0)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           kuro--cursor-marker
           kuro--last-cursor-row
           kuro--last-cursor-col
           kuro--last-cursor-visible
           kuro--last-cursor-shape
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

(ert-deftest kuro-render-buffer-update-cursor-moves-marker-to-position ()
  "kuro--update-cursor sets kuro--cursor-marker to the grid (row,col) buffer position."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "row0\nrow1\nrow2\n")
    (setq kuro--cursor-marker (point-marker))
    ;; row=1, col=2, visible=t, shape=0 → "row1\n" starts at pos 6, col 2 → pos 8
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(1 2 t 0)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    (should (= (marker-position kuro--cursor-marker) 8))))

(ert-deftest kuro-render-buffer-update-cursor-hidden-sets-cursor-type-nil ()
  "kuro--update-cursor sets cursor-type to nil when cursor is hidden."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (point-marker))
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 0 nil 0)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    (should-not cursor-type)))

(ert-deftest kuro-render-buffer-update-cursor-visible-sets-cursor-type ()
  "kuro--update-cursor sets cursor-type to a non-nil value when cursor is visible."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (point-marker))
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 0 t 0)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    (should cursor-type)))

(ert-deftest kuro-render-buffer-update-cursor-skips-when-scroll-offset-positive ()
  "kuro--update-cursor is a no-op when kuro--scroll-offset > 0 (viewport scrolled)."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (copy-marker (point-min))
          kuro--scroll-offset 5)
    (let ((state-calls 0))
      (cl-letf (((symbol-function 'kuro--get-cursor-state)
                 (lambda () (cl-incf state-calls) '(0 0 t 0))))
        (kuro--update-cursor)
        (should (= state-calls 0))))))

(ert-deftest kuro-render-buffer-update-cursor-caches-state-and-skips-on-repeat ()
  "kuro--update-cursor skips buffer-position work when cursor state is unchanged."
  (kuro-render-buffer-cursor-test--with-buffer
    (insert "hello\n")
    (setq kuro--cursor-marker (point-marker)
          kuro--last-cursor-row     0
          kuro--last-cursor-col     0
          kuro--last-cursor-visible t
          kuro--last-cursor-shape   0)
    (let ((apply-calls 0))
      (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 0 t 0)))
                ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window)))
                ((symbol-function 'kuro--anchor-window-at-pos) #'ignore)
                ((symbol-function 'kuro--apply-cursor-display)
                 (lambda (_v _s) (cl-incf apply-calls))))
        (kuro--update-cursor)
        ;; State unchanged → apply-cursor-display must NOT be called
        (should (= apply-calls 0))))))

;;; Group 17: kuro--scroll-lines — zero-count no-op and multi-step
;; ------------------------------------------------------------

(ert-deftest kuro-render-buffer-scroll-lines-up-zero-is-noop ()
  "kuro--scroll-lines 'up with n=0 leaves the buffer unchanged."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (let ((content-before (buffer-string))
          (inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'up 0 3)
      (should (string= (buffer-string) content-before)))))

(ert-deftest kuro-render-buffer-scroll-lines-down-zero-is-noop ()
  "kuro--scroll-lines 'down with n=0 leaves the buffer unchanged."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (let ((content-before (buffer-string))
          (inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'down 0 3)
      (should (string= (buffer-string) content-before)))))

(ert-deftest kuro-render-buffer-scroll-lines-up-multiple-steps ()
  "kuro--scroll-lines 'up with n=2 removes the first two lines."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\nline3\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'up 2 4))
    (goto-char (point-min))
    (should (looking-at "line2\n"))))

(ert-deftest kuro-render-buffer-scroll-lines-down-multiple-steps ()
  "kuro--scroll-lines 'down with n=2 removes the last two lines and prepends two blanks."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\nline2\nline3\n")
    (let ((inhibit-read-only t)
          (inhibit-modification-hooks t))
      (kuro--scroll-lines 'down 2 4))
    (goto-char (point-min))
    ;; Two blank lines prepended
    (should (looking-at "\n"))
    (forward-line 1)
    (should (looking-at "\n"))
    ;; line2 and line3 are gone
    (should-not (save-excursion
                  (goto-char (point-min))
                  (search-forward "line2" nil t)))))

;;; Group 18: kuro--apply-buffer-scroll — col-to-buf-map clearing
;; ------------------------------------------------------------

(ert-deftest kuro-render-buffer-apply-buffer-scroll-up-clears-col-to-buf-map ()
  "kuro--apply-buffer-scroll clears kuro--col-to-buf-map after a scroll-up."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (puthash 0 [0 1 2] kuro--col-to-buf-map)
    (puthash 1 [0 1] kuro--col-to-buf-map)
    (kuro--apply-buffer-scroll 1 0)
    (should (zerop (hash-table-count kuro--col-to-buf-map)))))

(ert-deftest kuro-render-buffer-apply-buffer-scroll-down-clears-col-to-buf-map ()
  "kuro--apply-buffer-scroll clears kuro--col-to-buf-map after a scroll-down."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\nc\n")
    (puthash 2 [0 1] kuro--col-to-buf-map)
    (kuro--apply-buffer-scroll 0 1)
    (should (zerop (hash-table-count kuro--col-to-buf-map)))))

(ert-deftest kuro-render-buffer-apply-buffer-scroll-zero-does-not-clear-map ()
  "kuro--apply-buffer-scroll with zero counts does not clear kuro--col-to-buf-map."
  (kuro-render-buffer-test--with-buffer
    (insert "a\nb\n")
    (puthash 0 [0 1] kuro--col-to-buf-map)
    (kuro--apply-buffer-scroll 0 0)
    (should (= (hash-table-count kuro--col-to-buf-map) 1))))

;;; Group 19: kuro--store-col-to-buf — nil-with-non-integer-row guard and overwrite
;; ------------------------------------------------------------

(ert-deftest kuro-render-buffer-store-col-to-buf-nil-non-integer-row-is-noop ()
  "kuro--store-col-to-buf with nil col-to-buf and a non-integer row.
The integerp guard was removed in Round 11 as dead code (row is always an
integer in production since it originates from the binary FFI decoder).
Without the guard, (gethash row ht) governs: if no entry exists, remhash
is not called (already a no-op).  Non-integer rows only arise in unit tests."
  (kuro-render-buffer-test--with-buffer
    ;; No entry for 'foo: no remhash call, no error — still a no-op.
    (kuro--store-col-to-buf 'foo nil)
    (should (null (gethash 'foo kuro--col-to-buf-map)))))

(ert-deftest kuro-render-buffer-store-col-to-buf-overwrites-existing-vector ()
  "kuro--store-col-to-buf replaces an existing vector entry with a new one."
  (kuro-render-buffer-test--with-buffer
    (puthash 0 [0 1 2] kuro--col-to-buf-map)
    (let ((new-vec [0 0 1]))
      (kuro--store-col-to-buf 0 new-vec)
      (should (equal (gethash 0 kuro--col-to-buf-map) new-vec)))))

(ert-deftest kuro-render-buffer-store-col-to-buf-nil-row-without-entry-is-noop ()
  "kuro--store-col-to-buf with nil col-to-buf and no existing entry is a no-op."
  (kuro-render-buffer-test--with-buffer
    (kuro--store-col-to-buf 7 nil)
    (should (null (gethash 7 kuro--col-to-buf-map)))))

;;; Group 20: kuro--clear-line-blink-overlays — dead-overlay handling
;; ------------------------------------------------------------

(ert-deftest kuro-render-buffer-clear-blink-overlays-skips-dead-overlay ()
  "Dead overlays (overlay-buffer returns nil) are kept in the list without crashing.
A dead overlay passes the (overlay-buffer ov) guard as falsy so it lands in
the `remaining' list rather than being deleted again."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (let ((dead-ov (make-overlay 1 3)))
      (delete-overlay dead-ov)          ; make it dead
      (setq kuro--blink-overlays (list dead-ov))
      (goto-char (point-min))
      ;; Must not signal an error
      (should-not (condition-case err
                      (progn (kuro--clear-line-blink-overlays 1) nil)
                    (error err)))
      ;; Dead overlay ends up in remaining (the guard `(overlay-buffer ov)' is nil)
      (should (= (length kuro--blink-overlays) 1)))))

(ert-deftest kuro-render-buffer-clear-blink-overlays-mixed-live-dead ()
  "Live overlay in range is deleted; dead overlay is kept; out-of-range live overlay is kept."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\nworld\n")
    (let ((live-in-range  (make-overlay 1 5))
          (dead-ov        (make-overlay 1 3))
          (live-other-row (make-overlay 7 11)))
      (delete-overlay dead-ov)
      (setq kuro--blink-overlays (list live-in-range dead-ov live-other-row))
      (goto-char (point-min))
      (kuro--clear-line-blink-overlays 1)
      ;; live-in-range was deleted
      (should (null (overlay-buffer live-in-range)))
      ;; remaining: dead-ov + live-other-row (order determined by nreverse)
      (should (= (length kuro--blink-overlays) 2)))))

;;; Group 27: kuro--anchor-window-at-pos — vscroll/hscroll reset paths
;; ------------------------------------------------------------

(ert-deftest kuro-render-buffer-anchor-window-sets-vscroll-to-zero ()
  "kuro--anchor-window-at-pos resets vscroll to 0 when it was non-zero."
  (with-temp-buffer
    (insert "line0\nline1\nline2\n")
    (set-window-buffer (selected-window) (current-buffer))
    (let ((win (selected-window)))
      ;; Force a non-zero vscroll to simulate tall-image drift.
      (set-window-vscroll win 5)
      (kuro--anchor-window-at-pos win (point-min))
      (should (= (window-vscroll win) 0)))))

(ert-deftest kuro-render-buffer-anchor-window-sets-hscroll-to-zero ()
  "kuro--anchor-window-at-pos resets hscroll to 0 when it was non-zero."
  (with-temp-buffer
    (insert "line0\nline1\nline2\n")
    (set-window-buffer (selected-window) (current-buffer))
    (let ((win (selected-window)))
      ;; Force a non-zero hscroll to simulate horizontal scroll drift.
      (set-window-hscroll win 3)
      (kuro--anchor-window-at-pos win (point-min))
      (should (= (window-hscroll win) 0)))))

(ert-deftest kuro-render-buffer-anchor-window-moves-window-start ()
  "kuro--anchor-window-at-pos sets window-start to point-min."
  (with-temp-buffer
    (insert "line0\nline1\nline2\n")
    (set-window-buffer (selected-window) (current-buffer))
    (let ((win (selected-window)))
      (kuro--anchor-window-at-pos win (point-min))
      (should (= (window-start win) (point-min))))))

(ert-deftest kuro-render-buffer-anchor-window-noop-when-pos-invalid ()
  "kuro--anchor-window-at-pos does not error when given point-max as target-pos.
point-max is a valid position so set-window-point accepts it; this test
confirms the function completes without signalling an error for a
boundary position."
  (with-temp-buffer
    (insert "line0\nline1\n")
    (set-window-buffer (selected-window) (current-buffer))
    (let ((win (selected-window)))
      (should-not (condition-case err
                      (progn (kuro--anchor-window-at-pos win (point-max)) nil)
                    (error err))))))

;;; Group 28: kuro--clear-line-blink-overlays — hash-table fast path

(ert-deftest kuro-render-buffer-clear-blink-overlays-fast-path-empty-hash ()
  "Fast path: when hash is empty and row is given, returns without error."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (goto-char (point-min))
    (let ((ht (make-hash-table :test 'eql))
          (sentinel (make-overlay 1 3)))
      (setq kuro--blink-overlays-by-row ht
            kuro--blink-overlays (list sentinel))
      (should-not
       (condition-case err
           (progn (kuro--clear-line-blink-overlays 1 0) nil)
         (error err)))
      ;; Row 0 had no hash entry — sentinel is untouched.
      (should (= (length kuro--blink-overlays) 1)))))

(ert-deftest kuro-render-buffer-clear-blink-overlays-fast-path-row-not-in-hash ()
  "Fast path: when given row has no entry in the hash, no overlay is removed."
  (kuro-render-buffer-test--with-buffer
    (insert "line0\nline1\n")
    (goto-char (point-min))
    (let ((ht (make-hash-table :test 'eql))
          (ov (make-overlay 7 11)))       ; overlay on row 1
      (puthash 1 (list ov) ht)            ; only row 1 is registered
      (setq kuro--blink-overlays-by-row ht
            kuro--blink-overlays (list ov))
      ;; Ask to clear row 0 — no entry exists for row 0.
      (kuro--clear-line-blink-overlays 1 0)
      ;; Overlay on row 1 must remain live and in the list.
      (should (overlay-buffer ov))
      (should (= (length kuro--blink-overlays) 1)))))

(ert-deftest kuro-render-buffer-clear-blink-overlays-removes-overlays-from-buffer ()
  "Fast path: overlays registered for the given row are deleted from the buffer."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (goto-char (point-min))
    (let ((ht (make-hash-table :test 'eql))
          (ov (make-overlay 1 5)))
      (puthash 0 (list ov) ht)
      (setq kuro--blink-overlays-by-row ht
            kuro--blink-overlays (list ov))
      (kuro--clear-line-blink-overlays 1 0)
      ;; The overlay must have been deleted (no buffer).
      (should (null (overlay-buffer ov))))))

(ert-deftest kuro-render-buffer-clear-blink-overlays-clears-hash-entry ()
  "Fast path: after clearing, the hash entry for the given row is removed."
  (kuro-render-buffer-test--with-buffer
    (insert "hello\n")
    (goto-char (point-min))
    (let ((ht (make-hash-table :test 'eql))
          (ov (make-overlay 1 5)))
      (puthash 0 (list ov) ht)
      (setq kuro--blink-overlays-by-row ht
            kuro--blink-overlays (list ov))
      (kuro--clear-line-blink-overlays 1 0)
      ;; remhash must have been called: row 0 entry is gone.
      (should (null (gethash 0 kuro--blink-overlays-by-row))))))

(provide 'kuro-render-buffer-ext-test)

;;; kuro-render-buffer-ext-test.el ends here
