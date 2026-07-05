;;; kuro-renderer-test.el --- Unit tests for kuro-renderer.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-renderer.el (render loop, cursor, line updates, title sanitization,
;; and render-cycle helper functions).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI and stream functions are stubbed with cl-letf.
;;
;; Groups covered:
;;     Group 1:  kuro--sanitize-title
;;     Group 2:  kuro--update-line-full
;;     Group 3:  kuro--update-cursor
;;     Group 5:  render loop lifecycle
;;     Group 6:  kuro--apply-title-update
;;     Group 7:  kuro--apply-decoded-scroll-shift
;;     Group 8:  kuro--detect-tui-mode
;;     Group 9:  kuro--update-tui-streaming-timer
;;     Group 10: kuro--handle-clipboard-actions
;;     Group 10b: blink overlay clearing during line update
;;     Group 12: kuro--install-render-timer
;;     Group 13: kuro--reset-cursor-cache
;;     Group 14: kuro--sanitize-title edge cases
;;     Group 16: kuro--recompute-budget-vars
;;     Group 25: kuro--timed
;;     FR-007:   render cycle timing (performance)
;;     FR-008:   post-insert face position correctness
;;
;; Pipeline, resize, coalescing, and render-cycle tests are in
;; kuro-renderer-pipeline-test.el (Groups 11+).
;;
;; Color, face, and attribute decoding tests are in kuro-faces-test.el.
;; Overlay management tests are in kuro-overlays-test.el.
;; Binary FFI decoder tests are in kuro-binary-decoder-test.el.

