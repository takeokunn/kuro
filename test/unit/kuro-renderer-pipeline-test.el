;;; kuro-renderer-pipeline-test.el --- Unit tests for kuro-renderer.el pipeline functions  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-renderer.el pipeline and related functions.
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI and stream functions are stubbed with cl-letf.
;;
;; Groups covered:
;;     Group 11b: kuro--apply-terminal-modes
;;     Group 11c: kuro--poll-cwd
;;     Group 11d: kuro--check-process-exit
;;     Group 11e: kuro--poll-prompt-mark-updates
;;     Group 12:  kuro--ring-pending-bell
;;     Group 13:  kuro--tick-blink-if-active
;;     Group 14:  kuro--poll-within-budget
;;     Group 15:  kuro--apply-dirty-lines
;;
;; Groups 16-21 (TUI mode, OOB rows, finalize-dirty, core pipeline,
;; binary FFI dispatch, resize) are in kuro-renderer-pipeline-ext3-test.el.
;; Groups 22-28 (frame coalescing, render-cycle, eviction, scroll suppression,
;; title sanitization) are in kuro-renderer-pipeline-ext-test.el.
;; Basic renderer tests (Groups 1-10b) are in kuro-renderer-test.el.
;; Color, face, and attribute decoding tests are in kuro-faces-test.el.
;; Overlay management tests are in kuro-overlays-test.el.
;; Binary FFI decoder tests are in kuro-binary-decoder-test.el.

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

(defmacro kuro-renderer-pipeline-test--with-buffer (&rest body)
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

;;; Group 11b: kuro--apply-terminal-modes

(ert-deftest kuro-renderer-pipeline-apply-terminal-modes-maps-all-fields ()
  "kuro--apply-terminal-modes assigns all 7 mode values to buffer-local vars."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro--apply-terminal-modes '(t t 1003 t t t 8))
    (should (eq kuro--application-cursor-keys-mode t))
    (should (eq kuro--app-keypad-mode t))
    (should (= kuro--mouse-mode 1003))
    (should (eq kuro--mouse-sgr t))
    (should (eq kuro--mouse-pixel-mode t))
    (should (eq kuro--bracketed-paste-mode t))
    (should (= kuro--keyboard-flags 8))))

(ert-deftest kuro-renderer-pipeline-apply-terminal-modes-nil-kbf-defaults-to-zero ()
  "kuro--apply-terminal-modes defaults keyboard-flags to 0 when 7th element is nil."
  (kuro-renderer-pipeline-test--with-buffer
    (kuro--apply-terminal-modes '(nil nil 0 nil nil nil nil))
    (should (= kuro--keyboard-flags 0))))

(ert-deftest kuro-renderer-pipeline-apply-terminal-modes-false-values ()
  "kuro--apply-terminal-modes correctly sets all fields to nil/false."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--application-cursor-keys-mode t
          kuro--mouse-mode 1003)
    (kuro--apply-terminal-modes '(nil nil 0 nil nil nil 0))
    (should-not kuro--application-cursor-keys-mode)
    (should (= kuro--mouse-mode 0))))

;;; Group 11c: kuro--poll-cwd

(ert-deftest kuro-renderer-pipeline-poll-cwd-updates-default-directory ()
  "kuro--poll-cwd sets default-directory from OSC 7."
  (kuro-renderer-pipeline-test--with-buffer
    (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () "/tmp/test")))
      (kuro--poll-cwd)
      (should (equal default-directory "/tmp/test/")))))

(ert-deftest kuro-renderer-pipeline-poll-cwd-noop-on-nil ()
  "kuro--poll-cwd does not modify default-directory when FFI returns nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((dir-before default-directory))
      (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () nil)))
        (kuro--poll-cwd)
        (should (equal default-directory dir-before))))))

