;;; kuro-module-test-2.el --- ERT tests for kuro-module.el (part 2)  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(unless (fboundp 'module-load)
  (fset 'module-load (lambda (_path) nil)))

(require 'kuro-config)
(require 'kuro-module)

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
  (let ((tmpfile (make-temp-file "kuro-hash-")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile (insert "hello kuro"))
          (let ((expected (with-temp-buffer
                            (set-buffer-multibyte nil)
                            (insert-file-contents-literally tmpfile)
                            (secure-hash 'sha256 (current-buffer)))))
            (should (kuro-module--verify-sha256 tmpfile expected))))
      (delete-file tmpfile))))

(ert-deftest kuro-module-test--verify-sha256-mismatch-rejects ()
  "`kuro-module--verify-sha256' returns nil when the digest does not match."
  (let ((tmpfile (make-temp-file "kuro-hash-")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile (insert "hello kuro"))
          (should-not
           (kuro-module--verify-sha256
            tmpfile
            "0000000000000000000000000000000000000000000000000000000000000000")))
      (delete-file tmpfile))))

(ert-deftest kuro-module-test--verify-sha256-nil-hash-warns-and-passes ()
  "`kuro-module--verify-sha256' returns t when EXPECTED-HASH is nil and emits a warning."
  (let ((tmpfile (make-temp-file "kuro-hash-"))
        (warned nil))
    (unwind-protect
        (cl-letf (((symbol-function 'display-warning)
                   (lambda (&rest _args) (setq warned t))))
          (with-temp-file tmpfile (insert "hello kuro"))
          (should (kuro-module--verify-sha256 tmpfile nil))
          (should warned))
      (delete-file tmpfile))))

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
  (let* ((tmpdir (make-temp-file "kuro-xdg-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'getenv)
                   (lambda (var)
                     (if (equal var "XDG_DATA_HOME") tmpdir (getenv var)))))
          (let ((dir (kuro-module--target-path)))
            (should (equal dir (expand-file-name "kuro" tmpdir)))
            (should (file-directory-p dir))))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-test--target-path-creates-directory ()
  "`kuro-module--target-path' creates the install directory if it is missing."
  (let* ((tmpdir (make-temp-file "kuro-xdg-" t))
         (target (expand-file-name "kuro" tmpdir)))
    (unwind-protect
        (cl-letf (((symbol-function 'getenv)
                   (lambda (var)
                     (if (equal var "XDG_DATA_HOME") tmpdir (getenv var)))))
          (should-not (file-directory-p target))
          (kuro-module--target-path)
          (should (file-directory-p target)))
      (delete-directory tmpdir t))))

;;; Group 21: kuro-module-download error paths

(ert-deftest kuro-module-test--download-tar-not-found ()
  "`kuro-module-download' errors when `tar' is not found in PATH."
  (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) nil)))
    (should (string-match-p "executable not found"
                            (cadr (should-error (kuro-module-download "0.0.0")
                                                :type 'error))))))

(ert-deftest kuro-module-test--download-sha256-fetch-fails ()
  "`kuro-module-download' errors when the .sha256 URL fetch returns nil."
  (cl-letf (((symbol-function 'executable-find) (lambda (_cmd) "/usr/bin/tar"))
            ((symbol-function 'kuro-module--platform-string)
             (lambda (&rest _) "x86_64-unknown-linux-gnu"))
            ((symbol-function 'kuro-module--target-path)
             (lambda () (make-temp-file "kuro-dl-test-" t)))
            ((symbol-function 'url-retrieve-synchronously) (lambda (&rest _) nil))
            ((symbol-function 'message) #'ignore))
    (should (string-match-p "failed to fetch SHA256"
                            (cadr (should-error (kuro-module-download "0.0.0")
                                                :type 'error))))))

(ert-deftest kuro-module-test--download-sha256-mismatch ()
  "`kuro-module-download' errors when SHA256 computed from file differs from expected."
  (let* ((tmpdir (make-temp-file "kuro-dl-mismatch-" t))
         (tmp-tar (expand-file-name "kuro-test.tar.gz" tmpdir))
         (sha-buf (generate-new-buffer " *kuro-sha-test*")))
    (unwind-protect
        (progn
          ;; Create a fake sha buffer with header + a known hash
          (with-current-buffer sha-buf
            (insert "HTTP/1.1 200 OK\r\n\r\n")
            (insert (make-string 64 ?a)))
          ;; Create a real temp tar file to write into
          (with-temp-file tmp-tar (insert "fake tarball content"))
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
      (ignore-errors (kill-buffer sha-buf))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-test--download-tar-extraction-fails ()
  "`kuro-module-download' errors when tar exits with a nonzero code."
  (let* ((tmpdir (make-temp-file "kuro-dl-tarfail-" t))
         (tmp-tar (expand-file-name "kuro-test.tar.gz" tmpdir))
         (sha-buf (generate-new-buffer " *kuro-sha-tarfail*")))
    (unwind-protect
        (progn
          (with-current-buffer sha-buf
            (insert "HTTP/1.1 200 OK\r\n\r\n")
            (insert (make-string 64 ?a)))
          (with-temp-file tmp-tar (insert "fake"))
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
      (ignore-errors (kill-buffer sha-buf))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-test--download-extracted-binary-missing ()
  "`kuro-module-download' errors when tar succeeds but the extracted file is absent.
Uses a real tmpdir that contains no libkuro_core binary, so file-exists-p
naturally returns nil for the installed-binary check without global stubbing."
  (let* ((tmpdir (make-temp-file "kuro-dl-binmiss-" t))
         (tmp-tar (expand-file-name "kuro-test.tar.gz" tmpdir))
         (sha-buf (generate-new-buffer " *kuro-sha-binmiss*")))
    (unwind-protect
        (progn
          (with-current-buffer sha-buf
            (insert "HTTP/1.1 200 OK\r\n\r\n")
            (insert (make-string 64 ?a)))
          (with-temp-file tmp-tar (insert "fake tarball"))
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
      (ignore-errors (kill-buffer sha-buf))
      (delete-directory tmpdir t))))

(ert-deftest kuro-module-test--download-sha256-malformed-response ()
  "`kuro-module-download' errors when SHA256 HTTP response has no blank-line separator."
  (let* ((tmpdir (make-temp-file "kuro-dl-malformed-" t))
         (tmp-tar (expand-file-name "kuro-test.tar.gz" tmpdir))
         ;; A buffer with no blank line between headers and body
         (sha-buf (generate-new-buffer " *kuro-sha-malformed*")))
    (unwind-protect
        (progn
          (with-current-buffer sha-buf
            (insert "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nabc123"))
          (with-temp-file tmp-tar (insert "fake"))
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
            (should (string-match-p "malformed SHA256 response"
                                    (cadr (should-error (kuro-module-download "0.0.0")
                                                        :type 'error))))))
      (ignore-errors (kill-buffer sha-buf))
      (delete-directory tmpdir t))))

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
  (let ((warned nil)
        (tmpfile (make-temp-file "kuro-verify-nil-")))
    (unwind-protect
        (cl-letf (((symbol-function 'display-warning)
                   (lambda (&rest _) (setq warned t))))
          (with-temp-file tmpfile (insert "content"))
          (should (kuro-module--verify-sha256 tmpfile nil))
          (should warned))
      (delete-file tmpfile))))

(ert-deftest kuro-module-test--verify-sha256-matching-hash-returns-t ()
  "`kuro-module--verify-sha256' returns t when the file hash matches exactly."
  (let ((tmpfile (make-temp-file "kuro-verify-match-")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile (insert "kuro test content"))
          (let ((hash (with-temp-buffer
                        (set-buffer-multibyte nil)
                        (insert-file-contents-literally tmpfile)
                        (secure-hash 'sha256 (current-buffer)))))
            (should (kuro-module--verify-sha256 tmpfile hash))))
      (delete-file tmpfile))))

(ert-deftest kuro-module-test--verify-sha256-mismatched-hash-returns-nil ()
  "`kuro-module--verify-sha256' returns nil when the expected hash does not match."
  (let ((tmpfile (make-temp-file "kuro-verify-mismatch-")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile (insert "kuro test content"))
          (should-not
           (kuro-module--verify-sha256
            tmpfile
            "0000000000000000000000000000000000000000000000000000000000000000")))
      (delete-file tmpfile))))

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
