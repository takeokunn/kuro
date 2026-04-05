;;; kuro-renderer-ext2-test.el --- Unit tests for kuro-renderer.el (Groups 7-11)  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-renderer.el (render loop, cursor, line updates, title sanitization,
;; and render-cycle helper functions).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI and stream functions are stubbed with cl-letf.
;;
;; This file contains Groups 7-11:
;;     Group 7:  kuro--process-scroll-events
;;     Group 8:  kuro--detect-tui-mode
;;     Group 9:  kuro--update-tui-streaming-timer
;;     Group 10: kuro--handle-clipboard-actions
;;     Group 10b: blink overlay clearing during line update
;;     Group 11: col-to-buf nil handling (see kuro-renderer-pipeline-test.el)
;;
;; Groups 1-6 are in kuro-renderer-test.el.
;; Extended tests (Groups 12-25) are in kuro-renderer-ext-test.el.
;; Pipeline, resize, coalescing, and render-cycle tests are in
;; kuro-renderer-pipeline-test.el (Groups 11+).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-renderer)
(require 'kuro-render-buffer)
(require 'kuro-binary-decoder)

;; kuro--last-rows and kuro--last-cols are defined in kuro.el (the main
;; entry-point file), which is not required here to avoid pulling in PTY
;; setup.  Declare them so the byte-compiler and tests do not error.
(defvar-local kuro--last-rows 0)
(defvar-local kuro--last-cols 0)

;;; Helpers

(defmacro kuro-renderer-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer suitable for renderer tests."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           kuro--cursor-marker
           (kuro--scroll-offset 0)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

(defmacro kuro-renderer-helpers-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer with renderer helper state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           (kuro--initialized t)
           (kuro--scroll-offset 0)
           (kuro--last-rows 24)
           (kuro--last-cols 80)
           (kuro--tui-mode-frame-count 0)
           (kuro--tui-mode-active nil)
           (kuro--last-dirty-count 0)
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           (kuro-streaming-latency-mode t)
           kuro--stream-idle-timer
           kuro--cursor-marker
           kuro--blink-overlays
           kuro--image-overlays
           kuro--timer)
       ,@body)))

;;; Group 7: kuro--process-scroll-events

