;;; kuro-mux-windows-test.el --- Tests for kuro-mux-windows.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))


;;; Group 47 — kuro-mux-last (last-session tracking)

(ert-deftest kuro-mux-windows-last-errors-when-no-session ()
  "`kuro-mux-last' signals user-error when `kuro-mux--last-session' is nil."
  (let ((kuro-mux--last-session nil))
    (should-error (kuro-mux-last) :type 'user-error)))

(ert-deftest kuro-mux-windows-last-errors-when-dead-session ()
  "`kuro-mux-last' signals user-error and clears the var when buffer is dead."
  (let* ((buf (get-buffer-create " *kuro-mux-dead*"))
         (kuro-mux--last-session buf))
    (kill-buffer buf)
    (should-error (kuro-mux-last) :type 'user-error)
    (should (null kuro-mux--last-session))))

(ert-deftest kuro-mux-windows-last-switches-to-live-session ()
  "`kuro-mux-last' calls `switch-to-buffer' when the session is live."
  (let* ((buf (get-buffer-create " *kuro-mux-live*"))
         (kuro-mux--last-session buf)
         switched-to)
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'switch-to-buffer)
                     (lambda (b) (setq switched-to b))))
            (kuro-mux-last))
          (should (eq switched-to buf)))
      (kill-buffer buf))))

