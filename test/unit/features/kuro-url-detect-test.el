;;; kuro-url-detect-test.el --- Unit tests for kuro-url-detect.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-url-detect.el (URL detection, overlay management,
;; and idle timer lifecycle).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'kuro-url-detect-test-support)

;;; Group 1: kuro--url-regexp matching

(kuro-url-detect-test--deftest-url-matches
  kuro-url-detect-test--url-match-cases)

;;; Group 2: kuro--url-regexp trailing punctuation exclusion

(kuro-url-detect-test--deftest-trailing-punctuation
  kuro-url-detect-test--trailing-punctuation-cases)

;;; Group 3: kuro--clear-url-overlays

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

;;; Group 4: kuro--make-url-overlay

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

(ert-deftest kuro-url-detect--make-url-overlay-rejects-invalid-target ()
  "kuro--make-url-overlay rejects unsafe browser targets."
  (kuro-url-detect-test--with-buffer
    (insert "https://example.com\n")
    (should-error (kuro--make-url-overlay 1 20 "file:///tmp/x"))
    (should-error (kuro--make-url-overlay 1 20 "https:///path"))
    (should-error (kuro--make-url-overlay 1 20 "https:path"))
    (should-error (kuro--make-url-overlay 1 20 "https://user@example.com"))
    (should-error (kuro--make-url-overlay 1 20 "https://example.com/bad path"))
    (should-error (kuro--make-url-overlay 1 20 "https://example.com:bad/path"))
    (should-error (kuro--make-url-overlay 1 20 "https://example.com:999999/path"))
    (should-error (kuro--make-url-overlay 1 20 "https://999.999.999.999/path"))
    (should-error (kuro--make-url-overlay 1 20 "https://[dead:beef]/path"))
    (should-error (kuro--make-url-overlay 1 20 "http://example.com:0/path"))))

(ert-deftest kuro-url-detect--make-url-overlay-rejects-invalid-range ()
  "kuro--make-url-overlay rejects non-integer and out-of-buffer ranges."
  (kuro-url-detect-test--with-buffer
    (insert "https://example.com\n")
    (should-error (kuro--make-url-overlay 0 20 "https://example.com"))
    (should-error (kuro--make-url-overlay 1 1 "https://example.com"))
    (should-error (kuro--make-url-overlay 1 (1+ (point-max))
                                          "https://example.com"))))

;;; Group 5: kuro-open-url-at-point

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

(ert-deftest kuro-url-detect--open-url-ignores-non-url-overlay ()
  "kuro-open-url-at-point ignores overlays without `kuro-url-target'."
  (kuro-url-detect-test--with-buffer
    (insert "/tmp/test-file.el:10\n")
    (let ((ov (make-overlay 1 21 nil t nil)))
      (overlay-put ov 'kuro-url t)
      (overlay-put ov 'kuro-file-target "/tmp/test-file.el")
      (overlay-put ov 'kuro-line-target 10))
    (goto-char 1)
    (let ((called nil))
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (_) (setq called t)))
                ((symbol-function 'find-file-other-window)
                 (lambda (_) (setq called t))))
        (kuro-open-url-at-point)
        (should-not called)))))

(ert-deftest kuro-url-detect--open-url-ignores-invalid-url-target ()
  "kuro-open-url-at-point ignores crafted overlays with unsafe URL targets."
  (kuro-url-detect-test--with-buffer
    (insert "unsafe\n")
    (let ((ov (make-overlay 1 7 nil t nil)))
      (overlay-put ov 'kuro-url t)
      (overlay-put ov 'kuro-url-target "file:///tmp/test-file.el"))
    (goto-char 1)
    (let ((called nil))
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (_) (setq called t))))
        (kuro-open-url-at-point)
        (should-not called)))))

(ert-deftest kuro-url-detect--open-url-selects-valid-url-overlay ()
  "kuro-open-url-at-point selects a valid URL when another overlay is present."
  (kuro-url-detect-test--with-buffer
    (insert "https://example.com\n")
    (let ((noise (make-overlay 1 20 nil nil t))
          (called nil))
      (overlay-put noise 'kuro-url t)
      (overlay-put noise 'kuro-url-target "file:///tmp/test-file.el")
      (kuro--make-url-overlay 1 20 "https://example.com")
      (goto-char 1)
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (url) (setq called url))))
        (kuro-open-url-at-point)
        (should (string= called "https://example.com"))))))

(ert-deftest kuro-url-detect--open-url-noop-when-no-overlay-at-point ()
  "kuro-open-url-at-point is a no-op when there is no overlay at point."
  (kuro-url-detect-test--with-buffer
    (insert "plain text\n")
    (goto-char 1)
    (let ((called nil))
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (_) (setq called t))))
        (kuro-open-url-at-point)
        (should-not called)))))

;;; Group 6: kuro--scan-urls-in-region

