;;; kuro-mux-layout-test-2.el --- Tests for kuro-mux-layout helpers  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)
(require 'kuro-mux-layout)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))


;;; Harness

(defmacro kuro-mux-layout-test--with-splits (&rest body)
  "Run BODY with window primitives mocked; return plist :retval :splits :assigns.
`split-window' returns distinct symbols win-1 win-2 … and records
 (from-window side).  `set-window-buffer' records (window buffer).
`selected-window' returns \\='win-root."
  `(let ((win-count 0) splits assigns retval)
     (cl-letf (((symbol-function 'split-window)
                (lambda (w _size side)
                  (let ((new (intern (format "win-%d" (cl-incf win-count)))))
                    (push (list w side) splits)
                    new)))
               ((symbol-function 'set-window-buffer)
                (lambda (w b) (push (list w b) assigns)))
               ((symbol-function 'selected-window)
                (lambda () 'win-root)))
       (setq retval (progn ,@body)))
     (list :retval retval
           :splits  (nreverse splits)
           :assigns (nreverse assigns))))


;;; Group 42 — kuro-mux--layout-chain

(ert-deftest kuro-mux-layout-chain-empty-buffers-is-noop ()
  "`kuro-mux--layout-chain' does nothing when BUFFERS is nil."
  (let ((result (kuro-mux-layout-test--with-splits
                  (kuro-mux--layout-chain 'win-a nil 'right))))
    (should (null (plist-get result :splits)))
    (should (null (plist-get result :assigns)))))

(ert-deftest kuro-mux-layout-chain-single-buffer-one-split ()
  "`kuro-mux--layout-chain' splits once for a single buffer."
  (let* ((result (kuro-mux-layout-test--with-splits
                   (kuro-mux--layout-chain 'win-a (list 'b1) 'right))))
    (should (= 1 (length (plist-get result :splits))))
    (should (= 1 (length (plist-get result :assigns))))))

(ert-deftest kuro-mux-layout-chain-uses-correct-side ()
  "`kuro-mux--layout-chain' passes SIDE to every `split-window' call."
  (let ((result (kuro-mux-layout-test--with-splits
                  (kuro-mux--layout-chain 'win-a (list 'b1 'b2 'b3) 'below))))
    (dolist (call (plist-get result :splits))
      (should (eq 'below (cadr call))))))

(ert-deftest kuro-mux-layout-chain-n-buffers-n-splits ()
  "`kuro-mux--layout-chain' with N buffers produces exactly N splits and N assigns."
  (let* ((result (kuro-mux-layout-test--with-splits
                   (kuro-mux--layout-chain 'win-a (list 'b1 'b2 'b3) 'right))))
    (should (= 3 (length (plist-get result :splits))))
    (should (= 3 (length (plist-get result :assigns))))))

(ert-deftest kuro-mux-layout-chain-threads-windows ()
  "`kuro-mux--layout-chain' threads: each split originates from the previous new window."
  (let* ((result (kuro-mux-layout-test--with-splits
                   (kuro-mux--layout-chain 'win-a (list 'b1 'b2) 'right)))
         (splits (plist-get result :splits)))
    ;; First split: from win-a; second split: from win-1 (result of first split)
    (should (eq 'win-a (car (nth 0 splits))))
    (should (eq 'win-1 (car (nth 1 splits))))))

(ert-deftest kuro-mux-layout-chain-assigns-buffers-in-order ()
  "`kuro-mux--layout-chain' assigns each buffer to the window created for it."
  (let* ((result  (kuro-mux-layout-test--with-splits
                    (kuro-mux--layout-chain 'win-a (list 'b1 'b2) 'right)))
         (assigns (plist-get result :assigns)))
    (should (equal (list 'win-1 'b1) (nth 0 assigns)))
    (should (equal (list 'win-2 'b2) (nth 1 assigns)))))


;;; Group 43 — kuro-mux--layout-main

(ert-deftest kuro-mux-layout-main-nil-buffers-is-noop ()
  "`kuro-mux--layout-main' does nothing when BUFFERS is nil."
  (let ((result (kuro-mux-layout-test--with-splits
                  (kuro-mux--layout-main 'win-a nil 'right 'below))))
    (should (null (plist-get result :splits)))
    (should (null (plist-get result :assigns)))))

(ert-deftest kuro-mux-layout-main-single-buffer-splits-toward-main-side ()
  "`kuro-mux--layout-main' with one buffer splits once toward MAIN-SIDE."
  (let* ((result (kuro-mux-layout-test--with-splits
                   (kuro-mux--layout-main 'win-a (list 'b1) 'right 'below)))
         (splits (plist-get result :splits)))
    (should (= 1 (length splits)))
    (should (eq 'right (cadr (car splits))))))

(ert-deftest kuro-mux-layout-main-assigns-first-buf-to-area ()
  "`kuro-mux--layout-main' assigns the first buffer to the split-off area."
  (let* ((result  (kuro-mux-layout-test--with-splits
                    (kuro-mux--layout-main 'win-a (list 'b1) 'right 'below)))
         (assigns (plist-get result :assigns)))
    ;; area = win-1 (returned by split-window)
    (should (= 1 (length assigns)))
    (should (equal (list 'win-1 'b1) (car assigns)))))

(ert-deftest kuro-mux-layout-main-two-buffers-uses-both-sides ()
  "`kuro-mux--layout-main' with 2 bufs: MAIN-SIDE split + SUB-SIDE chain split."
  (let* ((result  (kuro-mux-layout-test--with-splits
                    (kuro-mux--layout-main 'win-a (list 'b1 'b2) 'below 'right)))
         (splits  (plist-get result :splits))
         (assigns (plist-get result :assigns)))
    (should (= 2 (length splits)))
    (should (eq 'below (cadr (nth 0 splits))))
    (should (eq 'right (cadr (nth 1 splits))))
    (should (= 2 (length assigns)))))


;;; Group 44 — kuro-mux--fill-band

(ert-deftest kuro-mux-layout-fill-band-one-col-no-split ()
  "`kuro-mux--fill-band' with 1 column assigns band directly and does not split."
  (let* ((result (kuro-mux-layout-test--with-splits
                   (kuro-mux--fill-band 'win-band (list 'b0 'b1 'b2) 0 1))))
    (should (null (plist-get result :splits)))
    (should (= 1 (length (plist-get result :assigns))))))

(ert-deftest kuro-mux-layout-fill-band-returns-next-index ()
  "`kuro-mux--fill-band' returns (start + in-row)."
  (let* ((result (kuro-mux-layout-test--with-splits
                   (kuro-mux--fill-band 'win-band (list 'b0 'b1 'b2) 1 2))))
    ;; in-row = min(2, 3-1) = 2; returns 1+2 = 3
    (should (= 3 (plist-get result :retval)))))

(ert-deftest kuro-mux-layout-fill-band-three-cols-two-splits ()
  "`kuro-mux--fill-band' with 3 cols: 2 right-splits and 3 assigns."
  (let* ((result (kuro-mux-layout-test--with-splits
                   (kuro-mux--fill-band 'win-band (list 'b0 'b1 'b2) 0 3))))
    (should (= 2 (length (plist-get result :splits))))
    (should (= 3 (length (plist-get result :assigns))))
    (dolist (call (plist-get result :splits))
      (should (eq 'right (cadr call))))))

(ert-deftest kuro-mux-layout-fill-band-partial-row ()
  "`kuro-mux--fill-band' uses remaining count when fewer buffers than cols."
  ;; 4 cols requested but only 2 remain (start=1, len=3 → remaining=2)
  (let* ((result (kuro-mux-layout-test--with-splits
                   (kuro-mux--fill-band 'win-band (list 'b0 'b1 'b2) 1 4))))
    ;; in-row = min(4, 3-1) = 2
    (should (= 1 (length (plist-get result :splits))))
    (should (= 2 (length (plist-get result :assigns))))))

(ert-deftest kuro-mux-layout-fill-band-assigns-correct-buffers ()
  "`kuro-mux--fill-band' assigns buffers starting at START index."
  (let* ((result  (kuro-mux-layout-test--with-splits
                    (kuro-mux--fill-band 'win-band (list 'b0 'b1 'b2) 1 2)))
         (assigns (plist-get result :assigns)))
    ;; start=1: band←b1, win-1←b2
    (should (equal 'b1 (cadr (nth 0 assigns))))
    (should (equal 'b2 (cadr (nth 1 assigns))))))


;;; Group 46 — kuro-mux--layout-tiled

(ert-deftest kuro-mux-layout-tiled-single-buffer-no-splits ()
  "`kuro-mux--layout-tiled' with 1 buffer: no splits, 1 assign to selected-window."
  (let* ((result (kuro-mux-layout-test--with-splits
                   (kuro-mux--layout-tiled (list 'b0)))))
    (should (null (plist-get result :splits)))
    (should (= 1 (length (plist-get result :assigns))))
    (should (eq 'win-root (car (car (plist-get result :assigns)))))))

(ert-deftest kuro-mux-layout-tiled-four-buffers-three-splits ()
  "`kuro-mux--layout-tiled' 4 bufs (2×2 grid): 1 below + 2 right = 3 total splits."
  (let* ((result (kuro-mux-layout-test--with-splits
                   (kuro-mux--layout-tiled (list 'b0 'b1 'b2 'b3)))))
    (should (= 3 (length (plist-get result :splits))))
    (should (= 4 (length (plist-get result :assigns))))))

(ert-deftest kuro-mux-layout-tiled-row-splits-use-below ()
  "`kuro-mux--layout-tiled' row-creation splits use side \\='below."
  (let* ((result (kuro-mux-layout-test--with-splits
                   (kuro-mux--layout-tiled (list 'b0 'b1 'b2 'b3))))
         (splits (plist-get result :splits)))
    ;; The first split is the row-creation split; it must use 'below
    (should (eq 'below (cadr (nth 0 splits))))))

(ert-deftest kuro-mux-layout-tiled-two-buffers-one-row-split ()
  "`kuro-mux--layout-tiled' 2 bufs (2×1 grid): 1 below split, 0 right splits, 2 assigns."
  ;; n=2 → rows=ceiling(sqrt 2)=2, cols=ceiling(2/2)=1 → 1 row-split, no col-splits
  (let* ((result  (kuro-mux-layout-test--with-splits
                    (kuro-mux--layout-tiled (list 'b0 'b1))))
         (splits  (plist-get result :splits))
         (assigns (plist-get result :assigns)))
    (should (= 1 (length splits)))
    (should (eq 'below (cadr (car splits))))
    (should (= 2 (length assigns)))))

(ert-deftest kuro-mux-layout-tiled-assigns-all-buffers-exactly-once ()
  "`kuro-mux--layout-tiled' assigns every buffer exactly once."
  (let* ((bufs    (list 'b0 'b1 'b2))
         (result  (kuro-mux-layout-test--with-splits
                    (kuro-mux--layout-tiled bufs)))
         (assigned (mapcar #'cadr (plist-get result :assigns))))
    (should (= 3 (length assigned)))
    (dolist (b bufs)
      (should (memq b assigned)))))


(provide 'kuro-mux-layout-test-2)
;;; kuro-mux-layout-test-2.el ends here
