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

(defmacro kuro-url-detect-test--def-url-match (test-name url)
  "Generate an ERT test asserting that kuro--url-regexp matches URL."
  `(ert-deftest ,test-name ()
     ,(format "`kuro--url-regexp' matches `%s'." url)
     (should (string-match kuro--url-regexp ,url))))

(kuro-url-detect-test--def-url-match kuro-url-detect--regexp-matches-http
                                     "http://example.com")
(kuro-url-detect-test--def-url-match kuro-url-detect--regexp-matches-https
                                     "https://example.com")
(kuro-url-detect-test--def-url-match kuro-url-detect--regexp-matches-url-with-path
                                     "https://example.com/path/to/page")
(kuro-url-detect-test--def-url-match kuro-url-detect--regexp-matches-url-with-query
                                     "https://example.com/search?q=test&page=1")

;;; Group 2: kuro--url-regexp trailing punctuation exclusion

(defmacro kuro-url-detect-test--def-trailing-punct (test-name input expected)
  "Generate an ERT test asserting that kuro--url-regexp excludes trailing punctuation.
INPUT is the full string containing the URL; EXPECTED is the URL without the punct."
  `(ert-deftest ,test-name ()
     ,(format "`kuro--url-regexp' excludes trailing punctuation in `%s'." input)
     (string-match kuro--url-regexp ,input)
     (should (string= (match-string 0 ,input) ,expected))))

(kuro-url-detect-test--def-trailing-punct
 kuro-url-detect--regexp-excludes-trailing-period
 "Visit https://example.com." "https://example.com")
(kuro-url-detect-test--def-trailing-punct
 kuro-url-detect--regexp-excludes-trailing-comma
 "See https://example.com, then" "https://example.com")
(kuro-url-detect-test--def-trailing-punct
 kuro-url-detect--regexp-excludes-trailing-exclamation
 "Check https://example.com!" "https://example.com")

;;; Group 3: kuro--file-line-regexp matching

(defmacro kuro-url-detect-test--def-file-line-match (test-name input)
  "Generate an ERT test asserting kuro--file-line-regexp matches INPUT."
  `(ert-deftest ,test-name ()
     ,(format "`kuro--file-line-regexp' matches `%s'." input)
     (should (string-match kuro--file-line-regexp ,input))))

(kuro-url-detect-test--def-file-line-match
 kuro-url-detect--file-line-regexp-matches-absolute-path "/home/user/file.rs:42")

(ert-deftest kuro-url-detect--file-line-regexp-captures-file ()
  "kuro--file-line-regexp group 1 captures the file path."
  (string-match kuro--file-line-regexp "/home/user/file.rs:42")
  (should (string= (match-string 1 "/home/user/file.rs:42") "/home/user/file.rs")))

(ert-deftest kuro-url-detect--file-line-regexp-captures-line ()
  "kuro--file-line-regexp group 2 captures the line number."
  (string-match kuro--file-line-regexp "/home/user/file.rs:42")
  (should (string= (match-string 2 "/home/user/file.rs:42") "42")))

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

(ert-deftest kuro-url-detect--clear-skips-dead-overlays ()
  "kuro--clear-url-overlays does not error on an already-deleted overlay."
  (kuro-url-detect-test--with-buffer
    (insert "https://example.com\n")
    (let ((ov (kuro--make-url-overlay 1 20 "https://example.com")))
      ;; Pre-delete the overlay so overlay-buffer returns nil
      (delete-overlay ov)
      ;; clear must not error even though the overlay is dead
      (kuro--clear-url-overlays)
      (should (null kuro--url-overlays)))))

(ert-deftest kuro-url-detect--clear-noop-when-empty ()
  "kuro--clear-url-overlays is a no-op when the overlay list is already nil."
  (kuro-url-detect-test--with-buffer
    (kuro--clear-url-overlays)
    (should (null kuro--url-overlays))))

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

