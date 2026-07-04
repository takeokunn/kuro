;;; kuro-render-cursor-blink-test.el --- DECSCUSR blink cursor tests  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the DECSCUSR blinking-cursor display logic in
;; kuro-render-cursor.el: `kuro--decscusr-blinking-p',
;; `kuro--apply-cursor-blink', and `kuro--apply-cursor-display'.
;; Pure Emacs Lisp; the Rust module is stubbed.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-test-stubs)
(require 'kuro-render-cursor)

;;; Group 1: kuro--decscusr-blinking-p

(ert-deftest kuro-render-cursor-blink-shapes-0-1-3-5-blink ()
  "DECSCUSR shapes 0/1/3/5 are blinking."
  (should (kuro--decscusr-blinking-p 0))
  (should (kuro--decscusr-blinking-p 1))
  (should (kuro--decscusr-blinking-p 3))
  (should (kuro--decscusr-blinking-p 5)))

(ert-deftest kuro-render-cursor-blink-shapes-2-4-6-steady ()
  "DECSCUSR shapes 2/4/6 are steady (non-blinking)."
  (should-not (kuro--decscusr-blinking-p 2))
  (should-not (kuro--decscusr-blinking-p 4))
  (should-not (kuro--decscusr-blinking-p 6)))

(ert-deftest kuro-render-cursor-blink-non-integer-defaults-blinking ()
  "A non-integer shape defaults to blinking (matches DECSCUSR 0 default)."
  (should (kuro--decscusr-blinking-p nil))
  (should (kuro--decscusr-blinking-p 'box)))

;;; Group 2: kuro--apply-cursor-blink — toggles global blink-cursor-mode

(defmacro kuro-render-cursor-blink-test--with-blink (&rest body)
  "Run BODY capturing `blink-cursor-mode' toggle calls in `toggled'.
`toggled' accumulates the arguments passed to `blink-cursor-mode' (a list,
newest last).  The global mode is left untouched."
  `(let ((toggled nil))
     (cl-letf (((symbol-function 'blink-cursor-mode)
                (lambda (&optional arg) (push arg toggled))))
       ,@body
       (setq toggled (nreverse toggled)))))

(ert-deftest kuro-render-cursor-blink-enables-when-blinking-and-off ()
  "Visible blinking shape enables blink-cursor-mode when it is currently off."
  (kuro-render-cursor-blink-test--with-blink
   (cl-letf (((symbol-value 'blink-cursor-mode) nil))
     (kuro--apply-cursor-blink t 1))
   (should (equal toggled '(1)))))

(ert-deftest kuro-render-cursor-blink-disables-when-steady-and-on ()
  "Visible steady shape disables blink-cursor-mode when it is currently on."
  (kuro-render-cursor-blink-test--with-blink
   (cl-letf (((symbol-value 'blink-cursor-mode) t))
     (kuro--apply-cursor-blink t 2))
   (should (equal toggled '(-1)))))

(ert-deftest kuro-render-cursor-blink-noop-when-already-matching ()
  "No toggle when blinking shape and blink-cursor-mode already on."
  (kuro-render-cursor-blink-test--with-blink
   (cl-letf (((symbol-value 'blink-cursor-mode) t))
     (kuro--apply-cursor-blink t 0))
   (should (null toggled))))

(ert-deftest kuro-render-cursor-blink-noop-when-steady-already-off ()
  "No toggle when steady shape and blink-cursor-mode already off."
  (kuro-render-cursor-blink-test--with-blink
   (cl-letf (((symbol-value 'blink-cursor-mode) nil))
     (kuro--apply-cursor-blink t 4))
   (should (null toggled))))

(ert-deftest kuro-render-cursor-blink-hidden-leaves-blink-untouched ()
  "A hidden cursor never toggles blink-cursor-mode regardless of shape."
  (kuro-render-cursor-blink-test--with-blink
   (cl-letf (((symbol-value 'blink-cursor-mode) nil))
     (kuro--apply-cursor-blink nil 1))
   (should (null toggled)))
  (kuro-render-cursor-blink-test--with-blink
   (cl-letf (((symbol-value 'blink-cursor-mode) t))
     (kuro--apply-cursor-blink nil 2))
   (should (null toggled))))

;;; Group 3: kuro--apply-cursor-display — sets cursor-type AND drives blink

(ert-deftest kuro-render-cursor-blink-display-sets-cursor-type-and-blink ()
  "Visible blinking bar sets a bar cursor-type and requests blink enable."
  (with-temp-buffer
    (kuro-render-cursor-blink-test--with-blink
     (cl-letf (((symbol-value 'blink-cursor-mode) nil))
       (kuro--apply-cursor-display t 5))
     (should (equal cursor-type '(bar . 2)))
     (should (equal toggled '(1))))))

(ert-deftest kuro-render-cursor-blink-display-hidden-nil-cursor ()
  "Hidden cursor sets cursor-type nil and does not toggle blink."
  (with-temp-buffer
    (kuro-render-cursor-blink-test--with-blink
     (cl-letf (((symbol-value 'blink-cursor-mode) t))
       (kuro--apply-cursor-display nil 5))
     (should (null cursor-type))
     (should (null toggled)))))

(provide 'kuro-render-cursor-blink-test)
;;; kuro-render-cursor-blink-test.el ends here