(ert-deftest kuro-renderer-pipeline-poll-cwd-noop-on-empty-string ()
  "kuro--poll-cwd does not modify default-directory when FFI returns \"\"."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((dir-before default-directory))
      (cl-letf (((symbol-function 'kuro--get-cwd) (lambda () "")))
        (kuro--poll-cwd)
        (should (equal default-directory dir-before))))))

;;; Group 11d: kuro--check-process-exit

(ert-deftest kuro-renderer-pipeline-check-process-exit-kills-when-dead ()
  "kuro--check-process-exit calls kuro-kill when process is dead and kill-on-exit is set."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-kill-buffer-on-exit t)
    (let ((kill-called nil))
      (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () nil))
                ((symbol-function 'kuro-kill)              (lambda () (setq kill-called t))))
        (kuro--check-process-exit)
        (should kill-called)))))

(ert-deftest kuro-renderer-pipeline-check-process-exit-noop-when-alive ()
  "kuro--check-process-exit does not call kuro-kill when process is alive."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-kill-buffer-on-exit t)
    (let ((kill-called nil))
      (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () t))
                ((symbol-function 'kuro-kill)              (lambda () (setq kill-called t))))
        (kuro--check-process-exit)
        (should-not kill-called)))))

(ert-deftest kuro-renderer-pipeline-check-process-exit-noop-when-kill-disabled ()
  "kuro--check-process-exit does not call kuro-kill when kill-on-exit is nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-kill-buffer-on-exit nil)
    (let ((kill-called nil))
      (cl-letf (((symbol-function 'kuro--is-process-alive) (lambda () nil))
                ((symbol-function 'kuro-kill)              (lambda () (setq kill-called t))))
        (kuro--check-process-exit)
        (should-not kill-called)))))

;;; Group 11e: kuro--poll-prompt-mark-updates

(ert-deftest kuro-renderer-pipeline-poll-prompt-mark-updates-merges-marks ()
  "kuro--poll-prompt-mark-updates calls kuro--update-prompt-positions with marks."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--prompt-positions nil)
    (let ((update-called-with nil))
      (cl-letf (((symbol-function 'kuro--poll-prompt-marks)
                 (lambda () '(("prompt-start" 5 0))))
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (marks positions max)
                   (setq update-called-with (list marks positions max))
                   positions)))
        (kuro--poll-prompt-mark-updates)
        (should (equal (car update-called-with) '(("prompt-start" 5 0))))))))

(ert-deftest kuro-renderer-pipeline-poll-prompt-mark-updates-noop-on-nil ()
  "kuro--poll-prompt-mark-updates does nothing when FFI returns nil."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((update-called nil))
      (cl-letf (((symbol-function 'kuro--poll-prompt-marks) (lambda () nil))
                ((symbol-function 'kuro--update-prompt-positions)
                 (lambda (_m _p _mx) (setq update-called t) nil)))
        (kuro--poll-prompt-mark-updates)
        (should-not update-called)))))

;;; Group 12: kuro--ring-pending-bell

(ert-deftest kuro-renderer-pipeline-ring-pending-bell-rings-when-pending ()
  "kuro--ring-pending-bell calls ding when a bell event is pending.
`kuro--call' is a macro that checks `kuro--initialized' then calls
`kuro-core-take-bell-pending'; stub the FFI function directly."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((ding-called nil)
          (kuro--session-id 1))
      (cl-letf (((symbol-function 'kuro-core-take-bell-pending)
                 (lambda (_sid) t))
                ((symbol-function 'ding)
                 (lambda () (setq ding-called t))))
        (kuro--ring-pending-bell)
        (should ding-called)))))

(ert-deftest kuro-renderer-pipeline-ring-pending-bell-silent-when-no-bell ()
  "kuro--ring-pending-bell does not call ding when no bell is pending."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((ding-called nil)
          (kuro--session-id 1))
      (cl-letf (((symbol-function 'kuro-core-take-bell-pending)
                 (lambda (_sid) nil))
                ((symbol-function 'ding)
                 (lambda () (setq ding-called t))))
        (kuro--ring-pending-bell)
        (should-not ding-called)))))

;;; Group 13: kuro--tick-blink-if-active

(ert-deftest kuro-renderer-pipeline-tick-blink-calls-tick-when-overlays ()
  "kuro--tick-blink-if-active calls kuro--tick-blink-overlays when overlays exist."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((tick-called nil))
      (setq kuro--blink-overlays (list (make-overlay 1 1)))
      (cl-letf (((symbol-function 'kuro--tick-blink-overlays)
                 (lambda () (setq tick-called t))))
        (kuro--tick-blink-if-active)
        (should tick-called)))))

(ert-deftest kuro-renderer-pipeline-tick-blink-noop-when-no-overlays ()
  "kuro--tick-blink-if-active is a no-op when kuro--blink-overlays is nil."
  (kuro-renderer-pipeline-test--with-buffer
    (setq kuro--blink-overlays nil)
    (let ((tick-called nil))
      (cl-letf (((symbol-function 'kuro--tick-blink-overlays)
                 (lambda () (setq tick-called t))))
        (kuro--tick-blink-if-active)
        (should-not tick-called)))))

;;; Group 14: kuro--poll-within-budget

(ert-deftest kuro-renderer-pipeline-poll-within-budget-calls-poll-when-under-budget ()
  "kuro--poll-within-budget calls kuro--poll-terminal-modes when under budget."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-frame-rate 30)
    (let ((poll-called nil))
      (cl-letf (((symbol-function 'kuro--poll-terminal-modes)
                 (lambda () (setq poll-called t)))
                ((symbol-function 'kuro--is-process-alive)
                 (lambda () t)))
        ;; Use a frame-start well in the past so elapsed time > budget
        ;; Actually for under-budget: use float-time directly (near zero elapsed)
        (kuro--poll-within-budget (float-time))
        (should poll-called)))))

(ert-deftest kuro-renderer-pipeline-poll-within-budget-checks-exit-when-over-budget ()
  "kuro--poll-within-budget checks process-alive when over budget."
  (kuro-renderer-pipeline-test--with-buffer
    (setq-local kuro-frame-rate 30
                kuro-kill-buffer-on-exit t)
    (let ((is-alive-called nil))
      (cl-letf (((symbol-function 'kuro--poll-terminal-modes)
                 (lambda () (error "should not be called over-budget")))
                ((symbol-function 'kuro--is-process-alive)
                 (lambda () (setq is-alive-called t) t)))
        ;; Pass a frame-start 10 seconds ago — definitely over budget
        (kuro--poll-within-budget (- (float-time) 10.0))
        (should is-alive-called)))))

;;; Group 15: kuro--apply-dirty-lines

(ert-deftest kuro-renderer-pipeline-apply-dirty-lines-calls-update-for-each-row ()
  "kuro--apply-dirty-lines calls kuro--update-line-full for each update entry."
  (kuro-renderer-pipeline-test--with-buffer
    (insert "row0\nrow1\n")
    (let ((updated-rows nil))
      (cl-letf (((symbol-function 'kuro--update-line-full)
                 (lambda (row _text _faces _c2b)
                   (push row updated-rows))))
        (kuro--apply-dirty-lines
         '((((0 . "new0") . nil) . nil)
           (((1 . "new1") . nil) . nil)))
        (should (= (length updated-rows) 2))
        (should (member 0 updated-rows))
        (should (member 1 updated-rows))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-lines-swallows-per-row-errors ()
  "kuro--apply-dirty-lines swallows per-row errors and continues."
  (kuro-renderer-pipeline-test--with-buffer
    (insert "row0\nrow1\n")
    (let ((rows-attempted nil))
      (cl-letf (((symbol-function 'kuro--update-line-full)
                 (lambda (row _text _faces _c2b)
                   (push row rows-attempted)
                   (when (= row 0)
                     (error "simulated row error")))))
        (kuro--apply-dirty-lines
         '((((0 . "bad") . nil) . nil)
           (((1 . "ok") . nil) . nil)))
        ;; Both rows should have been attempted despite error on row 0
        (should (= (length rows-attempted) 2))))))

(ert-deftest kuro-renderer-pipeline-apply-dirty-lines-empty-updates-is-noop ()
  "kuro--apply-dirty-lines with an empty list is a no-op."
  (kuro-renderer-pipeline-test--with-buffer
    (let ((called nil))
      (cl-letf (((symbol-function 'kuro--update-line-full)
                 (lambda (&rest _) (setq called t))))
        (kuro--apply-dirty-lines nil)
        (should-not called)))))

(provide 'kuro-renderer-pipeline-test)

;;; kuro-renderer-pipeline-test.el ends here

