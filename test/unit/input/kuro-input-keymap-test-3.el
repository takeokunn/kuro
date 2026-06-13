;;; kuro-input-keymap-test-3.el --- Tests for kuro-input-keymap.el — Groups 10-14  -*- lexical-binding: t; -*-

;;; Code:

(require 'kuro-input-keymap-test-support)

;;; Group 10: kuro--keymap-setup-special — C-m, C-i, C-h, DEL aliases

(ert-deftest kuro-input-keymap-build-c-m-is-ret ()
  "C-m is bound to kuro--RET (same as [return]) in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "C-m")) #'kuro--RET))))

(ert-deftest kuro-input-keymap-build-c-i-is-tab ()
  "C-i is bound to kuro--TAB (same as [tab]) in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "C-i")) #'kuro--TAB))))

(ert-deftest kuro-input-keymap-build-c-h-is-del ()
  "C-h is bound to kuro--DEL (same as [backspace]) in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "C-h")) #'kuro--DEL))))

(ert-deftest kuro-input-keymap-build-del-is-del ()
  "DEL (kbd \"DEL\") is bound to kuro--DEL in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "DEL")) #'kuro--DEL))))


;;; Group 11: kuro-keymap-exceptions — exception removal clears binding

(ert-deftest kuro-input-keymap-exception-removes-binding ()
  "A key listed in kuro-keymap-exceptions is absent from the built keymap."
  (let* ((kuro-keymap-exceptions '("M-x"))
         (orig kuro--keymap)
         (map (unwind-protect
                  (kuro--build-keymap)
                (setq kuro--keymap orig))))
    ;; The binding for M-x must be nil (removed)
    (should-not (lookup-key map (kbd "M-x")))))

(ert-deftest kuro-input-keymap-exception-also-clears-esc-prefix-fallback ()
  "A M-CHAR exception also clears the ESC+char two-key fallback vector binding."
  (let* ((kuro-keymap-exceptions '("M-b"))
         (orig kuro--keymap)
         (map (unwind-protect
                  (kuro--build-keymap)
                (setq kuro--keymap orig))))
    ;; The raw [\e ?b] two-key form must also be cleared
    (should-not (lookup-key map (vector ?\e ?b)))))


;;; Group 12: kuro--send-meta-backspace behavior

(ert-deftest kuro-input-keymap-send-meta-backspace-sends-esc-del ()
  "`kuro--send-meta-backspace' sends ESC+DEL (\\e\\x7f) via kuro--send-key."
  (let ((sent nil))
    (cl-letf (((symbol-function 'kuro--send-key)
               (lambda (s) (push s sent)))
              ((symbol-function 'kuro--schedule-immediate-render)
               (lambda () nil)))
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

(ert-deftest kuro-input-keymap-build-m-del-bound-to-meta-backspace ()
  "M-DEL is bound to `kuro--send-meta-backspace' in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "M-DEL")) #'kuro--send-meta-backspace))))

(ert-deftest kuro-input-keymap-build-m-backspace-bound-to-meta-backspace ()
  "M-<backspace> is bound to `kuro--send-meta-backspace' in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (eq (lookup-key map (kbd "M-<backspace>")) #'kuro--send-meta-backspace))))


;;; Group 13: ctrl setup — escape sends byte 27; selected ctrl bytes

(ert-deftest kuro-input-keymap-escape-sends-ctrl-27 ()
  "[escape] binding sends byte 27 (ESC) via kuro--send-ctrl."
  (let* ((map (kuro-keymap-test--built-map))
         (binding (lookup-key map [escape]))
         (sent nil))
    (should (functionp binding))
    (cl-letf (((symbol-function 'kuro--send-ctrl)
               (lambda (byte) (push byte sent))))
      (funcall binding)
      (should (equal sent '(27))))))

(ert-deftest kuro-input-keymap-c-a-sends-ctrl-1 ()
  "C-a binding sends byte 1 via kuro--send-ctrl."
  (let* ((map (kuro-keymap-test--built-map))
         (binding (lookup-key map (kbd "C-a")))
         (sent nil))
    (should (functionp binding))
    (cl-letf (((symbol-function 'kuro--send-ctrl)
               (lambda (byte) (push byte sent))))
      (funcall binding)
      (should (equal sent '(1))))))

(ert-deftest kuro-input-keymap-c-z-sends-ctrl-26 ()
  "C-z binding sends byte 26 via kuro--send-ctrl."
  (let* ((map (kuro-keymap-test--built-map))
         (binding (lookup-key map (kbd "C-z")))
         (sent nil))
    (should (functionp binding))
    (cl-letf (((symbol-function 'kuro--send-ctrl)
               (lambda (byte) (push byte sent))))
      (funcall binding)
      (should (equal sent '(26))))))

(ert-deftest kuro-input-keymap-ctrl-all-entries-have-live-binding ()
  "Every entry in kuro--ctrl-key-table corresponds to a live keymap binding."
  (let ((map (kuro-keymap-test--built-map)))
    (dolist (entry kuro--ctrl-key-table)
      (should (lookup-key map (kbd (car entry)))))))


;;; Group 14: meta loop — M-digit and ESC+letter two-key fallbacks

(ert-deftest kuro-input-keymap-m-0-is-bound ()
  "M-0 is bound in the built keymap (digit range)."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map (kbd "M-0")))))

(ert-deftest kuro-input-keymap-m-9-is-bound ()
  "M-9 is bound in the built keymap (digit range)."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map (kbd "M-9")))))

(ert-deftest kuro-input-keymap-m-digits-send-correct-char ()
  "M-5 sends character ?5 via kuro--send-meta."
  (let* ((map (kuro-keymap-test--built-map))
         (binding (lookup-key map (kbd "M-5")))
         (sent nil))
    (should (functionp binding))
    (cl-letf (((symbol-function 'kuro--send-meta)
               (lambda (c) (push c sent))))
      (funcall binding)
      (should (equal sent (list ?5))))))

(ert-deftest kuro-input-keymap-esc-letter-two-key-fallback-is-bound ()
  "The raw [\\e ?a] two-key fallback is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map (vector ?\e ?a)))))

(ert-deftest kuro-input-keymap-esc-letter-two-key-sends-correct-char ()
  "The [\\e ?b] binding sends ?b via kuro--send-meta."
  (let* ((map (kuro-keymap-test--built-map))
         (binding (lookup-key map (vector ?\e ?b)))
         (sent nil))
    (should (functionp binding))
    (cl-letf (((symbol-function 'kuro--send-meta)
               (lambda (c) (push c sent))))
      (funcall binding)
      (should (equal sent (list ?b))))))

(ert-deftest kuro-input-keymap-esc-uppercase-letter-two-key-is-bound ()
  "The raw [\\e ?Z] two-key fallback is bound in the built keymap."
  (let ((map (kuro-keymap-test--built-map)))
    (should (lookup-key map (vector ?\e ?Z)))))

(provide 'kuro-input-keymap-test-3)
;;; kuro-input-keymap-test-3.el ends here
