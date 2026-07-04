;;; kuro-module-test-2.el --- ERT tests for kuro-module.el (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-module-test-support)

;;; Group 17: kuro-module--platform-string Rust-triple mapping

(ert-deftest kuro-module-test--platform-string-darwin-aarch64 ()
  "`kuro-module--platform-string' returns aarch64-apple-darwin on darwin/arm64."
  (should (equal (kuro-module--platform-string 'darwin "aarch64-apple-darwin23.0")
                 "aarch64-apple-darwin")))

(ert-deftest kuro-module-test--platform-string-darwin-arm64-prefix ()
  "`kuro-module--platform-string' also accepts arm64 as the aarch64 prefix on darwin."
  (should (equal (kuro-module--platform-string 'darwin "arm64-apple-darwin23.0")
                 "aarch64-apple-darwin")))

(ert-deftest kuro-module-test--platform-string-darwin-x86_64 ()
  "`kuro-module--platform-string' returns x86_64-apple-darwin on darwin/x86_64."
  (should (equal (kuro-module--platform-string 'darwin "x86_64-apple-darwin23.0")
                 "x86_64-apple-darwin")))

(ert-deftest kuro-module-test--platform-string-linux-x86_64 ()
  "`kuro-module--platform-string' returns x86_64-unknown-linux-gnu on Linux/x86_64."
  (should (equal (kuro-module--platform-string 'gnu/linux "x86_64-pc-linux-gnu")
                 "x86_64-unknown-linux-gnu")))

(ert-deftest kuro-module-test--platform-string-linux-aarch64 ()
  "`kuro-module--platform-string' returns aarch64-unknown-linux-gnu on Linux/arm64."
  (should (equal (kuro-module--platform-string 'gnu/linux "aarch64-unknown-linux-gnu")
                 "aarch64-unknown-linux-gnu")))

(ert-deftest kuro-module-test--platform-string-unknown-errors ()
  "`kuro-module--platform-string' signals an error for unsupported platforms."
  (should-error (kuro-module--platform-string 'windows-nt "x86_64-pc-windows-msvc")
                :type 'error))

;;; Group 18: kuro-module--verify-sha256

(ert-deftest kuro-module-test--verify-sha256-match-passes ()
  "`kuro-module--verify-sha256' returns t when the file digest matches."
  (kuro-module-test--with-temp-file (tmpfile "kuro-hash-")
    (with-temp-file tmpfile (insert "hello kuro"))
    (let ((expected (with-temp-buffer
                      (set-buffer-multibyte nil)
                      (insert-file-contents-literally tmpfile)
                      (secure-hash 'sha256 (current-buffer)))))
      (should (kuro-module--verify-sha256
               tmpfile
               (kuro-module--parse-sha256 expected "test digest"))))))

(ert-deftest kuro-module-test--verify-sha256-mismatch-rejects ()
  "`kuro-module--verify-sha256' returns nil when the digest does not match."
  (kuro-module-test--with-temp-file (tmpfile "kuro-hash-")
    (with-temp-file tmpfile (insert "hello kuro"))
    (should-not
     (kuro-module--verify-sha256
      tmpfile
      (kuro-module--parse-sha256
       "0000000000000000000000000000000000000000000000000000000000000000"
       "test digest")))))

(ert-deftest kuro-module-test--verify-sha256-nil-hash-errors ()
  "`kuro-module--verify-sha256' rejects missing expected digests."
  (kuro-module-test--with-temp-file (tmpfile "kuro-hash-")
    (with-temp-file tmpfile (insert "hello kuro"))
    (should (string-match-p
             "expected SHA256 must be a validated digest object"
             (cadr (should-error (kuro-module--verify-sha256 tmpfile nil)
                                 :type 'error))))))

;;; Group 19: kuro-module--shared-extension

(ert-deftest kuro-module-test--shared-extension-darwin ()
  "`kuro-module--shared-extension' returns \".dylib\" on darwin."
  (let ((system-type 'darwin))
    (should (equal (kuro-module--shared-extension) ".dylib"))))

(ert-deftest kuro-module-test--shared-extension-linux ()
  "`kuro-module--shared-extension' returns \".so\" on GNU/Linux."
  (let ((system-type 'gnu/linux))
    (should (equal (kuro-module--shared-extension) ".so"))))

;;; Group 20: kuro-module--target-path

(ert-deftest kuro-module-test--target-path-honours-xdg ()
  "`kuro-module--target-path' uses XDG_DATA_HOME when set."
  (kuro-module-test--with-temp-dir-env (tmpdir "kuro-xdg-" "XDG_DATA_HOME")
    (let ((dir (kuro-module--target-path)))
      (should (equal dir (expand-file-name "kuro" tmpdir)))
      (should (file-directory-p dir)))))

(ert-deftest kuro-module-test--target-path-creates-directory ()
  "`kuro-module--target-path' creates the install directory if it is missing."
  (kuro-module-test--with-temp-dir-env (tmpdir "kuro-xdg-" "XDG_DATA_HOME")
    (let ((target (expand-file-name "kuro" tmpdir)))
      (should-not (file-directory-p target))
      (kuro-module--target-path)
      (should (file-directory-p target)))))

(ert-deftest kuro-module-test--target-path-uses-private-mode ()
  "`kuro-module--target-path' creates a private install directory."
  (kuro-module-test--with-temp-dir-env (tmpdir "kuro-xdg-" "XDG_DATA_HOME")
    (let ((dir (kuro-module--target-path)))
      (should (= (logand (file-modes dir) #o777) #o700)))))

(ert-deftest kuro-module-test--target-path-rejects-symlink-directory ()
  "`kuro-module--target-path' rejects a symlinked install directory."
  (skip-unless (fboundp 'make-symbolic-link))
  (kuro-module-test--with-temp-dir-env (tmpdir "kuro-xdg-" "XDG_DATA_HOME")
    (let ((real (expand-file-name "real" tmpdir))
          (link (expand-file-name "kuro" tmpdir)))
      (make-directory real t)
      (make-symbolic-link real link)
      (should (string-match-p "must not be a symlink"
                              (cadr (should-error (kuro-module--target-path)
                                                  :type 'error)))))))

;;; Group 20b: kuro-module installation helper coverage

(defun kuro-module-test--tar-call-process-stub
    (members extract-exit &optional extract-callback)
  "Return a `call-process' stub for tar listing MEMBERS and extraction.
EXTRACT-EXIT is returned for extraction calls.  EXTRACT-CALLBACK receives the
tar arguments for extraction calls."
  (lambda (_program _infile destination _display &rest args)
    (cond
     ((equal (car args) "-tzf")
      (cond
       ((bufferp destination)
        (with-current-buffer destination
          (dolist (member members)
            (insert member "\n"))))
       ((stringp destination)
        (with-temp-file destination
          (dolist (member members)
            (insert member "\n"))))
       ((eq destination t)
        (dolist (member members)
          (princ (concat member "\n")))))
      0)
     ((equal (car args) "-xzf")
      (when extract-callback
        (funcall extract-callback args))
      extract-exit)
     (t 127))))

(ert-deftest kuro-module-test--shared-library-name-uses-shared-extension ()
  "`kuro-module--shared-library-name' prefixes the platform extension with libkuro_core."
  (cl-letf (((symbol-function 'kuro-module--shared-extension)
             (lambda () ".dylib")))
    (should (equal (kuro-module--shared-library-name) "libkuro_core.dylib"))))

(ert-deftest kuro-module-test--installed-module-path-joins-target-dir ()
  "`kuro-module--installed-module-path' appends the shared library filename to TARGET-DIR."
  (cl-letf (((symbol-function 'kuro-module--shared-library-name)
             (lambda () "libkuro_core.so")))
    (should (equal (kuro-module--installed-module-path "/tmp/kuro")
                   "/tmp/kuro/libkuro_core.so"))))

(ert-deftest kuro-module-test--validate-release-archive-accepts-single-library ()
  "`kuro-module--validate-release-archive' accepts exactly the shared library."
  (cl-letf (((symbol-function 'kuro-module--shared-library-name)
             (lambda () "libkuro_core.so"))
            ((symbol-function 'call-process)
             (kuro-module-test--tar-call-process-stub
              '("libkuro_core.so") 0)))
    (should-not
     (kuro-module--validate-release-archive "/usr/bin/tar" "/tmp/kuro.tar.gz"))))

(ert-deftest kuro-module-test--validate-release-archive-rejects-extra-member ()
  "`kuro-module--validate-release-archive' rejects archives with extra files."
  (cl-letf (((symbol-function 'kuro-module--shared-library-name)
             (lambda () "libkuro_core.so"))
            ((symbol-function 'call-process)
             (kuro-module-test--tar-call-process-stub
              '("libkuro_core.so" "README.md") 0)))
    (should (string-match-p
             "must contain exactly"
             (error-message-string
              (should-error
               (kuro-module--validate-release-archive
                "/usr/bin/tar" "/tmp/kuro.tar.gz")
               :type 'error))))))

(ert-deftest kuro-module-test--validate-release-archive-rejects-relative-escape ()
  "`kuro-module--validate-release-archive' rejects path-escaping members."
  (cl-letf (((symbol-function 'kuro-module--shared-library-name)
             (lambda () "libkuro_core.so"))
            ((symbol-function 'call-process)
             (kuro-module-test--tar-call-process-stub
              '("../libkuro_core.so") 0)))
    (should (string-match-p
             "must contain exactly"
             (error-message-string
              (should-error
               (kuro-module--validate-release-archive
                "/usr/bin/tar" "/tmp/kuro.tar.gz")
               :type 'error))))))

(ert-deftest kuro-module-test--validate-release-archive-errors-on-listing-failure ()
  "`kuro-module--validate-release-archive' errors when tar cannot list members."
  (cl-letf (((symbol-function 'call-process)
             (lambda (&rest _) 1)))
    (should (string-match-p
             "tar listing failed"
             (error-message-string
              (should-error
               (kuro-module--validate-release-archive
                "/usr/bin/tar" "/tmp/kuro.tar.gz")
               :type 'error))))))

(ert-deftest kuro-module-test--install-release-archive-extracts-only-shared-library ()
  "`kuro-module--install-release-archive' extracts only the validated library member."
  (kuro-module-test--with-temp-dir-file (tmpdir tmp-tar "kuro-install-archive-" "kuro.tar.gz")
    (let ((extract-args nil)
          (installed (expand-file-name "libkuro_core.so" tmpdir)))
      (cl-letf (((symbol-function 'kuro-module--shared-library-name)
                 (lambda () "libkuro_core.so"))
                ((symbol-function 'call-process)
                 (kuro-module-test--tar-call-process-stub
                  '("libkuro_core.so")
                  0
                  (lambda (args)
                    (setq extract-args args)
                    (let ((destination (nth 3 args))
                          (member (car (last args))))
                      (with-temp-file (expand-file-name member destination)
                        (insert "binary"))))))
                ((symbol-function 'message) #'ignore))
        (should (equal (kuro-module--install-release-archive
                        "/usr/bin/tar" tmp-tar tmpdir)
                       installed))
        ;; Extraction lands in an isolated temp dir (symlink-safety staging
        ;; area), not directly in TARGET-DIR, so only the fixed positions of
        ;; extract-args are asserted here.
        (should (equal (list (nth 0 extract-args) (nth 1 extract-args)
                              (nth 2 extract-args) (nth 4 extract-args))
                       (list "-xzf" tmp-tar "-C" "libkuro_core.so")))
        (should (string-prefix-p "kuro-module-extract-"
                                 (file-name-nondirectory (nth 3 extract-args))))
        (should-not (file-exists-p tmp-tar))))))

(ert-deftest kuro-module-test--install-release-archive-deletes-invalid-archive ()
  "`kuro-module--install-release-archive' deletes rejected temporary archives."
  (kuro-module-test--with-temp-dir-file (tmpdir tmp-tar "kuro-install-invalid-" "kuro.tar.gz")
    (cl-letf (((symbol-function 'kuro-module--shared-library-name)
               (lambda () "libkuro_core.so"))
              ((symbol-function 'call-process)
               (kuro-module-test--tar-call-process-stub
                '("libkuro_core.so" "README.md") 0)))
      (should-error
       (kuro-module--install-release-archive "/usr/bin/tar" tmp-tar tmpdir)
       :type 'error)
      (should-not (file-exists-p tmp-tar)))))

(ert-deftest kuro-module-test--release-spec-builds-urls ()
  "`kuro-module--release-spec' returns the expected release metadata plist."
  (let ((kuro-module-release-base-url "https://example.test/releases"))
    (cl-letf (((symbol-function 'kuro-module--platform-string)
               (lambda () "x86_64-unknown-linux-gnu")))
      (let ((spec (kuro-module--release-spec "1.2.3")))
        (should (equal (plist-get spec :version) "1.2.3"))
        (should (equal (plist-get spec :platform) "x86_64-unknown-linux-gnu"))
        (should (equal (plist-get spec :tarball)
                       "libkuro_core-1.2.3-x86_64-unknown-linux-gnu.tar.gz"))
        (should (equal (plist-get spec :url)
                       "https://example.test/releases/v1.2.3/libkuro_core-1.2.3-x86_64-unknown-linux-gnu.tar.gz"))
        (should (equal (plist-get spec :sha-url)
                       "https://example.test/releases/v1.2.3/libkuro_core-1.2.3-x86_64-unknown-linux-gnu.tar.gz.sha256"))))))

(ert-deftest kuro-module-test--release-spec-rejects-invalid-version ()
  "`kuro-module--release-spec' rejects malformed version strings."
  (let ((kuro-module-release-base-url "https://example.test/releases"))
    (should (string-match-p "invalid version string"
                            (error-message-string
                             (should-error (kuro-module--release-spec "1.2")
                                           :type 'error))))))

(ert-deftest kuro-module-test--release-spec-rejects-non-https-base-url ()
  "`kuro-module--release-spec' rejects non-HTTPS release bases."
  (let ((kuro-module-release-base-url "http://example.test/releases"))
    (should (string-match-p "must use https://"
                            (error-message-string
                             (should-error (kuro-module--release-spec "1.2.3")
                                           :type 'error))))))

(ert-deftest kuro-module-test--release-base-url-setter-rejects-http ()
  "`kuro-module-release-base-url' rejects non-HTTPS values at set time."
  (should (string-match-p "must use https://"
                          (error-message-string
                           (should-error
                            (customize-set-variable
                             'kuro-module-release-base-url
                             "http://example.test/releases")
                            :type 'error)))))

(ert-deftest kuro-module-test--http-response-body-string-reads-body ()
  "`kuro-module--http-response-body-string' returns the response body after the blank line."
  (with-temp-buffer
    (insert "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nhello kuro\n")
    (should (equal (kuro-module--http-response-body-string "https://example.test/file")
                   "hello kuro\n"))))

(ert-deftest kuro-module-test--http-response-body-string-errors-without-separator ()
  "`kuro-module--http-response-body-string' errors when the HTTP response is malformed."
  (with-temp-buffer
    (insert "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nhello kuro\n")
    (should (string-match-p "malformed HTTP response"
                            (error-message-string
                             (should-error
                              (kuro-module--http-response-body-string
                               "https://example.test/file")
                              :type 'error))))))

(ert-deftest kuro-module-test--fetch-sha256-trims-and-validates-body ()
  "`kuro-module--fetch-sha256' reads and trims a valid SHA256 sidecar response."
  (let ((hash (make-string 64 ?a))
        (buffer (generate-new-buffer " *kuro-sha256-ok*")))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (insert "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n")
            (insert hash)
            (insert "\n"))
          (cl-letf (((symbol-function 'url-retrieve-synchronously)
                     (lambda (&rest _) buffer)))
            (let ((digest (kuro-module--fetch-sha256
                           "https://example.test/file.sha256")))
              (should (kuro-module--sha256-p digest))
              (should (equal (kuro-module--sha256-digest digest) hash)))))
      (ignore-errors (kill-buffer buffer)))))

(ert-deftest kuro-module-test--fetch-sha256-rejects-invalid-body ()
  "`kuro-module--fetch-sha256' rejects non-hex or short SHA256 sidecars."
  (let ((buffer (generate-new-buffer " *kuro-sha256-bad*")))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (insert "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n")
            (insert "not-a-sha256"))
          (cl-letf (((symbol-function 'url-retrieve-synchronously)
                     (lambda (&rest _) buffer)))
            (let ((message (error-message-string
                            (should-error
                             (kuro-module--fetch-sha256
                              "https://example.test/file.sha256")
                             :type 'error))))
              (should (string-match-p "invalid SHA256" message)))))
      (ignore-errors (kill-buffer buffer)))))

(ert-deftest kuro-module-test--write-http-body-to-file-copies-body-bytes ()
  "`kuro-module--write-http-body-to-file' writes only the HTTP body to FILE."
  (let ((buffer (generate-new-buffer " *kuro-body-write*")))
    (unwind-protect
        (kuro-module-test--with-temp-file (file "kuro-body-write-")
          (with-current-buffer buffer
            (insert "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n")
            (insert "payload\n"))
          (kuro-module--write-http-body-to-file buffer file "https://example.test/file")
          (with-temp-buffer
            (insert-file-contents-literally file)
            (should (equal (buffer-string) "payload\n"))))
      (ignore-errors (kill-buffer buffer)))))

;;; Group 21: kuro-module-download error paths

(ert-deftest kuro-module-test--download-tar-not-found ()
  "`kuro-module-download' errors when `tar' is not found in PATH."
  (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) nil)))
    (should (string-match-p "executable not found"
                            (error-message-string
                             (should-error (kuro-module-download "0.0.0")
                                           :type 'error))))))

(ert-deftest kuro-module-test--download-sha256-fetch-fails ()
  "`kuro-module-download' errors when the .sha256 URL fetch returns nil."
  (kuro-module-test--with-temp-dir (tmpdir "kuro-dl-test-")
    (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) "/usr/bin/tar"))
              ((symbol-function 'kuro-module--platform-string)
               (lambda (&rest _) "x86_64-unknown-linux-gnu"))
              ((symbol-function 'kuro-module--target-path)
               (lambda () tmpdir))
              ((symbol-function 'url-retrieve-synchronously) (lambda (&rest _) nil))
              ((symbol-function 'message) #'ignore))
      (should (string-match-p "failed to fetch SHA256"
                              (error-message-string
                               (should-error (kuro-module-download "0.0.0")
                                             :type 'error)))))))

(ert-deftest kuro-module-test--download-sha256-mismatch ()
  "`kuro-module-download' errors when SHA256 computed from file differs from expected."
  (kuro-module-test--with-temp-dir-file (tmpdir tmp-tar "kuro-dl-mismatch-" "kuro-test.tar.gz")
    (let ((sha-buf (generate-new-buffer " *kuro-sha-test*")))
      (unwind-protect
          (progn
            ;; Create a fake sha buffer with header + a known hash
            (with-current-buffer sha-buf
              (insert "HTTP/1.1 200 OK\r\n\r\n")
              (insert (make-string 64 ?a)))
            (cl-letf (((symbol-function 'executable-find)
                       (lambda (_cmd) "/usr/bin/tar"))
                      ((symbol-function 'kuro-module--platform-string)
                       (lambda (&rest _) "x86_64-unknown-linux-gnu"))
                      ((symbol-function 'kuro-module--target-path)
                       (lambda () tmpdir))
                      ((symbol-function 'make-temp-file)
                       (lambda (&rest _) tmp-tar))
                      ((symbol-function 'url-retrieve-synchronously)
                       (lambda (url &rest _)
                         (if (string-suffix-p ".sha256" url)
                             sha-buf
                           ;; return a minimal HTTP buffer for the tarball
                           (let ((buf (generate-new-buffer " *kuro-dl-test*")))
                             (with-current-buffer buf
                               (insert "HTTP/1.1 200 OK\r\n\r\nfake"))
                             buf))))
                      ((symbol-function 'write-region) #'ignore)
                      ((symbol-function 'kuro-module--verify-sha256)
                       (lambda (_file _hash) nil))
                      ((symbol-function 'message) #'ignore))
              (should (string-match-p "SHA256 mismatch"
                                      (error-message-string
                                       (should-error (kuro-module-download "0.0.0")
                                                     :type 'error))))))
        (ignore-errors (kill-buffer sha-buf))))))

(ert-deftest kuro-module-test--download-tar-extraction-fails ()
  "`kuro-module-download' errors when tar exits with a nonzero code."
  (kuro-module-test--with-temp-dir-file (tmpdir tmp-tar "kuro-dl-tarfail-" "kuro-test.tar.gz")
    (let ((sha-buf (generate-new-buffer " *kuro-sha-tarfail*")))
      (unwind-protect
          (progn
            (with-current-buffer sha-buf
              (insert "HTTP/1.1 200 OK\r\n\r\n")
              (insert (make-string 64 ?a)))
            (cl-letf (((symbol-function 'executable-find)
                       (lambda (_cmd) "/usr/bin/tar"))
                      ((symbol-function 'kuro-module--platform-string)
                       (lambda (&rest _) "x86_64-unknown-linux-gnu"))
                      ((symbol-function 'kuro-module--target-path)
                       (lambda () tmpdir))
                      ((symbol-function 'make-temp-file)
                       (lambda (_prefix &optional dir-flag _suffix)
                         (if dir-flag
                             (let ((extract-dir (expand-file-name "extract" tmpdir)))
                               (make-directory extract-dir t)
                               extract-dir)
                           tmp-tar)))
                      ((symbol-function 'url-retrieve-synchronously)
                       (lambda (url &rest _)
                         (if (string-suffix-p ".sha256" url)
                             sha-buf
                           (let ((buf (generate-new-buffer " *kuro-dl-tarfail-body*")))
                             (with-current-buffer buf
                               (insert "HTTP/1.1 200 OK\r\n\r\nfake"))
                             buf))))
                      ((symbol-function 'write-region) #'ignore)
                      ((symbol-function 'kuro-module--verify-sha256)
                       (lambda (_file _hash) t))
                      ((symbol-function 'kuro-module--archive-members)
                       (lambda (_tar _archive)
                         (list (kuro-module--shared-library-name))))
                      ((symbol-function 'kuro-module--extract-archive-member)
                       (lambda (&rest _)
                         (error "Kuro: tar extraction failed (exit 1, see *kuro-module-download*)")))
                      ((symbol-function 'delete-file) #'ignore)
                      ((symbol-function 'message) #'ignore))
              (should (string-match-p "tar extraction failed"
                                      (error-message-string
                                       (should-error (kuro-module-download "0.0.0")
                                                     :type 'error))))))
        (ignore-errors (kill-buffer sha-buf))))))

(ert-deftest kuro-module-test--download-extracted-binary-missing ()
  "`kuro-module-download' errors when tar succeeds but the extracted file is absent.
Uses a real tmpdir that contains no libkuro_core binary, so file-exists-p
naturally returns nil for the installed-binary check without global stubbing."
  (kuro-module-test--with-temp-dir-file (tmpdir tmp-tar "kuro-dl-binmiss-" "kuro-test.tar.gz")
    (let ((sha-buf (generate-new-buffer " *kuro-sha-binmiss*")))
      (unwind-protect
          (progn
            (with-current-buffer sha-buf
              (insert "HTTP/1.1 200 OK\r\n\r\n")
              (insert (make-string 64 ?a)))
            (cl-letf (((symbol-function 'executable-find)
                       (lambda (_cmd) "/usr/bin/tar"))
                      ((symbol-function 'kuro-module--platform-string)
                       (lambda (&rest _) "x86_64-unknown-linux-gnu"))
                      ((symbol-function 'kuro-module--target-path)
                       (lambda () tmpdir))
                      ((symbol-function 'make-temp-file)
                       (lambda (_prefix &optional dir-flag _suffix)
                         (if dir-flag
                             (let ((extract-dir (expand-file-name "extract" tmpdir)))
                               (make-directory extract-dir t)
                               extract-dir)
                           tmp-tar)))
                      ((symbol-function 'url-retrieve-synchronously)
                       (lambda (url &rest _)
                         (if (string-suffix-p ".sha256" url)
                             sha-buf
                             (let ((buf (generate-new-buffer " *kuro-dl-binmiss-body*")))
                               (with-current-buffer buf
                                 (insert "HTTP/1.1 200 OK\r\n\r\nfake"))
                             buf))))
                      ((symbol-function 'kuro-module--write-http-body-to-file)
                       #'ignore)
                      ;; Verify passes, tar returns 0 — but no binary is extracted
                      ((symbol-function 'kuro-module--verify-sha256)
                       (lambda (_file _hash) t))
                      ((symbol-function 'kuro-module--archive-members)
                       (lambda (_tar _archive)
                         (list (kuro-module--shared-library-name))))
                      ((symbol-function 'kuro-module--extract-archive-member) #'ignore)
                      ((symbol-function 'message) #'ignore))
              ;; tmpdir has no libkuro_core.so/.dylib → file-exists-p naturally nil
              (should (string-match-p "extracted archive does not contain"
                                      (error-message-string
                                       (should-error (kuro-module-download "0.0.0")
                                                     :type 'error))))))
        (ignore-errors (kill-buffer sha-buf))))))

(ert-deftest kuro-module-test--install-release-archive-copies-library ()
  "`kuro-module--install-release-archive' installs the single expected library member."
  (let ((tar-bin (executable-find "tar")))
    (skip-unless tar-bin)
    (let* ((root (make-temp-file "kuro-module-archive-ok-" t))
           (src (expand-file-name "src" root))
           (target (expand-file-name "target" root))
           (archive (expand-file-name "module.tar.gz" root))
           (library (kuro-module--shared-library-name))
           (source-library (expand-file-name library src))
           (installed (expand-file-name library target)))
      (unwind-protect
          (progn
            (make-directory src t)
            (write-region "binary" nil source-library nil 'silent)
            (should (zerop (call-process tar-bin nil nil nil
                                         "-czf" archive "-C" src library)))
            (kuro-module--install-release-archive tar-bin archive target)
            (should (file-exists-p installed))
            (with-temp-buffer
              (insert-file-contents-literally installed)
              (should (equal (buffer-string) "binary")))
            (should (= (logand (file-modes target) #o777) #o700))
            (should (= (logand (file-modes installed) #o777) #o600))
            (should (= (file-nlinks installed) 1))
            (should-not (file-exists-p archive)))
        (when (file-exists-p root)
          (delete-directory root t))))))

(ert-deftest kuro-module-test--install-release-archive-rejects-extra-member ()
  "`kuro-module--install-release-archive' rejects archives with extra members."
  (let ((tar-bin (executable-find "tar")))
    (skip-unless tar-bin)
    (let* ((root (make-temp-file "kuro-module-archive-extra-" t))
           (src (expand-file-name "src" root))
           (target (expand-file-name "target" root))
           (archive (expand-file-name "module.tar.gz" root))
           (library (kuro-module--shared-library-name))
           (source-library (expand-file-name library src))
           (extra (expand-file-name "extra.txt" src))
           (installed (expand-file-name library target)))
      (unwind-protect
          (progn
            (make-directory src t)
            (write-region "binary" nil source-library nil 'silent)
            (write-region "extra" nil extra nil 'silent)
            (should (zerop (call-process tar-bin nil nil nil
                                         "-czf" archive "-C" src library "extra.txt")))
            (should (string-match-p "archive must contain exactly"
                                    (cadr (should-error
                                           (kuro-module--install-release-archive
                                            tar-bin archive target)
                                           :type 'error))))
            (should-not (file-exists-p installed)))
        (when (file-exists-p root)
          (delete-directory root t))))))

(ert-deftest kuro-module-test--install-release-archive-rejects-symlink-library ()
  "`kuro-module--install-release-archive' rejects symlinked library payloads."
  (let* ((root (make-temp-file "kuro-module-symlink-" t))
         (target (expand-file-name "target" root))
         (archive (expand-file-name "module.tar.gz" root))
         (extract-dir (expand-file-name "extract" root))
         (library (kuro-module--shared-library-name))
         (real (expand-file-name "real-lib" root)))
    (unwind-protect
        (progn
          (make-directory target t)
          (make-directory extract-dir t)
          (with-temp-file archive)
          (write-region "binary" nil real nil 'silent)
          (cl-letf (((symbol-function 'make-temp-file)
                     (lambda (_prefix &optional dir-flag _suffix)
                       (if dir-flag extract-dir archive)))
                    ((symbol-function 'kuro-module--archive-members)
                     (lambda (_tar _archive) (list library)))
                    ((symbol-function 'kuro-module--extract-archive-member)
                     (lambda (_tar _archive destination member)
                       (make-symbolic-link real (expand-file-name member destination))))
                    ((symbol-function 'message) #'ignore))
            (should (string-match-p "contains symlink"
                                    (cadr (should-error
                                           (kuro-module--install-release-archive
                                            "/usr/bin/tar" archive target)
                                           :type 'error))))))
      (when (file-exists-p root)
        (delete-directory root t)))))

(ert-deftest kuro-module-test--install-release-archive-rejects-destination-symlink ()
  "`kuro-module--install-release-archive' rejects a symlinked destination file."
  (skip-unless (fboundp 'make-symbolic-link))
  (let ((tar-bin (executable-find "tar")))
    (skip-unless tar-bin)
    (let* ((root (make-temp-file "kuro-module-dest-symlink-" t))
           (src (expand-file-name "src" root))
           (target (expand-file-name "target" root))
           (archive (expand-file-name "module.tar.gz" root))
           (library (kuro-module--shared-library-name))
           (source-library (expand-file-name library src))
           (installed (expand-file-name library target))
           (victim (expand-file-name "victim" root)))
      (unwind-protect
          (progn
            (make-directory src t)
            (make-directory target t)
            (write-region "binary" nil source-library nil 'silent)
            (write-region "victim" nil victim nil 'silent)
            (make-symbolic-link victim installed)
            (should (zerop (call-process tar-bin nil nil nil
                                         "-czf" archive "-C" src library)))
            (should (string-match-p "destination must not be a symlink"
                                    (cadr (should-error
                                           (kuro-module--install-release-archive
                                            tar-bin archive target)
                                           :type 'error))))
            (with-temp-buffer
              (insert-file-contents-literally victim)
              (should (equal (buffer-string) "victim"))))
        (when (file-exists-p root)
          (delete-directory root t))))))

(ert-deftest kuro-module-test--install-release-archive-rejects-hardlink-library ()
  "`kuro-module--install-release-archive' rejects hardlinked library payloads."
  (skip-unless (fboundp 'add-name-to-file))
  (let* ((root (make-temp-file "kuro-module-hardlink-" t))
         (target (expand-file-name "target" root))
         (archive (expand-file-name "module.tar.gz" root))
         (extract-dir (expand-file-name "extract" root))
         (library (kuro-module--shared-library-name))
         (real (expand-file-name "real-lib" root))
         (probe (expand-file-name "probe-link" root))
         (hardlinks-supported nil))
    (unwind-protect
        (progn
          (make-directory target t)
          (make-directory extract-dir t)
          (with-temp-file archive)
          (write-region "binary" nil real nil 'silent)
          (condition-case nil
              (progn
                (add-name-to-file real probe)
                (setq hardlinks-supported t)
                (delete-file probe))
            (file-error nil))
          (skip-unless hardlinks-supported)
          (cl-letf (((symbol-function 'make-temp-file)
                     (lambda (_prefix &optional dir-flag _suffix)
                       (if dir-flag extract-dir archive)))
                    ((symbol-function 'kuro-module--archive-members)
                     (lambda (_tar _archive) (list library)))
                    ((symbol-function 'kuro-module--extract-archive-member)
                     (lambda (_tar _archive destination member)
                       (add-name-to-file real
                                         (expand-file-name member destination))))
                    ((symbol-function 'message) #'ignore))
            (should (string-match-p "exactly one filesystem link"
                                    (cadr (should-error
                                           (kuro-module--install-release-archive
                                            "/usr/bin/tar" archive target)
                                           :type 'error))))))
      (when (file-exists-p root)
        (delete-directory root t)))))

(ert-deftest kuro-module-test--download-sha256-malformed-response ()
  "`kuro-module-download' errors when SHA256 HTTP response has no blank-line separator."
  (kuro-module-test--with-temp-dir-file (tmpdir tmp-tar "kuro-dl-malformed-" "kuro-test.tar.gz")
    (let (;; A buffer with no blank line between headers and body
          (sha-buf (generate-new-buffer " *kuro-sha-malformed*")))
      (unwind-protect
          (progn
            (with-current-buffer sha-buf
              (insert "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nabc123"))
            (cl-letf (((symbol-function 'executable-find)
                       (lambda (_cmd) "/usr/bin/tar"))
                      ((symbol-function 'kuro-module--platform-string)
                       (lambda (&rest _) "x86_64-unknown-linux-gnu"))
                      ((symbol-function 'kuro-module--target-path)
                       (lambda () tmpdir))
                      ((symbol-function 'make-temp-file)
                       (lambda (&rest _) tmp-tar))
                      ((symbol-function 'url-retrieve-synchronously)
                       (lambda (url &rest _)
                         (when (string-suffix-p ".sha256" url) sha-buf)))
                      ((symbol-function 'message) #'ignore))
              (should (string-match-p "malformed HTTP response"
                                      (error-message-string
                                       (should-error (kuro-module-download "0.0.0")
                                                     :type 'error))))))
        (ignore-errors (kill-buffer sha-buf))))))

;;; Group 22: kuro-module-build error paths

(ert-deftest kuro-module-test--install-built-library-copies-with-private-mode ()
  "`kuro-module--install-built-library' installs cargo output with strict modes."
  (let* ((root (make-temp-file "kuro-module-built-ok-" t))
         (target (expand-file-name "target" root))
         (library (kuro-module--shared-library-name))
         (built (expand-file-name library root))
         (dest (expand-file-name library target)))
    (unwind-protect
        (progn
          (write-region "binary" nil built nil 'silent)
          (should (equal (kuro-module--install-built-library built dest) dest))
          (should (= (logand (file-modes target) #o777) #o700))
          (should (= (logand (file-modes dest) #o777) #o600))
          (with-temp-buffer
            (insert-file-contents-literally dest)
            (should (equal (buffer-string) "binary"))))
      (when (file-exists-p root)
        (delete-directory root t)))))

(ert-deftest kuro-module-test--install-built-library-rejects-symlink-source ()
  "`kuro-module--install-built-library' rejects a symlinked cargo output file."
  (skip-unless (fboundp 'make-symbolic-link))
  (let* ((root (make-temp-file "kuro-module-built-source-link-" t))
         (target (expand-file-name "target" root))
         (library (kuro-module--shared-library-name))
         (real (expand-file-name "real-lib" root))
         (built (expand-file-name library root))
         (dest (expand-file-name library target)))
    (unwind-protect
        (progn
          (write-region "binary" nil real nil 'silent)
          (make-symbolic-link real built)
          (should (string-match-p "native module source must not be a symlink"
                                  (cadr (should-error
                                         (kuro-module--install-built-library
                                          built dest)
                                         :type 'error)))))
      (when (file-exists-p root)
        (delete-directory root t)))))

(ert-deftest kuro-module-test--install-built-library-rejects-destination-symlink ()
  "`kuro-module--install-built-library' rejects a symlinked install file."
  (skip-unless (fboundp 'make-symbolic-link))
  (let* ((root (make-temp-file "kuro-module-built-dest-link-" t))
         (target (expand-file-name "target" root))
         (library (kuro-module--shared-library-name))
         (built (expand-file-name library root))
         (dest (expand-file-name library target))
         (victim (expand-file-name "victim" root)))
    (unwind-protect
        (progn
          (make-directory target t)
          (write-region "binary" nil built nil 'silent)
          (write-region "victim" nil victim nil 'silent)
          (make-symbolic-link victim dest)
          (should (string-match-p "destination must not be a symlink"
                                  (cadr (should-error
                                         (kuro-module--install-built-library
                                          built dest)
                                         :type 'error))))
          (with-temp-buffer
            (insert-file-contents-literally victim)
            (should (equal (buffer-string) "victim"))))
      (when (file-exists-p root)
        (delete-directory root t)))))

(ert-deftest kuro-module-test--build-cargo-toml-not-found ()
  "`kuro-module-build' errors when `kuro-module--locate-cargo-toml' returns nil."
  (cl-letf (((symbol-function 'kuro-module--locate-cargo-toml) (lambda () nil)))
    (should (string-match-p "rust-core not found alongside"
                            (error-message-string
                             (should-error (kuro-module-build) :type 'error))))))

(ert-deftest kuro-module-test--build-cargo-not-found ()
  "`kuro-module-build' errors when `cargo' is not found in PATH."
  (cl-letf (((symbol-function 'kuro-module--locate-cargo-toml)
             (lambda () "/fake/rust-core/Cargo.toml"))
            ((symbol-function 'file-exists-p)
             (lambda (p) (equal p "/fake/rust-core/Cargo.toml")))
            ((symbol-function 'executable-find) (lambda (_cmd) nil)))
    (should (string-match-p "executable not found"
                            (error-message-string
                             (should-error (kuro-module-build) :type 'error))))))

(ert-deftest kuro-module-test--build-cargo-build-fails ()
  "`kuro-module-build' errors and pops to buffer when cargo exits with nonzero."
  (let ((pop-called nil))
    (cl-letf (((symbol-function 'kuro-module--locate-cargo-toml)
               (lambda () "/fake/rust-core/Cargo.toml"))
              ((symbol-function 'executable-find)
               (lambda (_cmd) "/usr/bin/cargo"))
              ((symbol-function 'call-process)
               (lambda (&rest _) 1))
              ((symbol-function 'pop-to-buffer)
               (lambda (_buf) (setq pop-called t)))
              ((symbol-function 'message) #'ignore))
      (should (string-match-p "cargo build failed"
                              (error-message-string
                               (should-error (kuro-module-build) :type 'error))))
      (should pop-called))))

(ert-deftest kuro-module-test--build-lib-missing-after-build ()
  "`kuro-module-build' errors when cargo exits 0 but the built lib path is absent."
  (cl-letf (((symbol-function 'kuro-module--locate-cargo-toml)
             (lambda () "/fake/rust-core/Cargo.toml"))
            ((symbol-function 'executable-find)
             (lambda (_cmd) "/usr/bin/cargo"))
            ((symbol-function 'call-process)
             (lambda (&rest _) 0))
            ;; file-exists-p: always returns nil so built lib appears missing
            ((symbol-function 'file-exists-p)
             (lambda (_p) nil))
            ((symbol-function 'kuro-module--target-path)
             (lambda () "/fake/target-dir"))
            ((symbol-function 'message) #'ignore))
    (should (string-match-p "cargo reported success but"
                            (error-message-string
                             (should-error (kuro-module-build) :type 'error))))))

;;; Group 23: kuro-module--verify-sha256 — dedicated coverage

(ert-deftest kuro-module-test--verify-sha256-raw-string-errors ()
  "`kuro-module--verify-sha256' rejects unparsed expected digest strings."
  (kuro-module-test--with-temp-file (tmpfile "kuro-verify-raw-")
    (with-temp-file tmpfile (insert "content"))
    (should (string-match-p
             "expected SHA256 must be a validated digest object"
             (cadr (should-error
                    (kuro-module--verify-sha256 tmpfile (make-string 64 ?0))
                    :type 'error))))))

(ert-deftest kuro-module-test--parse-sha256-rejects-malformed-digest ()
  "`kuro-module--parse-sha256' rejects malformed expected digest strings."
  (should (string-match-p
           "invalid SHA256"
           (cadr (should-error
                  (kuro-module--parse-sha256 "not-a-sha256" "test digest")
                  :type 'error)))))

(ert-deftest kuro-module-test--verify-sha256-matching-hash-returns-t ()
  "`kuro-module--verify-sha256' returns t when the file hash matches exactly."
  (kuro-module-test--with-temp-file (tmpfile "kuro-verify-match-")
    (with-temp-file tmpfile (insert "kuro test content"))
    (let ((hash (with-temp-buffer
                  (set-buffer-multibyte nil)
                  (insert-file-contents-literally tmpfile)
                  (secure-hash 'sha256 (current-buffer)))))
      (should (kuro-module--verify-sha256
               tmpfile
               (kuro-module--parse-sha256 hash "test digest"))))))

(ert-deftest kuro-module-test--verify-sha256-mismatched-hash-returns-nil ()
  "`kuro-module--verify-sha256' returns nil when the expected hash does not match."
  (kuro-module-test--with-temp-file (tmpfile "kuro-verify-mismatch-")
    (with-temp-file tmpfile (insert "kuro test content"))
    (should-not
     (kuro-module--verify-sha256
      tmpfile
      (kuro-module--parse-sha256
       "0000000000000000000000000000000000000000000000000000000000000000"
       "test digest")))))

;;; Group 24: kuro--ensure-module-loaded error path

(ert-deftest kuro-module-test--ensure-module-loaded-errors-when-load-fails ()
  "`kuro--ensure-module-loaded' signals error containing \"native module could not be loaded\"
when `kuro-module-load' runs but `kuro-core-init' remains unbound."
  (let ((was-bound (fboundp 'kuro-core-init)))
    (when was-bound (fmakunbound 'kuro-core-init))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-module-load) #'ignore))
          (should (string-match-p "native module could not be loaded"
                                  (error-message-string
                                   (should-error (kuro--ensure-module-loaded)
                                                 :type 'error)))))
      (when was-bound
        (fset 'kuro-core-init (lambda () nil))))))

(provide 'kuro-module-test-2)

;;; kuro-module-test-2.el ends here
