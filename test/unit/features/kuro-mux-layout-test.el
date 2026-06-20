;;; kuro-mux-layout-test.el --- Unit tests for kuro-mux-layout.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for the preset window-layout engine (kuro-mux-layout.el).
;; Layout-splitting helpers require real windows and are covered by integration
;; tests; this file focuses on pure-logic paths testable in batch Emacs.

;;; Code:

(require 'kuro-test-stubs)
(require 'kuro-config)
(require 'kuro-mux)
(require 'kuro-mux-layout)

(unless (fboundp 'kuro-mode)
  (define-derived-mode kuro-mode fundamental-mode "Kuro-test"))


;;; Group 37 — kuro-mux--layout-handlers and kuro-mux-layouts invariants

(ert-deftest kuro-mux-layout-handlers-has-five-entries ()
  "`kuro-mux--layout-handlers' contains exactly 5 entries."
  (should (= (length kuro-mux--layout-handlers) 5)))

(ert-deftest kuro-mux-layout-handlers-all-values-are-functions ()
  "Every value in `kuro-mux--layout-handlers' is a callable function."
  (dolist (entry kuro-mux--layout-handlers)
    (should (functionp (cdr entry)))))

(ert-deftest kuro-mux-layout-handlers-keys-match-layouts ()
  "`kuro-mux-layouts' equals the key list of `kuro-mux--layout-handlers'."
  (should (equal kuro-mux-layouts (mapcar #'car kuro-mux--layout-handlers))))

(ert-deftest kuro-mux-layout-layouts-has-five-entries ()
  "`kuro-mux-layouts' contains exactly 5 preset names."
  (should (= (length kuro-mux-layouts) 5)))

(ert-deftest kuro-mux-layout-layouts-all-strings ()
  "Every entry in `kuro-mux-layouts' is a non-empty string."
  (dolist (l kuro-mux-layouts)
    (should (stringp l))
    (should (> (length l) 0))))

(ert-deftest kuro-mux-layout-layouts-includes-tiled ()
  "`kuro-mux-layouts' includes the \"tiled\" layout."
  (should (member "tiled" kuro-mux-layouts)))

(ert-deftest kuro-mux-layout-layouts-includes-even-horizontal ()
  "`kuro-mux-layouts' includes \"even-horizontal\"."
  (should (member "even-horizontal" kuro-mux-layouts)))

(ert-deftest kuro-mux-layout-layouts-includes-main-vertical ()
  "`kuro-mux-layouts' includes \"main-vertical\"."
  (should (member "main-vertical" kuro-mux-layouts)))

(ert-deftest kuro-mux-layout-dispatch-layout-macroexpands-to-pcase ()
  "`kuro--dispatch-layout' expands to fixed `pcase' dispatch."
  (should (equal (macroexpand-1 '(kuro--dispatch-layout layout win buffers))
                 '(pcase layout
                    ("even-horizontal" (kuro-mux--layout-chain win (cdr buffers) 'right))
                    ("even-vertical" (kuro-mux--layout-chain win (cdr buffers) 'below))
                    ("main-vertical" (kuro-mux--layout-main win (cdr buffers) 'right 'below))
                    ("main-horizontal" (kuro-mux--layout-main win (cdr buffers) 'below 'right))
                    ("tiled" (kuro-mux--layout-tiled buffers))
                    (_ (user-error "Kuro-mux: unknown layout: %s" layout))))))


;;; Group 38 — kuro-mux--visible-session-buffers

(ert-deftest kuro-mux-layout-visible-session-buffers-empty-when-no-kuro ()
  "`kuro-mux--visible-session-buffers' returns nil when no kuro buffers are visible."
  (cl-letf (((symbol-function 'window-list)
             (lambda (&rest _) (list (selected-window))))
            ((symbol-function 'window-buffer)
             (lambda (_) (current-buffer)))
            ((symbol-function 'derived-mode-p)
             (lambda (&rest _) nil)))
    (with-temp-buffer
      (should (null (kuro-mux--visible-session-buffers))))))

(ert-deftest kuro-mux-layout-visible-session-buffers-returns-kuro-buffers ()
  "`kuro-mux--visible-session-buffers' returns kuro buffers in window order."
  (let* ((buf1 (generate-new-buffer " *layout-test-1*"))
         (buf2 (generate-new-buffer " *layout-test-2*"))
         (win1 'fake-window-1)
         (win2 'fake-window-2)
         (buf-map (list (cons win1 buf1) (cons win2 buf2))))
    (unwind-protect
        (cl-letf (((symbol-function 'window-list)
                   (lambda (&rest _) (list win1 win2)))
                  ((symbol-function 'window-buffer)
                   (lambda (w) (cdr (assq w buf-map))))
                  ((symbol-function 'derived-mode-p)
                   (lambda (&rest _) t)))
          (let ((result (kuro-mux--visible-session-buffers)))
            (should (equal result (list buf1 buf2)))))
      (kill-buffer buf1)
      (kill-buffer buf2))))

(ert-deftest kuro-mux-layout-visible-session-buffers-deduplicates ()
  "`kuro-mux--visible-session-buffers' returns each buffer only once."
  (let* ((buf (generate-new-buffer " *layout-dedup-test*"))
         (w   (selected-window)))
    (unwind-protect
        (cl-letf (((symbol-function 'window-list)
                   (lambda (&rest _) (list w w)))
                  ((symbol-function 'window-buffer)
                   (lambda (_) buf))
                  ((symbol-function 'buffer-live-p) #'identity)
                  ((symbol-function 'derived-mode-p)
                   (lambda (&rest _) t)))
          (let ((result (kuro-mux--visible-session-buffers)))
            (should (= (length result) 1))
            (should (eq (car result) buf))))
      (kill-buffer buf))))


;;; Group 39 — kuro-mux-select-layout error cases

(ert-deftest kuro-mux-layout-select-layout-errors-on-unknown ()
  "`kuro-mux-select-layout' signals user-error for unknown layout names."
  (should-error (kuro-mux-select-layout "diagonal-chaos") :type 'user-error))

(ert-deftest kuro-mux-layout-select-layout-errors-on-no-panes ()
  "`kuro-mux-select-layout' signals user-error when no kuro panes are visible."
  (cl-letf (((symbol-function 'kuro-mux--visible-session-buffers) (lambda () nil)))
    (should-error (kuro-mux-select-layout "even-horizontal") :type 'user-error)))


;;; Group 40 — kuro-mux--cycle-layout pure logic

(defmacro kuro-mux-layout-test--with-cycle (current-layout &rest body)
  "Run BODY with frame's kuro-mux-current-layout set to CURRENT-LAYOUT.
Stubs `kuro-mux-select-layout' to capture the chosen layout."
  (declare (indent 1))
  `(let (chosen)
     (cl-letf (((symbol-function 'frame-parameter)
                (lambda (_f param)
                  (when (eq param 'kuro-mux-current-layout) ,current-layout)))
               ((symbol-function 'kuro-mux-select-layout)
                (lambda (l) (setq chosen l))))
       ,@body
       chosen)))

(ert-deftest kuro-mux-layout-cycle-next-from-nil-selects-first ()
  "From no current layout, +1 step selects the first layout."
  (let ((chosen (kuro-mux-layout-test--with-cycle nil
                  (kuro-mux--cycle-layout 1))))
    (should (equal chosen (car kuro-mux-layouts)))))

(ert-deftest kuro-mux-layout-cycle-prev-from-nil-selects-last ()
  "From no current layout, -1 step selects the last layout."
  (let ((chosen (kuro-mux-layout-test--with-cycle nil
                  (kuro-mux--cycle-layout -1))))
    (should (equal chosen (car (last kuro-mux-layouts))))))

(ert-deftest kuro-mux-layout-cycle-forward-wraps ()
  "Cycling +1 from the last layout wraps to the first."
  (let ((last-layout (car (last kuro-mux-layouts))))
    (let ((chosen (kuro-mux-layout-test--with-cycle last-layout
                    (kuro-mux--cycle-layout 1))))
      (should (equal chosen (car kuro-mux-layouts))))))

(ert-deftest kuro-mux-layout-cycle-backward-wraps ()
  "Cycling -1 from the first layout wraps to the last."
  (let ((first-layout (car kuro-mux-layouts)))
    (let ((chosen (kuro-mux-layout-test--with-cycle first-layout
                    (kuro-mux--cycle-layout -1))))
      (should (equal chosen (car (last kuro-mux-layouts)))))))

(ert-deftest kuro-mux-layout-cycle-advances-from-known-layout ()
  "Cycling +1 from a known layout advances to the next one."
  (let* ((first  (car kuro-mux-layouts))
         (second (cadr kuro-mux-layouts)))
    (let ((chosen (kuro-mux-layout-test--with-cycle first
                    (kuro-mux--cycle-layout 1))))
      (should (equal chosen second)))))


;;; Group 41 — kuro-mux-next-layout / kuro-mux-previous-layout

(ert-deftest kuro-mux-layout-next-layout-calls-cycle-plus-1 ()
  "`kuro-mux-next-layout' delegates to `kuro-mux--cycle-layout' with step 1."
  (let (step-used)
    (cl-letf (((symbol-function 'kuro-mux--cycle-layout)
               (lambda (s) (setq step-used s))))
      (kuro-mux-next-layout)
      (should (= step-used 1)))))

(ert-deftest kuro-mux-layout-previous-layout-calls-cycle-minus-1 ()
  "`kuro-mux-previous-layout' delegates to `kuro-mux--cycle-layout' with step -1."
  (let (step-used)
    (cl-letf (((symbol-function 'kuro-mux--cycle-layout)
               (lambda (s) (setq step-used s))))
      (kuro-mux-previous-layout)
      (should (= step-used -1)))))

(ert-deftest kuro-mux-layout-next-layout-is-interactive ()
  "`kuro-mux-next-layout' is interactive."
  (should (commandp #'kuro-mux-next-layout)))

(ert-deftest kuro-mux-layout-previous-layout-is-interactive ()
  "`kuro-mux-previous-layout' is interactive."
  (should (commandp #'kuro-mux-previous-layout)))

(provide 'kuro-mux-layout-test)
;;; kuro-mux-layout-test.el ends here
