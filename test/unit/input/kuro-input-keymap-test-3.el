;;; kuro-input-keymap-test-3.el --- kuro-input-keymap.el tests (3) -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-keymap-test-support)

;;; Group 10: kuro--keymap-setup-special — C-m, C-i, C-h, DEL aliases

(kuro-input-keymap-test--deftest-built-binding-cases)


;;; Group 11: kuro-keymap-exceptions — exception removal clears binding

(ert-deftest kuro-input-keymap-exception-removes-binding ()
  "A key listed in kuro-keymap-exceptions is absent from the built keymap."
  (let* ((kuro-keymap-exceptions '("M-x"))
         (orig kuro--keymap)
         (kuro--keymap (copy-tree orig)))
    (kuro--build-keymap)
    (should-not (lookup-key kuro--keymap (kbd "M-x")))))

(ert-deftest kuro-input-keymap-exception-also-clears-esc-prefix-fallback ()
  "A M-CHAR exception also clears the ESC+char two-key fallback vector binding."
  (let* ((kuro-keymap-exceptions '("M-b"))
         (orig kuro--keymap)
         (kuro--keymap (copy-tree orig)))
    (kuro--build-keymap)
    (should-not (lookup-key kuro--keymap (kbd "M-b")))
    ;; The raw [\e ?b] two-key form must also be cleared
    (should-not (lookup-key kuro--keymap (vector ?\e ?b)))))


;;; Group 12: kuro--send-meta-backspace behavior

(ert-deftest kuro-input-keymap-send-meta-backspace-sends-esc-del ()
  "`kuro--send-meta-backspace' sends ESC+DEL (\\e\\x7f) via kuro--send-key."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (value) (push value sent))))
      (kuro--send-meta-backspace)
      (should (equal (car sent) (string ?\e ?\x7f))))))

(ert-deftest kuro-input-keymap-send-meta-backspace-schedules-render ()
  "`kuro--send-meta-backspace' calls `kuro--schedule-immediate-render'."
  (let ((render-called nil))
    (cl-letf (((symbol-function 'kuro--send-key) (lambda (_) nil))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () (setq render-called t))))
      (kuro--send-meta-backspace)
      (should render-called))))

;;; Group 13: ctrl setup — escape sends byte 27; selected ctrl bytes

(kuro-input-keymap-test--deftest-built-send-cases)

(ert-deftest kuro-input-keymap-ctrl-all-entries-have-live-binding ()
  "Every entry in kuro--ctrl-key-table corresponds to a live keymap binding."
  (kuro-input-keymap-test--with-built-map map
    (kuro-input-keymap-test--each-entry
     kuro--ctrl-key-table
     (lambda (entry)
       (should (lookup-key map (kbd (car entry))))))))


;;; Group 14: meta loop — M-digit and ESC+letter two-key fallbacks

(kuro-input-keymap-test--deftest-built-live-binding-cases
  kuro-input-keymap-m-0-is-bound
  kuro-input-keymap-m-9-is-bound
  kuro-input-keymap-esc-letter-two-key-fallback-is-bound
  kuro-input-keymap-esc-letter-two-key-upper-fallback-is-bound)

;;; kuro-input-keymap-test-3.el ends here