(ert-deftest kuro-mux-windows-last-is-interactive ()
  "`kuro-mux-last' is an interactive command."
  (should (commandp #'kuro-mux-last)))


;;; Group 48 — kuro-mux--track-window-change

(ert-deftest kuro-mux-windows-track-window-change-records-kuro-buf ()
  "`kuro-mux--track-window-change' sets `kuro-mux--last-session' to old kuro buffer."
  (let* ((kuro-buf (get-buffer-create " *kuro-wc-track*"))
         (kuro-mux--last-session nil))
    (unwind-protect
        (progn
          (with-current-buffer kuro-buf (kuro-mode))
          (cl-letf (((symbol-function 'old-selected-window) (lambda () 'fake-win))
                    ((symbol-function 'window-live-p) (lambda (_w) t))
                    ((symbol-function 'window-buffer) (lambda (_w) kuro-buf))
                    ((symbol-function 'current-buffer) (lambda () (get-buffer-create " *kuro-other*"))))
            (kuro-mux--track-window-change nil)
            (should (eq kuro-mux--last-session kuro-buf))))
      (kill-buffer kuro-buf)
      (ignore-errors (kill-buffer " *kuro-other*")))))

(ert-deftest kuro-mux-windows-track-window-change-ignores-dead-window ()
  "`kuro-mux--track-window-change' does nothing when old window is not live."
  (let ((kuro-mux--last-session :sentinel))
    (cl-letf (((symbol-function 'old-selected-window) (lambda () nil))
              ((symbol-function 'window-live-p) (lambda (_w) nil)))
      (kuro-mux--track-window-change nil)
      ;; Should not have changed the value.
      (should (eq kuro-mux--last-session :sentinel)))))

(ert-deftest kuro-mux-windows-track-window-change-ignores-same-buffer ()
  "`kuro-mux--track-window-change' skips recording when the buffer is the current one."
  (let* ((buf (get-buffer-create " *kuro-wc-same*"))
         (kuro-mux--last-session nil))
    (unwind-protect
        (progn
          (with-current-buffer buf (kuro-mode))
          (cl-letf (((symbol-function 'old-selected-window) (lambda () 'w))
                    ((symbol-function 'window-live-p)  (lambda (_w) t))
                    ((symbol-function 'window-buffer)  (lambda (_w) buf))
                    ((symbol-function 'current-buffer) (lambda () buf)))
            (kuro-mux--track-window-change nil)
            (should (null kuro-mux--last-session))))
      (kill-buffer buf))))


;;; Group 49 — kuro-mux-find-window

(ert-deftest kuro-mux-windows-find-window-is-interactive ()
  "`kuro-mux-find-window' is an interactive command."
  (should (commandp #'kuro-mux-find-window)))

(ert-deftest kuro-mux-windows-find-window-errors-when-buffer-missing ()
  "`kuro-mux-find-window' signals user-error when no buffer with NAME exists."
  (should-error (kuro-mux-find-window " *no-such-buf-xyz*") :type 'user-error))

(ert-deftest kuro-mux-windows-find-window-selects-visible-window ()
  "`kuro-mux-find-window' calls `select-window' when the buffer is visible."
  (let* ((buf (get-buffer-create " *kuro-fw-visible*"))
         (selected nil))
    (unwind-protect
        (cl-letf (((symbol-function 'get-buffer-window)
                   (lambda (_b _frame) 'fake-win))
                  ((symbol-function 'select-window)
                   (lambda (w) (setq selected w))))
          (kuro-mux-find-window (buffer-name buf))
          (should (eq selected 'fake-win)))
      (kill-buffer buf))))

(ert-deftest kuro-mux-windows-find-window-switches-when-not-visible ()
  "`kuro-mux-find-window' calls `switch-to-buffer' when buffer not in a window."
  (let* ((buf (get-buffer-create " *kuro-fw-hidden*"))
         (switched nil))
    (unwind-protect
        (cl-letf (((symbol-function 'get-buffer-window)
                   (lambda (_b _frame) nil))
                  ((symbol-function 'switch-to-buffer)
                   (lambda (b) (setq switched b))))
          (kuro-mux-find-window (buffer-name buf))
          (should (eq switched buf)))
      (kill-buffer buf))))


;;; Group 50 — kuro--def-mux-split macro + generated commands

(ert-deftest kuro-mux-windows-def-mux-split-expands-to-defun ()
  "`kuro--def-mux-split' single-step expands to a `defun' form."
  (let ((expansion (macroexpand-1
                    '(kuro--def-mux-split kuro-test--split split-window-right "doc"))))
    (should (eq 'defun (car expansion)))
    (should (eq 'kuro-test--split (cadr expansion)))))

(ert-deftest kuro-mux-windows-split-right-is-interactive ()
  "`kuro-mux-split-right' is an interactive command."
  (should (commandp #'kuro-mux-split-right)))

(ert-deftest kuro-mux-windows-split-below-is-interactive ()
  "`kuro-mux-split-below' is an interactive command."
  (should (commandp #'kuro-mux-split-below)))

(ert-deftest kuro-mux-windows-split-right-calls-split-and-create ()
  "`kuro-mux-split-right' calls `split-window-right', selects the window, then `kuro-create'."
  (let (win-selected create-called)
    (cl-letf (((symbol-function 'split-window-right) (lambda () 'new-win))
              ((symbol-function 'select-window) (lambda (w) (setq win-selected w)))
              ((symbol-function 'kuro-create)  (lambda (&rest _) (setq create-called t))))
      (kuro-mux-split-right)
      (should (eq win-selected 'new-win))
      (should create-called))))

(ert-deftest kuro-mux-windows-split-below-calls-split-and-create ()
  "`kuro-mux-split-below' calls `split-window-below', selects the window, then `kuro-create'."
  (let (win-selected create-called)
    (cl-letf (((symbol-function 'split-window-below) (lambda () 'new-win-b))
              ((symbol-function 'select-window) (lambda (w) (setq win-selected w)))
              ((symbol-function 'kuro-create)  (lambda (&rest _) (setq create-called t))))
      (kuro-mux-split-below)
      (should (eq win-selected 'new-win-b))
      (should create-called))))


;;; Group 51 — kuro-mux-zoom

(ert-deftest kuro-mux-windows-zoom-is-interactive ()
  "`kuro-mux-zoom' is an interactive command."
  (should (commandp #'kuro-mux-zoom)))

(ert-deftest kuro-mux-windows-zoom-saves-config-and-maximizes ()
  "`kuro-mux-zoom' (first call) saves window config and calls `delete-other-windows'."
  (let ((kuro-mux--zoom-config nil)
        deleted)
    (cl-letf (((symbol-function 'current-window-configuration) (lambda () 'saved-cfg))
              ((symbol-function 'delete-other-windows) (lambda () (setq deleted t))))
      (kuro-mux-zoom)
      (should (eq kuro-mux--zoom-config 'saved-cfg))
      (should deleted))))

(ert-deftest kuro-mux-windows-zoom-restores-config-on-second-call ()
  "`kuro-mux-zoom' (second call) restores saved config and clears the var."
  (let ((kuro-mux--zoom-config 'saved)
        restored)
    (cl-letf (((symbol-function 'set-window-configuration)
               (lambda (cfg) (setq restored cfg))))
      (kuro-mux-zoom)
      (should (eq restored 'saved))
      (should (null kuro-mux--zoom-config)))))


;;; Group 52 — kuro-mux-kill

(ert-deftest kuro-mux-windows-kill-is-interactive ()
  "`kuro-mux-kill' is an interactive command."
  (should (commandp #'kuro-mux-kill)))

(ert-deftest kuro-mux-windows-kill-kills-buffer-when-confirm-nil ()
  "`kuro-mux-kill' kills the current kuro buffer when `kuro-mux-kill-confirm' is nil."
  (let* ((buf (get-buffer-create " *kuro-kill-noconf*"))
         (killed nil)
         (kuro-mux-kill-confirm nil))
    (unwind-protect
        (progn
          (with-current-buffer buf
            (kuro-mode)
            (cl-letf (((symbol-function 'kill-buffer)
                       (lambda (b) (setq killed b))))
              (kuro-mux-kill)))
          (should (eq killed buf)))
      (ignore-errors (kill-buffer buf)))))

(ert-deftest kuro-mux-windows-kill-skips-when-user-says-no ()
  "`kuro-mux-kill' does not kill when `y-or-n-p' returns nil."
  (let* ((buf (get-buffer-create " *kuro-kill-skip*"))
         (killed nil)
         (kuro-mux-kill-confirm t))
    (unwind-protect
        (with-current-buffer buf
          (kuro-mode)
          (cl-letf (((symbol-function 'y-or-n-p)  (lambda (_p) nil))
                    ((symbol-function 'kill-buffer) (lambda (_b) (setq killed t))))
            (kuro-mux-kill))
          (should-not killed))
      (ignore-errors (kill-buffer buf)))))


;;; Group 53 — kuro--def-mux-swap macro + generated commands

(ert-deftest kuro-mux-windows-def-mux-swap-expands-to-defun ()
  "`kuro--def-mux-swap' single-step expands to a `defun' form."
  (let ((expansion (macroexpand-1
                    '(kuro--def-mux-swap kuro-test--swap next-window "doc"))))
    (should (eq 'defun (car expansion)))
    (should (eq 'kuro-test--swap (cadr expansion)))))

(ert-deftest kuro-mux-windows-swap-forward-is-interactive ()
  "`kuro-mux-swap-pane-forward' is an interactive command."
  (should (commandp #'kuro-mux-swap-pane-forward)))

(ert-deftest kuro-mux-windows-swap-backward-is-interactive ()
  "`kuro-mux-swap-pane-backward' is an interactive command."
  (should (commandp #'kuro-mux-swap-pane-backward)))

(ert-deftest kuro-mux-windows-swap-forward-swaps-states ()
  "`kuro-mux-swap-pane-forward' calls `window-swap-states' with current and next windows."
  (let ((cur 'win-a) (nxt 'win-b) swapped)
    (cl-letf (((symbol-function 'selected-window) (lambda () cur))
              ((symbol-function 'next-window)
               (lambda (_w _m _f) nxt))
              ((symbol-function 'window-swap-states)
               (lambda (a b) (setq swapped (list a b)))))
      (kuro-mux-swap-pane-forward)
      (should (equal swapped (list cur nxt))))))

(ert-deftest kuro-mux-windows-swap-errors-when-only-one-window ()
  "`kuro-mux-swap-pane-forward' signals user-error when peer = selected window."
  (cl-letf (((symbol-function 'selected-window) (lambda () 'only-win))
            ((symbol-function 'next-window) (lambda (_w _m _f) 'only-win)))
    (should-error (kuro-mux-swap-pane-forward) :type 'user-error)))


;;; Group 54 — kuro-mux-resize-pane

(ert-deftest kuro-mux-windows-resize-pane-is-interactive ()
  "`kuro-mux-resize-pane' is an interactive command."
  (should (commandp #'kuro-mux-resize-pane)))

(ert-deftest kuro-mux-windows-resize-directions-table-is-complete ()
  "`kuro--mux-resize-directions' covers all four directions."
  (should (assq 'up    kuro--mux-resize-directions))
  (should (assq 'down  kuro--mux-resize-directions))
  (should (assq 'left  kuro--mux-resize-directions))
  (should (assq 'right kuro--mux-resize-directions)))

(ert-deftest kuro-mux-windows-resize-pane-calls-correct-fn ()
  "`kuro-mux-resize-pane' dispatches via the alist to the correct resize function."
  (let (called-fn called-n)
    (cl-letf (((symbol-function 'enlarge-window)
               (lambda (n) (setq called-fn 'enlarge-window called-n n))))
      (kuro-mux-resize-pane 'up 5)
      (should (eq called-fn 'enlarge-window))
      (should (= called-n 5)))))

(ert-deftest kuro-mux-windows-resize-pane-defaults-delta-to-1 ()
  "`kuro-mux-resize-pane' uses DELTA=1 when nil is passed."
  (let (called-n)
    (cl-letf (((symbol-function 'enlarge-window) (lambda (n) (setq called-n n))))
      (kuro-mux-resize-pane 'up nil)
      (should (= called-n 1)))))

(ert-deftest kuro-mux-windows-resize-pane-errors-on-bad-direction ()
  "`kuro-mux-resize-pane' signals user-error for an unknown direction."
  (should-error (kuro-mux-resize-pane 'diagonal 1) :type 'user-error))


(provide 'kuro-mux-windows-test)
;;; kuro-mux-windows-test.el ends here