(ert-deftest kuro-url-detect--scan-creates-url-overlays ()
  "kuro--scan-urls-in-region creates overlays for URLs in the buffer."
  (kuro-url-detect-test--with-buffer
    (insert "Visit https://example.com for info\n")
    (kuro--scan-urls-in-region (point-min) (point-max))
    (should (= (length kuro--url-overlays) 1))
    (let ((ov (car kuro--url-overlays)))
      (should (string= (overlay-get ov 'kuro-url-target)
                        "https://example.com")))))

(ert-deftest kuro-url-detect--scan-creates-bracketed-ipv6-url-overlay ()
  "kuro--scan-urls-in-region creates overlays for strict bracketed IPv6 URLs."
  (kuro-url-detect-test--with-buffer
    (insert "Visit https://[2001:db8::1]/path now\n")
    (kuro--scan-urls-in-region (point-min) (point-max))
    (should (= (length kuro--url-overlays) 1))
    (let ((ov (car kuro--url-overlays)))
      (should (string= (overlay-get ov 'kuro-url-target)
                       "https://[2001:db8::1]/path")))))

(ert-deftest kuro-url-detect--scan-skips-duplicate-overlays ()
  "kuro--scan-urls-in-region does not create duplicate overlays."
  (kuro-url-detect-test--with-buffer
    (insert "Visit https://example.com for info\n")
    (kuro--scan-urls-in-region (point-min) (point-max))
    (kuro--scan-urls-in-region (point-min) (point-max))
    (should (= (length kuro--url-overlays) 1))))

(ert-deftest kuro-url-detect--scan-does-not-link-file-line-text ()
  "kuro--scan-urls-in-region does not create overlays for local file text."
  (kuro-url-detect-test--with-buffer
    (insert "/tmp/test-file.el:10\n")
    (cl-letf (((symbol-function 'file-exists-p) (lambda (_) t)))
      (kuro--scan-urls-in-region (point-min) (point-max))
      (should (null kuro--url-overlays)))))

(ert-deftest kuro-url-detect--scan-rejects-hostless-http-url ()
  "kuro--scan-urls-in-region rejects hostless HTTP(S) matches."
  (kuro-url-detect-test--with-buffer
    (insert "Bad https:///tmp/path\n")
    (kuro--scan-urls-in-region (point-min) (point-max))
    (should (null kuro--url-overlays))))

(ert-deftest kuro-url-detect--scan-rejects-userinfo-http-url ()
  "kuro--scan-urls-in-region rejects URLs with userinfo."
  (kuro-url-detect-test--with-buffer
    (insert "Bad https://user@example.com/path\n")
    (kuro--scan-urls-in-region (point-min) (point-max))
    (should (null kuro--url-overlays))))

(ert-deftest kuro-url-detect--scan-rejects-invalid-port-http-url ()
  "kuro--scan-urls-in-region rejects URLs with malformed or invalid ports."
  (dolist (input '("Bad https://example.com:bad/path\n"
                   "Bad https://example.com:999999/path\n"
                   "Bad http://example.com:0/path\n"))
    (kuro-url-detect-test--with-buffer
      (insert input)
      (kuro--scan-urls-in-region (point-min) (point-max))
      (should (null kuro--url-overlays)))))

(ert-deftest kuro-url-detect--scan-rejects-malformed-ip-literals ()
  "kuro--scan-urls-in-region rejects malformed IPv4 and IPv6 literals."
  (dolist (input '("Bad https://999.999.999.999/path\n"
                   "Bad https://[dead:beef]/path\n"
                   "Bad https://[:::]/path\n"))
    (kuro-url-detect-test--with-buffer
      (insert input)
      (kuro--scan-urls-in-region (point-min) (point-max))
      (should (null kuro--url-overlays)))))

(ert-deftest kuro-url-detect--scan-creates-multiple-url-overlays ()
  "kuro--scan-urls-in-region creates overlays for multiple URLs."
  (kuro-url-detect-test--with-buffer
    (insert "Visit https://a.com and https://b.com\n")
    (kuro--scan-urls-in-region (point-min) (point-max))
    (should (= (length kuro--url-overlays) 2))))

;;; Group 7: kuro--start-url-detection / kuro--stop-url-detection

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

;;; Group 8: defcustom defaults

(kuro-url-detect-test--deftest-defcustom-defaults
  kuro-url-detect-test--defcustom-default-cases)

;;; Group 9: kuro--url-detect-visible

(ert-deftest kuro-url-detect--visible-skips-when-not-kuro-mode ()
  "`kuro--url-detect-visible' does nothing when `derived-mode-p' returns nil."
  (kuro-url-detect-test--with-buffer
    (let ((scanned nil))
      (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) nil))
                ((symbol-function 'kuro--scan-urls-in-region)
                 (lambda (&rest _) (setq scanned t))))
        (kuro--url-detect-visible)
        (should-not scanned)))))

(ert-deftest kuro-url-detect--visible-skips-when-url-detection-off ()
  "`kuro--url-detect-visible' does nothing when URL detection is nil."
  (kuro-url-detect-test--with-buffer
    (let ((kuro-url-detection nil)
          (scanned nil))
      (cl-letf (((symbol-function 'derived-mode-p) (lambda (&rest _) t))
                ((symbol-function 'kuro--scan-urls-in-region)
                 (lambda (&rest _) (setq scanned t))))
        (kuro--url-detect-visible)
        (should-not scanned)))))

(kuro-url-detect-test--deftest-detection-proceeds
  kuro-url-detect-test--detection-flag-table)

(ert-deftest kuro-url-detect--visible-detection-flag-invariant ()
  "Invariant: `kuro--url-detect-visible' scans for every entry in detection table."
  (dolist (entry kuro-url-detect-test--detection-flag-table)
    (pcase-let ((`(,_name ,url-flag) entry))
      (kuro-url-detect-test--with-buffer
        (let ((kuro-url-detection url-flag)
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

(provide 'kuro-url-detect-test)

;;; kuro-url-detect-test.el ends here
