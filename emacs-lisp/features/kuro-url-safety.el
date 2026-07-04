;;; kuro-url-safety.el --- Terminal-originated web URL validation for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; Shared validation for URLs that come from terminal output and may be
;; opened in an external browser.  Terminal output is untrusted input, so this
;; module accepts only explicit HTTP(S) authority-form URLs.

;;; Code:

(require 'cl-lib)
(require 'url-parse)

(defconst kuro--terminal-web-url-allowed-schemes '("https" "http")
  "Schemes that terminal-originated browser targets may use.")

(defconst kuro--terminal-web-url-unsafe-characters-regexp
  "[[:cntrl:][:space:]\"'`<>{}|\\\\^]"
  "Raw URL characters that terminal-originated browser targets may not contain.")

(defun kuro--terminal-web-url-characters-valid-p (url)
  "Return non-nil when URL has no raw unsafe characters."
  (and (stringp url)
       (not (string-match-p kuro--terminal-web-url-unsafe-characters-regexp
                            url))))

(defun kuro--terminal-web-url-port-valid-p (port)
  "Return non-nil when PORT is absent or a valid TCP port."
  (or (null port)
      (and (integerp port)
           (<= 1 port)
           (<= port 65535))))

(defun kuro--terminal-web-url-dns-label-valid-p (label)
  "Return non-nil when LABEL is a strict ASCII DNS label."
  (let ((len (length label)))
    (and (<= 1 len)
         (<= len 63)
         (string-match-p
          "\\`[A-Za-z0-9]\\(?:[A-Za-z0-9-]*[A-Za-z0-9]\\)?\\'"
          label))))

(defun kuro--terminal-web-url-dns-host-valid-p (host)
  "Return non-nil when HOST is a strict ASCII DNS hostname."
  (let ((labels (and (stringp host)
                     (split-string host "\\." t))))
    (and labels
         (<= 1 (length host))
         (<= (length host) 253)
         (not (string-match-p "\\`\\.\\|\\.\\'" host))
         (not (string-match-p "\\.\\." host))
         (cl-every #'kuro--terminal-web-url-dns-label-valid-p labels)
         (string-match-p "[A-Za-z]" (car (last labels))))))

(defun kuro--terminal-web-url-ipv4-looking-p (host)
  "Return non-nil when HOST is made only of IPv4-literal characters."
  (and (stringp host)
       (string-match-p "\\`[0-9.]+\\'" host)))

(defun kuro--terminal-web-url-decimal-octet-valid-p (octet)
  "Return non-nil when OCTET is a canonical decimal IPv4 octet."
  (and (stringp octet)
       (string-match-p "\\`\\(?:0\\|[1-9][0-9]\\{0,2\\}\\)\\'" octet)
       (<= (string-to-number octet) 255)))

(defun kuro--terminal-web-url-ipv4-address-valid-p (host)
  "Return non-nil when HOST is a canonical dotted-quad IPv4 literal."
  (and (kuro--terminal-web-url-ipv4-looking-p host)
       (let ((octets (split-string host "\\." nil)))
         (and (= (length octets) 4)
              (cl-every #'kuro--terminal-web-url-decimal-octet-valid-p
                        octets)))))

(defun kuro--terminal-web-url-ipv6-h16-valid-p (group)
  "Return non-nil when GROUP is an IPv6 h16 group."
  (and (stringp group)
       (string-match-p "\\`[0-9A-Fa-f]\\{1,4\\}\\'" group)))

(defun kuro--terminal-web-url-ipv6-split-side (side)
  "Split one side of an IPv6 address around colons."
  (if (string= side "")
      nil
    (split-string side ":" nil)))

(defun kuro--terminal-web-url-ipv6-group-count (groups allow-ipv4-at-end)
  "Return IPv6 GROUPS width, or nil when GROUPS are malformed.

When ALLOW-IPV4-AT-END is non-nil, the final group may be a canonical
IPv4 dotted quad and counts as two IPv6 groups."
  (let ((count 0)
        (valid t)
        (remaining groups))
    (while (and valid remaining)
      (let* ((group (car remaining))
             (last-group (null (cdr remaining)))
             (embedded-ipv4 (string-match-p "\\." group)))
        (cond
         ((string= group "")
          (setq valid nil))
         ((and embedded-ipv4
               allow-ipv4-at-end
               last-group
               (kuro--terminal-web-url-ipv4-address-valid-p group))
          (setq count (+ count 2)))
         (embedded-ipv4
          (setq valid nil))
         ((kuro--terminal-web-url-ipv6-h16-valid-p group)
          (setq count (1+ count)))
         (t
          (setq valid nil))))
      (setq remaining (cdr remaining)))
    (and valid count)))

(defun kuro--terminal-web-url-ipv6-address-valid-p (address)
  "Return non-nil when ADDRESS is a strict IPv6 literal."
  (and (stringp address)
       (not (string= address ""))
       (not (string-match-p "[^0-9A-Fa-f:.]" address))
       (let ((double-colon (string-match "::" address)))
         (if double-colon
             (let ((double-colon-end (match-end 0)))
               (and (not (string-match "::" address double-colon-end))
                    (let* ((left (substring address 0 double-colon))
                           (right (substring address double-colon-end))
                           (left-groups
                            (kuro--terminal-web-url-ipv6-split-side left))
                           (right-groups
                            (kuro--terminal-web-url-ipv6-split-side right))
                           (left-count
                            (kuro--terminal-web-url-ipv6-group-count
                             left-groups nil))
                           (right-count
                            (kuro--terminal-web-url-ipv6-group-count
                             right-groups t)))
                      (and left-count
                           right-count
                           (< (+ left-count right-count) 8)))))
           (let* ((groups (split-string address ":" nil))
                  (count (kuro--terminal-web-url-ipv6-group-count
                          groups t)))
             (and count (= count 8)))))))

(defun kuro--terminal-web-url-ipv6-host-valid-p (host)
  "Return non-nil when HOST is a bracketed IPv6 literal."
  (and (stringp host)
       (string-match-p "\\`\\[[0-9A-Fa-f:.]+\\]\\'" host)
       (kuro--terminal-web-url-ipv6-address-valid-p
        (substring host 1 (1- (length host))))))

(defun kuro--terminal-web-url-host-valid-p (host)
  "Return non-nil when HOST parsed from URL is acceptable."
  (and (stringp host)
       (not (string= host ""))
       (not (string-match-p "[[:cntrl:][:space:]/@\\\\]" host))
       (cond
        ((kuro--terminal-web-url-ipv6-host-valid-p host)
         t)
        ((string-match-p "[][]\\|:" host)
         nil)
        ((kuro--terminal-web-url-ipv4-looking-p host)
         (kuro--terminal-web-url-ipv4-address-valid-p host))
        (t
         (kuro--terminal-web-url-dns-host-valid-p host)))))

(defun kuro--terminal-web-url-target-summary (url)
  "Return a safe short display string for rejected URL."
  (truncate-string-to-width
   (if (stringp url) url (format "%S" url))
   80))

(defun kuro--terminal-web-url-valid-p (url)
  "Return non-nil when URL is a strict HTTP(S) browser target.

The accepted shape is `https://HOST...' or `http://HOST...' with no
userinfo, no raw unsafe characters, a valid host, and either no port or a
numeric TCP port in the range 1..65535."
  (and (stringp url)
       (kuro--terminal-web-url-characters-valid-p url)
       (string-match-p "\\`https?://" url)
       (condition-case nil
           (let* ((parsed (url-generic-parse-url url))
                  (scheme (url-type parsed))
                  (host (url-host parsed))
                  (port (url-portspec parsed)))
             (and (member scheme kuro--terminal-web-url-allowed-schemes)
                   (kuro--terminal-web-url-host-valid-p host)
                   (null (url-user parsed))
                   (null (url-password parsed))
                   (kuro--terminal-web-url-port-valid-p port)))
         (error nil))))

(provide 'kuro-url-safety)

;;; kuro-url-safety.el ends here
