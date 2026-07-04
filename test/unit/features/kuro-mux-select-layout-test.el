;;; kuro-mux-select-layout-test.el --- ERT tests for kuro-mux-select-layout  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

;;; Helpers

(defmacro kuro-mux-select-layout-test--with-layout-stubs (sessions-fn split-fn &rest body)
  "Stub the window management functions used by `kuro-mux-select-layout'.
SESSIONS-FN is bound to `kuro-mux--visible-session-buffers';
SPLIT-FN is bound to `split-window'.  The three bookkeeping functions
`delete-other-windows', `set-window-buffer', and `balance-windows' are
always stubbed to `#\\='ignore'."
  `(cl-letf (((symbol-function 'kuro-mux--visible-session-buffers) ,sessions-fn)
             ((symbol-function 'delete-other-windows) #'ignore)
             ((symbol-function 'set-window-buffer)    #'ignore)
             ((symbol-function 'balance-windows)      #'ignore)
             ((symbol-function 'split-window)         ,split-fn))
     ,@body))

;;; Group 27 — kuro-mux-select-layout (tmux preset layouts)

(ert-deftest kuro-mux-test-layouts-constant ()
  "`kuro-mux-layouts' lists the five tmux preset layout names."
  (should (equal kuro-mux-layouts
                 '("even-horizontal" "even-vertical"
                   "main-vertical" "main-horizontal" "tiled"))))

(ert-deftest kuro-mux-test-select-layout-in-prefix-map ()
  "`kuro-mux-prefix-map' binds `M-SPC' to the `kuro-mux-select-layout' picker.
`SPC' itself cycles to the next layout (tmux parity); see Group 28."
  (should (eq (lookup-key kuro-mux-prefix-map (kbd "M-SPC"))
              #'kuro-mux-select-layout)))

(ert-deftest kuro-mux-test-select-layout-rejects-unknown ()
  "`kuro-mux-select-layout' signals user-error for an unrecognized layout."
  (should-error (kuro-mux-select-layout "spiral") :type 'user-error))

(ert-deftest kuro-mux-test-visible-session-buffers-filters-kuro ()
  "`kuro-mux--visible-session-buffers' returns only kuro-mode buffers, deduped."
  (let ((kuro-buf (get-buffer-create "*mux-vis-kuro*"))
        (plain    (get-buffer-create "*mux-vis-plain*")))
    (unwind-protect
        (progn
          (with-current-buffer kuro-buf (kuro-mode))
          (cl-letf (((symbol-function 'window-list)
                     (lambda (&rest _) '(w1 w2 w3)))
                    ((symbol-function 'window-buffer)
                     (lambda (w) (pcase w
                                   ('w1 kuro-buf)
                                   ('w2 plain)
                                   ('w3 kuro-buf)))))
            (should (equal (kuro-mux--visible-session-buffers)
                           (list kuro-buf)))))
      (kill-buffer kuro-buf)
      (kill-buffer plain))))

(ert-deftest kuro-mux-test-select-layout-no-panes-errors ()
  "`kuro-mux-select-layout' signals user-error when no kuro panes are visible."
  (cl-letf (((symbol-function 'kuro-mux--visible-session-buffers)
             (lambda () nil)))
    (should-error (kuro-mux-select-layout "tiled") :type 'user-error)))

(ert-deftest kuro-mux-test-select-layout-even-horizontal-chains-splits ()
  "even-horizontal splits to the `right' once per non-main buffer."
  (let ((b1 (get-buffer-create "*mux-eh1*"))
        (b2 (get-buffer-create "*mux-eh2*"))
        (b3 (get-buffer-create "*mux-eh3*"))
        (split-sides nil))
    (unwind-protect
        (kuro-mux-select-layout-test--with-layout-stubs
          (lambda () (list b1 b2 b3))
          (lambda (_win _size side) (push side split-sides) 'newwin)
          (kuro-mux-select-layout "even-horizontal")
          ;; Two non-main buffers → two splits, both toward `right'.
          (should (equal split-sides '(right right))))
      (kill-buffer b1) (kill-buffer b2) (kill-buffer b3))))

(ert-deftest kuro-mux-test-select-layout-even-vertical-uses-below ()
  "even-vertical splits toward `below'."
  (let ((b1 (get-buffer-create "*mux-ev1*"))
        (b2 (get-buffer-create "*mux-ev2*"))
        (split-sides nil))
    (unwind-protect
        (kuro-mux-select-layout-test--with-layout-stubs
          (lambda () (list b1 b2))
          (lambda (_win _size side) (push side split-sides) 'newwin)
          (kuro-mux-select-layout "even-vertical")
          (should (equal split-sides '(below))))
      (kill-buffer b1) (kill-buffer b2))))

(ert-deftest kuro-mux-test-select-layout-main-vertical-splits ()
  "main-vertical splits the main area `right' then stacks the rest `below'."
  (let ((b1 (get-buffer-create "*mux-mv1*"))
        (b2 (get-buffer-create "*mux-mv2*"))
        (b3 (get-buffer-create "*mux-mv3*"))
        (split-sides nil))
    (unwind-protect
        (kuro-mux-select-layout-test--with-layout-stubs
          (lambda () (list b1 b2 b3))
          (lambda (_win _size side) (push side split-sides) 'newwin)
          (kuro-mux-select-layout "main-vertical")
          ;; First split carves the secondary area (right); remaining buffer
          ;; (b3) stacks below within it.
          (should (equal (nreverse split-sides) '(right below))))
      (kill-buffer b1) (kill-buffer b2) (kill-buffer b3))))

(ert-deftest kuro-mux-test-select-layout-single-pane-no-splits ()
  "With one visible pane, no splits occur and the layout still applies."
  (let ((b1 (get-buffer-create "*mux-sp1*"))
        (split-count 0))
    (unwind-protect
        (kuro-mux-select-layout-test--with-layout-stubs
          (lambda () (list b1))
          (lambda (&rest _) (setq split-count (1+ split-count)) 'w)
          (kuro-mux-select-layout "even-horizontal")
          (should (= split-count 0)))
      (kill-buffer b1))))


(provide 'kuro-mux-select-layout-test)
;;; kuro-mux-select-layout-test.el ends here
