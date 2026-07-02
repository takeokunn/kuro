;;; kuro-url-detect-test-cases.el --- Case data for kuro-url-detect tests  -*- lexical-binding: t; -*-

;;; Code:

(eval-and-compile
  (defconst kuro-url-detect-test--url-match-cases
    '((kuro-url-detect--regexp-matches-http "http://example.com")
      (kuro-url-detect--regexp-matches-https "https://example.com")
      (kuro-url-detect--regexp-matches-url-with-path
       "https://example.com/path/to/page")
      (kuro-url-detect--regexp-matches-url-with-query
       "https://example.com/search?q=test&page=1")
      (kuro-url-detect--regexp-matches-bracketed-ipv6
       "https://[2001:db8::1]/path"))
    "Table: (test-name url) for `kuro--url-regexp' match tests.")

  (defconst kuro-url-detect-test--trailing-punctuation-cases
    '((kuro-url-detect--regexp-excludes-trailing-period
       "Visit https://example.com." "https://example.com")
      (kuro-url-detect--regexp-excludes-trailing-comma
       "See https://example.com, then" "https://example.com")
      (kuro-url-detect--regexp-excludes-trailing-exclamation
       "Check https://example.com!" "https://example.com"))
    "Table: (test-name input expected) for trailing punctuation tests.")

  (defconst kuro-url-detect-test--defcustom-default-cases
    '((kuro-url-detect--url-detection-default-t
       kuro-url-detection t eq)
      (kuro-url-detect--detection-delay-default
       kuro-url-detection-delay 0.5 =))
    "Table: (test-name variable expected predicate) for defcustom defaults.")

  (defconst kuro-url-detect-test--detection-flag-table
    '((kuro-url-detect--visible-proceeds-when-url-detection-enabled t))
    "Table: (test-name url-flag) for visible scan tests."))

(provide 'kuro-url-detect-test-cases)
;;; kuro-url-detect-test-cases.el ends here
