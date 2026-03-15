;;; kuro-renderer-unit-test.el --- Unit tests for kuro-renderer.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-renderer.el (render loop, cursor, line updates, title sanitization).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Color, face, and attribute decoding tests are in kuro-faces-test.el.
;; Overlay management tests are in kuro-overlays-test.el.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-renderer)

;;; Helper

(defmacro kuro-renderer-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer suitable for renderer tests."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (inhibit-modification-hooks t)
           kuro--cursor-marker
           (kuro--scroll-offset 0)
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

;;; Group 2: kuro--update-line

(ert-deftest kuro-renderer-update-line-replaces-content ()
  "kuro--update-line replaces the text on the specified row."
  (kuro-renderer-test--with-buffer
    (insert "original\nsecond\n")
    (kuro--update-line 0 "replaced")
    (goto-char (point-min))
    (should (looking-at "replaced\n"))))

(ert-deftest kuro-renderer-update-line-preserves-other-lines ()
  "kuro--update-line does not affect other rows."
  (kuro-renderer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (kuro--update-line 0 "updated")
    (goto-char (point-min))
    (forward-line 1)
    (should (looking-at "line1\n"))
    (forward-line 1)
    (should (looking-at "line2\n"))))

(ert-deftest kuro-renderer-update-line-appends-newline ()
  "kuro--update-line always appends a newline after the text."
  (kuro-renderer-test--with-buffer
    (insert "old\n")
    (kuro--update-line 0 "new")
    (goto-char (point-min))
    (should (looking-at "new\n"))))

(ert-deftest kuro-renderer-update-line-empty-text ()
  "kuro--update-line with empty string produces a lone newline on the row."
  (kuro-renderer-test--with-buffer
    (insert "content\n")
    (kuro--update-line 0 "")
    (goto-char (point-min))
    (should (looking-at "\n"))))

(ert-deftest kuro-renderer-update-line-unicode ()
  "kuro--update-line handles multi-byte Unicode content correctly."
  (kuro-renderer-test--with-buffer
    (insert "old\n")
    (kuro--update-line 0 "日本語テスト")
    (goto-char (point-min))
    (should (looking-at "日本語テスト\n"))))

(ert-deftest kuro-renderer-update-line-preserves-line-count ()
  "kuro--update-line preserves the total number of lines."
  (kuro-renderer-test--with-buffer
    (insert "a\nb\nc\n")
    (kuro--update-line 1 "B")
    (should (= (count-lines (point-min) (point-max)) 3))))

(ert-deftest kuro-renderer-update-line-nil-text-is-noop ()
  "kuro--update-line with nil text is a no-op (guard clause)."
  (kuro-renderer-test--with-buffer
    (insert "keep\n")
    (kuro--update-line 0 nil)
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

;;; Group 4: kuro--apply-faces-simple

(ert-deftest kuro-renderer-apply-faces-simple-calls-apply-faces ()
  "kuro--apply-faces-simple iterates over updates and calls kuro--apply-faces."
  (kuro-renderer-test--with-buffer
    (insert "Hello World\n")
    (let ((called-with nil))
      (cl-letf (((symbol-function 'kuro--apply-faces)
                 (lambda (line-num ranges)
                   (push (cons line-num ranges) called-with))))
        (kuro--apply-faces-simple '((0 . ((0 5 . some-attrs)))))
        (should (= (length called-with) 1))
        (should (= (car (car called-with)) 0))))))

(ert-deftest kuro-renderer-apply-faces-simple-multiple-lines ()
  "kuro--apply-faces-simple processes multiple line updates."
  (kuro-renderer-test--with-buffer
    (insert "line0\nline1\nline2\n")
    (let ((call-count 0))
      (cl-letf (((symbol-function 'kuro--apply-faces)
                 (lambda (_line-num _ranges) (cl-incf call-count))))
        (kuro--apply-faces-simple '((0 . ()) (1 . ()) (2 . ())))
        (should (= call-count 3))))))

;;; Group 5: Render loop lifecycle

(ert-deftest kuro-renderer-start-stop-render-loop ()
  "kuro--start-render-loop creates a timer; kuro--stop-render-loop cancels it."
  (kuro-renderer-test--with-buffer
    (setq-local kuro-frame-rate 30)
    (setq-local kuro-timer nil)
    (kuro--start-render-loop)
    (should (timerp kuro-timer))
    (kuro--stop-render-loop)
    (should-not kuro-timer)))

(ert-deftest kuro-renderer-stop-render-loop-idempotent ()
  "Calling kuro--stop-render-loop when no timer is running is safe."
  (kuro-renderer-test--with-buffer
    (setq-local kuro-timer nil)
    ;; Should not error
    (should-not (condition-case err
                    (progn (kuro--stop-render-loop) nil)
                  (error err)))))

(ert-deftest kuro-renderer-start-render-loop-replaces-existing-timer ()
  "kuro--start-render-loop cancels any existing timer before creating a new one."
  (kuro-renderer-test--with-buffer
    (setq-local kuro-frame-rate 30)
    (setq-local kuro-timer nil)
    (kuro--start-render-loop)
    (let ((first-timer kuro-timer))
      (kuro--start-render-loop)
      (should (timerp kuro-timer))
      (should-not (eq kuro-timer first-timer)))
    (kuro--stop-render-loop)))

(provide 'kuro-renderer-unit-test)

;;; kuro-renderer-unit-test.el ends here