;;; Code:
(require 'kuro-renderer-test-support)



;;; Group 1: kuro--sanitize-title

(kuro-renderer-test--deftest-sanitize-title-base-cases)

;;; Group 2: kuro--update-line-full

(kuro-renderer-test--deftest-update-line-full-cases)

;;; Group 3: kuro--update-cursor

(ert-deftest kuro-renderer-update-cursor-positions-marker ()
  "kuro--update-cursor moves kuro--cursor-marker when cursor is visible."
  (kuro-renderer-test--with-buffer
    (insert "row0\nrow1\nrow2\n")
    (setq kuro--cursor-marker (point-marker))
    ;; Stub consolidated FFI to return cursor at row=1, col=2, visible=t, shape=0
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(1 2 t 0)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    ;; Row 1, col 2 → "row1\n" starts at position 6, col 2 → pos 8
    (should (= (marker-position kuro--cursor-marker) 8))))

(ert-deftest kuro-renderer-update-cursor-hidden-sets-nil ()
  "When cursor is hidden (DECTCEM off), cursor-type is set to nil."
  (kuro-renderer-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (point-marker))
    (cl-letf (((symbol-function 'kuro--get-cursor-state) (lambda () '(0 0 nil 0)))
              ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
      (kuro--update-cursor))
    (should-not cursor-type)))

(ert-deftest kuro-renderer-update-cursor-shapes ()
  "DECSCUSR cursor shape codes map to correct Emacs cursor-type values."
  (kuro-renderer-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (point-marker))
    (dolist (shape-pair '((0 . box) (1 . box) (2 . box)
                          (3 . (hbar . 2)) (4 . (hbar . 2))
                          (5 . (bar . 2)) (6 . (bar . 2))))
      (cl-letf (((symbol-function 'kuro--get-cursor-state)
                 (lambda () (list 0 0 t (car shape-pair))))
                ((symbol-function 'get-buffer-window) (lambda (&rest _) (selected-window))))
        (kuro--update-cursor))
      (should (equal cursor-type (cdr shape-pair))))))

(ert-deftest kuro-renderer-update-cursor-nil-when-scrolled ()
  "kuro--update-cursor is skipped when scroll offset > 0."
  (kuro-renderer-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (point-marker)
          kuro--scroll-offset 5)
    ;; Mock should NOT be called — if it is, the test will error
    (let ((called nil))
      (cl-letf (((symbol-function 'kuro--get-cursor-state)
                 (lambda () (setq called t) nil)))
        (kuro--update-cursor))
      (should-not called))))

;;; Group 5: Render loop lifecycle

(ert-deftest kuro-renderer-start-stop-render-loop ()
  "kuro--start-render-loop creates a timer; kuro--stop-render-loop cancels it."
  (kuro-renderer-test--with-buffer
    (setq-local kuro-frame-rate 30)
    (setq-local kuro--timer nil)
    (kuro--start-render-loop)
    (should (timerp kuro--timer))
    (kuro--stop-render-loop)
    (should-not kuro--timer)))

(ert-deftest kuro-renderer-stop-render-loop-idempotent ()
  "Calling kuro--stop-render-loop when no timer is running is safe."
  (kuro-renderer-test--with-buffer
    (setq-local kuro--timer nil)
    ;; Should not error
    (should-not (condition-case err
                    (progn (kuro--stop-render-loop) nil)
                  (error err)))))

(ert-deftest kuro-renderer-start-render-loop-replaces-existing-timer ()
  "kuro--start-render-loop cancels any existing timer before creating a new one."
  (kuro-renderer-test--with-buffer
    (setq-local kuro-frame-rate 30)
    (setq-local kuro--timer nil)
    (kuro--start-render-loop)
    (let ((first-timer kuro--timer))
      (kuro--start-render-loop)
      (should (timerp kuro--timer))
      (should-not (eq kuro--timer first-timer)))
    (kuro--stop-render-loop)))

;;; Group 6: kuro--apply-title-update

(kuro-renderer-test--deftest-apply-title-update-cases)

;;; Group 7: kuro--apply-decoded-scroll-shift

(ert-deftest kuro-renderer-apply-decoded-scroll-shift-calls-apply-buffer-scroll ()
  "kuro--apply-decoded-scroll-shift applies the decoded v3 frame shift."
  (kuro-renderer-helpers-test--with-buffer
    (insert (make-string 24 ?\n))  ; 24 lines matching kuro--last-rows
    (let ((apply-args nil)
          (kuro--decode-scroll-up 2)
          (kuro--decode-scroll-down 0))
      (cl-letf (((symbol-function 'kuro--apply-buffer-scroll)
                 (lambda (up down) (push (cons up down) apply-args)))
                ((symbol-function 'kuro--shift-blink-overlay-rows) #'ignore))
        (kuro--apply-decoded-scroll-shift)
        (should (= (length apply-args) 1))
        (should (equal (car apply-args) '(2 . 0)))))))

(ert-deftest kuro-renderer-apply-decoded-scroll-shift-noop-on-zero ()
  "kuro--apply-decoded-scroll-shift does nothing when the frame had no shift."
  (kuro-renderer-helpers-test--with-buffer
    (let ((apply-called nil)
          (kuro--decode-scroll-up 0)
          (kuro--decode-scroll-down 0))
      (cl-letf (((symbol-function 'kuro--apply-buffer-scroll)
                 (lambda (_up _down) (setq apply-called t))))
        (kuro--apply-decoded-scroll-shift)
        (should-not apply-called)))))

(ert-deftest kuro-renderer-apply-decoded-scroll-shift-noop-when-last-rows-zero ()
  "kuro--apply-decoded-scroll-shift does nothing when kuro--last-rows is 0."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 0)
    (let ((apply-called nil)
          (kuro--decode-scroll-up 1)
          (kuro--decode-scroll-down 0))
      (cl-letf (((symbol-function 'kuro--apply-buffer-scroll)
                 (lambda (_up _down) (setq apply-called t))))
        (kuro--apply-decoded-scroll-shift)
        (should-not apply-called)))))

(ert-deftest kuro-renderer-apply-decoded-scroll-shift-zeroes-scratch-vars ()
  "The decode scratch vars are zeroed once read, applied or not.
A stale shift must not replay on a later frame (e.g. after toggling
`kuro-use-binary-ffi', whose legacy path never writes the vars)."
  (kuro-renderer-helpers-test--with-buffer
    (insert (make-string 24 ?\n))
    (setq kuro--decode-scroll-up 3
          kuro--decode-scroll-down 0)
    (cl-letf (((symbol-function 'kuro--apply-buffer-scroll) #'ignore)
              ((symbol-function 'kuro--shift-blink-overlay-rows) #'ignore))
      (kuro--apply-decoded-scroll-shift))
    (should (= kuro--decode-scroll-up 0))
    (should (= kuro--decode-scroll-down 0))))

(ert-deftest kuro-renderer-apply-decoded-scroll-shift-resets-cursor-cache ()
  "Applying a shift invalidates the cached cursor state.
The buffer edit moves the cursor marker with the text, so the cached
grid position no longer corresponds to the marker."
  (kuro-renderer-helpers-test--with-buffer
    (insert (make-string 24 ?\n))
    (setq kuro--last-cursor-row 5
          kuro--last-cursor-col 3)
    (let ((kuro--decode-scroll-up 1)
          (kuro--decode-scroll-down 0))
      (cl-letf (((symbol-function 'kuro--apply-buffer-scroll) #'ignore)
                ((symbol-function 'kuro--shift-blink-overlay-rows) #'ignore))
        (kuro--apply-decoded-scroll-shift)))
    (should-not kuro--last-cursor-row)
    (should-not kuro--last-cursor-col)))

;;; Group 9: kuro--update-tui-streaming-timer (TUI streaming timer management)

(kuro-renderer-test--deftest-update-tui-streaming-timer-cases)

(provide 'kuro-renderer-test)
;;; kuro-renderer-test.el ends here
