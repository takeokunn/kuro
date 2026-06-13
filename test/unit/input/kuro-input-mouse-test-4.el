;;; kuro-input-mouse-test-4.el --- Mouse input tests Groups 12-15  -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-input-mouse-test-support)

;;; Group 12: kuro--encode-mouse — pixel mode with SGR also set

(ert-deftest kuro-input-mouse-pixel-and-sgr-both-set ()
  "When both pixel-mode and sgr are set, pixel-mode wins: SGR format, no +1 offset."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr t)
    (setq-local kuro--mouse-pixel-mode t)
    (kuro-mouse-test--with-event 150 200
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (equal result "\e[<0;150;200M"))))))

;;; Group 13: kuro--encode-mouse — X10 exact boundary (col1=223, row1=1)

(ert-deftest kuro-input-mouse-x10-col-boundary-222-passes ()
  "X10 col1=223 (posn-col-row=222) is the last valid column."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 222 0
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (stringp result))))))

(ert-deftest kuro-input-mouse-x10-row-boundary-222-passes ()
  "X10 row1=223 (posn-col-row row=222) is the last valid row."
  (with-temp-buffer
    (setq-local kuro--mouse-mode 1000)
    (setq-local kuro--mouse-sgr nil)
    (setq-local kuro--mouse-pixel-mode nil)
    (kuro-mouse-test--with-event 0 222
      (let ((result (kuro--encode-mouse 'fake-event 0 t)))
        (should (stringp result))))))

;;; Group 14: kuro--dispatch-mouse-event — SGR scroll events sent correctly
;; (covered in kuro-input-mouse-test-2.el Groups 14+)

;;; Group 15: kuro--mouse-button-alist invariants

(ert-deftest kuro-input-mouse-button-alist-has-mouse-1 ()
  "`kuro--mouse-button-alist' maps `mouse-1' to button index 0."
  (should (= (alist-get 'mouse-1 kuro--mouse-button-alist) 0)))

(ert-deftest kuro-input-mouse-button-alist-has-mouse-2 ()
  "`kuro--mouse-button-alist' maps `mouse-2' to button index 1."
  (should (= (alist-get 'mouse-2 kuro--mouse-button-alist) 1)))

(ert-deftest kuro-input-mouse-button-alist-has-mouse-3 ()
  "`kuro--mouse-button-alist' maps `mouse-3' to button index 2."
  (should (= (alist-get 'mouse-3 kuro--mouse-button-alist) 2)))

(ert-deftest kuro-input-mouse-button-alist-covers-three-buttons ()
  "`kuro--mouse-button-alist' has exactly three entries."
  (should (= (length kuro--mouse-button-alist) 3)))

(ert-deftest kuro-input-mouse-button-alist-unknown-returns-nil ()
  "Looking up an unknown event type in `kuro--mouse-button-alist' returns nil."
  (should (null (alist-get 'mouse-4 kuro--mouse-button-alist))))

(provide 'kuro-input-mouse-test-4)
;;; kuro-input-mouse-test-4.el ends here
