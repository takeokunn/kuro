;;; kuro-module-install.el --- Installation helpers for Kuro native module  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Download/build/install helpers for the Kuro native module.

;;; Code:

(require 'kuro-module-platform)
(require 'subr-x)
(require 'url)

(defun kuro-module--ensure-https-base-url (base-url)
  "Return BASE-URL when it uses https://, otherwise signal an error."
  (unless (string-prefix-p "https://" base-url)
    (error "Kuro: kuro-module-release-base-url must use https://, got: %s"
           base-url))
  base-url)

(defcustom kuro-module-installation-method nil
  "Preferred method for installing the Kuro native module.
When nil, the user is prompted at install time.  Otherwise, must be one of
the symbols `prebuilt' (download from GitHub Releases), `cargo' (build from
source via cargo), or `manual' (the user installs the binary themselves)."
  :group 'kuro
  :type '(choice (const :tag "Prompt" nil)
                 (const :tag "Download prebuilt" prebuilt)
                 (const :tag "Build with cargo" cargo)
                 (const :tag "Manual install" manual)))

(defcustom kuro-module-release-base-url
  "https://github.com/takeokunn/kuro/releases/download"
  "Base URL prefix for constructing prebuilt-artifact download URLs.
Must use the https:// scheme; http:// values are rejected at set time."
  :group 'kuro
  :type 'string
  :set (lambda (sym val)
         (set-default sym (kuro-module--ensure-https-base-url val))))

(defun kuro-module--verify-sha256 (file expected-hash)
  "Return non-nil when FILE matches EXPECTED-HASH (a hex SHA256 digest).
When EXPECTED-HASH is nil, emit a warning via `display-warning' and return t
so that callers can opt in to verification incrementally."
  (cond
   ((null expected-hash)
    (display-warning 'kuro
                     (format "No known SHA256 for %s; skipping verification."
                             file)
                     :warning)
    t)
   (t
    (let ((actual (with-temp-buffer
                    (set-buffer-multibyte nil)
                    (insert-file-contents-literally file)
                    (secure-hash 'sha256 (current-buffer)))))
      (equal actual expected-hash)))))

(defun kuro-module--target-path ()
  "Return the directory in which prebuilt or cargo-built binaries are installed.
Honours XDG_DATA_HOME when set; otherwise defaults to \"~/.local/share\".
Creates the target directory if it does not yet exist."
  (let* ((xdg (getenv "XDG_DATA_HOME"))
         (base (or xdg "~/.local/share"))
         (dir (expand-file-name "kuro" base)))
    (unless (file-directory-p dir)
      (make-directory dir t))
    dir))

(defun kuro-module--shared-library-name ()
  "Return the filename of the native shared library for the current platform."
  (concat "libkuro_core" (kuro-module--shared-extension)))

(defun kuro-module--installed-module-path (target-dir)
  "Return the installed module path under TARGET-DIR."
  (expand-file-name (kuro-module--shared-library-name) target-dir))

(defun kuro-module--release-spec (&optional version)
  "Return release metadata for VERSION as a plist.
VERSION defaults to `kuro-module--version'.  The plist contains :version,
:platform, :tarball, :url, and :sha-url."
  (kuro-module--ensure-https-base-url kuro-module-release-base-url)
  (let* ((ver (or version kuro-module--version))
         (_ (unless (string-match-p "\\`[0-9]+\\.[0-9]+\\.[0-9]+\\'" ver)
              (error "Kuro: invalid version string: %S" ver)))
         (platform (kuro-module--platform-string))
         (tarball (format "libkuro_core-%s-%s.tar.gz" ver platform))
         (url (format "%s/v%s/%s" kuro-module-release-base-url ver tarball))
         (sha-url (format "%s.sha256" url)))
    (list :version ver
          :platform platform
          :tarball tarball
          :url url
          :sha-url sha-url)))

(defun kuro-module--http-response-body-start (source)
  "Return the body start position in the current HTTP response buffer.
SOURCE is used in the error message when the buffer does not contain the
expected blank-line separator."
  (goto-char (point-min))
  (unless (re-search-forward "\r?\n\r?\n" nil t)
    (error "Kuro: malformed HTTP response from %s" source))
  (point))

(defun kuro-module--http-response-body-string (source)
  "Return the HTTP body as a string from the current response buffer."
  (let ((body-start (kuro-module--http-response-body-start source)))
    (buffer-substring-no-properties body-start (point-max))))

(defun kuro-module--fetch-sha256 (sha-url)
  "Fetch the SHA256 digest from SHA-URL and return it as a string."
  (let ((buffer (url-retrieve-synchronously sha-url t t 30)))
    (unless buffer
      (error "Kuro: failed to fetch SHA256 from %s" sha-url))
    (unwind-protect
        (with-current-buffer buffer
          (let ((hash (string-trim (kuro-module--http-response-body-string
                                    sha-url))))
            (unless (string-match-p "\\`[0-9a-f]\\{64\\}\\'" hash)
              (error "Kuro: invalid SHA256 in sidecar response: %S" hash))
            hash))
      (kill-buffer buffer))))

(defun kuro-module--write-http-body-to-file (buffer file source)
  "Write the HTTP body from BUFFER to FILE in binary mode."
  (with-current-buffer buffer
    (let ((body-start (kuro-module--http-response-body-start source))
          (coding-system-for-write 'binary))
      (write-region body-start (point-max) file nil 'silent))))

(defun kuro-module--download-release-archive (url sha-url tmp-file)
  "Download URL to TMP-FILE and verify it against SHA-URL."
  (message "Kuro: fetching checksum from %s" sha-url)
  (let ((expected-hash (kuro-module--fetch-sha256 sha-url)))
    (message "Kuro: downloading %s" url)
    (let ((buffer (url-retrieve-synchronously url t t 300)))
      (unless buffer
        (error "Kuro: download failed for %s" url))
      (unwind-protect
          (kuro-module--write-http-body-to-file buffer tmp-file url)
        (kill-buffer buffer)))
    (unless (kuro-module--verify-sha256 tmp-file expected-hash)
      (error "Kuro: SHA256 mismatch for %s (expected %s)" url expected-hash))))

(defun kuro-module--install-release-archive (tar-bin tmp-file target-dir)
  "Extract TMP-FILE with TAR-BIN into TARGET-DIR and return the installed path."
  (let ((rc (call-process tar-bin nil "*kuro-module-download*" t
                          "-xzf" tmp-file "-C" target-dir)))
    (delete-file tmp-file)
    (unless (zerop rc)
      (error "Kuro: tar extraction failed (exit %d, see *kuro-module-download*)" rc))
    (let ((installed (kuro-module--installed-module-path target-dir)))
      (unless (file-exists-p installed)
        (error "Kuro: extracted archive does not contain %s"
               (kuro-module--shared-library-name)))
      (message "Kuro: installed prebuilt module at %s" installed)
      installed)))

;;;###autoload
(defun kuro-module-download (&optional version)
  "Download a prebuilt libkuro_core matching the current platform.
VERSION is the release tag without the leading \"v\" (defaults to
`kuro-module--version').  The artifact URL is constructed from
`kuro-module-release-base-url' and the platform triple returned by
`kuro-module--platform-string'.

Fetches the accompanying .sha256 sidecar from the same release and
verifies the digest before extraction.  On mismatch, the temp file is
deleted and an error is signalled.  On success, the tarball is extracted
under `kuro-module--target-path' using the system `tar' executable.
Requires `tar' in PATH.  Emacs is unresponsive during the download."
  (interactive)
  (let* ((spec (kuro-module--release-spec version))
         (url (plist-get spec :url))
         (sha-url (plist-get spec :sha-url))
         (tar-bin (executable-find "tar")))
    (unless tar-bin
      (error "Kuro: `tar' executable not found in PATH"))
    (let ((target-dir (kuro-module--target-path))
          (tmp-file (make-temp-file "kuro-module-" nil ".tar.gz")))
      (unwind-protect
          (progn
            (kuro-module--download-release-archive url sha-url tmp-file)
            (kuro-module--install-release-archive tar-bin tmp-file target-dir))
        (when (file-exists-p tmp-file)
          (delete-file tmp-file))))))

(defun kuro-module--locate-cargo-toml ()
  "Locate the rust-core/Cargo.toml sibling of the installed package.
Walks up from the directory containing this file looking for a sibling
\"rust-core/Cargo.toml\".  Returns the absolute path on success, nil
otherwise."
  (let* ((this-file (or load-file-name
                        (locate-library "kuro-module")
                        buffer-file-name))
         (dir (and this-file (file-name-directory this-file)))
         (found nil))
    (while (and dir (not found)
                (not (string= dir (file-name-directory (directory-file-name dir)))))
      (let ((candidate (expand-file-name "rust-core/Cargo.toml" dir)))
        (if (file-exists-p candidate)
            (setq found candidate)
          (setq dir (file-name-directory (directory-file-name dir))))))
    found))

(defun kuro-module--cargo-built-library-path (cargo-toml)
  "Return the expected release artifact path produced from CARGO-TOML."
  (let ((rust-root (file-name-directory cargo-toml))
        (lib-name (kuro-module--shared-library-name)))
    (expand-file-name (concat "target/release/" lib-name) rust-root)))

(defun kuro-module--install-built-library (built dest)
  "Copy BUILT to DEST and return DEST after validating the source exists."
  (unless (file-exists-p built)
    (error "Kuro: cargo reported success but %s is missing" built))
  (copy-file built dest t)
  (message "Kuro: built and installed module at %s" dest)
  dest)

;;;###autoload
(defun kuro-module-build ()
  "Build libkuro_core from source via cargo.
Requires a development checkout: a sibling rust-core/Cargo.toml must be
reachable from the directory containing this file.  Streams cargo output
to the buffer *kuro-module-build*; on success, copies the produced
libkuro_core into `kuro-module--target-path'."
  (interactive)
  (let ((cargo-toml (kuro-module--locate-cargo-toml)))
    (unless cargo-toml
      (error "Kuro: rust-core not found alongside the package.  Run from a development checkout, or use `M-x kuro-module-download'"))
    (let ((cargo-bin (executable-find "cargo")))
      (unless cargo-bin
        (error "Kuro: `cargo' executable not found in PATH"))
      (let* ((buf (get-buffer-create "*kuro-module-build*"))
             (rc (progn
                   (with-current-buffer buf (erase-buffer))
                   (call-process cargo-bin nil buf t
                                 "build" "--release"
                                 "--manifest-path" cargo-toml))))
        (unless (zerop rc)
          (pop-to-buffer buf)
          (error "Kuro: cargo build failed (exit %d, see *kuro-module-build*)" rc))
        (let* ((built (kuro-module--cargo-built-library-path cargo-toml))
               (target-dir (kuro-module--target-path))
               (dest (kuro-module--installed-module-path target-dir)))
          (kuro-module--install-built-library built dest))))))

(provide 'kuro-module-install)
;;; kuro-module-install.el ends here
