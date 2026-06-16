;;; kuro-input-test-cases.el --- Data cases for kuro-input unit tests  -*- lexical-binding: t; -*-

;;; Commentary:
;; Shared test case data for kuro-input.el unit tests.

;;; Code:

(defconst kuro-input-test--named-key-sequence-cases
  '((kuro-input-named-key-return-maps-to-cr return "\r")
    (kuro-input-named-key-tab-maps-to-ht tab "\t")
    (kuro-input-named-key-backspace-maps-to-del backspace "\x7f")
    (kuro-input-named-key-escape-maps-to-esc escape "\e"))
  "Named-key sequence lookup test cases.
Each entry is (TEST-NAME KEY EXPECTED-SEQUENCE).")

(defconst kuro-input-test--encode-key-event-cases
  '((kuro-input-encode-key-ctrl-meta-char
     (C-M-a) (control meta) ?a "\e\1")
    (kuro-input-encode-key-ctrl-char
     C-a (control) ?a "\1")
    (kuro-input-encode-key-meta-char
     M-a (meta) ?a "\ea")
    (kuro-input-encode-key-plain-char
     z nil ?z "z")
    (kuro-input-encode-key-return
     return nil return "\r")
    (kuro-input-encode-key-tab
     tab nil tab "\t")
    (kuro-input-encode-key-backspace
     backspace nil backspace "\x7f")
    (kuro-input-encode-key-escape
     escape nil escape "\e")
    (kuro-input-encode-key-unsupported-returns-nil
     f13 nil f13 nil))
  "Key event encoding cases.
Each entry is (TEST-NAME EVENT MODIFIERS BASIC-TYPE EXPECTED).")

(provide 'kuro-input-test-cases)
;;; kuro-input-test-cases.el ends here
