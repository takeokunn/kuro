;;; kuro-hyperlinks-test.el --- Unit tests for kuro-hyperlinks.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;;; Commentary:

;; ERT tests for kuro-hyperlinks.el (OSC 8 hyperlink overlay management).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Groups:
;;   Group 1: kuro-open-hyperlink-at-point — browse-url dispatch
;;   Group 2: kuro--clear-hyperlink-overlays — cleanup
;;   Group 3: kuro--apply-hyperlink-ranges — overlay creation from polled data
;;   Group 4: kuro-hyperlink face
;;   Group 5: kuro--hyperlink-keymap bindings
;;   Group 6: terminal web URL allowlist invariants

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Stub FFI symbols so kuro-hyperlinks loads without the Rust module.
(dolist (sym '(kuro-core-init
               kuro-core-send-key
               kuro-core-poll-updates
               kuro-core-poll-updates-with-faces
               kuro-core-resize
               kuro-core-shutdown
               kuro-core-get-cursor
               kuro-core-get-cursor-visible
               kuro-core-get-cursor-shape
               kuro-core-is-process-alive
               kuro-core-poll-hyperlink-ranges))
  (unless (fboundp sym)
    (fset sym (lambda (&rest _) nil))))

(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (el-dir (expand-file-name "../../emacs-lisp" this-dir)))
  (add-to-list 'load-path el-dir t))

(require 'kuro-hyperlinks)

;;; Helpers

(defmacro kuro-hyperlinks-test--with-buffer (&rest body)
  "Run BODY in a temp buffer with hyperlink state initialized."
  `(with-temp-buffer
     (let ((inhibit-read-only t)
           (kuro--hyperlink-overlays nil))
       ,@body)))

;;; Group 1: kuro-open-hyperlink-at-point — browse-url dispatch

(ert-deftest test-kuro-hyperlinks-open-at-point-calls-browse-url ()
  "kuro-open-hyperlink-at-point calls browse-url when overlay has uri."
  (kuro-hyperlinks-test--with-buffer
    (insert "click here\n")
    (let ((ov (make-overlay 1 6)))
      (overlay-put ov 'kuro-hyperlink-uri "https://example.com")
      (goto-char 1)
      (let ((called nil))
        (cl-letf (((symbol-function 'browse-url)
                   (lambda (url) (setq called url))))
          (kuro-open-hyperlink-at-point)
          (should (string= called "https://example.com")))))))

(ert-deftest test-kuro-hyperlinks-open-at-point-no-overlay-no-error ()
  "kuro-open-hyperlink-at-point does nothing when no overlay at point."
  (kuro-hyperlinks-test--with-buffer
    (insert "no overlay here\n")
    (goto-char 1)
    (let ((called nil))
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (url) (setq called url))))
        (kuro-open-hyperlink-at-point)
        (should (null called))))))

(ert-deftest test-kuro-hyperlinks-open-at-point-overlay-without-uri-no-error ()
  "kuro-open-hyperlink-at-point does nothing when overlay has no uri property."
  (kuro-hyperlinks-test--with-buffer
    (insert "some text\n")
    (let ((ov (make-overlay 1 5)))
      (overlay-put ov 'face 'bold)
      (goto-char 1)
      (let ((called nil))
        (cl-letf (((symbol-function 'browse-url)
                   (lambda (url) (setq called url))))
          (kuro-open-hyperlink-at-point)
          (should (null called)))))))

(ert-deftest test-kuro-hyperlinks-open-at-point-blocks-invalid-target ()
  "kuro-open-hyperlink-at-point blocks unsafe URI-shaped targets."
  (kuro-hyperlinks-test--with-buffer
    (insert "click here\n")
    (let ((ov (make-overlay 1 6)))
      (overlay-put ov 'kuro-hyperlink-uri "https://user@example.com")
      (goto-char 1)
      (let ((called nil)
            (msg nil))
        (cl-letf (((symbol-function 'browse-url)
                   (lambda (url) (setq called url)))
                  ((symbol-function 'message)
                   (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
          (kuro-open-hyperlink-at-point)
          (should (null called))
          (should (string-match-p "blocked hyperlink target" msg)))))))

(ert-deftest test-kuro-hyperlinks-open-at-point-blocks-non-string-target ()
  "kuro-open-hyperlink-at-point reports crafted non-string targets safely."
  (kuro-hyperlinks-test--with-buffer
    (insert "click here\n")
    (let ((ov (make-overlay 1 6)))
      (overlay-put ov 'kuro-hyperlink-uri 42)
      (goto-char 1)
      (let ((called nil)
            (msg nil))
        (cl-letf (((symbol-function 'browse-url)
                   (lambda (url) (setq called url)))
                  ((symbol-function 'message)
                   (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
          (kuro-open-hyperlink-at-point)
          (should (null called))
          (should (string-match-p "42" msg)))))))

;;; Group 2: kuro--clear-hyperlink-overlays — cleanup

(ert-deftest test-kuro-hyperlinks-clear-removes-all-overlays ()
  "kuro--clear-hyperlink-overlays removes all overlays and empties the list."
  (kuro-hyperlinks-test--with-buffer
    (insert "some text here\n")
    (let ((ov1 (make-overlay 1 5))
          (ov2 (make-overlay 6 10)))
      (push ov1 kuro--hyperlink-overlays)
      (push ov2 kuro--hyperlink-overlays)
      (should (= (length kuro--hyperlink-overlays) 2))
      (kuro--clear-hyperlink-overlays)
      (should (null kuro--hyperlink-overlays)))))

(ert-deftest test-kuro-hyperlinks-clear-sets-list-to-nil ()
  "kuro--clear-hyperlink-overlays sets kuro--hyperlink-overlays to nil."
  (kuro-hyperlinks-test--with-buffer
    (insert "text\n")
    (let ((ov (make-overlay 1 3)))
      (push ov kuro--hyperlink-overlays)
      (kuro--clear-hyperlink-overlays)
      (should (eq kuro--hyperlink-overlays nil)))))

(ert-deftest test-kuro-hyperlinks-clear-handles-empty-list ()
  "kuro--clear-hyperlink-overlays handles empty list without error."
  (kuro-hyperlinks-test--with-buffer
    (should (null kuro--hyperlink-overlays))
    (kuro--clear-hyperlink-overlays)
    (should (null kuro--hyperlink-overlays))))

;;; Group 3: kuro--apply-hyperlink-ranges — overlay creation from polled data

(ert-deftest test-kuro-hyperlinks-apply-creates-overlays-from-ranges ()
  "kuro--apply-hyperlink-ranges creates overlays when ranges are returned."
  (kuro-hyperlinks-test--with-buffer
    (insert "hello world link\n")
    (cl-letf (((symbol-function 'kuro--poll-hyperlink-ranges)
               (lambda () '((0 6 11 "https://example.com"))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-hyperlink-ranges)
      (should (= (length kuro--hyperlink-overlays) 1)))))

(ert-deftest test-kuro-hyperlinks-apply-sets-correct-overlay-properties ()
  "kuro--apply-hyperlink-ranges sets face, keymap, help-echo, mouse-face, and uri."
  (kuro-hyperlinks-test--with-buffer
    (insert "hello world link\n")
    (cl-letf (((symbol-function 'kuro--poll-hyperlink-ranges)
               (lambda () '((0 6 11 "https://example.com"))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-hyperlink-ranges)
      (let ((ov (car kuro--hyperlink-overlays)))
        (should (eq (overlay-get ov 'face) 'kuro-hyperlink))
        (should (string= (overlay-get ov 'kuro-hyperlink-uri) "https://example.com"))
        (should (eq (overlay-get ov 'mouse-face) 'highlight))
        (should (string= (overlay-get ov 'help-echo) "https://example.com"))
        (should (overlay-get ov 'keymap))))))

(ert-deftest test-kuro-hyperlinks-apply-clears-old-overlays-before-creating ()
  "kuro--apply-hyperlink-ranges clears old overlays before creating new ones."
  (kuro-hyperlinks-test--with-buffer
    (insert "hello world link\n")
    ;; Pre-populate with an old overlay.
    (let ((old-ov (make-overlay 1 3)))
      (push old-ov kuro--hyperlink-overlays))
    (cl-letf (((symbol-function 'kuro--poll-hyperlink-ranges)
               (lambda () '((0 6 11 "https://example.com"))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-hyperlink-ranges)
      ;; Only the newly created overlay should remain.
      (should (= (length kuro--hyperlink-overlays) 1))
      (should (string= (overlay-get (car kuro--hyperlink-overlays)
                                     'kuro-hyperlink-uri)
                        "https://example.com")))))

(ert-deftest test-kuro-hyperlinks-apply-does-nothing-when-poll-returns-nil ()
  "kuro--apply-hyperlink-ranges does nothing when poll returns nil and no old overlays."
  (kuro-hyperlinks-test--with-buffer
    (insert "hello\n")
    (cl-letf (((symbol-function 'kuro--poll-hyperlink-ranges)
               (lambda () nil)))
      (kuro--apply-hyperlink-ranges)
      (should (null kuro--hyperlink-overlays)))))

(ert-deftest test-kuro-hyperlinks-apply-clears-stale-overlays-when-poll-returns-nil ()
  "kuro--apply-hyperlink-ranges clears old overlays even when poll returns nil."
  (kuro-hyperlinks-test--with-buffer
    (insert "hello world link\n")
    ;; Simulate a previous poll that created overlays.
    (let ((old-ov (make-overlay 1 6)))
      (overlay-put old-ov 'kuro-hyperlink-uri "https://old.example.com")
      (push old-ov kuro--hyperlink-overlays))
    (should (= (length kuro--hyperlink-overlays) 1))
    (cl-letf (((symbol-function 'kuro--poll-hyperlink-ranges)
               (lambda () nil)))
      (kuro--apply-hyperlink-ranges)
      (should (null kuro--hyperlink-overlays)))))

(ert-deftest test-kuro-hyperlinks-apply-skips-disallowed-schemes ()
  "kuro--apply-hyperlink-ranges does not create overlays for blocked schemes."
  (kuro-hyperlinks-test--with-buffer
    (insert "contact\n")
    (cl-letf (((symbol-function 'kuro--poll-hyperlink-ranges)
               (lambda () '((0 0 7 "mailto:test@example.com"))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-hyperlink-ranges)
      (should (null kuro--hyperlink-overlays)))))

(ert-deftest test-kuro-hyperlinks-apply-skips-malformed-ranges ()
  "kuro--apply-hyperlink-ranges only creates overlays for typed valid ranges."
  (kuro-hyperlinks-test--with-buffer
    (insert "link ok\n")
    (cl-letf (((symbol-function 'kuro--poll-hyperlink-ranges)
               (lambda ()
                 '((0 0 4 "ftp://example.com/file")
                   (-1 0 4 "https://negative-row.example")
                   (0 -1 4 "https://negative-start.example")
                   (0 4 4 "https://empty.example")
                   (0 4 2 "https://inverted.example")
                   (0 0 4 42)
                   (0 0 4 "https:///hostless")
                   (0 0 4 "https://user@example.com")
                    (0 0 4 "https://example.com/bad\npath")
                    (0 0 4 "https://example.com:bad/path")
                    (0 0 4 "https://example.com:999999/path")
                    (0 0 4 "https://999.999.999.999/path")
                    (0 0 4 "https://[dead:beef]/path")
                    (0 0 4 "https://ok.example"))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-hyperlink-ranges)
      (should (= (length kuro--hyperlink-overlays) 1))
      (should (string= (overlay-get (car kuro--hyperlink-overlays)
                                     'kuro-hyperlink-uri)
                       "https://ok.example")))))

(ert-deftest test-kuro-hyperlinks-apply-skips-out-of-buffer-ranges ()
  "kuro--apply-hyperlink-ranges rejects overlay bounds outside the buffer."
  (kuro-hyperlinks-test--with-buffer
    (insert "short\n")
    (cl-letf (((symbol-function 'kuro--poll-hyperlink-ranges)
               (lambda () '((0 0 999 "https://example.com"))))
              ((symbol-function 'kuro--row-position)
               (lambda (_row) 1)))
      (kuro--apply-hyperlink-ranges)
      (should (null kuro--hyperlink-overlays)))))

;;; Group 4: kuro-hyperlink face

(ert-deftest test-kuro-hyperlinks-face-exists ()
  "kuro-hyperlink face is defined."
  (should (facep 'kuro-hyperlink)))

(ert-deftest test-kuro-hyperlinks-face-has-underline ()
  "kuro-hyperlink face has underline attribute."
  (should (face-attribute 'kuro-hyperlink :underline nil 'default)))

;;; Group 5: kuro--hyperlink-keymap bindings

(ert-deftest test-kuro-hyperlinks-keymap-has-mouse-1 ()
  "kuro--hyperlink-keymap has mouse-1 binding."
  (should (lookup-key kuro--hyperlink-keymap [mouse-1])))

(ert-deftest test-kuro-hyperlinks-keymap-has-ret ()
  "kuro--hyperlink-keymap has RET binding."
  (should (lookup-key kuro--hyperlink-keymap (kbd "RET"))))

;;; Group 6: terminal web URL allowlist invariants

(ert-deftest test-kuro-hyperlinks-open-blocked-scheme-shows-message ()
  "kuro-open-hyperlink-at-point shows message for blocked scheme."
  (kuro-hyperlinks-test--with-buffer
    (insert "click here\n")
    (let ((ov (make-overlay 1 6)))
      (overlay-put ov 'kuro-hyperlink-uri "file:///etc/passwd")
      (goto-char 1)
      (let ((called nil)
            (msg nil))
        (cl-letf (((symbol-function 'browse-url)
                   (lambda (url) (setq called url)))
                  ((symbol-function 'message)
                   (lambda (fmt &rest args) (setq msg (apply #'format fmt args)))))
          (kuro-open-hyperlink-at-point)
          (should (null called))
          (should (string-match-p "blocked hyperlink target" msg)))))))

;;; ── terminal web URL allowlist invariants ────────────────────────────────────

(ert-deftest kuro-hyperlinks-allowed-schemes-includes-https ()
  "`kuro--terminal-web-url-allowed-schemes' must include \"https\"."
  (should (member "https" kuro--terminal-web-url-allowed-schemes)))

(ert-deftest kuro-hyperlinks-allowed-schemes-includes-http ()
  "`kuro--terminal-web-url-allowed-schemes' includes \"http\"."
  (should (member "http" kuro--terminal-web-url-allowed-schemes)))

(ert-deftest kuro-hyperlinks-allowed-schemes-excludes-file ()
  "`kuro--terminal-web-url-allowed-schemes' must NOT include \"file\"."
  (should-not (member "file" kuro--terminal-web-url-allowed-schemes)))

(ert-deftest kuro-hyperlinks-allowed-schemes-excludes-ftp ()
  "`kuro--terminal-web-url-allowed-schemes' must NOT include \"ftp\"."
  (should-not (member "ftp" kuro--terminal-web-url-allowed-schemes)))

(ert-deftest kuro-hyperlinks-allowed-schemes-excludes-mailto ()
  "`kuro--terminal-web-url-allowed-schemes' must NOT include \"mailto\"."
  (should-not (member "mailto" kuro--terminal-web-url-allowed-schemes)))

(provide 'kuro-hyperlinks-test)

;;; kuro-hyperlinks-test.el ends here
