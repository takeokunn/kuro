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
      (should (kuro-module--verify-sha256 tmpfile expected)))))

(ert-deftest kuro-module-test--verify-sha256-mismatch-rejects ()
  "`kuro-module--verify-sha256' returns nil when the digest does not match."
  (kuro-module-test--with-temp-file (tmpfile "kuro-hash-")
    (with-temp-file tmpfile (insert "hello kuro"))
    (should-not
     (kuro-module--verify-sha256
      tmpfile
      "0000000000000000000000000000000000000000000000000000000000000000"))))

(ert-deftest kuro-module-test--verify-sha256-nil-hash-warns-and-passes ()
  "`kuro-module--verify-sha256' returns t when EXPECTED-HASH is nil and emits a warning."
  (let ((warned nil))
    (kuro-module-test--with-temp-file (tmpfile "kuro-hash-")
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (&rest _args) (setq warned t))))
        (with-temp-file tmpfile (insert "hello kuro"))
        (should (kuro-module--verify-sha256 tmpfile nil))
        (should warned)))))

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

;;; Group 20b: kuro-module installation helper coverage

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
            (should (equal (kuro-module--fetch-sha256 "https://example.test/file.sha256")
                           hash))))
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
              (should (string-match-p "invalid SHA256 in sidecar response"
                                      message)))))
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
                            (cadr (should-error (kuro-module-download "0.0.0")
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
                              (cadr (should-error (kuro-module-download "0.0.0")
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
                                      (cadr (should-error (kuro-module-download "0.0.0")
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
                       (lambda (&rest _) tmp-tar))
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
                      ((symbol-function 'call-process)
                       (lambda (&rest _) 1))
                      ((symbol-function 'delete-file) #'ignore)
                      ((symbol-function 'message) #'ignore))
              (should (string-match-p "tar extraction failed"
                                      (cadr (should-error (kuro-module-download "0.0.0")
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
                       (lambda (&rest _) tmp-tar))
                      ((symbol-function 'url-retrieve-synchronously)
                       (lambda (url &rest _)
                         (if (string-suffix-p ".sha256" url)
                             sha-buf
                           (let ((buf (generate-new-buffer " *kuro-dl-binmiss-body*")))
                             (with-current-buffer buf
                               (insert "HTTP/1.1 200 OK\r\n\r\nfake"))
                             buf))))
                      ;; Verify passes, tar returns 0 — but no binary is extracted
                      ((symbol-function 'kuro-module--verify-sha256)
                       (lambda (_file _hash) t))
                      ((symbol-function 'call-process)
                       (lambda (&rest _) 0))
                      ((symbol-function 'message) #'ignore))
              ;; tmpdir has no libkuro_core.so/.dylib → file-exists-p naturally nil
              (should (string-match-p "extracted archive does not contain"
                                      (cadr (should-error (kuro-module-download "0.0.0")
                                                          :type 'error))))))
        (ignore-errors (kill-buffer sha-buf))))))

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
                                      (cadr (should-error (kuro-module-download "0.0.0")
                                                          :type 'error))))))
        (ignore-errors (kill-buffer sha-buf))))))

;;; Group 22: kuro-module-build error paths

(ert-deftest kuro-module-test--build-cargo-toml-not-found ()
  "`kuro-module-build' errors when `kuro-module--locate-cargo-toml' returns nil."
  (cl-letf (((symbol-function 'kuro-module--locate-cargo-toml) (lambda () nil)))
    (should (string-match-p "rust-core not found alongside"
                            (cadr (should-error (kuro-module-build) :type 'error))))))

(ert-deftest kuro-module-test--build-cargo-not-found ()
  "`kuro-module-build' errors when `cargo' is not found in PATH."
  (cl-letf (((symbol-function 'kuro-module--locate-cargo-toml)
             (lambda () "/fake/rust-core/Cargo.toml"))
            ((symbol-function 'file-exists-p)
             (lambda (p) (equal p "/fake/rust-core/Cargo.toml")))
            ((symbol-function 'executable-find) (lambda (_cmd) nil)))
    (should (string-match-p "executable not found"
                            (cadr (should-error (kuro-module-build) :type 'error))))))

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
                              (cadr (should-error (kuro-module-build) :type 'error))))
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
                            (cadr (should-error (kuro-module-build) :type 'error))))))

;;; Group 23: kuro-module--verify-sha256 — dedicated coverage

(ert-deftest kuro-module-test--verify-sha256-nil-hash-warns-and-returns-t ()
  "`kuro-module--verify-sha256' returns t and calls `display-warning' when hash is nil."
  (let ((warned nil))
    (kuro-module-test--with-temp-file (tmpfile "kuro-verify-nil-")
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (&rest _) (setq warned t))))
        (with-temp-file tmpfile (insert "content"))
        (should (kuro-module--verify-sha256 tmpfile nil))
        (should warned)))))

(ert-deftest kuro-module-test--verify-sha256-matching-hash-returns-t ()
  "`kuro-module--verify-sha256' returns t when the file hash matches exactly."
  (kuro-module-test--with-temp-file (tmpfile "kuro-verify-match-")
    (with-temp-file tmpfile (insert "kuro test content"))
    (let ((hash (with-temp-buffer
                  (set-buffer-multibyte nil)
                  (insert-file-contents-literally tmpfile)
                  (secure-hash 'sha256 (current-buffer)))))
      (should (kuro-module--verify-sha256 tmpfile hash)))))

(ert-deftest kuro-module-test--verify-sha256-mismatched-hash-returns-nil ()
  "`kuro-module--verify-sha256' returns nil when the expected hash does not match."
  (kuro-module-test--with-temp-file (tmpfile "kuro-verify-mismatch-")
    (with-temp-file tmpfile (insert "kuro test content"))
    (should-not
     (kuro-module--verify-sha256
      tmpfile
      "0000000000000000000000000000000000000000000000000000000000000000"))))

;;; Group 24: kuro--ensure-module-loaded error path

(ert-deftest kuro-module-test--ensure-module-loaded-errors-when-load-fails ()
  "`kuro--ensure-module-loaded' signals error containing \"native module could not be loaded\"
when `kuro-module-load' runs but `kuro-core-init' remains unbound."
  (let ((was-bound (fboundp 'kuro-core-init)))
    (when was-bound (fmakunbound 'kuro-core-init))
    (unwind-protect
        (cl-letf (((symbol-function 'kuro-module-load) #'ignore))
          (should (string-match-p "native module could not be loaded"
                                  (cadr (should-error (kuro--ensure-module-loaded)
                                                      :type 'error)))))
      (when was-bound
        (fset 'kuro-core-init (lambda () nil))))))

(provide 'kuro-module-test-2)

;;; kuro-module-test-2.el ends here
