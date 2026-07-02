;;; kuro-binary-decoder-test.el --- Unit tests for kuro-binary-decoder.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the binary FFI frame decoder (kuro-binary-decoder.el).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Groups covered:
;;   Group 1:  kuro--read-u32-le — basic decoding
;;   Group 5:  kuro--decode-face-ranges, kuro--decode-col-to-buf
;;   Group 6:  kuro--read-u32-le — edge cases
;;   Group 9:  kuro--decode-face-ranges — additional cases
;;   Group 10: kuro--decode-col-to-buf — additional cases
;;   Group 15: kuro--decode-binary-updates-with-strings
;;   Group 16: kuro--poll-updates-binary-optimised

;;; Code:

(require 'ert)
(require 'cl-lib)
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

;;; Groups 1 + 6: kuro--read-u32-le

(defconst kuro-binary-decoder-test--read-u32-le-table
  ;;  test-name                                        bytes-vector                            offset  expected
  '((kuro-binary-decoder-read-u32-le-zero              [0 0 0 0]                               0       0)
    (kuro-binary-decoder-read-u32-le-one               [1 0 0 0]                               0       1)
    (kuro-binary-decoder-read-u32-le-max-u8            [255 0 0 0]                             0       255)
    (kuro-binary-decoder-read-u32-le-multi-byte        [#x04 #x03 #x02 #x01]                  0       #x01020304)
    (kuro-binary-decoder-read-u32-le-with-offset       [0 0 #x78 #x56 #x34 #x12]              2       #x12345678)
    (kuro-binary-decoder-read-u32-le-known-value       [#x78 #x56 #x34 #x12]                  0       #x12345678)
    (kuro-binary-decoder-read-u32-le-max-value         [#xFF #xFF #xFF #xFF]                   0       #xFFFFFFFF)
    (kuro-binary-decoder-read-u32-le-exact-four-bytes  [42 0 0 0]                              0       42)
    (kuro-binary-decoder-read-u32-le-mid-vector-offset [0 0 0 0 #x78 #x56 #x34 #x12 0 0 0 0] 4       #x12345678))
  "Table of (test-name byte-vector offset expected) for `kuro--read-u32-le'.")

(defmacro kuro-binary-decoder-test--def-read-u32-le (test-name bytes offset expected)
  `(ert-deftest ,test-name ()
     ,(format "`kuro--read-u32-le' %S at offset %d → #x%X." bytes offset expected)
     (should (= (kuro--read-u32-le ,bytes ,offset) ,expected))))

(kuro-binary-decoder-test--def-read-u32-le kuro-binary-decoder-read-u32-le-zero              [0 0 0 0]                               0 0)
(kuro-binary-decoder-test--def-read-u32-le kuro-binary-decoder-read-u32-le-one               [1 0 0 0]                               0 1)
(kuro-binary-decoder-test--def-read-u32-le kuro-binary-decoder-read-u32-le-max-u8            [255 0 0 0]                             0 255)
(kuro-binary-decoder-test--def-read-u32-le kuro-binary-decoder-read-u32-le-multi-byte        [#x04 #x03 #x02 #x01]                  0 #x01020304)
(kuro-binary-decoder-test--def-read-u32-le kuro-binary-decoder-read-u32-le-with-offset       [0 0 #x78 #x56 #x34 #x12]              2 #x12345678)
(kuro-binary-decoder-test--def-read-u32-le kuro-binary-decoder-read-u32-le-known-value       [#x78 #x56 #x34 #x12]                  0 #x12345678)
(kuro-binary-decoder-test--def-read-u32-le kuro-binary-decoder-read-u32-le-max-value         [#xFF #xFF #xFF #xFF]                   0 #xFFFFFFFF)
(kuro-binary-decoder-test--def-read-u32-le kuro-binary-decoder-read-u32-le-exact-four-bytes  [42 0 0 0]                              0 42)
(kuro-binary-decoder-test--def-read-u32-le kuro-binary-decoder-read-u32-le-mid-vector-offset [0 0 0 0 #x78 #x56 #x34 #x12 0 0 0 0] 4 #x12345678)

(ert-deftest kuro-binary-decoder-test--all-read-u32-le-correct ()
  "All kuro-binary-decoder-test--read-u32-le-table entries decode correctly."
  (dolist (entry kuro-binary-decoder-test--read-u32-le-table)
    (pcase-let ((`(,_name ,bytes ,offset ,expected) entry))
      (should (= (kuro--read-u32-le bytes offset) expected)))))

(ert-deftest kuro-binary-decoder-read-u32-le-rejects-non-vector ()
  "kuro--read-u32-le rejects non-vector input."
  (should-error (kuro--read-u32-le '(0 0 0 0) 0)))

(ert-deftest kuro-binary-decoder-read-u32-le-rejects-negative-offset ()
  "kuro--read-u32-le rejects negative offsets."
  (should-error (kuro--read-u32-le [0 0 0 0] -1)))

(ert-deftest kuro-binary-decoder-read-u32-le-rejects-truncated-vector ()
  "kuro--read-u32-le rejects truncated input before byte reads."
  (should-error (kuro--read-u32-le [0 0 0] 0)))

(ert-deftest kuro-binary-decoder-read-u32-le-rejects-negative-byte ()
  "kuro--read-u32-le rejects byte values below 0."
  (should-error (kuro--read-u32-le [-1 0 0 0] 0)))

(ert-deftest kuro-binary-decoder-read-u32-le-rejects-overflow-byte ()
  "kuro--read-u32-le rejects byte values above 255."
  (should-error (kuro--read-u32-le [256 0 0 0] 0)))

(ert-deftest kuro-binary-decoder-read-u32-le-rejects-nonnumeric-byte ()
  "kuro--read-u32-le rejects non-integer byte values."
  (should-error (kuro--read-u32-le ["x" 0 0 0] 0)))

;;; Group 5: kuro--decode-face-ranges, kuro--decode-col-to-buf

(ert-deftest kuro-binary-decoder-decode-face-ranges-empty ()
  "kuro--decode-face-ranges with 0 ranges returns an empty vector and sets kuro--decode-pos."
  (let ((v (make-vector 0 0)))
    (let* ((face-list (kuro--decode-face-ranges v 0 0 nil))
           (new-pos kuro--decode-pos))
      (should (vectorp face-list))
      (should (= (length face-list) 0))
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

(ert-deftest kuro-binary-decoder-decode-face-ranges-rejects-negative-count ()
  "kuro--decode-face-ranges rejects negative range counts."
  (should-error (kuro--decode-face-ranges [] 0 -1 nil)))

(ert-deftest kuro-binary-decoder-decode-face-ranges-rejects-truncated-v2-range ()
  "kuro--decode-face-ranges rejects truncated v2 range payloads before allocation."
  (should-error (kuro--decode-face-ranges [0 0 0 0] 0 1 t)))

(ert-deftest kuro-binary-decoder-decode-face-ranges-rejects-huge-count-before-allocation ()
  "kuro--decode-face-ranges rejects huge counts when bytes are unavailable."
  (should-error (kuro--decode-face-ranges [] 0 #x100000 nil)))

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
                   (kuro-binary-decoder-test--make-u32-le 5)))))
    (let* ((col-to-buf (kuro--decode-col-to-buf v 4))
           (new-pos kuro--decode-pos))
      (should (= (aref col-to-buf 0) 5))
      (should (= new-pos 12)))))

(ert-deftest kuro-binary-decoder-decode-col-to-buf-rejects-truncated-header ()
  "kuro--decode-col-to-buf rejects missing length bytes."
  (should-error (kuro--decode-col-to-buf [1 0 0] 0)))

(ert-deftest kuro-binary-decoder-decode-col-to-buf-rejects-truncated-entry ()
  "kuro--decode-col-to-buf rejects missing entry bytes before allocation."
  (should-error (kuro--decode-col-to-buf [1 0 0 0 5] 0)))

(ert-deftest kuro-binary-decoder-decode-col-to-buf-rejects-huge-length-before-allocation ()
  "kuro--decode-col-to-buf rejects huge lengths when bytes are unavailable."
  (let ((vec (apply #'vector (kuro-binary-decoder-test--make-u32-le #x100000))))
    (should-error (kuro--decode-col-to-buf vec 0))))

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

(defun kuro-binary-decoder-test--make-v1-frame-row (row-index text-strings-count)
  "Build a v1 frame with TEXT-STRINGS-COUNT rows, all at sequential indices from ROW-INDEX.
Each row has 0 face ranges, text_byte_len=0, and no col-to-buf entries."
  (let* ((make-row (lambda (idx)
                     (append
                      (kuro-binary-decoder-test--make-u32-le idx)  ; row_index
                      (kuro-binary-decoder-test--make-u32-le 0)    ; num_face_ranges
                      (kuro-binary-decoder-test--make-u32-le 0)    ; text_byte_len
                      (kuro-binary-decoder-test--make-u32-le 0)))) ; col_to_buf_len
         (row-bytes (mapcan make-row
                            (number-sequence row-index (+ row-index (1- text-strings-count)))))
         (frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 1)              ; format_version=1
           (kuro-binary-decoder-test--make-u32-le text-strings-count)
           row-bytes)))
    (apply #'vector frame-bytes)))

(ert-deftest kuro-binary-decoder-decode-with-strings-empty-frame-returns-nil ()
  "kuro--decode-binary-updates-with-strings returns nil for a 0-row frame."
  (let* ((empty-frame (apply #'vector
                             (append (kuro-binary-decoder-test--make-u32-le 2)
                                     (kuro-binary-decoder-test--make-u32-le 0))))
         (result (kuro--decode-binary-updates-with-strings (vector) empty-frame)))
    (should (null result))))

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

(ert-deftest kuro-binary-decoder-decode-with-strings-multi-row ()
  "kuro--decode-binary-updates-with-strings decodes 3 rows in correct order.
Row indices come from the binary data; text strings come from the vector."
  (let* ((text-strings (vector "row-A" "row-B" "row-C"))
         ;; 3 rows: indices 10, 20, 30
         (make-row (lambda (idx)
                     (append
                      (kuro-binary-decoder-test--make-u32-le idx)  ; row_index
                      (kuro-binary-decoder-test--make-u32-le 0)    ; num_face_ranges
                      (kuro-binary-decoder-test--make-u32-le 0)    ; text_byte_len=0
                      (kuro-binary-decoder-test--make-u32-le 0)))) ; col_to_buf_len
         (frame-bytes (append
                       (kuro-binary-decoder-test--make-u32-le 2)   ; format_version=2
                       (kuro-binary-decoder-test--make-u32-le 3)   ; num_rows=3
                       (funcall make-row 10)
                       (funcall make-row 20)
                       (funcall make-row 30)))
         (vec (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates-with-strings text-strings vec)))
    (should (= (length result) 3))
    ;; Verify row indices preserved
    (should (= (aref (aref result 0) 0) 10))
    (should (= (aref (aref result 1) 0) 20))
    (should (= (aref (aref result 2) 0) 30))
    ;; Verify text from string vector
    (should (equal (aref (aref result 0) 1) "row-A"))
    (should (equal (aref (aref result 1) 1) "row-B"))
    (should (equal (aref (aref result 2) 1) "row-C"))))

(ert-deftest kuro-binary-decoder-decode-with-strings-v1-format ()
  "kuro--decode-binary-updates-with-strings handles v1 format (24-byte face ranges)."
  ;; v1 frame with 1 row, 1 face range (24 bytes: no ul-color)
  (let* ((range-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 0)    ; start_buf=0
           (kuro-binary-decoder-test--make-u32-le 5)    ; end_buf=5
           (kuro-binary-decoder-test--make-u32-le #xFF) ; fg
           (kuro-binary-decoder-test--make-u32-le 0)    ; bg
           (kuro-binary-decoder-test--make-u64-le 1)))  ; flags=1 (bold)
         (frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 1)    ; format_version=1
           (kuro-binary-decoder-test--make-u32-le 1)    ; num_rows=1
           (kuro-binary-decoder-test--make-u32-le 2)    ; row_index=2
           (kuro-binary-decoder-test--make-u32-le 1)    ; num_face_ranges=1
           (kuro-binary-decoder-test--make-u32-le 0)    ; text_byte_len=0
           range-bytes
           (kuro-binary-decoder-test--make-u32-le 0)))  ; col_to_buf_len=0
         (vec (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates-with-strings (vector "v1-text") vec))
         (entry (aref result 0)))
    (should (= (length result) 1))
    (should (= (aref entry 0) 2))                 ; row index
    (should (equal (aref entry 1) "v1-text"))      ; text from string vector
    ;; face-ranges is stride-6: [start end fg bg flags ul] (ul=0 for v1)
    (let ((fr (aref entry 2)))
      (should (= (/ (length fr) 6) 1))
      (should (= (aref fr 0) 0))   ; start_buf
      (should (= (aref fr 1) 5))   ; end_buf
      (should (= (aref fr 4) 1))   ; flags
      (should (= (aref fr 5) 0))))) ; ul-color absent in v1 → 0

(ert-deftest kuro-binary-decoder-decode-with-strings-col-to-buf-preserved ()
  "kuro--decode-binary-updates-with-strings correctly decodes col-to-buf entries."
  ;; Row with 2 col-to-buf entries: [3, 7]
  (let* ((frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 2)   ; format_version=2
           (kuro-binary-decoder-test--make-u32-le 1)   ; num_rows=1
           (kuro-binary-decoder-test--make-u32-le 0)   ; row_index=0
           (kuro-binary-decoder-test--make-u32-le 0)   ; num_face_ranges=0
           (kuro-binary-decoder-test--make-u32-le 0)   ; text_byte_len=0
           (kuro-binary-decoder-test--make-u32-le 2)   ; col_to_buf_len=2
           (kuro-binary-decoder-test--make-u32-le 3)   ; entry 0
           (kuro-binary-decoder-test--make-u32-le 7))) ; entry 1
         (vec (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates-with-strings (vector "text") vec))
         (c2b (aref (aref result 0) 3)))
    (should (vectorp c2b))
    (should (= (length c2b) 2))
    (should (= (aref c2b 0) 3))
    (should (= (aref c2b 1) 7))))

(ert-deftest kuro-binary-decoder-decode-with-strings-errors-on-unknown-version ()
  "kuro--decode-binary-updates-with-strings signals error for unsupported format version."
  (let* ((frame-bytes
          (append (kuro-binary-decoder-test--make-u32-le 99)   ; format_version=99
                  (kuro-binary-decoder-test--make-u32-le 0)))  ; num_rows=0
         (vec (apply #'vector frame-bytes)))
    (should-error (kuro--decode-binary-updates-with-strings (vector) vec))))

(ert-deftest kuro-binary-decoder-decode-with-strings-rejects-non-vector-texts ()
  "kuro--decode-binary-updates-with-strings rejects non-vector text payloads."
  (let ((vec (kuro-binary-decoder-test--make-v2-frame-no-text 0 0)))
    (should-error (kuro--decode-binary-updates-with-strings '("x") vec))))

(ert-deftest kuro-binary-decoder-decode-with-strings-rejects-text-count-mismatch ()
  "kuro--decode-binary-updates-with-strings requires one text string per row."
  (let ((vec (kuro-binary-decoder-test--make-v2-frame-no-text 0 0)))
    (should-error (kuro--decode-binary-updates-with-strings (vector "x" "y") vec))))

(ert-deftest kuro-binary-decoder-decode-with-strings-rejects-non-string-text-entry ()
  "kuro--decode-binary-updates-with-strings rejects non-string text entries."
  (let ((vec (kuro-binary-decoder-test--make-v2-frame-no-text 0 0)))
    (should-error (kuro--decode-binary-updates-with-strings (vector 42) vec))))

(ert-deftest kuro-binary-decoder-decode-with-strings-rejects-truncated-header ()
  "kuro--decode-binary-updates-with-strings rejects incomplete frame headers."
  (should-error (kuro--decode-binary-updates-with-strings (vector) [2 0 0])))

(ert-deftest kuro-binary-decoder-decode-with-strings-rejects-text-bytes ()
  "kuro--decode-binary-updates-with-strings rejects non-zero text byte lengths."
  (let* ((frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 2)
           (kuro-binary-decoder-test--make-u32-le 1)
           (kuro-binary-decoder-test--make-u32-le 0)
           (kuro-binary-decoder-test--make-u32-le 0)
           (kuro-binary-decoder-test--make-u32-le 1)
           (kuro-binary-decoder-test--make-u32-le 0)))
         (vec (apply #'vector frame-bytes)))
    (should-error (kuro--decode-binary-updates-with-strings (vector "x") vec))))

(ert-deftest kuro-binary-decoder-decode-with-strings-rejects-trailing-bytes ()
  "kuro--decode-binary-updates-with-strings rejects trailing bytes after rows."
  (let ((vec (vconcat (kuro-binary-decoder-test--make-v2-frame-no-text 0 0) [99])))
    (should-error (kuro--decode-binary-updates-with-strings (vector "x") vec))))

(ert-deftest kuro-binary-decoder-decode-with-strings-rejects-invalid-byte ()
  "kuro--decode-binary-updates-with-strings rejects non-byte frame values."
  (let ((vec (kuro-binary-decoder-test--make-v2-frame-no-text 0 0)))
    (aset vec 0 256)
    (should-error (kuro--decode-binary-updates-with-strings (vector "x") vec))))

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

(ert-deftest kuro-binary-decoder-poll-optimised-rejects-non-cons-result ()
  "kuro--poll-updates-binary-optimised rejects non-cons FFI results."
  (cl-letf (((symbol-function 'kuro-core-poll-updates-binary-with-strings)
             (lambda (_id) [1 2 3])))
    (should-error (kuro--poll-updates-binary-optimised 'fake-id))))

(ert-deftest kuro-binary-decoder-poll-optimised-rejects-non-vector-text-payload ()
  "kuro--poll-updates-binary-optimised rejects non-vector text payloads."
  (cl-letf (((symbol-function 'kuro-core-poll-updates-binary-with-strings)
             (lambda (_id) (cons '("x") []))))
    (should-error (kuro--poll-updates-binary-optimised 'fake-id))))

(ert-deftest kuro-binary-decoder-poll-optimised-rejects-non-vector-byte-payload ()
  "kuro--poll-updates-binary-optimised rejects non-vector byte payloads."
  (cl-letf (((symbol-function 'kuro-core-poll-updates-binary-with-strings)
             (lambda (_id) (cons (vector "x") '(1 2 3)))))
    (should-error (kuro--poll-updates-binary-optimised 'fake-id))))

;;; ── Binary format version constants ──────────────────────────────────────────

(ert-deftest kuro-binary-decoder-format-version-v1-is-1 ()
  "`kuro--binary-format-version-v1' is 1 (wire encoding for v1 frames)."
  (should (= kuro--binary-format-version-v1 1)))

(ert-deftest kuro-binary-decoder-format-version-v2-is-2 ()
  "`kuro--binary-format-version-v2' is 2 (wire encoding for v2 frames with ul-color)."
  (should (= kuro--binary-format-version-v2 2)))

(ert-deftest kuro-binary-decoder-format-versions-are-distinct ()
  "`kuro--binary-format-version-v1' and `kuro--binary-format-version-v2' must differ."
  (should (/= kuro--binary-format-version-v1 kuro--binary-format-version-v2)))

(provide 'kuro-binary-decoder-test)

;;; kuro-binary-decoder-test.el ends here
