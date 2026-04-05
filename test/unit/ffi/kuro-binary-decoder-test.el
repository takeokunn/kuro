;;; kuro-binary-decoder-test.el --- Unit tests for kuro-binary-decoder.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the binary FFI frame decoder (kuro-binary-decoder.el).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Groups covered:
;;   Group 1: kuro--read-u32-le
;;   Group 3: kuro--decode-binary-updates — single-row and multi-face
;;   Group 4: kuro--decode-binary-updates — multi-row and col-to-buf
;;   Group 5: kuro--decode-row-text, kuro--decode-face-ranges, kuro--decode-col-to-buf
;;   Group 6: kuro--read-u32-le — edge cases
;;   Group 7: kuro--read-u32-le — additional edge cases

;;; Code:

(require 'ert)
(require 'kuro-binary-decoder)

;;; Helpers

(defun kuro-binary-decoder-test--make-u32-le (n)
  "Return a list of 4 bytes encoding N as u32 little-endian."
  (list (logand n #xff)
        (logand (ash n -8) #xff)
        (logand (ash n -16) #xff)
        (logand (ash n -24) #xff)))

(defun kuro-binary-decoder-test--make-u64-le (n)
  "Return a list of 8 bytes encoding N as u64 little-endian."
  (append (kuro-binary-decoder-test--make-u32-le (logand n #xffffffff))
          (kuro-binary-decoder-test--make-u32-le (logand (ash n -32) #xffffffff))))

(defun kuro-binary-decoder-test--make-vec (&rest bytes)
  "Build an Emacs vector of byte integers from BYTES (integers 0-255)."
  (apply #'vector bytes))

;;; Group 1: kuro--read-u32-le

(ert-deftest kuro-binary-decoder-read-u32-le-zero ()
  "kuro--read-u32-le reads 0 from four zero bytes."
  (let ((v (vector 0 0 0 0)))
    (should (= (kuro--read-u32-le v 0) 0))))

(ert-deftest kuro-binary-decoder-read-u32-le-one ()
  "kuro--read-u32-le reads 1 from LE bytes [1 0 0 0]."
  (let ((v (vector 1 0 0 0)))
    (should (= (kuro--read-u32-le v 0) 1))))

(ert-deftest kuro-binary-decoder-read-u32-le-max-u8 ()
  "kuro--read-u32-le reads 255 from bytes [255 0 0 0]."
  (let ((v (vector 255 0 0 0)))
    (should (= (kuro--read-u32-le v 0) 255))))

(ert-deftest kuro-binary-decoder-read-u32-le-multi-byte ()
  "kuro--read-u32-le decodes a multi-byte LE value correctly."
  ;; 0x01020304 in LE is [04 03 02 01]
  (let ((v (vector #x04 #x03 #x02 #x01)))
    (should (= (kuro--read-u32-le v 0) #x01020304))))

(ert-deftest kuro-binary-decoder-read-u32-le-with-offset ()
  "kuro--read-u32-le reads from a non-zero offset."
  ;; offset 2: bytes [#x78 #x56 #x34 #x12] → 0x12345678
  (let ((v (vector 0 0 #x78 #x56 #x34 #x12)))
    (should (= (kuro--read-u32-le v 2) #x12345678))))

(ert-deftest kuro-binary-decoder-read-u32-le-known-value ()
  "kuro--read-u32-le handles a known 32-bit value: 305419896 = 0x12345678."
  (let ((v (vector #x78 #x56 #x34 #x12)))
    (should (= (kuro--read-u32-le v 0) #x12345678))))

;;; Group 3: kuro--decode-binary-updates — single-row

(ert-deftest kuro-binary-decoder-decode-updates-empty ()
  "kuro--decode-binary-updates with 0 rows returns nil."
  ;; Frame: format_version=1, num_rows=0
  (let ((v (apply #'vector
                  (append (kuro-binary-decoder-test--make-u32-le 1)
                          (kuro-binary-decoder-test--make-u32-le 0)))))
    (should (null (kuro--decode-binary-updates v)))))

(ert-deftest kuro-binary-decoder-decode-updates-one-row-no-faces ()
  "kuro--decode-binary-updates decodes one row with empty text and no face ranges."
  ;; Build a frame: format_version=1, 1 row, row_index=0, 0 face ranges, text="", 0 col_to_buf entries
  (let* ((frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 1)   ; format_version
           (kuro-binary-decoder-test--make-u32-le 1)   ; num_rows
           (kuro-binary-decoder-test--make-u32-le 0)   ; row_index
           (kuro-binary-decoder-test--make-u32-le 0)   ; num_face_ranges
           (kuro-binary-decoder-test--make-u32-le 0)   ; text_byte_len
           ;; (no text bytes)
           (kuro-binary-decoder-test--make-u32-le 0))) ; col_to_buf_len
         (v (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates v)))
    (should (= (length result) 1))
    (let* ((entry      (aref result 0))
           (row        (aref entry 0))
           (text       (aref entry 1))
           (face-list  (aref entry 2))
           (col-to-buf (aref entry 3)))
      (should (= row 0))                     ; row index
      (should (equal text ""))               ; text
      (should (null face-list))              ; no face ranges
      (should (equal col-to-buf [])))))      ; empty col-to-buf

(ert-deftest kuro-binary-decoder-decode-updates-one-row-one-face ()
  "kuro--decode-binary-updates decodes one row with ASCII text and one face range."
  ;; Text: \"hi\" (2 bytes: 0x68 0x69)
  ;; Face range: start=0, end=2, fg=0xFF000000 (default), bg=0xFF000000, flags=0x01 (bold)
  (let* ((text-bytes '(#x68 #x69)) ; "hi"
         (fg #xFF000000)
         (bg #xFF000000)
         (flags #x01) ; bold
         (frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 1)   ; format_version
           (kuro-binary-decoder-test--make-u32-le 1)   ; num_rows
           (kuro-binary-decoder-test--make-u32-le 3)   ; row_index = 3
           (kuro-binary-decoder-test--make-u32-le 1)   ; num_face_ranges
           (kuro-binary-decoder-test--make-u32-le 2)   ; text_byte_len = 2
           text-bytes
           ;; face range: start_buf=0, end_buf=2, fg, bg, flags (8 bytes)
           (kuro-binary-decoder-test--make-u32-le 0)   ; start_buf
           (kuro-binary-decoder-test--make-u32-le 2)   ; end_buf
           (kuro-binary-decoder-test--make-u32-le fg)  ; fg
           (kuro-binary-decoder-test--make-u32-le bg)  ; bg
           (kuro-binary-decoder-test--make-u64-le flags) ; flags (8 bytes)
           (kuro-binary-decoder-test--make-u32-le 0))) ; col_to_buf_len
         (v (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates v)))
    (should (= (length result) 1))
    (let* ((entry      (aref result 0))
           (row        (aref entry 0))
           (text       (aref entry 1))
           (face-list  (aref entry 2))
           (col-to-buf (aref entry 3)))
      (should (= row 3))                             ; row index
      (should (equal text "hi"))                     ; text
      (should (= (/ (length face-list) 6) 1))        ; one face range (stride-6)
      ;; Range 0 at base index 0: [start end fg bg flags ul]
      (should (= (aref face-list 0) 0))              ; start_buf
      (should (= (aref face-list 1) 2))              ; end_buf
      (should (= (aref face-list 2) fg))             ; fg
      (should (= (aref face-list 3) bg))             ; bg
      (should (= (aref face-list 4) flags))          ; flags
      (should (equal col-to-buf [])))))              ; empty col-to-buf

;;; Group 4: kuro--decode-binary-updates — multi-row and col-to-buf

(ert-deftest kuro-binary-decoder-decode-updates-two-rows-two-faces-each ()
  "kuro--decode-binary-updates decodes a single frame with 2 rows and 2 face ranges each.
This tests that pos advances correctly across rows — the bug was that
pcase-let* bindings for pos were lexically scoped and did not update the
outer pos, so row 2+ were decoded at the wrong byte offset.

Row 0: text \"AB\", 2 face ranges:
  range 0: start=0 end=1 fg=0x000000 bg=0xFFFFFF flags=0
  range 1: start=1 end=2 fg=0xFF0000 bg=0x000000 flags=1

Row 1: text \"CD\", 2 face ranges:
  range 0: start=0 end=1 fg=0x00FF00 bg=0x000000 flags=2
  range 1: start=1 end=2 fg=0x0000FF bg=0xFFFFFF flags=3"
  (let* ((frame
          (apply #'vector
                 (append
                  ;; Header: format_version=1, num_rows=2
                  (kuro-binary-decoder-test--make-u32-le 1)
                  (kuro-binary-decoder-test--make-u32-le 2)
                  ;; Row 0: row_index=0, num_face_ranges=2, text_byte_len=2
                  (kuro-binary-decoder-test--make-u32-le 0)
                  (kuro-binary-decoder-test--make-u32-le 2)
                  (kuro-binary-decoder-test--make-u32-le 2)
                  '(#x41 #x42)                           ; "AB"
                  ;; face range 0: start=0 end=1 fg=0x000000 bg=0xFFFFFF flags=0
                  (kuro-binary-decoder-test--make-u32-le 0)
                  (kuro-binary-decoder-test--make-u32-le 1)
                  (kuro-binary-decoder-test--make-u32-le #x000000)
                  (kuro-binary-decoder-test--make-u32-le #xFFFFFF)
                  (kuro-binary-decoder-test--make-u64-le 0)
                  ;; face range 1: start=1 end=2 fg=0xFF0000 bg=0x000000 flags=1
                  (kuro-binary-decoder-test--make-u32-le 1)
                  (kuro-binary-decoder-test--make-u32-le 2)
                  (kuro-binary-decoder-test--make-u32-le #xFF0000)
                  (kuro-binary-decoder-test--make-u32-le #x000000)
                  (kuro-binary-decoder-test--make-u64-le 1)
                  (kuro-binary-decoder-test--make-u32-le 0)   ; col_to_buf_len=0 for row 0
                  ;; Row 1: row_index=1, num_face_ranges=2, text_byte_len=2
                  (kuro-binary-decoder-test--make-u32-le 1)
                  (kuro-binary-decoder-test--make-u32-le 2)
                  (kuro-binary-decoder-test--make-u32-le 2)
                  '(#x43 #x44)                           ; "CD"
                  ;; face range 0: start=0 end=1 fg=0x00FF00 bg=0x000000 flags=2
                  (kuro-binary-decoder-test--make-u32-le 0)
                  (kuro-binary-decoder-test--make-u32-le 1)
                  (kuro-binary-decoder-test--make-u32-le #x00FF00)
                  (kuro-binary-decoder-test--make-u32-le #x000000)
                  (kuro-binary-decoder-test--make-u64-le 2)
                  ;; face range 1: start=1 end=2 fg=0x0000FF bg=0xFFFFFF flags=3
                  (kuro-binary-decoder-test--make-u32-le 1)
                  (kuro-binary-decoder-test--make-u32-le 2)
                  (kuro-binary-decoder-test--make-u32-le #x0000FF)
                  (kuro-binary-decoder-test--make-u32-le #xFFFFFF)
                  (kuro-binary-decoder-test--make-u64-le 3)
                  (kuro-binary-decoder-test--make-u32-le 0)))) ; col_to_buf_len=0 for row 1
         (result (kuro--decode-binary-updates frame)))
    (should (= (length result) 2))
    ;; Verify row 0
    (let* ((entry0   (aref result 0))
           (row0     (aref entry0 0))
           (text0    (aref entry0 1))
           (faces0   (aref entry0 2))
           (c2b0     (aref entry0 3)))
      (should (= row0 0))                           ; row index
      (should (equal text0 "AB"))                   ; text
      (should (= (/ (length faces0) 6) 2))          ; 2 face ranges (stride-6)
      ;; Range 0 at base 0
      (should (= (aref faces0 0) 0))
      (should (= (aref faces0 1) 1))
      (should (= (aref faces0 2) #x000000))
      (should (= (aref faces0 3) #xFFFFFF))
      (should (= (aref faces0 4) 0))
      ;; Range 1 at base 6
      (should (= (aref faces0 6) 1))
      (should (= (aref faces0 7) 2))
      (should (= (aref faces0 8) #xFF0000))
      (should (= (aref faces0 9) #x000000))
      (should (= (aref faces0 10) 1))
      (should (equal c2b0 [])))
    ;; Verify row 1 — this was silently broken before the fix
    (let* ((entry1   (aref result 1))
           (row1     (aref entry1 0))
           (text1    (aref entry1 1))
           (faces1   (aref entry1 2))
           (c2b1     (aref entry1 3)))
      (should (= row1 1))                           ; row index
      (should (equal text1 "CD"))                   ; text
      (should (= (/ (length faces1) 6) 2))          ; 2 face ranges (stride-6)
      ;; Range 0 at base 0
      (should (= (aref faces1 0) 0))
      (should (= (aref faces1 1) 1))
      (should (= (aref faces1 2) #x00FF00))
      (should (= (aref faces1 3) #x000000))
      (should (= (aref faces1 4) 2))
      ;; Range 1 at base 6
      (should (= (aref faces1 6) 1))
      (should (= (aref faces1 7) 2))
      (should (= (aref faces1 8) #x0000FF))
      (should (= (aref faces1 9) #xFFFFFF))
      (should (= (aref faces1 10) 3))
      (should (equal c2b1 [])))))

(ert-deftest kuro-binary-decoder-decode-updates-non-zero-col-to-buf ()
  "kuro--decode-binary-updates decodes a non-empty col_to_buf mapping."
  ;; Row 0: text "X" (1 byte), 0 face ranges, col_to_buf=[0 1] (2 entries)
  (let* ((frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 1)   ; format_version
           (kuro-binary-decoder-test--make-u32-le 1)   ; num_rows
           (kuro-binary-decoder-test--make-u32-le 0)   ; row_index
           (kuro-binary-decoder-test--make-u32-le 0)   ; num_face_ranges
           (kuro-binary-decoder-test--make-u32-le 1)   ; text_byte_len ("X")
           '(#x58)                                      ; text bytes: 'X'
           ;; col_to_buf_len = 2; entries: 0, 1
           (kuro-binary-decoder-test--make-u32-le 2)
           (kuro-binary-decoder-test--make-u32-le 0)
           (kuro-binary-decoder-test--make-u32-le 1)))
         (v (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates v)))
    (should (= (length result) 1))
    (let* ((entry  (aref result 0))
           (row    (aref entry 0))
           (text   (aref entry 1))
           (faces  (aref entry 2))
           (c2b    (aref entry 3)))
      (should (= row 0))
      (should (equal text "X"))
      (should (null faces))
      ;; col-to-buf must be a vector of length 2 with values 0 and 1
      (should (vectorp c2b))
      (should (= (length c2b) 2))
      (should (= (aref c2b 0) 0))
      (should (= (aref c2b 1) 1)))))

;;; Group 5: kuro--decode-row-text, kuro--decode-face-ranges, kuro--decode-col-to-buf

(ert-deftest kuro-binary-decoder-decode-row-text-empty ()
  "kuro--decode-row-text with length 0 returns empty string and unchanged pos."
  (let ((v (make-vector 0 0)))
    (pcase-let ((`(,text . ,new-pos) (kuro--decode-row-text v 0 0)))
      (should (string= text ""))
      (should (= new-pos 0)))))

(ert-deftest kuro-binary-decoder-decode-row-text-ascii ()
  "kuro--decode-row-text decodes ASCII bytes correctly."
  (let ((v (apply #'vector (mapcar #'identity (string-to-list "hi")))))
    (pcase-let ((`(,text . ,new-pos) (kuro--decode-row-text v 0 2)))
      (should (string= text "hi"))
      (should (= new-pos 2)))))

(ert-deftest kuro-binary-decoder-decode-face-ranges-empty ()
  "kuro--decode-face-ranges with 0 ranges returns nil and sets kuro--decode-pos."
  (let ((v (make-vector 0 0)))
    (let* ((face-list (kuro--decode-face-ranges v 0 0 nil))
           (new-pos kuro--decode-pos))
      (should (null face-list))
      (should (= new-pos 0)))))

(ert-deftest kuro-binary-decoder-decode-face-ranges-one ()
  "kuro--decode-face-ranges decodes one 24-byte face tuple correctly."
  ;; One tuple: start=1 end=5 fg=0xFF000001 bg=0xFF000000 flags=0
  (let* ((start 1) (end 5) (fg #xFF000001) (bg #xFF000000)
         (v (apply #'vector
                   (append
                    (list (logand start #xFF) 0 0 0)        ; start-buf u32 LE
                    (list (logand end #xFF) 0 0 0)          ; end-buf u32 LE
                    (list (logand fg #xFF)
                          (logand (ash fg -8) #xFF)
                          (logand (ash fg -16) #xFF)
                          (logand (ash fg -24) #xFF))       ; fg u32 LE
                    (list #x00 #x00 #x00 #xFF)              ; bg u32 LE (#xFF000000)
                    (list 0 0 0 0 0 0 0 0)))))              ; flags u64 LE
    (let* ((face-list (kuro--decode-face-ranges v 0 1 nil))
           (new-pos kuro--decode-pos))
      ;; Stride-6 flat vector: 1 range × 6 slots = 6 elements.
      (should (= (/ (length face-list) 6) 1))
      (should (= (aref face-list 0) start))   ; start_buf at base 0
      (should (= (aref face-list 1) end))     ; end_buf at base 1
      (should (= new-pos 24)))))

(ert-deftest kuro-binary-decoder-decode-col-to-buf-empty ()
  "kuro--decode-col-to-buf with length 0 returns empty vector, sets kuro--decode-pos."
  (let ((v (kuro-binary-decoder-test--make-vec 0 0 0 0)))  ; ctb-len = 0
    (let* ((col-to-buf (kuro--decode-col-to-buf v 0))
           (new-pos kuro--decode-pos))
      (should (vectorp col-to-buf))
      (should (zerop (length col-to-buf)))
      (should (= new-pos 4)))))

(ert-deftest kuro-binary-decoder-decode-col-to-buf-two-entries ()
  "kuro--decode-col-to-buf decodes length-2 vector correctly."
  ;; Format: len=2 (u32 LE), then 2 u32 entries [10, 20]
  (let ((v (kuro-binary-decoder-test--make-vec
            2 0 0 0    ; length = 2
            10 0 0 0   ; entry 0 = 10
            20 0 0 0)))  ; entry 1 = 20
    (let* ((col-to-buf (kuro--decode-col-to-buf v 0))
           (new-pos kuro--decode-pos))
      (should (= (length col-to-buf) 2))
      (should (= (aref col-to-buf 0) 10))
      (should (= (aref col-to-buf 1) 20))
      (should (= new-pos 12)))))

;;; Group 6: kuro--read-u32-le — edge cases

(ert-deftest kuro-binary-decoder-read-u32-le-max-value ()
  "kuro--read-u32-le reads the maximum u32 value 0xFFFFFFFF."
  (let ((v (vector #xFF #xFF #xFF #xFF)))
    (should (= (kuro--read-u32-le v 0) #xFFFFFFFF))))

(ert-deftest kuro-binary-decoder-read-u32-le-exact-four-bytes ()
  "kuro--read-u32-le reads correctly from a vector of exactly 4 bytes."
  (let ((v (apply #'vector (kuro-binary-decoder-test--make-u32-le 42))))
    (should (= (kuro--read-u32-le v 0) 42))))

(ert-deftest kuro-binary-decoder-read-u32-le-mid-vector-offset ()
  "kuro--read-u32-le reads at an arbitrary middle offset."
  ;; Vector: [0 0 0 0] [#x78 #x56 #x34 #x12] [0 0 0 0]
  (let ((v (apply #'vector
                  (append
                   (kuro-binary-decoder-test--make-u32-le 0)
                   (kuro-binary-decoder-test--make-u32-le #x12345678)
                   (kuro-binary-decoder-test--make-u32-le 0)))))
    (should (= (kuro--read-u32-le v 4) #x12345678))))

;;; Group 8: kuro--decode-row-text — additional cases

(ert-deftest kuro-binary-decoder-decode-row-text-multibyte-utf8 ()
  "kuro--decode-row-text decodes 3-byte UTF-8 (U+2603 SNOWMAN) correctly."
  ;; U+2603 encodes as E2 98 83 in UTF-8
  (let* ((v (vector #xE2 #x98 #x83))
         (result (kuro--decode-row-text v 0 3)))
    (should (string= (car result) "\u2603"))
    (should (= (cdr result) 3))))

(ert-deftest kuro-binary-decoder-decode-row-text-two-byte-utf8 ()
  "kuro--decode-row-text decodes 2-byte UTF-8 (U+00E9 é) correctly."
  ;; U+00E9 encodes as C3 A9 in UTF-8
  (let* ((v (vector #xC3 #xA9))
         (result (kuro--decode-row-text v 0 2)))
    (should (string= (car result) "\u00E9"))
    (should (= (cdr result) 2))))

(ert-deftest kuro-binary-decoder-decode-row-text-advances-pos-correctly ()
  "kuro--decode-row-text advances pos by exactly text-byte-len."
  ;; Vector with padding before and after the text region
  ;; Use offset 4, text = "AB" (2 bytes), expect new-pos = 6
  (let* ((v (vector 0 0 0 0 #x41 #x42 0 0))
         (result (kuro--decode-row-text v 4 2)))
    (should (string= (car result) "AB"))
    (should (= (cdr result) 6))))

;;; Group 9: kuro--decode-face-ranges — additional cases

(ert-deftest kuro-binary-decoder-decode-face-ranges-max-flags ()
  "kuro--decode-face-ranges decodes the maximum wire-format flags value.
`encode_attrs' in Rust produces values in 0..=0xBFF (9 SGR flag bits + 3
underline-style bits).  The decoder reads `flags' as a u32 (low 4 bytes of
the 8-byte wire field) because the upper 4 bytes are always zero.  The
maximum representable u32 value 0xFFFFFFFF is used here to exercise the
decoder boundary."
  ;; flags = 0xFFFFFFFF (max u32; upper 4 bytes on the wire are 0x00000000)
  (let* ((v (apply #'vector
                   (append
                    (kuro-binary-decoder-test--make-u32-le 0)   ; start_buf
                    (kuro-binary-decoder-test--make-u32-le 10)  ; end_buf
                    (kuro-binary-decoder-test--make-u32-le 0)   ; fg
                    (kuro-binary-decoder-test--make-u32-le 0)   ; bg
                    (kuro-binary-decoder-test--make-u64-le #xFFFFFFFF)))) ; flags (u32 max)
         (result (kuro--decode-face-ranges v 0 1 nil))
         (new-pos kuro--decode-pos))
    ;; Stride-6: 1 range × 6 = 6 elements; flags at index 4 (base 0 + 4).
    (should (= (/ (length result) 6) 1))
    (should (= (aref result 4) #xFFFFFFFF))
    (should (= new-pos 24))))

(ert-deftest kuro-binary-decoder-decode-face-ranges-pos-advances-per-range ()
  "kuro--decode-face-ranges advances pos by 24 bytes per face range."
  (let* ((range-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 0)
           (kuro-binary-decoder-test--make-u32-le 1)
           (kuro-binary-decoder-test--make-u32-le 0)
           (kuro-binary-decoder-test--make-u32-le 0)
           (kuro-binary-decoder-test--make-u64-le 0)))
         ;; Three identical ranges
         (v (apply #'vector (append range-bytes range-bytes range-bytes)))
         (result (kuro--decode-face-ranges v 0 3 nil))
         (new-pos kuro--decode-pos))
    ;; Stride-6: 3 ranges × 6 = 18 elements.
    (should (= (/ (length result) 6) 3))
    (should (= new-pos 72))))    ; 3 × 24 bytes

;;; Group 10: kuro--decode-col-to-buf — additional cases

(ert-deftest kuro-binary-decoder-decode-col-to-buf-single-entry ()
  "kuro--decode-col-to-buf decodes a single-entry col-to-buf mapping."
  ;; Format: len=1 (u32 LE), then 1 u32 entry [7]
  (let ((v (kuro-binary-decoder-test--make-vec
            1 0 0 0    ; length = 1
            7 0 0 0))) ; entry 0 = 7
    (let* ((col-to-buf (kuro--decode-col-to-buf v 0))
           (new-pos kuro--decode-pos))
      (should (vectorp col-to-buf))
      (should (= (length col-to-buf) 1))
      (should (= (aref col-to-buf 0) 7))
      (should (= new-pos 8)))))

(ert-deftest kuro-binary-decoder-decode-col-to-buf-preserves-large-values ()
  "kuro--decode-col-to-buf correctly stores large u32 values."
  ;; Entry value = 0xFFFFFF (large but fits in u32)
  (let ((v (apply #'vector
                  (append
                   (kuro-binary-decoder-test--make-u32-le 1)
                   (kuro-binary-decoder-test--make-u32-le #xFFFFFF)))))
    (let ((col-to-buf (kuro--decode-col-to-buf v 0)))
      (should (= (aref col-to-buf 0) #xFFFFFF)))))

(ert-deftest kuro-binary-decoder-decode-col-to-buf-with-offset ()
  "kuro--decode-col-to-buf reads from a non-zero offset."
  ;; 4 bytes padding, then len=1, then entry=5
  (let ((v (apply #'vector
                  (append
                   (kuro-binary-decoder-test--make-u32-le 0)  ; padding
                   (kuro-binary-decoder-test--make-u32-le 1)  ; length
                   (kuro-binary-decoder-test--make-u32-le 5)))) ; entry
         )
    (let* ((col-to-buf (kuro--decode-col-to-buf v 4))
           (new-pos kuro--decode-pos))
      (should (= (aref col-to-buf 0) 5))
      (should (= new-pos 12)))))

;;; Group 11: kuro--decode-binary-updates — frame structure edge cases

(ert-deftest kuro-binary-decoder-decode-updates-row-with-col-to-buf ()
  "kuro--decode-binary-updates correctly passes a non-empty col_to_buf."
  ;; Row: index=5, text="A", 0 face ranges, col_to_buf=[0, 1, 2]
  (let* ((frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 1)   ; format_version
           (kuro-binary-decoder-test--make-u32-le 1)   ; num_rows
           (kuro-binary-decoder-test--make-u32-le 5)   ; row_index = 5
           (kuro-binary-decoder-test--make-u32-le 0)   ; num_face_ranges
           (kuro-binary-decoder-test--make-u32-le 1)   ; text_byte_len ("A")
           '(#x41)                                      ; text: 'A'
           (kuro-binary-decoder-test--make-u32-le 3)   ; col_to_buf_len = 3
           (kuro-binary-decoder-test--make-u32-le 0)
           (kuro-binary-decoder-test--make-u32-le 1)
           (kuro-binary-decoder-test--make-u32-le 2)))
         (v (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates v)))
    (should (= (length result) 1))
    (let* ((entry (aref result 0))
           (c2b   (aref entry 3)))
      (should (vectorp c2b))
      (should (= (length c2b) 3))
      (should (= (aref c2b 0) 0))
      (should (= (aref c2b 1) 1))
      (should (= (aref c2b 2) 2)))))

(ert-deftest kuro-binary-decoder-decode-updates-preserves-row-order ()
  "kuro--decode-binary-updates returns rows in ascending row-index order."
  ;; 3 rows: indices 10, 20, 30 — verify order is preserved
  (let* ((make-row
          (lambda (row-idx text-char)
            (append
             (kuro-binary-decoder-test--make-u32-le row-idx)
             (kuro-binary-decoder-test--make-u32-le 0)    ; 0 face ranges
             (kuro-binary-decoder-test--make-u32-le 1)    ; 1 text byte
             (list text-char)
             (kuro-binary-decoder-test--make-u32-le 0)))) ; 0 col_to_buf
         (frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 1)   ; format_version
           (kuro-binary-decoder-test--make-u32-le 3)
           (funcall make-row 10 ?A)
           (funcall make-row 20 ?B)
           (funcall make-row 30 ?C)))
         (v (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates v)))
    (should (= (length result) 3))
    ;; Each entry is a flat vector [row-index text face-ranges col-to-buf].
    (should (= (aref (aref result 0) 0) 10))
    (should (= (aref (aref result 1) 0) 20))
    (should (= (aref (aref result 2) 0) 30))))

;;; Group 12: kuro--decode-binary-updates — high row indices and face ordering

(ert-deftest kuro-binary-decoder-decode-updates-high-row-index ()
  "kuro--decode-binary-updates preserves a large row index value."
  ;; row_index = 65535 — ensure u32 round-trips through the decoder
  (let* ((row-idx #xFFFF)
         (frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 1)         ; format_version
           (kuro-binary-decoder-test--make-u32-le 1)         ; num_rows
           (kuro-binary-decoder-test--make-u32-le row-idx)   ; row_index
           (kuro-binary-decoder-test--make-u32-le 0)         ; num_face_ranges
           (kuro-binary-decoder-test--make-u32-le 0)         ; text_byte_len
           (kuro-binary-decoder-test--make-u32-le 0)))       ; col_to_buf_len
         (v (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates v)))
    (should (= (length result) 1))
    (should (= (aref (aref result 0) 0) row-idx))))

(ert-deftest kuro-binary-decoder-decode-updates-face-order-preserved ()
  "kuro--decode-binary-updates returns face ranges in ascending start_buf order.
The encoder writes them in order; the decoder must not reverse them."
  ;; Two face ranges: range0 start=0, range1 start=5
  (let* ((frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 1)    ; format_version
           (kuro-binary-decoder-test--make-u32-le 1)    ; num_rows
           (kuro-binary-decoder-test--make-u32-le 0)    ; row_index
           (kuro-binary-decoder-test--make-u32-le 2)    ; num_face_ranges
           (kuro-binary-decoder-test--make-u32-le 0)    ; text_byte_len
           ;; range 0: start=0, end=5, fg=1, bg=2, flags=3
           (kuro-binary-decoder-test--make-u32-le 0)
           (kuro-binary-decoder-test--make-u32-le 5)
           (kuro-binary-decoder-test--make-u32-le 1)
           (kuro-binary-decoder-test--make-u32-le 2)
           (kuro-binary-decoder-test--make-u64-le 3)
           ;; range 1: start=5, end=10, fg=4, bg=5, flags=6
           (kuro-binary-decoder-test--make-u32-le 5)
           (kuro-binary-decoder-test--make-u32-le 10)
           (kuro-binary-decoder-test--make-u32-le 4)
           (kuro-binary-decoder-test--make-u32-le 5)
           (kuro-binary-decoder-test--make-u64-le 6)
           (kuro-binary-decoder-test--make-u32-le 0)))  ; col_to_buf_len
         (v (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates v)))
    (let* ((entry     (aref result 0))
           (face-list (aref entry 2)))
      ;; Stride-6: 2 ranges × 6 = 12 elements.
      (should (= (/ (length face-list) 6) 2))
      ;; Range 0 at base 0: start_buf=0
      (should (= (aref face-list 0) 0))
      ;; Range 1 at base 6: start_buf=5
      (should (= (aref face-list 6) 5)))))

(ert-deftest kuro-binary-decoder-decode-updates-three-rows-different-col-to-buf ()
  "kuro--decode-binary-updates decodes 3 rows with varying col_to_buf sizes."
  ;; row 0: col_to_buf size 0; row 1: size 1; row 2: size 2
  (let* ((make-row
          (lambda (row-idx ctb-entries)
            (let ((ctb-len (length ctb-entries)))
              (append
               (kuro-binary-decoder-test--make-u32-le row-idx)
               (kuro-binary-decoder-test--make-u32-le 0)   ; num_face_ranges
               (kuro-binary-decoder-test--make-u32-le 0)   ; text_byte_len
               (kuro-binary-decoder-test--make-u32-le ctb-len)
               (mapcan #'kuro-binary-decoder-test--make-u32-le ctb-entries)))))
         (frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 1)   ; format_version
           (kuro-binary-decoder-test--make-u32-le 3)
           (funcall make-row 0 '())
           (funcall make-row 1 '(42))
           (funcall make-row 2 '(10 20))))
         (v (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates v)))
    (should (= (length result) 3))
    ;; Each entry: flat vector [row text face-ranges col-to-buf]; col-to-buf at index 3.
    (should (= (length (aref (aref result 0) 3)) 0))         ; row 0: empty col-to-buf
    (should (= (length (aref (aref result 1) 3)) 1))         ; row 1: 1 entry
    (should (= (aref (aref (aref result 1) 3) 0) 42))        ; row 1 entry value
    (should (= (length (aref (aref result 2) 3)) 2))         ; row 2: 2 entries
    (should (= (aref (aref (aref result 2) 3) 0) 10))
    (should (= (aref (aref (aref result 2) 3) 1) 20))))

(ert-deftest kuro-binary-decoder-decode-updates-result-is-vector ()
  "kuro--decode-binary-updates returns a vector for non-empty frames, nil for 0 rows."
  ;; 0-row frame → nil (callers guard on (when updates ...))
  (let* ((empty-frame
          (apply #'vector
                 (append (kuro-binary-decoder-test--make-u32-le 1)
                         (kuro-binary-decoder-test--make-u32-le 0))))
         (empty-result (kuro--decode-binary-updates empty-frame)))
    (should (null empty-result)))
  ;; 1-row frame → vector
  (let* ((one-row-frame
          (apply #'vector
                 (append
                  (kuro-binary-decoder-test--make-u32-le 1)  ; format_version
                  (kuro-binary-decoder-test--make-u32-le 1)  ; num_rows=1
                  (kuro-binary-decoder-test--make-u32-le 0)  ; row_index
                  (kuro-binary-decoder-test--make-u32-le 0)  ; num_face_ranges
                  (kuro-binary-decoder-test--make-u32-le 0)  ; text_byte_len
                  (kuro-binary-decoder-test--make-u32-le 0)))) ; col_to_buf_len
         (result (kuro--decode-binary-updates one-row-frame)))
    (should (vectorp result))
    (should (= (length result) 1))))

;;; Group 13: kuro--decode-row-text — 4-byte UTF-8 and offset advancement

(ert-deftest kuro-binary-decoder-decode-row-text-four-byte-utf8 ()
  "kuro--decode-row-text decodes a 4-byte UTF-8 codepoint (U+1F600 GRINNING FACE)."
  ;; U+1F600 encodes as F0 9F 98 80 in UTF-8
  (let* ((v (vector #xF0 #x9F #x98 #x80))
         (result (kuro--decode-row-text v 0 4)))
    (should (string= (car result) "\U0001F600"))
    (should (= (cdr result) 4))))

(ert-deftest kuro-binary-decoder-decode-row-text-mixed-ascii-and-utf8 ()
  "kuro--decode-row-text decodes a mix of ASCII and UTF-8 multi-byte sequences."
  ;; 'A' (1 byte) + U+00E9 é (2 bytes C3 A9) + 'Z' (1 byte) = 4 bytes total
  (let* ((v (vector ?A #xC3 #xA9 ?Z))
         (result (kuro--decode-row-text v 0 4)))
    (should (string= (car result) "A\u00E9Z"))
    (should (= (cdr result) 4))))

(ert-deftest kuro-binary-decoder-decode-row-text-with-start-offset ()
  "kuro--decode-row-text reads text starting at a non-zero byte offset."
  ;; Padding: 2 bytes, then 'H' 'i' at offset 2
  (let* ((v (vector 0 0 ?H ?i 0 0))
         (result (kuro--decode-row-text v 2 2)))
    (should (string= (car result) "Hi"))
    (should (= (cdr result) 4))))

(ert-deftest kuro-binary-decoder-decode-row-text-single-byte ()
  "kuro--decode-row-text decodes a single ASCII byte."
  (let* ((v (vector ?X))
         (result (kuro--decode-row-text v 0 1)))
    (should (string= (car result) "X"))
    (should (= (cdr result) 1))))

;;; Group 14: kuro--decode-binary-frame-rows — CPS text-fn continuation

(ert-deftest kuro-binary-decoder-frame-rows-custom-text-fn-called-with-correct-args ()
  "kuro--decode-binary-frame-rows calls text-fn with correct idx and text-byte-len."
  (let* ((calls nil)
         (text-fn (lambda (idx pos text-byte-len)
                    (push (list idx text-byte-len) calls)
                    (cons "" pos)))
         (frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 2)   ; format_version=2
           (kuro-binary-decoder-test--make-u32-le 2)   ; num_rows
           (kuro-binary-decoder-test--make-u32-le 0)   ; row_index
           (kuro-binary-decoder-test--make-u32-le 0)   ; num_face_ranges
           (kuro-binary-decoder-test--make-u32-le 0)   ; text_byte_len
           (kuro-binary-decoder-test--make-u32-le 0)   ; col_to_buf_len
           (kuro-binary-decoder-test--make-u32-le 1)   ; row_index
           (kuro-binary-decoder-test--make-u32-le 0)   ; num_face_ranges
           (kuro-binary-decoder-test--make-u32-le 0)   ; text_byte_len
           (kuro-binary-decoder-test--make-u32-le 0))) ; col_to_buf_len
         (v (apply #'vector frame-bytes)))
    (kuro--decode-binary-frame-rows v text-fn)
    (let ((sorted (nreverse calls)))
      (should (= (length sorted) 2))
      (should (equal (car sorted) '(0 0)))
      (should (equal (cadr sorted) '(1 0))))))

(ert-deftest kuro-binary-decoder-frame-rows-returns-text-fn-result ()
  "kuro--decode-binary-frame-rows uses the text returned by text-fn."
  (let* ((text-fn (lambda (_idx pos _text-byte-len) (cons "CUSTOM" pos)))
         (frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 2)   ; format_version=2
           (kuro-binary-decoder-test--make-u32-le 1)   ; num_rows
           (kuro-binary-decoder-test--make-u32-le 0)   ; row_index
           (kuro-binary-decoder-test--make-u32-le 0)   ; num_face_ranges
           (kuro-binary-decoder-test--make-u32-le 0)   ; text_byte_len
           (kuro-binary-decoder-test--make-u32-le 0))) ; col_to_buf_len
         (v (apply #'vector frame-bytes))
         (result (kuro--decode-binary-frame-rows v text-fn)))
    (should (= (length result) 1))
    ;; Flat vector [row text face-ranges col-to-buf]: text is at index 1.
    (should (equal (aref (aref result 0) 1) "CUSTOM"))))

(ert-deftest kuro-binary-decoder-frame-rows-errors-on-unknown-version ()
  "kuro--decode-binary-frame-rows signals an error for an unsupported format version."
  (let* ((frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 99)  ; format_version=99
           (kuro-binary-decoder-test--make-u32-le 0))) ; num_rows
         (v (apply #'vector frame-bytes))
         (text-fn (lambda (_idx pos _len) (cons "" pos))))
    (should-error (kuro--decode-binary-frame-rows v text-fn))))

(ert-deftest kuro-binary-decoder-frame-rows-empty-frame-returns-empty-list ()
  "kuro--decode-binary-frame-rows with num_rows=0 returns nil."
  (let* ((frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 2)   ; format_version=2
           (kuro-binary-decoder-test--make-u32-le 0))) ; num_rows=0
         (v (apply #'vector frame-bytes))
         (text-fn (lambda (_idx pos _len) (cons "" pos))))
    (should (null (kuro--decode-binary-frame-rows v text-fn)))))

;;; Group 15: kuro--decode-binary-updates-with-strings

(defun kuro-binary-decoder-test--make-v2-frame-no-text (row-index num-face-ranges)
  "Build a minimal v2 binary frame for ROW-INDEX with NUM-FACE-RANGES and text_byte_len=0.
col_to_buf section is also empty (length 0).  Each face range is 28 zero bytes."
  (let* ((face-bytes (make-list (* num-face-ranges 28) 0))
         (frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 2)              ; format_version=2
           (kuro-binary-decoder-test--make-u32-le 1)              ; num_rows=1
           ;; row descriptor
           (kuro-binary-decoder-test--make-u32-le row-index)      ; row_index
           (kuro-binary-decoder-test--make-u32-le num-face-ranges) ; num_face_ranges
           (kuro-binary-decoder-test--make-u32-le 0)              ; text_byte_len=0
           face-bytes
           (kuro-binary-decoder-test--make-u32-le 0))))           ; col_to_buf_len=0
    (apply #'vector frame-bytes)))

(ert-deftest kuro-binary-decoder-decode-with-strings-returns-one-row ()
  "kuro--decode-binary-updates-with-strings returns one entry for a 1-row frame."
  (let* ((text-strings (vector "hello"))
         (vec (kuro-binary-decoder-test--make-v2-frame-no-text 0 1))
         (result (kuro--decode-binary-updates-with-strings text-strings vec)))
    (should (= (length result) 1))))

(ert-deftest kuro-binary-decoder-decode-with-strings-uses-text-vector ()
  "kuro--decode-binary-updates-with-strings takes row text from TEXT-STRINGS.
Each entry is a flat vector [row-index text face-ranges col-to-buf]."
  (let* ((text-strings (vector "row-text"))
         (vec (kuro-binary-decoder-test--make-v2-frame-no-text 3 0))
         (result (kuro--decode-binary-updates-with-strings text-strings vec))
         (entry (aref result 0)))
    ;; text is at index 1 of the flat entry vector
    (should (equal (aref entry 1) "row-text"))))

(ert-deftest kuro-binary-decoder-decode-with-strings-row-index-preserved ()
  "kuro--decode-binary-updates-with-strings preserves the row index from binary data."
  (let* ((text-strings (vector "x"))
         (vec (kuro-binary-decoder-test--make-v2-frame-no-text 7 0))
         (result (kuro--decode-binary-updates-with-strings text-strings vec))
         (entry (aref result 0)))
    ;; row-index is at index 0 of the flat entry vector
    (should (= (aref entry 0) 7))))

;;; Group 16: kuro--poll-updates-binary-optimised

(ert-deftest kuro-binary-decoder-poll-optimised-returns-nil-when-ffi-nil ()
  "kuro--poll-updates-binary-optimised returns nil when FFI returns nil."
  (cl-letf (((symbol-function 'kuro-core-poll-updates-binary-with-strings)
             (lambda (_id) nil)))
    (should (null (kuro--poll-updates-binary-optimised 'fake-id)))))

(ert-deftest kuro-binary-decoder-poll-optimised-decodes-when-ffi-returns-cons ()
  "kuro--poll-updates-binary-optimised decodes when FFI returns a cons."
  (let* ((text-strings (vector "decoded-row"))
         (vec (kuro-binary-decoder-test--make-v2-frame-no-text 0 0)))
    (cl-letf (((symbol-function 'kuro-core-poll-updates-binary-with-strings)
               (lambda (_id) (cons text-strings vec))))
      (let* ((result (kuro--poll-updates-binary-optimised 'fake-id))
             (entry (aref result 0)))
        (should result)
        (should (= (length result) 1))
        ;; entry is a flat vector [row-index text face-ranges col-to-buf]
        (should (equal (aref entry 1) "decoded-row"))))))

(provide 'kuro-binary-decoder-test)

;;; kuro-binary-decoder-test.el ends here
