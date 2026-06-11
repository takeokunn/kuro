;;; kuro-mux-test-5.el --- ERT tests for kuro-mux.el — Groups 28-29  -*-  lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
;;; Group 28 — kuro-mux-next-layout / kuro-mux-previous-layout (cycling)

(ert-deftest kuro-mux-test-next-layout-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `SPC' to `kuro-mux-next-layout' (tmux parity)."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "SPC"))
              #'kuro-mux-next-layout)))

(ert-deftest kuro-mux-test-prev-layout-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `M-{' to `kuro-mux-previous-layout'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "M-{"))
              #'kuro-mux-previous-layout)))

(ert-deftest kuro-mux-test-next-layout-from-unset-picks-first ()
  "`kuro-mux-next-layout' on a fresh frame applies the first preset."
  (set-frame-parameter nil 'kuro-mux-current-layout nil)
  (let ((applied nil))
    (cl-letf (((symbol-function 'kuro-mux-select-layout)
               (lambda (layout) (setq applied layout))))
      (kuro-mux-next-layout)
      (should (equal applied "even-horizontal")))))

(ert-deftest kuro-mux-test-prev-layout-from-unset-picks-last ()
  "`kuro-mux-previous-layout' on a fresh frame applies the last preset."
  (set-frame-parameter nil 'kuro-mux-current-layout nil)
  (let ((applied nil))
    (cl-letf (((symbol-function 'kuro-mux-select-layout)
               (lambda (layout) (setq applied layout))))
      (kuro-mux-previous-layout)
      (should (equal applied "tiled")))))

(ert-deftest kuro-mux-test-next-layout-advances-one ()
  "`kuro-mux-next-layout' moves to the layout one position forward."
  (set-frame-parameter nil 'kuro-mux-current-layout "even-vertical")
  (let ((applied nil))
    (cl-letf (((symbol-function 'kuro-mux-select-layout)
               (lambda (layout) (setq applied layout))))
      (kuro-mux-next-layout)
      ;; even-vertical (idx 1) → main-vertical (idx 2)
      (should (equal applied "main-vertical")))))

(ert-deftest kuro-mux-test-next-layout-wraps-around ()
  "`kuro-mux-next-layout' wraps from the last preset back to the first."
  (set-frame-parameter nil 'kuro-mux-current-layout "tiled")
  (let ((applied nil))
    (cl-letf (((symbol-function 'kuro-mux-select-layout)
               (lambda (layout) (setq applied layout))))
      (kuro-mux-next-layout)
      (should (equal applied "even-horizontal")))))

(ert-deftest kuro-mux-test-prev-layout-wraps-around ()
  "`kuro-mux-previous-layout' wraps from the first preset to the last."
  (set-frame-parameter nil 'kuro-mux-current-layout "even-horizontal")
  (let ((applied nil))
    (cl-letf (((symbol-function 'kuro-mux-select-layout)
               (lambda (layout) (setq applied layout))))
      (kuro-mux-previous-layout)
      (should (equal applied "tiled")))))

(ert-deftest kuro-mux-test-select-layout-records-frame-param ()
  "`kuro-mux-select-layout' stores the applied layout on the frame."
  (let ((b1 (get-buffer-create "*mux-rec1*")))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-mux--visible-session-buffers)
                   (lambda () (list b1)))
                  ((symbol-function 'delete-other-windows) (lambda () nil))
                  ((symbol-function 'set-window-buffer) (lambda (&rest _) nil))
                  ((symbol-function 'balance-windows) (lambda (&rest _) nil))
                  ((symbol-function 'split-window) (lambda (&rest _) 'w)))
          (set-frame-parameter nil 'kuro-mux-current-layout nil)
          (kuro-mux-select-layout "main-horizontal")
          (should (equal (frame-parameter nil 'kuro-mux-current-layout)
                         "main-horizontal")))
      (kill-buffer b1)
      (set-frame-parameter nil 'kuro-mux-current-layout nil))))

;;; Group 29 — kuro-mux-rotate-panes (tmux rotate-window)

(ert-deftest kuro-mux-test-rotate-panes-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `C-o' to `kuro-mux-rotate-panes'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "C-o"))
              #'kuro-mux-rotate-panes)))

(ert-deftest kuro-mux-test-rotate-backward-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `M-o' to `kuro-mux-rotate-panes-backward'."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "M-o"))
              #'kuro-mux-rotate-panes-backward)))

(ert-deftest kuro-mux-test-rotate-panes-needs-two ()
  "`kuro-mux-rotate-panes' signals user-error with fewer than two panes."
  (cl-letf (((symbol-function 'kuro-mux--visible-windows)
             (lambda () '(w1))))
    (should-error (kuro-mux-rotate-panes) :type 'user-error)))

(ert-deftest kuro-mux-test-rotate-panes-forward-mapping ()
  "Forward rotation: each window takes the previous window's buffer; w1 wraps."
  (let ((assignments nil))
    (cl-letf (((symbol-function 'kuro-mux--visible-windows)
               (lambda () '(w1 w2 w3)))
              ((symbol-function 'window-buffer)
               (lambda (w) (pcase w ('w1 'A) ('w2 'B) ('w3 'C))))
              ((symbol-function 'set-window-buffer)
               (lambda (win buf) (push (cons win buf) assignments)))
              ((symbol-function 'select-window) #'ignore))
      (kuro-mux-rotate-panes)
      (should (equal (nreverse assignments)
                     '((w1 . C) (w2 . A) (w3 . B)))))))

(ert-deftest kuro-mux-test-rotate-panes-backward-mapping ()
  "Backward rotation: each window takes the next window's buffer; w1 takes w2's."
  (let ((assignments nil))
    (cl-letf (((symbol-function 'kuro-mux--visible-windows)
               (lambda () '(w1 w2 w3)))
              ((symbol-function 'window-buffer)
               (lambda (w) (pcase w ('w1 'A) ('w2 'B) ('w3 'C))))
              ((symbol-function 'set-window-buffer)
               (lambda (win buf) (push (cons win buf) assignments)))
              ((symbol-function 'select-window) #'ignore))
      (kuro-mux-rotate-panes t)
      (should (equal (nreverse assignments)
                     '((w1 . B) (w2 . C) (w3 . A)))))))

(ert-deftest kuro-mux-test-rotate-backward-command-delegates ()
  "`kuro-mux-rotate-panes-backward' calls `kuro-mux-rotate-panes' with t."
  (let ((arg 'unset))
    (cl-letf (((symbol-function 'kuro-mux-rotate-panes)
               (lambda (&optional b) (setq arg b))))
      (kuro-mux-rotate-panes-backward)
      (should (eq arg t)))))

(ert-deftest kuro-mux-test-visible-windows-filters-kuro ()
  "`kuro-mux--visible-windows' returns only windows showing kuro buffers."
  (let ((kuro-buf (get-buffer-create "*mux-vw-kuro*"))
        (plain    (get-buffer-create "*mux-vw-plain*")))
    (unwind-protect
        (progn
          (with-current-buffer kuro-buf (kuro-mode))
          (cl-letf (((symbol-function 'window-list)
                     (lambda (&rest _) '(w1 w2)))
                    ((symbol-function 'window-buffer)
                     (lambda (w) (pcase w ('w1 kuro-buf) ('w2 plain)))))
            (should (equal (kuro-mux--visible-windows) '(w1)))))
      (kill-buffer kuro-buf)
      (kill-buffer plain))))


(provide 'kuro-mux-test-5)
;;; kuro-mux-test-5.el ends here