(ert-deftest kuro-renderer-process-scroll-events-calls-apply-buffer-scroll ()
  "kuro--process-scroll-events calls kuro--apply-buffer-scroll with FFI values."
  (kuro-renderer-helpers-test--with-buffer
    (insert (make-string 24 ?\n))  ; 24 lines matching kuro--last-rows
    (let ((apply-args nil))
      (cl-letf (((symbol-function 'kuro--consume-scroll-events)
                 (lambda () '(2 . 0)))
                ((symbol-function 'kuro--apply-buffer-scroll)
                 (lambda (up down) (push (cons up down) apply-args))))
        (kuro--process-scroll-events)
        (should (= (length apply-args) 1))
        (should (equal (car apply-args) '(2 . 0)))))))

(ert-deftest kuro-renderer-process-scroll-events-noop-on-nil ()
  "kuro--process-scroll-events does nothing when FFI returns nil."
  (kuro-renderer-helpers-test--with-buffer
    (let ((apply-called nil))
      (cl-letf (((symbol-function 'kuro--consume-scroll-events)
                 (lambda () nil))
                ((symbol-function 'kuro--apply-buffer-scroll)
                 (lambda (_up _down) (setq apply-called t))))
        (kuro--process-scroll-events)
        (should-not apply-called)))))

(ert-deftest kuro-renderer-process-scroll-events-noop-when-last-rows-zero ()
  "kuro--process-scroll-events does nothing when kuro--last-rows is 0."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 0)
    (let ((apply-called nil))
      (cl-letf (((symbol-function 'kuro--consume-scroll-events)
                 (lambda () '(1 . 0)))
                ((symbol-function 'kuro--apply-buffer-scroll)
                 (lambda (_up _down) (setq apply-called t))))
        (kuro--process-scroll-events)
        (should-not apply-called)))))

;;; Group 8: kuro--detect-tui-mode (pure TUI mode heuristic)

(ert-deftest kuro-renderer-detect-tui-mode-above-threshold ()
  "High dirty fraction should return t."
  (should (kuro--detect-tui-mode 9 10 0.8)))  ; 90% dirty > 80% threshold

(ert-deftest kuro-renderer-detect-tui-mode-below-threshold ()
  "Low dirty fraction should return nil."
  (should-not (kuro--detect-tui-mode 1 10 0.8)))  ; 10% dirty < 80% threshold

(ert-deftest kuro-renderer-detect-tui-mode-at-exact-threshold ()
  "Dirty fraction exactly at threshold (ceiling) should return t."
  ;; ceiling(0.8 * 10) = 8; 8 dirty rows >= 8 → t
  (should (kuro--detect-tui-mode 8 10 0.8)))

(ert-deftest kuro-renderer-detect-tui-mode-one-below-threshold ()
  "One row below ceiling threshold should return nil."
  ;; ceiling(0.8 * 10) = 8; 7 dirty rows < 8 → nil
  (should-not (kuro--detect-tui-mode 7 10 0.8)))

(ert-deftest kuro-renderer-detect-tui-mode-all-dirty ()
  "All rows dirty should always return t."
  (should (kuro--detect-tui-mode 24 24 0.8)))

(ert-deftest kuro-renderer-detect-tui-mode-zero-dirty ()
  "Zero dirty rows should return nil."
  (should-not (kuro--detect-tui-mode 0 24 0.8)))

(ert-deftest kuro-renderer-detect-tui-mode-zero-total-rows ()
  "With total-rows=0, ceiling(threshold*0)=0 so any dirty count >= 0 returns t.
This is the degenerate case before the first resize; the guard in
`kuro--update-tui-streaming-timer' (> kuro--last-rows 0) prevents calling
kuro--detect-tui-mode with total-rows=0 in the real render loop."
  ;; ceiling(0.8 * 0) = 0; dirty-lines(0) >= 0 → t
  (should (kuro--detect-tui-mode 0 0 0.8)))

;;; Group 9: kuro--update-tui-streaming-timer (TUI streaming timer management)

(ert-deftest kuro-renderer-update-tui-increments-frame-count-when-full-dirty ()
  "kuro--update-tui-streaming-timer increments kuro--tui-mode-frame-count on full-dirty frames."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 24
          kuro--tui-mode-frame-count 0
          kuro--last-dirty-count 20)
    (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer) (lambda () nil))
              ((symbol-function 'kuro--start-stream-idle-timer) (lambda () nil))
              ((symbol-function 'kuro--switch-render-timer) (lambda (_rate) nil)))
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count 1)))))

(ert-deftest kuro-renderer-update-tui-resets-count-when-below-threshold ()
  "kuro--update-tui-streaming-timer resets frame count when dirty-row fraction is below threshold."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 24
          kuro--tui-mode-frame-count 3
          kuro--last-dirty-count 5)
    (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer) (lambda () nil))
              ((symbol-function 'kuro--start-stream-idle-timer) (lambda () nil))
              ((symbol-function 'kuro--switch-render-timer) (lambda (_rate) nil)))
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count 0)))))

(ert-deftest kuro-renderer-update-tui-stops-idle-timer-at-threshold ()
  "kuro--update-tui-streaming-timer calls kuro--stop-stream-idle-timer when threshold is reached."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 24
          kuro--tui-mode-frame-count (1- kuro--tui-mode-threshold)
          kuro--last-dirty-count 20)
    (let ((stop-called nil)
          (switch-rate nil))
      (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer)
                 (lambda () (setq stop-called t)))
                ((symbol-function 'kuro--start-stream-idle-timer) (lambda () nil))
                ((symbol-function 'kuro--switch-render-timer)
                 (lambda (rate) (setq switch-rate rate))))
        (kuro--update-tui-streaming-timer)
        (should stop-called)
        (should (= kuro--tui-mode-frame-count kuro--tui-mode-threshold))
        (should kuro--tui-mode-active)
        (should (= switch-rate kuro-tui-frame-rate))))))

(ert-deftest kuro-renderer-update-tui-restarts-idle-timer-on-tui-exit ()
  "kuro--update-tui-streaming-timer calls kuro--start-stream-idle-timer when leaving TUI mode."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 24
          kuro--tui-mode-frame-count kuro--tui-mode-threshold
          kuro--tui-mode-active t
          kuro--last-dirty-count 5)
    (let ((start-called nil)
          (switch-rate nil))
      (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer) (lambda () nil))
                ((symbol-function 'kuro--start-stream-idle-timer)
                 (lambda () (setq start-called t)))
                ((symbol-function 'kuro--switch-render-timer)
                 (lambda (rate) (setq switch-rate rate))))
        (kuro--update-tui-streaming-timer)
        (should start-called)
        (should (= kuro--tui-mode-frame-count 0))
        (should-not kuro--tui-mode-active)
        (should (= switch-rate kuro-frame-rate))))))

(ert-deftest kuro-renderer-update-tui-noop-when-streaming-mode-disabled ()
  "kuro--update-tui-streaming-timer is a no-op when kuro-streaming-latency-mode is nil."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro-streaming-latency-mode nil
          kuro--last-rows 24
          kuro--tui-mode-frame-count 0
          kuro--last-dirty-count 20)
    (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer)
               (lambda () (error "should not be called")))
              ((symbol-function 'kuro--start-stream-idle-timer)
               (lambda () (error "should not be called")))
              ((symbol-function 'kuro--switch-render-timer)
               (lambda (_rate) (error "should not be called"))))
      (should-not (condition-case err
                      (progn (kuro--update-tui-streaming-timer) nil)
                    (error err)))
      (should (= kuro--tui-mode-frame-count 0)))))

(ert-deftest kuro-renderer-update-tui-noop-when-last-rows-zero ()
  "kuro--update-tui-streaming-timer is a no-op when kuro--last-rows is 0."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 0
          kuro--tui-mode-frame-count 0
          kuro--last-dirty-count 20)
    (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer) (lambda () nil))
              ((symbol-function 'kuro--start-stream-idle-timer) (lambda () nil))
              ((symbol-function 'kuro--switch-render-timer) (lambda (_rate) nil)))
      (kuro--update-tui-streaming-timer)
      (should (= kuro--tui-mode-frame-count 0)))))

(ert-deftest kuro-renderer-update-tui-noop-on-zero-dirty ()
  "kuro--update-tui-streaming-timer handles zero dirty rows without error."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 24
          kuro--tui-mode-frame-count 0
          kuro--last-dirty-count 0)
    (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer) (lambda () nil))
              ((symbol-function 'kuro--start-stream-idle-timer) (lambda () nil))
              ((symbol-function 'kuro--switch-render-timer) (lambda (_rate) nil)))
      (should-not (condition-case err
                      (progn (kuro--update-tui-streaming-timer) nil)
                    (error err)))
      (should (= kuro--tui-mode-frame-count 0)))))

;;; Group 10: kuro--handle-clipboard-actions

(ert-deftest kuro-renderer-handle-clipboard-write-only-policy-calls-kill-new ()
  "kuro--handle-clipboard-actions calls kill-new for write actions under write-only policy."
  (kuro-renderer-helpers-test--with-buffer
    (let ((kill-new-called-with nil)
          (kuro-clipboard-policy 'write-only))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "hello from terminal"))))
                ((symbol-function 'kill-new)
                 (lambda (text) (setq kill-new-called-with text)))
                ((symbol-function 'message) #'ignore))
        (kuro--handle-clipboard-actions)
        (should (equal kill-new-called-with "hello from terminal"))))))

(ert-deftest kuro-renderer-handle-clipboard-allow-policy-calls-kill-new ()
  "kuro--handle-clipboard-actions calls kill-new for write actions under allow policy."
  (kuro-renderer-helpers-test--with-buffer
    (let ((kill-new-called nil)
          (kuro-clipboard-policy 'allow))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "data"))))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t)))
                ((symbol-function 'message) #'ignore))
        (kuro--handle-clipboard-actions)
        (should kill-new-called)))))

(ert-deftest kuro-renderer-handle-clipboard-deny-policy-does-not-call-kill-new ()
  "kuro--handle-clipboard-actions does NOT call kill-new under an unknown/deny policy."
  (kuro-renderer-helpers-test--with-buffer
    (let ((kill-new-called nil)
          ;; 'deny is not a defined policy value; the pcase falls through
          ;; without matching any branch, so kill-new must never be called.
          (kuro-clipboard-policy 'deny))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "secret"))))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t))))
        (kuro--handle-clipboard-actions)
        (should-not kill-new-called)))))

(ert-deftest kuro-renderer-handle-clipboard-write-only-blocks-query ()
  "kuro--handle-clipboard-actions does NOT respond to query actions under write-only policy."
  (kuro-renderer-helpers-test--with-buffer
    (let ((send-key-called nil)
          (kuro-clipboard-policy 'write-only))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((query))))
                ((symbol-function 'kuro--send-key)
                 (lambda (_s) (setq send-key-called t))))
        (kuro--handle-clipboard-actions)
        (should-not send-key-called)))))

(ert-deftest kuro-renderer-handle-clipboard-empty-actions-noop ()
  "kuro--handle-clipboard-actions is a no-op when the action list is nil."
  (kuro-renderer-helpers-test--with-buffer
    (let ((kill-new-called nil))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () nil))
                ((symbol-function 'kill-new)
                 (lambda (_text) (setq kill-new-called t))))
        (kuro--handle-clipboard-actions)
        (should-not kill-new-called)))))

(ert-deftest kuro-renderer-handle-clipboard-multiple-write-actions ()
  "kuro--handle-clipboard-actions processes multiple write actions in sequence."
  (kuro-renderer-helpers-test--with-buffer
    (let ((killed-texts nil)
          (kuro-clipboard-policy 'write-only))
      (cl-letf (((symbol-function 'kuro--poll-clipboard-actions)
                 (lambda () '((write . "first") (write . "second"))))
                ((symbol-function 'kill-new)
                 (lambda (text) (push text killed-texts)))
                ((symbol-function 'message) #'ignore))
        (kuro--handle-clipboard-actions)
        (should (= (length killed-texts) 2))
        (should (member "first" killed-texts))
        (should (member "second" killed-texts))))))

;;; Group 10b: Blink overlay clearing during line update

(ert-deftest test-kuro-update-line-full-clears-blink-overlays-on-row ()
  "Updating a line removes blink overlays on that row."
  (with-temp-buffer
    (insert "old text\n")
    (insert "other row\n")
    (let ((kuro--blink-overlays nil)
          (kuro--blink-overlays-by-row nil)
          (kuro--image-overlays nil)
          (kuro--col-to-buf-map (make-hash-table :test 'eql)))
      ;; Create a blink overlay on row 0
      (let ((ov (make-overlay 1 5)))
        (overlay-put ov 'kuro-blink t)
        (overlay-put ov 'kuro-blink-type 'slow)
        (push ov kuro--blink-overlays))
      ;; Update row 0 — should clear blink overlay on that row
      (kuro--update-line-full 0 "new text" nil nil)
      (should (null kuro--blink-overlays)))))

(ert-deftest test-kuro-update-line-full-preserves-blink-overlays-other-row ()
  "Updating a line preserves blink overlays on other rows."
  (with-temp-buffer
    (insert "row zero\n")
    (insert "row one\n")
    (let ((kuro--blink-overlays nil)
          (kuro--image-overlays nil)
          (kuro--col-to-buf-map (make-hash-table :test 'eql)))
      ;; Create a blink overlay on row 1
      (let ((ov (make-overlay 10 15)))
        (overlay-put ov 'kuro-blink t)
        (overlay-put ov 'kuro-blink-type 'fast)
        (push ov kuro--blink-overlays))
      ;; Update row 0 — should NOT clear blink overlay on row 1
      (kuro--update-line-full 0 "new text" nil nil)
      (should (= 1 (length kuro--blink-overlays))))))

(provide 'kuro-renderer-ext2-test)

;;; kuro-renderer-ext2-test.el ends here
