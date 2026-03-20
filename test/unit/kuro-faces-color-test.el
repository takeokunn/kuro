;;; kuro-faces-color-test.el --- Unit tests for kuro-faces-color.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for kuro-faces-color.el (FFI color sentinel, ANSI color name
;; vector, and color conversion helpers).
;; These tests are pure Emacs Lisp and do NOT require the Rust dynamic module.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-faces-color)

;;; Group 1: kuro--ffi-color-default sentinel

(ert-deftest kuro-faces-color--default-sentinel-value ()
  "kuro--ffi-color-default must equal #xFF000000."
  (should (= kuro--ffi-color-default #xFF000000)))

(ert-deftest kuro-faces-color--default-sentinel-is-integer ()
  "kuro--ffi-color-default must be an integer (not a symbol or string)."
  (should (integerp kuro--ffi-color-default)))

(ert-deftest kuro-faces-color--default-sentinel-distinct-from-true-black ()
  "kuro--ffi-color-default must differ from true black (0x000000)."
  (should-not (= kuro--ffi-color-default 0)))

;;; Group 2: kuro--ansi-color-names vector

(ert-deftest kuro-faces-color--ansi-color-names-is-vector ()
  "kuro--ansi-color-names must be a vector."
  (should (vectorp kuro--ansi-color-names)))

(ert-deftest kuro-faces-color--ansi-color-names-length ()
  "kuro--ansi-color-names must have exactly 16 entries."
  (should (= (length kuro--ansi-color-names) 16)))

(ert-deftest kuro-faces-color--ansi-color-names-all-strings ()
  "Every element of kuro--ansi-color-names must be a non-empty string."
  (dotimes (i 16)
    (let ((name (aref kuro--ansi-color-names i)))
      (should (stringp name))
      (should (> (length name) 0)))))

(ert-deftest kuro-faces-color--ansi-color-names-normal-colors ()
  "Indices 0-7 must be the standard ANSI names (no 'bright-' prefix)."
  (let ((expected ["black" "red" "green" "yellow"
                   "blue" "magenta" "cyan" "white"]))
    (dotimes (i 8)
      (should (string= (aref kuro--ansi-color-names i)
                       (aref expected i))))))

(ert-deftest kuro-faces-color--ansi-color-names-bright-black-hyphenated ()
  "Index 8 must be \"bright-black\" (hyphenated, not \"brightblack\" or \"dark-gray\")."
  (should (string= (aref kuro--ansi-color-names 8) "bright-black")))

(ert-deftest kuro-faces-color--ansi-color-names-bright-colors ()
  "Indices 8-15 must be the bright ANSI names with 'bright-' prefix."
  (let ((expected ["bright-black" "bright-red" "bright-green" "bright-yellow"
                   "bright-blue" "bright-magenta" "bright-cyan" "bright-white"]))
    (dotimes (i 8)
      (should (string= (aref kuro--ansi-color-names (+ 8 i))
                       (aref expected i))))))

;;; Group 3: kuro--decode-ffi-color — focused on sentinel and boundary cases
;;; (Broad coverage is already in kuro-faces-test.el; these tests add gaps.)

(ert-deftest kuro-faces-color--decode-ffi-color-sentinel-returns-default ()
  "kuro--ffi-color-default sentinel decodes to the :default keyword."
  (should (eq (kuro--decode-ffi-color kuro--ffi-color-default) :default)))

(ert-deftest kuro-faces-color--decode-ffi-color-named-index-15 ()
  "Named color at index 15 (bit 31 + 0x0F) decodes to (named . \"bright-white\")."
  (let ((result (kuro--decode-ffi-color (logior #x80000000 15))))
    (should (consp result))
    (should (eq (car result) 'named))
    (should (string= (cdr result) "bright-white"))))

(ert-deftest kuro-faces-color--decode-ffi-color-named-out-of-range-index ()
  "Named color with index >= 16 (bit 31 + 0x10) returns nil (no valid name)."
  ;; Index 16 is beyond the 16-entry kuro--ansi-color-names vector.
  (let ((result (kuro--decode-ffi-color (logior #x80000000 16))))
    (should (null result))))

(ert-deftest kuro-faces-color--decode-ffi-color-indexed-boundary-zero ()
  "Indexed color at index 0 (bit 30 + 0x00) decodes to (indexed . 0)."
  (let ((result (kuro--decode-ffi-color #x40000000)))
    (should (consp result))
    (should (eq (car result) 'indexed))
    (should (= (cdr result) 0))))

(ert-deftest kuro-faces-color--decode-ffi-color-indexed-boundary-255 ()
  "Indexed color at index 255 (bit 30 + 0xFF) decodes to (indexed . 255)."
  (let ((result (kuro--decode-ffi-color (logior #x40000000 255))))
    (should (consp result))
    (should (eq (car result) 'indexed))
    (should (= (cdr result) 255))))

(ert-deftest kuro-faces-color--decode-ffi-color-rgb-white ()
  "0x00FFFFFF decodes to (rgb . #xFFFFFF)."
  (let ((result (kuro--decode-ffi-color #x00FFFFFF)))
    (should (consp result))
    (should (eq (car result) 'rgb))
    (should (= (cdr result) #xFFFFFF))))

;;; Group 4: kuro--rgb-to-emacs — boundary values

(ert-deftest kuro-faces-color--rgb-to-emacs-midtone ()
  "0x7F7F7F encodes to #7f7f7f."
  (should (equal (kuro--rgb-to-emacs #x7F7F7F) "#7f7f7f")))

(ert-deftest kuro-faces-color--rgb-to-emacs-channel-isolation ()
  "Each color channel is masked independently."
  ;; Only blue channel: 0x0000FF → #0000ff
  (should (equal (kuro--rgb-to-emacs #x0000FF) "#0000ff"))
  ;; Only green channel: 0x00FF00 → #00ff00
  (should (equal (kuro--rgb-to-emacs #x00FF00) "#00ff00"))
  ;; Only red channel: 0xFF0000 → #ff0000
  (should (equal (kuro--rgb-to-emacs #xFF0000) "#ff0000")))

;;; Group 5: kuro--indexed-to-emacs — boundary values not in kuro-faces-test.el

(ert-deftest kuro-faces-color--indexed-to-emacs-index-16-is-black ()
  "Index 16 (start of 6x6x6 color cube) must be #000000."
  (should (equal (kuro--indexed-to-emacs 16) "#000000")))

(ert-deftest kuro-faces-color--indexed-to-emacs-index-231-is-white ()
  "Index 231 (end of 6x6x6 color cube) must be #ffffff."
  (should (equal (kuro--indexed-to-emacs 231) "#ffffff")))

(ert-deftest kuro-faces-color--indexed-to-emacs-index-232-grayscale-start ()
  "Index 232 (grayscale ramp start) must be #080808."
  (should (equal (kuro--indexed-to-emacs 232) "#080808")))

(ert-deftest kuro-faces-color--indexed-to-emacs-index-255-grayscale-end ()
  "Index 255 (grayscale ramp end) must be #eeeeee."
  (should (equal (kuro--indexed-to-emacs 255) "#eeeeee")))

(provide 'kuro-faces-color-test)

;;; kuro-faces-color-test.el ends here
