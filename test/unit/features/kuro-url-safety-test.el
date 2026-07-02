;;; kuro-url-safety-test.el --- Unit tests for kuro-url-safety.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for terminal-originated browser target validation.

;;; Code:

(require 'ert)

(let* ((this-dir (file-name-directory
                  (or load-file-name buffer-file-name default-directory)))
       (features-dir (expand-file-name "../../../emacs-lisp/features" this-dir)))
  (add-to-list 'load-path features-dir t))

(require 'kuro-url-safety)

(ert-deftest kuro-url-safety--accepts-strict-web-urls ()
  "`kuro--terminal-web-url-valid-p' accepts strict HTTP(S) authority URLs."
  (dolist (url '("https://example.com"
                 "http://example.com"
                 "https://sub.example.com/path?x=1#fragment"
                 "http://example.com:8080/path"
                 "https://192.0.2.1/path"
                 "https://[::]/"
                 "https://[::1]:443/path"
                 "https://[1:2:3:4:5:6:7:8]/path"
                 "https://[::ffff:192.0.2.128]/path"
                 "https://[2001:db8::1]/path"))
    (should (kuro--terminal-web-url-valid-p url))))

(ert-deftest kuro-url-safety--rejects-unsafe-browser-targets ()
  "`kuro--terminal-web-url-valid-p' rejects non-web and malformed URLs."
  (dolist (url '(nil
                 42
                 ""
                 "ftp://example.com/file"
                 "mailto:test@example.com"
                 "file:///etc/passwd"
                 "data:text/html,<h1>hi</h1>"
                 "javascript:alert(1)"
                 "https:///path"
                 "https:path"
                 "https://user@example.com"
                 "https://user:pass@example.com"
                 "https://example.com/bad path"
                 "https://example.com/bad\npath"
                 "https://example.com/bad\"path"
                 "https://example.com/path|x"
                 "https://example.com/<bad>"
                 "https://example.com:bad/path"
                 "https://example.com:0/path"
                 "https://example.com:999999/path"
                 "https://dead:beef/path"
                 "https://999.999.999.999/path"
                 "https://127.1/path"
                 "https://01.02.03.04/path"
                 "https://2130706433/path"
                 "https://example.123/path"
                 "https://[dead:beef]/path"
                 "https://[:::]/path"
                 "https://[2001:db8:::1]/path"
                 "https://[2001:db8::1::2]/path"
                 "https://[2001:db8::zz]/path"
                 "https://[2001:db8::1%25lo0]/path"
                 "https://[]/path"
                 "https://[1:2:3:4:5:6:7]/path"
                 "https://[1:2:3:4:5:6:7:8:9]/path"
                 "https://[::ffff:999.0.2.1]/path"
                 "https://bad_host.example"))
    (should-not (kuro--terminal-web-url-valid-p url))))

(ert-deftest kuro-url-safety--target-summary-handles-non-strings ()
  "`kuro--terminal-web-url-target-summary' never assumes string input."
  (should (string-match-p "42" (kuro--terminal-web-url-target-summary 42)))
  (should (stringp (kuro--terminal-web-url-target-summary nil))))

(ert-deftest kuro-url-safety--allowed-schemes-are-web-only ()
  "`kuro--terminal-web-url-allowed-schemes' contains only browser-safe web schemes."
  (should (member "https" kuro--terminal-web-url-allowed-schemes))
  (should (member "http" kuro--terminal-web-url-allowed-schemes))
  (should-not (member "file" kuro--terminal-web-url-allowed-schemes))
  (should-not (member "ftp" kuro--terminal-web-url-allowed-schemes))
  (should-not (member "mailto" kuro--terminal-web-url-allowed-schemes))
  (should-not (member "javascript" kuro--terminal-web-url-allowed-schemes)))

(provide 'kuro-url-safety-test)

;;; kuro-url-safety-test.el ends here
