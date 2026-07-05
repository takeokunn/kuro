;;; kuro-binary-decoder-scroll-shift-test.el --- Tests for v3 scroll-shift frame decoding  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the version-3 binary frame header: the scroll_up /
;; scroll_down shift fields consumed atomically with the dirty rows.
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Groups covered:
;;   Group 1: v3 header decoding into the scroll scratch vars
;;   Group 2: v1/v2 compatibility (scratch vars zeroed)
;;   Group 3: malformed v3 frames

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'kuro-binary-decoder)

;;; Helpers

(defun kuro-binary-decoder-scroll-test--u32-le (n)
  "Return a list of 4 bytes encoding N as u32 little-endian."
  (list (logand n #xff)
        (logand (ash n -8) #xff)
        (logand (ash n -16) #xff)
        (logand (ash n -24) #xff)))

(defun kuro-binary-decoder-scroll-test--v3-frame (scroll-up scroll-down row-indices)
  "Build a v3 frame with SCROLL-UP, SCROLL-DOWN, and empty rows at ROW-INDICES.
Each row has 0 face ranges, text_byte_len=0, and no col-to-buf entries."
  (let ((u32 #'kuro-binary-decoder-scroll-test--u32-le))
    (apply #'vector
           (append
            (funcall u32 3)                    ; format_version=3
            (funcall u32 (length row-indices)) ; num_rows
            (funcall u32 scroll-up)            ; scroll_up
            (funcall u32 scroll-down)          ; scroll_down
            (mapcan (lambda (idx)
                      (append (funcall u32 idx) ; row_index
                              (funcall u32 0)   ; num_face_ranges
                              (funcall u32 0)   ; text_byte_len
                              (funcall u32 0))) ; col_to_buf_len
                    row-indices)))))

;;; Group 1: v3 header decoding

(ert-deftest kuro-binary-decoder-v3-sets-scroll-scratch-vars ()
  "A v3 frame's scroll fields land in the decode scratch vars."
  (let ((kuro--decode-scroll-up 99)
        (kuro--decode-scroll-down 99))
    (kuro--decode-binary-updates-with-strings
     (vector "a") (kuro-binary-decoder-scroll-test--v3-frame 2 0 '(23)))
    (should (= kuro--decode-scroll-up 2))
    (should (= kuro--decode-scroll-down 0))))

(ert-deftest kuro-binary-decoder-v3-scroll-down-field-decoded ()
  "The scroll_down header field decodes independently of scroll_up."
  (let ((kuro--decode-scroll-up 0)
        (kuro--decode-scroll-down 0))
    (kuro--decode-binary-updates-with-strings
     (vector) (kuro-binary-decoder-scroll-test--v3-frame 0 4 '()))
    (should (= kuro--decode-scroll-up 0))
    (should (= kuro--decode-scroll-down 4))))

(ert-deftest kuro-binary-decoder-v3-scroll-only-frame-returns-nil-rows ()
  "A shift-only frame (0 rows, non-zero scroll) decodes to nil rows.
The renderer still applies the shift from the scratch vars — this is
the case where every shifted row survived the Rust hash skip."
  (let ((kuro--decode-scroll-up 0)
        (kuro--decode-scroll-down 0))
    (should (null (kuro--decode-binary-updates-with-strings
                   (vector)
                   (kuro-binary-decoder-scroll-test--v3-frame 3 0 '()))))
    (should (= kuro--decode-scroll-up 3))))

(ert-deftest kuro-binary-decoder-v3-rows-decode-after-16-byte-header ()
  "v3 row payloads start at byte 16, after the extended header."
  (let* ((kuro--decode-scroll-up 0)
         (kuro--decode-scroll-down 0)
         (result (kuro--decode-binary-updates-with-strings
                  (vector "x" "y")
                  (kuro-binary-decoder-scroll-test--v3-frame 1 0 '(5 9)))))
    (should (= (length result) 2))
    (should (= (aref (aref result 0) 0) 5))
    (should (= (aref (aref result 1) 0) 9))
    (should (equal (aref (aref result 0) 1) "x"))))

;;; Group 2: v1/v2 compatibility

(ert-deftest kuro-binary-decoder-v2-frame-zeroes-scroll-scratch-vars ()
  "Old v2 frames (8-byte header) never carry a shift; vars must be zeroed.
Guards against a stale shift from a previous v3 frame replaying when an
older .so module is loaded."
  (let ((kuro--decode-scroll-up 7)
        (kuro--decode-scroll-down 7)
        (u32 #'kuro-binary-decoder-scroll-test--u32-le))
    (kuro--decode-binary-updates-with-strings
     (vector)
     (apply #'vector (append (funcall u32 2) (funcall u32 0))))
    (should (= kuro--decode-scroll-up 0))
    (should (= kuro--decode-scroll-down 0))))

;;; Group 3: malformed v3 frames

(ert-deftest kuro-binary-decoder-v3-truncated-scroll-header-errors ()
  "A v3 frame shorter than the 16-byte header is rejected."
  (let ((u32 #'kuro-binary-decoder-scroll-test--u32-le))
    (should-error
     (kuro--decode-binary-updates-with-strings
      (vector)
      ;; version=3, num_rows=0, then only 4 of the 8 scroll bytes.
      (apply #'vector (append (funcall u32 3) (funcall u32 0) '(0 0 0 0)))))))

(ert-deftest kuro-binary-decoder-unsupported-version-4-errors ()
  "Future format versions are rejected loudly, not misparsed."
  (let ((u32 #'kuro-binary-decoder-scroll-test--u32-le))
    (should-error
     (kuro--decode-binary-updates-with-strings
      (vector)
      (apply #'vector (append (funcall u32 4) (funcall u32 0)))))))

(provide 'kuro-binary-decoder-scroll-shift-test)

;;; kuro-binary-decoder-scroll-shift-test.el ends here
