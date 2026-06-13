;;; kuro-input-encode-test.el --- Tests for named-key-sequences and encode-key-event  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-input.el — Groups 14-15.
;; Groups 1-13 are in kuro-input-test.el and kuro-input-test-2.el.

;;; Code:
(require 'kuro-input-test-support)

;;; Group 14: kuro--named-key-sequences data table

(ert-deftest kuro-input-named-key-sequences-is-alist ()
  "kuro--named-key-sequences is a non-empty alist of (symbol . string) pairs."
  (should (consp kuro--named-key-sequences))
  (dolist (entry kuro--named-key-sequences)
    (should (symbolp (car entry)))
    (should (stringp (cdr entry)))))

(ert-deftest kuro-input-named-key-return-maps-to-cr ()
  "kuro--named-key-sequences maps `return' to carriage return."
  (should (equal (cdr (assq 'return kuro--named-key-sequences)) "\r")))

(ert-deftest kuro-input-named-key-tab-maps-to-ht ()
  "kuro--named-key-sequences maps `tab' to horizontal tab."
  (should (equal (cdr (assq 'tab kuro--named-key-sequences)) "\t")))

(ert-deftest kuro-input-named-key-backspace-maps-to-del ()
  "kuro--named-key-sequences maps `backspace' to DEL (\\x7f)."
  (should (equal (cdr (assq 'backspace kuro--named-key-sequences)) "\x7f")))

(ert-deftest kuro-input-named-key-escape-maps-to-esc ()
  "kuro--named-key-sequences maps `escape' to ESC (\\e)."
  (should (equal (cdr (assq 'escape kuro--named-key-sequences)) "\e")))

;;; Group 15: kuro--encode-key-event

(ert-deftest kuro-input-encode-key-ctrl-meta-char ()
  "Control+Meta+char encodes as ESC + control byte (C-M-a → ESC ^A)."
  ;; Simulate C-M-a: modifiers=(control meta), base=?a
  (let ((event (list 'C-M-a)))
    (cl-letf (((symbol-function 'event-modifiers)
               (lambda (_ev) '(control meta)))
              ((symbol-function 'event-basic-type)
               (lambda (_ev) ?a)))
      (should (equal (kuro--encode-key-event event)
                     (string ?\e (logand ?a 31)))))))

(ert-deftest kuro-input-encode-key-ctrl-char ()
  "Control+char encodes as a single control byte (C-a → ^A = \\x01)."
  (let ((event 'C-a))
    (cl-letf (((symbol-function 'event-modifiers)
               (lambda (_ev) '(control)))
              ((symbol-function 'event-basic-type)
               (lambda (_ev) ?a)))
      (should (equal (kuro--encode-key-event event)
                     (string (logand ?a 31)))))))

(ert-deftest kuro-input-encode-key-meta-char ()
  "Meta+char encodes as ESC + the base character (M-a → ESC a)."
  (let ((event 'M-a))
    (cl-letf (((symbol-function 'event-modifiers)
               (lambda (_ev) '(meta)))
              ((symbol-function 'event-basic-type)
               (lambda (_ev) ?a)))
      (should (equal (kuro--encode-key-event event)
                     (string ?\e ?a))))))

(ert-deftest kuro-input-encode-key-plain-char ()
  "Plain character encodes as itself."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) ?z)))
    (should (equal (kuro--encode-key-event 'z) (string ?z)))))

(ert-deftest kuro-input-encode-key-return ()
  "Named key `return' encodes as carriage return."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'return)))
    (should (equal (kuro--encode-key-event 'return) "\r"))))

(ert-deftest kuro-input-encode-key-tab ()
  "Named key `tab' encodes as horizontal tab."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'tab)))
    (should (equal (kuro--encode-key-event 'tab) "\t"))))

(ert-deftest kuro-input-encode-key-backspace ()
  "Named key `backspace' encodes as DEL (\\x7f)."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'backspace)))
    (should (equal (kuro--encode-key-event 'backspace) "\x7f"))))

(ert-deftest kuro-input-encode-key-escape ()
  "Named key `escape' encodes as ESC."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'escape)))
    (should (equal (kuro--encode-key-event 'escape) "\e"))))

(ert-deftest kuro-input-encode-key-unsupported-returns-nil ()
  "An unrecognised key symbol encodes as nil."
  (cl-letf (((symbol-function 'event-modifiers) (lambda (_ev) nil))
            ((symbol-function 'event-basic-type) (lambda (_ev) 'f13)))
    (should-not (kuro--encode-key-event 'f13))))


(provide 'kuro-input-encode-test)
;;; kuro-input-encode-test.el ends here
