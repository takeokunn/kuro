;;; kuro-render-buffer-ext3-test.el --- Render buffer tests: resolve-window, cursor-marker, grid-col  -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for kuro-render-buffer.el — Groups 29-30.
;; Helper macros are in kuro-render-buffer-test-support.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-render-buffer-test-support)

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

(provide 'kuro-render-buffer-ext3-test)

;;; kuro-render-buffer-ext3-test.el ends here
