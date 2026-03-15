;;; kuro-overlays-test.el --- Unit tests for kuro-overlays.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-overlays.el (blink overlays, image overlays,
;; hyperlink overlays, prompt navigation, focus events).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-overlays)

;;; Helpers

(defmacro kuro-overlays-test--with-buffer (&rest body)
  "Run BODY in a fresh buffer with kuro overlay state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (kuro--blink-overlays nil)
           (kuro--image-overlays nil)
           (kuro--hyperlink-overlays nil)
           (kuro--prompt-positions nil)
           (kuro--blink-frame-count 0)
           (kuro--blink-visible-slow t)
           (kuro--blink-visible-fast t))
       ,@body)))

;;; Group 1: Blink overlays

(ert-deftest kuro-overlays-apply-blink-slow-creates-overlay ()
  "kuro--apply-blink-overlay creates a blink overlay with correct properties."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (kuro--apply-blink-overlay 1 6 'slow)
    (should (= (length kuro--blink-overlays) 1))
    (let ((ov (car kuro--blink-overlays)))
      (should (overlay-get ov 'kuro-blink))
      (should (eq (overlay-get ov 'kuro-blink-type) 'slow)))))

(ert-deftest kuro-overlays-apply-blink-fast-creates-overlay ()
  "Fast blink overlay has kuro-blink-type = fast."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (kuro--apply-blink-overlay 1 6 'fast)
    (let ((ov (car kuro--blink-overlays)))
      (should (eq (overlay-get ov 'kuro-blink-type) 'fast)))))

(ert-deftest kuro-overlays-apply-blink-visible-when-visible ()
  "Blink overlay is visible (invisible=nil) when blink state is visible."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (setq kuro--blink-visible-slow t)
    (kuro--apply-blink-overlay 1 6 'slow)
    (let ((ov (car kuro--blink-overlays)))
      ;; visible-slow=t → invisible should be nil (= not invisible = visible)
      (should-not (overlay-get ov 'invisible)))))

(ert-deftest kuro-overlays-apply-blink-invisible-when-hidden ()
  "Blink overlay is invisible when blink state is hidden."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (setq kuro--blink-visible-slow nil)
    (kuro--apply-blink-overlay 1 6 'slow)
    (let ((ov (car kuro--blink-overlays)))
      (should (overlay-get ov 'invisible)))))

(ert-deftest kuro-overlays-clear-line-blink-overlays-removes-on-row ()
  "kuro--clear-line-blink-overlays removes overlays on the specified row."
  (kuro-overlays-test--with-buffer
    (insert "line0\nline1\nline2\n")
    ;; Add blink overlay on row 1 (line2)
    (save-excursion
      (goto-char (point-min))
      (forward-line 1)
      (kuro--apply-blink-overlay (point) (line-end-position) 'slow))
    (should (= (length kuro--blink-overlays) 1))
    ;; Clear row 1
    (kuro--clear-line-blink-overlays 1)
    (should (= (length kuro--blink-overlays) 0))))

(ert-deftest kuro-overlays-clear-line-blink-overlays-preserves-other-rows ()
  "kuro--clear-line-blink-overlays only removes overlays on the target row."
  (kuro-overlays-test--with-buffer
    (insert "row0\nrow1\nrow2\n")
    ;; Add overlay on row 0
    (save-excursion
      (goto-char (point-min))
      (kuro--apply-blink-overlay (point) (line-end-position) 'slow))
    ;; Add overlay on row 2
    (save-excursion
      (goto-char (point-min))
      (forward-line 2)
      (kuro--apply-blink-overlay (point) (line-end-position) 'slow))
    (should (= (length kuro--blink-overlays) 2))
    ;; Clear row 1 (no overlays there) — should preserve both
    (kuro--clear-line-blink-overlays 1)
    (should (= (length kuro--blink-overlays) 2))))

;;; Group 2: kuro--tick-blink-overlays

(ert-deftest kuro-overlays-tick-blink-increments-counter ()
  "kuro--tick-blink-overlays increments kuro--blink-frame-count by 1."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-frame-count 0)
    (kuro--tick-blink-overlays)
    (should (= kuro--blink-frame-count 1))))

(ert-deftest kuro-overlays-tick-blink-slow-toggles-at-30 ()
  "Slow blink state toggles when frame count reaches multiple of 30."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-frame-count 29
          kuro--blink-visible-slow t)
    (kuro--tick-blink-overlays)  ; count becomes 30
    (should (= kuro--blink-frame-count 30))
    (should-not kuro--blink-visible-slow)))

(ert-deftest kuro-overlays-tick-blink-fast-toggles-at-10 ()
  "Fast blink state toggles when frame count reaches multiple of 10."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-frame-count 9
          kuro--blink-visible-fast t)
    (kuro--tick-blink-overlays)  ; count becomes 10
    (should (= kuro--blink-frame-count 10))
    (should-not kuro--blink-visible-fast)))

(ert-deftest kuro-overlays-tick-blink-no-toggle-at-non-boundary ()
  "Slow/fast blink states do NOT toggle at non-boundary frame counts."
  (kuro-overlays-test--with-buffer
    (setq kuro--blink-frame-count 5
          kuro--blink-visible-slow t
          kuro--blink-visible-fast t)
    (kuro--tick-blink-overlays)  ; count becomes 6
    (should kuro--blink-visible-slow)
    (should kuro--blink-visible-fast)))

;;; Group 3: Image overlays

(ert-deftest kuro-overlays-clear-all-image-overlays-empties-list ()
  "kuro--clear-all-image-overlays removes all image overlays and clears the list."
  (kuro-overlays-test--with-buffer
    (insert "line\n")
    ;; Create a dummy overlay and push it
    (let ((ov (make-overlay 1 5)))
      (overlay-put ov 'kuro-image t)
      (push ov kuro--image-overlays))
    (should (= (length kuro--image-overlays) 1))
    (kuro--clear-all-image-overlays)
    (should (null kuro--image-overlays))))

(ert-deftest kuro-overlays-clear-row-image-overlays-removes-on-row ()
  "kuro--clear-row-image-overlays removes overlays starting on the target row."
  (kuro-overlays-test--with-buffer
    (insert "row0\nrow1\n")
    ;; Create overlay on row 1
    (save-excursion
      (goto-char (point-min))
      (forward-line 1)
      (let ((ov (make-overlay (point) (+ (point) 3))))
        (overlay-put ov 'kuro-image t)
        (push ov kuro--image-overlays)))
    (should (= (length kuro--image-overlays) 1))
    (kuro--clear-row-image-overlays 1)
    (should (null kuro--image-overlays))))

(ert-deftest kuro-overlays-clear-row-image-overlays-preserves-other-rows ()
  "kuro--clear-row-image-overlays preserves overlays on other rows."
  (kuro-overlays-test--with-buffer
    (insert "row0\nrow1\n")
    ;; Create overlay on row 0
    (save-excursion
      (goto-char (point-min))
      (let ((ov (make-overlay (point) (+ (point) 3))))
        (overlay-put ov 'kuro-image t)
        (push ov kuro--image-overlays)))
    (should (= (length kuro--image-overlays) 1))
    ;; Clear row 1 — should not remove the overlay on row 0
    (kuro--clear-row-image-overlays 1)
    (should (= (length kuro--image-overlays) 1))))

;;; Group 4: Hyperlink overlays

(ert-deftest kuro-overlays-apply-hyperlink-overlay-creates-overlay ()
  "kuro--apply-hyperlink-overlay creates a hyperlink overlay in the buffer."
  (kuro-overlays-test--with-buffer
    (insert "Visit http://example.com here\n")
    (kuro--apply-hyperlink-overlay 7 25 "http://example.com")
    (should (= (length kuro--hyperlink-overlays) 1))
    (let ((ov (car kuro--hyperlink-overlays)))
      (should (overlay-get ov 'kuro-hyperlink))
      (should (overlay-get ov 'help-echo))
      (should (overlay-get ov 'keymap)))))

(ert-deftest kuro-overlays-apply-hyperlink-overlay-help-echo-contains-uri ()
  "Hyperlink overlay help-echo text includes the URI."
  (kuro-overlays-test--with-buffer
    (insert "link\n")
    (kuro--apply-hyperlink-overlay 1 5 "https://example.org")
    (let* ((ov (car kuro--hyperlink-overlays))
           (echo (overlay-get ov 'help-echo)))
      (should (string-match-p "https://example.org" echo)))))

(ert-deftest kuro-overlays-clear-all-hyperlink-overlays-removes-all ()
  "kuro--clear-all-hyperlink-overlays removes all hyperlink overlays."
  (kuro-overlays-test--with-buffer
    (insert "link1 link2\n")
    (kuro--apply-hyperlink-overlay 1 6 "http://a.com")
    (kuro--apply-hyperlink-overlay 7 12 "http://b.com")
    (should (= (length kuro--hyperlink-overlays) 2))
    (kuro--clear-all-hyperlink-overlays)
    (should (null kuro--hyperlink-overlays))))

(ert-deftest kuro-overlays-make-hyperlink-keymap-has-return-binding ()
  "kuro--make-hyperlink-keymap returns a keymap with [return] binding."
  (let ((map (kuro--make-hyperlink-keymap "http://example.com")))
    (should (keymapp map))
    (should (lookup-key map [return]))))

;;; Group 5: Prompt navigation (OSC 133)

(ert-deftest kuro-overlays-prompt-positions-initially-nil ()
  "kuro--prompt-positions starts as nil in a new buffer context."
  (kuro-overlays-test--with-buffer
    (should (null kuro--prompt-positions))))

(ert-deftest kuro-overlays-previous-prompt-no-prompts ()
  "kuro-previous-prompt shows message when no prompts available."
  (kuro-overlays-test--with-buffer
    (insert "line1\nline2\n")
    ;; With no prompt marks, should message "no previous prompt"
    (let ((messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
        (kuro-previous-prompt)
        (should (cl-some (lambda (m) (string-match-p "no previous prompt" m)) messages))))))

(ert-deftest kuro-overlays-next-prompt-no-prompts ()
  "kuro-next-prompt shows message when no prompts available."
  (kuro-overlays-test--with-buffer
    (insert "line1\nline2\n")
    (let ((messages nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
        (kuro-next-prompt)
        (should (cl-some (lambda (m) (string-match-p "no next prompt" m)) messages))))))

(ert-deftest kuro-overlays-next-prompt-jumps-to-mark ()
  "kuro-next-prompt moves point to the next prompt-start row."
  (kuro-overlays-test--with-buffer
    (insert "line0\nline1\nPROMPT\nline3\n")
    ;; Register row 2 as a prompt-start
    (setq kuro--prompt-positions (list (cons 2 'prompt-start)))
    ;; Start at row 0
    (goto-char (point-min))
    (kuro-next-prompt)
    ;; Should now be on row 2
    (should (= (1- (line-number-at-pos)) 2))))

;;; Group 6: kuro--apply-faces-from-ffi (overlay side effects)

(ert-deftest kuro-overlays-apply-faces-from-ffi-blink-slow-creates-overlay ()
  "kuro--apply-faces-from-ffi creates a slow blink overlay when flags include 0x10."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    ;; flags=0x10 (blink-slow), fg=#xFF000000 (default), bg=#xFF000000 (default)
    (kuro--apply-faces-from-ffi 0 (list (list 0 5 #xFF000000 #xFF000000 #x10)))
    (should (> (length kuro--blink-overlays) 0))
    (should (eq (overlay-get (car kuro--blink-overlays) 'kuro-blink-type) 'slow))))

(ert-deftest kuro-overlays-apply-faces-from-ffi-blink-fast-creates-overlay ()
  "kuro--apply-faces-from-ffi creates a fast blink overlay when flags include 0x20."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (kuro--apply-faces-from-ffi 0 (list (list 0 5 #xFF000000 #xFF000000 #x20)))
    (should (> (length kuro--blink-overlays) 0))
    (should (eq (overlay-get (car kuro--blink-overlays) 'kuro-blink-type) 'fast))))

(ert-deftest kuro-overlays-apply-faces-from-ffi-hidden-sets-invisible ()
  "kuro--apply-faces-from-ffi sets invisible text property when flags include 0x80."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (kuro--apply-faces-from-ffi 0 (list (list 0 5 #xFF000000 #xFF000000 #x80)))
    (should (get-text-property 1 'invisible))))

(ert-deftest kuro-overlays-apply-faces-from-ffi-no-blink-no-overlay ()
  "kuro--apply-faces-from-ffi creates no blink overlay when no blink flags set."
  (kuro-overlays-test--with-buffer
    (insert "Hello\n")
    (kuro--apply-faces-from-ffi 0 (list (list 0 5 #xFF000000 #xFF000000 0)))
    (should (null kuro--blink-overlays))))

(provide 'kuro-overlays-test)

;;; kuro-overlays-test.el ends here
