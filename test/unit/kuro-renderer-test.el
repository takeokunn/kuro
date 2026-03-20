;;; kuro-renderer-test.el --- Unit tests for kuro-renderer.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-renderer.el (render loop, cursor, line updates, title sanitization,
;; and render-cycle helper functions).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;; All FFI and stream functions are stubbed with cl-letf.
;;
;; Groups covered:
;;   From kuro-renderer-unit-test.el:
;;     Group 1: kuro--sanitize-title
;;     Group 2: kuro--update-line-full
;;     Group 3: kuro--update-cursor
;;     Group 5: render loop lifecycle
;;
;;   From kuro-renderer-helpers-test.el:
;;     Group 6: kuro--apply-title-update
;;     Group 7: kuro--process-scroll-events
;;     Group 8: kuro--detect-tui-mode
;;     Group 9: kuro--update-tui-streaming-timer
;;     Group 10: kuro--handle-clipboard-actions
;;
;; Color, face, and attribute decoding tests are in kuro-faces-test.el.
;; Overlay management tests are in kuro-overlays-test.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-renderer)
(require 'kuro-render-buffer)

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
           (kuro--col-to-buf-map (make-hash-table :test 'eql))
           (kuro-streaming-latency-mode t)
           kuro--stream-idle-timer
           kuro--cursor-marker
           kuro--blink-overlays
           kuro--image-overlays)
       ,@body)))

;;; Group 1: kuro--sanitize-title

(ert-deftest kuro-renderer-sanitize-title-clean-ascii ()
  "Clean ASCII strings pass through unchanged."
  (should (equal (kuro--sanitize-title "bash") "bash"))
  (should (equal (kuro--sanitize-title "vim - file.txt") "vim - file.txt")))