(ert-deftest kuro-url-detect--open-url-noop-when-no-overlay-at-point ()
  "kuro-open-url-at-point is a no-op when there is no overlay at point."
  (kuro-url-detect-test--with-buffer
    (insert "plain text\n")
    (goto-char 1)
    (let ((called nil))
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (_) (setq called t)))
                ((symbol-function 'find-file-other-window)
                 (lambda (_) (setq called t))))
        (kuro-open-url-at-point)
        (should-not called)))))

(ert-deftest kuro-url-detect--open-url-noop-when-file-not-found ()
  "kuro-open-url-at-point skips find-file when the file does not exist."
  (kuro-url-detect-test--with-buffer
    (insert "/nonexistent/path.el:5\n")
    (kuro--make-file-line-overlay 1 23 "/nonexistent/path.el" 5)
    (goto-char 1)
    (let ((opened nil))
      (cl-letf (((symbol-function 'file-exists-p) (lambda (_) nil))
                ((symbol-function 'find-file-other-window)
                 (lambda (f) (setq opened f))))
        (kuro-open-url-at-point)
        (should-not opened)))))

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


;;; Group 11: kuro--url-detect-visible

(defmacro kuro-url-detect-test--with-kuro-visible (&rest body)
  "Run BODY in a url-detect buffer mocked as kuro-mode with full-window scan.
`derived-mode-p' returns t, `window-start'/`window-end' cover the full buffer,
`kuro--scan-urls-in-region' is stubbed to a no-op unless overridden."
  `(kuro-url-detect-test--with-buffer
     (cl-letf (((symbol-function 'derived-mode-p)
                (lambda (&rest _) t))
               ((symbol-function 'window-start)
                (lambda () (point-min)))
               ((symbol-function 'window-end)
                (lambda (_w _u) (point-max)))
               ((symbol-function 'kuro--scan-urls-in-region)
                (lambda (_s _e) nil)))
       ,@body)))

(ert-deftest kuro-url-detect--visible-skips-when-not-kuro-mode ()
  "`kuro--url-detect-visible' does nothing when `derived-mode-p' returns nil."
  (kuro-url-detect-test--with-buffer
    (let ((scanned nil))
      (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) nil))
                ((symbol-function 'kuro--scan-urls-in-region)
                 (lambda (&rest _) (setq scanned t))))
        (kuro--url-detect-visible)
        (should-not scanned)))))

(ert-deftest kuro-url-detect--visible-skips-when-both-detection-off ()
  "`kuro--url-detect-visible' does nothing when both detection flags are nil."
  (kuro-url-detect-test--with-buffer
    (let ((kuro-url-detection nil)
          (kuro-file-line-detection nil)
          (scanned nil))
      (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
                ((symbol-function 'kuro--scan-urls-in-region)
                 (lambda (&rest _) (setq scanned t))))
        (kuro--url-detect-visible)
        (should-not scanned)))))

(defconst kuro-url-detect-test--detection-flag-table
  '((kuro-url-detect--visible-proceeds-when-url-only   t   nil)
    (kuro-url-detect--visible-proceeds-when-file-only  nil t))
  "Table: (test-name url-flag file-flag) — each enables scan via one flag.")

(defmacro kuro-url-detect-test--def-detection-proceeds (test-name url-flag file-flag)
  "Generate a test verifying `kuro--url-detect-visible' scans when flags allow it."
  `(ert-deftest ,test-name ()
     ,(format "`kuro--url-detect-visible' scans when url=%s file-line=%s." url-flag file-flag)
     (kuro-url-detect-test--with-buffer
       (let ((kuro-url-detection ,url-flag)
             (kuro-file-line-detection ,file-flag)
             (scanned nil))
         (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
                   ((symbol-function 'window-start) (lambda () (point-min)))
                   ((symbol-function 'window-end)   (lambda (_w _u) (point-max)))
                   ((symbol-function 'kuro--scan-urls-in-region)
                    (lambda (&rest _) (setq scanned t))))
           (kuro--url-detect-visible)
           (should scanned))))))

(kuro-url-detect-test--def-detection-proceeds
 kuro-url-detect--visible-proceeds-when-url-only  t   nil)
(kuro-url-detect-test--def-detection-proceeds
 kuro-url-detect--visible-proceeds-when-file-only nil t)

(ert-deftest kuro-url-detect--visible-detection-flag-invariant ()
  "Invariant: `kuro--url-detect-visible' scans for every entry in detection table."
  (dolist (entry kuro-url-detect-test--detection-flag-table)
    (pcase-let ((`(,_name ,url-flag ,file-flag) entry))
      (kuro-url-detect-test--with-buffer
        (let ((kuro-url-detection url-flag)
              (kuro-file-line-detection file-flag)
              (scanned nil))
          (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
                    ((symbol-function 'window-start) (lambda () (point-min)))
                    ((symbol-function 'window-end)   (lambda (_w _u) (point-max)))
                    ((symbol-function 'kuro--scan-urls-in-region)
                     (lambda (&rest _) (setq scanned t))))
            (kuro--url-detect-visible)
            (should scanned)))))))

(ert-deftest kuro-url-detect--visible-passes-window-region-to-scan ()
  "`kuro--url-detect-visible' passes exact window-start/end to scan."
  (kuro-url-detect-test--with-buffer
    (insert "0123456789")
    (let ((kuro-url-detection t)
          (kuro-file-line-detection nil)
          (scan-start nil) (scan-end nil))
      (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
                ((symbol-function 'window-start) (lambda () 3))
                ((symbol-function 'window-end)   (lambda (_w _u) 8))
                ((symbol-function 'kuro--scan-urls-in-region)
                 (lambda (s e) (setq scan-start s scan-end e))))
        (kuro--url-detect-visible)
        (should (= 3 scan-start))
        (should (= 8 scan-end))))))

(ert-deftest kuro-url-detect--visible-prunes-dead-overlays ()
  "`kuro--url-detect-visible' removes already-dead overlays from the list."
  (kuro-url-detect-test--with-buffer
    (insert "0123456789")
    (let* ((live-ov (make-overlay 1 4))
           (dead-ov (make-overlay 1 4))
           (kuro-url-detection t)
           (kuro-file-line-detection nil)
           (kuro--url-overlays (list live-ov dead-ov)))
      ;; Kill dead-ov before the call; live-ov is outside window (window=5..11)
      (delete-overlay dead-ov)
      (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
                ((symbol-function 'window-start) (lambda () 5))
                ((symbol-function 'window-end)   (lambda (_w _u) 11))
                ((symbol-function 'kuro--scan-urls-in-region) #'ignore))
        (kuro--url-detect-visible)
        (should (= 1 (length kuro--url-overlays)))
        (should (eq live-ov (car kuro--url-overlays))))
      (delete-overlay live-ov))))

(ert-deftest kuro-url-detect--make-file-line-overlay-pushes-to-url-overlays ()
  "kuro--make-file-line-overlay pushes the new overlay onto kuro--url-overlays."
  (kuro-url-detect-test--with-buffer
    (insert "/tmp/foo.rs:7\n")
    (kuro--make-file-line-overlay 1 14 "/tmp/foo.rs" 7)
    (should (= (length kuro--url-overlays) 1))
    (should (equal (overlay-get (car kuro--url-overlays) 'kuro-file-target) "/tmp/foo.rs"))))

(ert-deftest kuro-url-detect--make-file-line-overlay-keymap-is-bound ()
  "kuro--make-file-line-overlay attaches kuro--url-keymap to the overlay."
  (kuro-url-detect-test--with-buffer
    (insert "/tmp/bar.el:3\n")
    (let ((ov (kuro--make-file-line-overlay 1 14 "/tmp/bar.el" 3)))
      (should (eq (overlay-get ov 'keymap) kuro--url-keymap)))))

(provide 'kuro-url-detect-test)

;;; kuro-url-detect-test.el ends here
