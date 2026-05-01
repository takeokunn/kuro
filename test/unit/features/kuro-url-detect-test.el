;;; kuro-url-detect-test.el --- Unit tests for kuro-url-detect.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-url-detect.el (URL detection, file:line detection,
;; overlay management, and idle timer lifecycle).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-url-detect)

;;; Helpers

(defmacro kuro-url-detect-test--with-buffer (&rest body)
  "Run BODY in a temp buffer with URL detection state initialized to defaults.
Sets the following buffer-local variables:
  `kuro--url-overlays' nil (no active overlays)
  `kuro--url-detect-timer' nil (no active timer)
  `kuro-url-detection' t (URL detection enabled)
  `kuro-file-line-detection' t (file:line detection enabled)
  `inhibit-read-only' t (allows buffer modification in tests)"
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (kuro--url-overlays nil)
           (kuro--url-detect-timer nil)
           (kuro-url-detection t)
           (kuro-file-line-detection t))
       ,@body)))

;;; Group 1: kuro--url-regexp matching

(ert-deftest kuro-url-detect--regexp-matches-http ()
  "kuro--url-regexp matches a simple HTTP URL."
  (should (string-match kuro--url-regexp "http://example.com")))

(ert-deftest kuro-url-detect--regexp-matches-https ()
  "kuro--url-regexp matches a simple HTTPS URL."
  (should (string-match kuro--url-regexp "https://example.com")))

(ert-deftest kuro-url-detect--regexp-matches-url-with-path ()
  "kuro--url-regexp matches a URL with path components."
  (should (string-match kuro--url-regexp "https://example.com/path/to/page")))

(ert-deftest kuro-url-detect--regexp-matches-url-with-query ()
  "kuro--url-regexp matches a URL with query parameters."
  (should (string-match kuro--url-regexp "https://example.com/search?q=test&page=1")))

;;; Group 2: kuro--url-regexp trailing punctuation exclusion

(ert-deftest kuro-url-detect--regexp-excludes-trailing-period ()
  "kuro--url-regexp does not include a trailing period."
  (string-match kuro--url-regexp "Visit https://example.com.")
  (should (string= (match-string 0 "Visit https://example.com.")
                    "https://example.com")))

(ert-deftest kuro-url-detect--regexp-excludes-trailing-comma ()
  "kuro--url-regexp does not include a trailing comma."
  (string-match kuro--url-regexp "See https://example.com, then")
  (should (string= (match-string 0 "See https://example.com, then")
                    "https://example.com")))

(ert-deftest kuro-url-detect--regexp-excludes-trailing-exclamation ()
  "kuro--url-regexp does not include a trailing exclamation mark."
  (string-match kuro--url-regexp "Check https://example.com!")
  (should (string= (match-string 0 "Check https://example.com!")
                    "https://example.com")))

;;; Group 3: kuro--file-line-regexp matching

(ert-deftest kuro-url-detect--file-line-regexp-matches-absolute-path ()
  "kuro--file-line-regexp matches an absolute path with line number."
  (should (string-match kuro--file-line-regexp "/home/user/file.rs:42")))

(ert-deftest kuro-url-detect--file-line-regexp-captures-file ()
  "kuro--file-line-regexp group 1 captures the file path."
  (string-match kuro--file-line-regexp "/home/user/file.rs:42")
  (should (string= (match-string 1 "/home/user/file.rs:42")
                    "/home/user/file.rs")))

(ert-deftest kuro-url-detect--file-line-regexp-captures-line ()
  "kuro--file-line-regexp group 2 captures the line number."
  (string-match kuro--file-line-regexp "/home/user/file.rs:42")
  (should (string= (match-string 2 "/home/user/file.rs:42")
                    "42")))

(ert-deftest kuro-url-detect--file-line-regexp-no-match-relative ()
  "kuro--file-line-regexp does not match relative paths (no leading /)."
  (should-not (string-match kuro--file-line-regexp "file.rs:42")))

;;; Group 4: kuro--clear-url-overlays

(ert-deftest kuro-url-detect--clear-removes-all-overlays ()
  "kuro--clear-url-overlays removes all overlays and empties the list."
  (kuro-url-detect-test--with-buffer
    (insert "https://example.com\n")
    (kuro--make-url-overlay 1 20 "https://example.com")
    (should (= (length kuro--url-overlays) 1))
    (kuro--clear-url-overlays)
    (should (null kuro--url-overlays))
    (should (null (overlays-in (point-min) (point-max))))))

;;; Group 5: kuro--make-url-overlay

(ert-deftest kuro-url-detect--make-url-overlay-creates-overlay ()
  "kuro--make-url-overlay creates an overlay with correct properties."
  (kuro-url-detect-test--with-buffer
    (insert "https://example.com\n")
    (let ((ov (kuro--make-url-overlay 1 20 "https://example.com")))
      (should (overlayp ov))
      (should (overlay-get ov 'kuro-url))
      (should (string= (overlay-get ov 'kuro-url-target) "https://example.com"))
      (should (eq (overlay-get ov 'face) 'link))
      (should (eq (overlay-get ov 'mouse-face) 'highlight))
      (should (string= (overlay-get ov 'help-echo) "https://example.com"))
      (should (overlay-get ov 'keymap)))))

(ert-deftest kuro-url-detect--make-url-overlay-pushes-to-list ()
  "kuro--make-url-overlay pushes the overlay onto kuro--url-overlays."
  (kuro-url-detect-test--with-buffer
    (insert "https://example.com\n")
    (kuro--make-url-overlay 1 20 "https://example.com")
    (should (= (length kuro--url-overlays) 1))))

;;; Group 6: kuro--make-file-line-overlay

(ert-deftest kuro-url-detect--make-file-line-overlay-creates-overlay ()
  "kuro--make-file-line-overlay creates an overlay with correct properties."
  (kuro-url-detect-test--with-buffer
    (insert "/home/user/file.rs:42\n")
    (let ((ov (kuro--make-file-line-overlay 1 22 "/home/user/file.rs" 42)))
      (should (overlayp ov))
      (should (overlay-get ov 'kuro-url))
      (should (string= (overlay-get ov 'kuro-file-target) "/home/user/file.rs"))
      (should (= (overlay-get ov 'kuro-line-target) 42))
      (should (eq (overlay-get ov 'face) 'link))
      (should (string= (overlay-get ov 'help-echo) "/home/user/file.rs:42")))))

;;; Group 7: kuro-open-url-at-point

(ert-deftest kuro-url-detect--open-url-dispatches-browse-url ()
  "kuro-open-url-at-point calls browse-url for URL overlays."
  (kuro-url-detect-test--with-buffer
    (insert "https://example.com\n")
    (kuro--make-url-overlay 1 20 "https://example.com")
    (goto-char 1)
    (let ((called nil))
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (url) (setq called url))))
        (kuro-open-url-at-point)
        (should (string= called "https://example.com"))))))

(ert-deftest kuro-url-detect--open-url-dispatches-find-file ()
  "kuro-open-url-at-point calls find-file-other-window for file overlays."
  (kuro-url-detect-test--with-buffer
    (insert "/tmp/test-file.el:10\n")
    (kuro--make-file-line-overlay 1 21 "/tmp/test-file.el" 10)
    (goto-char 1)
    (let ((opened-file nil))
      (cl-letf (((symbol-function 'file-exists-p)
                 (lambda (_f) t))
                ((symbol-function 'find-file-other-window)
                 (lambda (f) (setq opened-file f))))
        (kuro-open-url-at-point)
        (should (string= opened-file "/tmp/test-file.el"))))))

;;; Group 8: kuro--scan-urls-in-region

(ert-deftest kuro-url-detect--scan-creates-url-overlays ()
  "kuro--scan-urls-in-region creates overlays for URLs in the buffer."
  (kuro-url-detect-test--with-buffer
    (insert "Visit https://example.com for info\n")
    (kuro--scan-urls-in-region (point-min) (point-max))
    (should (= (length kuro--url-overlays) 1))
    (let ((ov (car kuro--url-overlays)))
      (should (string= (overlay-get ov 'kuro-url-target)
                        "https://example.com")))))

(ert-deftest kuro-url-detect--scan-skips-duplicate-overlays ()
  "kuro--scan-urls-in-region does not create duplicate overlays."
  (kuro-url-detect-test--with-buffer
    (insert "Visit https://example.com for info\n")
    (kuro--scan-urls-in-region (point-min) (point-max))
    (kuro--scan-urls-in-region (point-min) (point-max))
    (should (= (length kuro--url-overlays) 1))))

(ert-deftest kuro-url-detect--scan-creates-multiple-url-overlays ()
  "kuro--scan-urls-in-region creates overlays for multiple URLs."
  (kuro-url-detect-test--with-buffer
    (insert "Visit https://a.com and https://b.com\n")
    (kuro--scan-urls-in-region (point-min) (point-max))
    (should (= (length kuro--url-overlays) 2))))

;;; Group 9: kuro--start-url-detection / kuro--stop-url-detection

(ert-deftest kuro-url-detect--start-creates-timer ()
  "kuro--start-url-detection creates an idle timer."
  (kuro-url-detect-test--with-buffer
    (kuro--start-url-detection)
    (unwind-protect
        (should (timerp kuro--url-detect-timer))
      (kuro--stop-url-detection))))

(ert-deftest kuro-url-detect--stop-cancels-timer-and-clears ()
  "kuro--stop-url-detection cancels the timer and clears overlays."
  (kuro-url-detect-test--with-buffer
    (insert "https://example.com\n")
    (kuro--make-url-overlay 1 20 "https://example.com")
    (kuro--start-url-detection)
    (kuro--stop-url-detection)
    (should (null kuro--url-detect-timer))
    (should (null kuro--url-overlays))))

(ert-deftest kuro-url-detect--start-idempotent ()
  "kuro--start-url-detection does not create a second timer if one exists."
  (kuro-url-detect-test--with-buffer
    (kuro--start-url-detection)
    (let ((first-timer kuro--url-detect-timer))
      (kuro--start-url-detection)
      (unwind-protect
          (should (eq kuro--url-detect-timer first-timer))
        (kuro--stop-url-detection)))))

;;; Group 10: defcustom defaults

(ert-deftest kuro-url-detect--url-detection-default-t ()
  "kuro-url-detection defcustom defaults to t."
  (should (eq (default-value 'kuro-url-detection) t)))

(ert-deftest kuro-url-detect--file-line-detection-default-t ()
  "kuro-file-line-detection defcustom defaults to t."
  (should (eq (default-value 'kuro-file-line-detection) t)))

(ert-deftest kuro-url-detect--detection-delay-default ()
  "kuro-url-detection-delay defcustom defaults to 0.5."
  (should (= (default-value 'kuro-url-detection-delay) 0.5)))

(provide 'kuro-url-detect-test)

;;; kuro-url-detect-test.el ends here