(ert-deftest kuro-renderer-sanitize-title-strips-control-chars ()
  "Control characters (U+0000-U+001F, U+007F) are stripped."
  ;; Use string constructor to avoid string-literal escaping ambiguity.
  (should (equal (kuro--sanitize-title (concat "a" (string 1) "b"))   "ab"))  ; U+0001
  (should (equal (kuro--sanitize-title (concat "a" (string #x1f) "b")) "ab")) ; U+001F
  (should (equal (kuro--sanitize-title (concat "a" (string #x7f) "b")) "ab")) ; U+007F
  (should (equal (kuro--sanitize-title (concat "a" (string #x1b) "b")) "ab")) ; ESC
  )

(ert-deftest kuro-renderer-sanitize-title-strips-bidi-overrides ()
  "Unicode bidi override codepoints (U+202A-U+202E) are stripped."
  (should (equal (kuro--sanitize-title (concat "a" "\u202e" "b")) "ab"))
  (should (equal (kuro--sanitize-title (concat "a" "\u202a" "b")) "ab")))

(ert-deftest kuro-renderer-sanitize-title-strips-isolates ()
  "Unicode directional isolates (U+2066-U+2069) are stripped."
  (should (equal (kuro--sanitize-title (concat "a" "\u2066" "b")) "ab"))
  (should (equal (kuro--sanitize-title (concat "a" "\u2069" "b")) "ab")))

(ert-deftest kuro-renderer-sanitize-title-empty-string ()
  "Empty string remains empty."
  (should (equal (kuro--sanitize-title "") "")))

(ert-deftest kuro-renderer-sanitize-title-mixed-content ()
  "Normal chars around control chars: control chars stripped, rest preserved."
  (should (equal (kuro--sanitize-title "vim\x00\x1b[31m file.txt") "vim[31m file.txt")))

;;; Group 2: kuro--update-line-full

(ert-deftest kuro-renderer-update-line-replaces-content ()
  "kuro--update-line-full replaces the text on the specified row."
  (kuro-renderer-test--with-buffer
    (insert "original\nsecond\n")
    (kuro--update-line-full 0 "replaced" nil nil)
    (goto-char (point-min))
    (should (looking-at "replaced\n"))))

(ert-deftest kuro-renderer-update-line-preserves-other-lines ()
  "kuro--update-line-full does not affect other rows."
  (kuro-renderer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (kuro--update-line-full 0 "updated" nil nil)
    (goto-char (point-min))
    (forward-line 1)
    (should (looking-at "line1\n"))
    (forward-line 1)
    (should (looking-at "line2\n"))))

(ert-deftest kuro-renderer-update-line-appends-newline ()
  "kuro--update-line-full always appends a newline after the text."
  (kuro-renderer-test--with-buffer
    (insert "old\n")
    (kuro--update-line-full 0 "new" nil nil)
    (goto-char (point-min))
    (should (looking-at "new\n"))))

(ert-deftest kuro-renderer-update-line-empty-text ()
  "kuro--update-line-full with empty string produces a lone newline on the row."
  (kuro-renderer-test--with-buffer
    (insert "content\n")
    (kuro--update-line-full 0 "" nil nil)
    (goto-char (point-min))
    (should (looking-at "\n"))))

(ert-deftest kuro-renderer-update-line-unicode ()
  "kuro--update-line-full handles multi-byte Unicode content correctly."
  (kuro-renderer-test--with-buffer
    (insert "old\n")
    (kuro--update-line-full 0 "日本語テスト" nil nil)
    (goto-char (point-min))
    (should (looking-at "日本語テスト\n"))))

(ert-deftest kuro-renderer-update-line-preserves-line-count ()
  "kuro--update-line-full preserves the total number of lines."
  (kuro-renderer-test--with-buffer
    (insert "a\nb\nc\n")
    (kuro--update-line-full 1 "B" nil nil)
    (should (= (count-lines (point-min) (point-max)) 3))))

(ert-deftest kuro-renderer-update-line-nil-text-is-noop ()
  "kuro--update-line-full with nil text is a no-op (guard clause)."
  (kuro-renderer-test--with-buffer
    (insert "keep\n")
    (kuro--update-line-full 0 nil nil nil)
    (goto-char (point-min))
    (should (looking-at "keep\n"))))

;;; Group 3: kuro--update-cursor

(ert-deftest kuro-renderer-update-cursor-positions-marker ()
  "kuro--update-cursor moves kuro--cursor-marker when cursor is visible."
  (kuro-renderer-test--with-buffer
    (insert "row0\nrow1\nrow2\n")
    (setq kuro--cursor-marker (point-marker))
    ;; Stub FFI to return cursor at (1, 2)
    (cl-letf (((symbol-function 'kuro--get-cursor)        (lambda () '(1 . 2)))
              ((symbol-function 'kuro--get-cursor-visible) (lambda () t))
              ((symbol-function 'kuro--get-cursor-shape)   (lambda () 0)))
      (kuro--update-cursor))
    ;; Row 1, col 2 → "row1\n" starts at position 6, col 2 → pos 8
    (should (= (marker-position kuro--cursor-marker) 8))))

(ert-deftest kuro-renderer-update-cursor-hidden-sets-nil ()
  "When cursor is hidden (DECTCEM off), cursor-type is set to nil."
  (kuro-renderer-test--with-buffer
    (insert "line\n")
    (setq kuro--cursor-marker (point-marker))
    (cl-letf (((symbol-function 'kuro--get-cursor)        (lambda () '(0 . 0)))
              ((symbol-function 'kuro--get-cursor-visible) (lambda () nil))
              ((symbol-function 'kuro--get-cursor-shape)   (lambda () 0)))
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
      (cl-letf (((symbol-function 'kuro--get-cursor)        (lambda () '(0 . 0)))
                ((symbol-function 'kuro--get-cursor-visible) (lambda () t))
                ((symbol-function 'kuro--get-cursor-shape)   (lambda () (car shape-pair))))
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
      (cl-letf (((symbol-function 'kuro--get-cursor) (lambda () (setq called t) nil)))
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

(ert-deftest kuro-renderer-apply-title-update-renames-buffer ()
  "kuro--apply-title-update renames the buffer to *kuro: <title>* format."
  (kuro-renderer-helpers-test--with-buffer
    (cl-letf (((symbol-function 'kuro--get-and-clear-title)
               (lambda () "vim")))
      (kuro--apply-title-update)
      (should (string-match-p "\\*kuro: vim\\*" (buffer-name))))))

(ert-deftest kuro-renderer-apply-title-update-sanitizes-title ()
  "kuro--apply-title-update sanitizes the title (strips control chars)."
  (kuro-renderer-helpers-test--with-buffer
    (cl-letf (((symbol-function 'kuro--get-and-clear-title)
               (lambda () (concat "bash" (string #x1b) "[31m"))))
      (kuro--apply-title-update)
      ;; ESC and bracket should be stripped; result: "bash[31m"
      (should (string-match-p "\\*kuro: bash\\[31m\\*" (buffer-name))))))

(ert-deftest kuro-renderer-apply-title-update-noop-on-nil-title ()
  "kuro--apply-title-update does not rename when FFI returns nil."
  (kuro-renderer-helpers-test--with-buffer
    (let ((name-before (buffer-name)))
      (cl-letf (((symbol-function 'kuro--get-and-clear-title)
                 (lambda () nil)))
        (kuro--apply-title-update)
        (should (equal (buffer-name) name-before))))))

(ert-deftest kuro-renderer-apply-title-update-noop-on-empty-title ()
  "kuro--apply-title-update does not rename when FFI returns an empty string."
  (kuro-renderer-helpers-test--with-buffer
    (let ((name-before (buffer-name)))
      (cl-letf (((symbol-function 'kuro--get-and-clear-title)
                 (lambda () "")))
        (kuro--apply-title-update)
        (should (equal (buffer-name) name-before))))))

(ert-deftest kuro-renderer-apply-title-update-sets-frame-name ()
  "kuro--apply-title-update sets the frame name via set-frame-parameter."
  (kuro-renderer-helpers-test--with-buffer
    (let ((frame-name-set nil))
      (cl-letf (((symbol-function 'kuro--get-and-clear-title)
                 (lambda () "htop"))
                ((symbol-function 'get-buffer-window)
                 (lambda (_buf _all) (selected-window)))
                ((symbol-function 'set-frame-parameter)
                 (lambda (_frame param val)
                   (when (eq param 'name)
                     (setq frame-name-set val)))))
        (kuro--apply-title-update)
        (should (equal frame-name-set "htop"))))))

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
    ;; 24 rows; dirty-threshold = 0.8 → ceiling(0.8*24) = 20.
    ;; Pass 20 updates (>= threshold) to trigger full-dirty detection.
    (setq kuro--last-rows 24
          kuro--tui-mode-frame-count 0)
    (let ((updates (make-list 20 '(((0 . "") . nil) . nil))))
      (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer) (lambda () nil))
                ((symbol-function 'kuro--start-stream-idle-timer) (lambda () nil)))
        (kuro--update-tui-streaming-timer updates)
        (should (= kuro--tui-mode-frame-count 1))))))

(ert-deftest kuro-renderer-update-tui-resets-count-when-below-threshold ()
  "kuro--update-tui-streaming-timer resets frame count when dirty-row fraction is below threshold."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 24
          kuro--tui-mode-frame-count 3)
    ;; 5 dirty rows out of 24 is well below 80%
    (let ((updates (make-list 5 '(((0 . "") . nil) . nil))))
      (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer) (lambda () nil))
                ((symbol-function 'kuro--start-stream-idle-timer) (lambda () nil)))
        (kuro--update-tui-streaming-timer updates)
        (should (= kuro--tui-mode-frame-count 0))))))

(ert-deftest kuro-renderer-update-tui-stops-idle-timer-at-threshold ()
  "kuro--update-tui-streaming-timer calls kuro--stop-stream-idle-timer when threshold is reached."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 24
          ;; One frame away from threshold (threshold = 10)
          kuro--tui-mode-frame-count (1- kuro--tui-mode-threshold))
    (let ((stop-called nil))
      (let ((updates (make-list 20 '(((0 . "") . nil) . nil))))
        (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer)
                   (lambda () (setq stop-called t)))
                  ((symbol-function 'kuro--start-stream-idle-timer) (lambda () nil)))
          (kuro--update-tui-streaming-timer updates)
          (should stop-called)
          (should (= kuro--tui-mode-frame-count kuro--tui-mode-threshold)))))))

(ert-deftest kuro-renderer-update-tui-restarts-idle-timer-on-tui-exit ()
  "kuro--update-tui-streaming-timer calls kuro--start-stream-idle-timer when leaving TUI mode."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 24
          ;; Already in TUI mode (frame count >= threshold)
          kuro--tui-mode-frame-count kuro--tui-mode-threshold)
    (let ((start-called nil))
      ;; Only 5 dirty rows — below threshold, transitions out of TUI mode
      (let ((updates (make-list 5 '(((0 . "") . nil) . nil))))
        (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer) (lambda () nil))
                  ((symbol-function 'kuro--start-stream-idle-timer)
                   (lambda () (setq start-called t))))
          (kuro--update-tui-streaming-timer updates)
          (should start-called)
          (should (= kuro--tui-mode-frame-count 0)))))))

(ert-deftest kuro-renderer-update-tui-noop-when-streaming-mode-disabled ()
  "kuro--update-tui-streaming-timer is a no-op when kuro-streaming-latency-mode is nil."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro-streaming-latency-mode nil
          kuro--last-rows 24
          kuro--tui-mode-frame-count 0)
    (let ((updates (make-list 20 '(((0 . "") . nil) . nil))))
      (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer)
                 (lambda () (error "should not be called")))
                ((symbol-function 'kuro--start-stream-idle-timer)
                 (lambda () (error "should not be called"))))
        ;; Should not error and frame count should remain 0
        (should-not (condition-case err
                        (progn (kuro--update-tui-streaming-timer updates) nil)
                      (error err)))
        (should (= kuro--tui-mode-frame-count 0))))))

(ert-deftest kuro-renderer-update-tui-noop-when-last-rows-zero ()
  "kuro--update-tui-streaming-timer is a no-op when kuro--last-rows is 0."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 0
          kuro--tui-mode-frame-count 0)
    (let ((updates (make-list 20 '(((0 . "") . nil) . nil))))
      (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer) (lambda () nil))
                ((symbol-function 'kuro--start-stream-idle-timer) (lambda () nil)))
        (kuro--update-tui-streaming-timer updates)
        (should (= kuro--tui-mode-frame-count 0))))))

(ert-deftest kuro-renderer-update-tui-noop-on-nil-updates ()
  "kuro--update-tui-streaming-timer handles nil updates (no dirty rows) without error."
  (kuro-renderer-helpers-test--with-buffer
    (setq kuro--last-rows 24
          kuro--tui-mode-frame-count 0)
    (cl-letf (((symbol-function 'kuro--stop-stream-idle-timer) (lambda () nil))
              ((symbol-function 'kuro--start-stream-idle-timer) (lambda () nil)))
      (should-not (condition-case err
                      (progn (kuro--update-tui-streaming-timer nil) nil)
                    (error err)))
      ;; 0 dirty rows < threshold; count stays 0
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

(provide 'kuro-renderer-test)

;;; kuro-renderer-test.el ends here
