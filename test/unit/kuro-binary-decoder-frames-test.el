;;; kuro-binary-decoder-ext-test.el --- Extended unit tests for kuro-binary-decoder.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Extended unit tests for the binary FFI frame decoder (kuro-binary-decoder.el).
;; Tests are pure Emacs Lisp and do NOT require the Rust dynamic module.
;;
;; Groups covered:
;;   Group 8:  kuro--decode-row-text — additional cases
;;   Group 9:  kuro--decode-face-ranges — additional cases
;;   Group 10: kuro--decode-col-to-buf — additional cases
;;   Group 11: kuro--decode-binary-updates — frame structure edge cases
;;   Group 12: kuro--decode-binary-updates — high row indices and face ordering
;;   Group 13: kuro--decode-row-text — 4-byte UTF-8 and offset advancement
;;   Group 14: kuro--decode-binary-frame-rows — CPS text-fn continuation
;;   Group 15: kuro--decode-binary-updates-with-strings
;;   Group 16: kuro--poll-updates-binary-optimised

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
  "kuro--decode-face-ranges decodes maximum u64 flags value correctly."
  ;; flags = 0xFFFFFFFFFFFFFFFF (all bits set — all SGR flags combined)
  (let* ((v (apply #'vector
                   (append
                    (kuro-binary-decoder-test--make-u32-le 0)   ; start_buf
                    (kuro-binary-decoder-test--make-u32-le 10)  ; end_buf
                    (kuro-binary-decoder-test--make-u32-le 0)   ; fg
                    (kuro-binary-decoder-test--make-u32-le 0)   ; bg
                    (kuro-binary-decoder-test--make-u64-le #xFFFFFFFFFFFFFFFF)))) ; flags
         (result (kuro--decode-face-ranges v 0 1 kuro--binary-format-version-v1)))
    (should (= (length (car result)) 1))
    (should (= (nth 4 (caar result)) #xFFFFFFFFFFFFFFFF))
    (should (= (cdr result) 24))))

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
         (result (kuro--decode-face-ranges v 0 3 kuro--binary-format-version-v1)))
    (should (= (length (car result)) 3))
    (should (= (cdr result) 72))))    ; 3 × 24 bytes

;;; Group 10: kuro--decode-col-to-buf — additional cases

(ert-deftest kuro-binary-decoder-decode-col-to-buf-single-entry ()
  "kuro--decode-col-to-buf decodes a single-entry col-to-buf mapping."
  ;; Format: len=1 (u32 LE), then 1 u32 entry [7]
  (let ((v (kuro-binary-decoder-test--make-vec
            1 0 0 0    ; length = 1
            7 0 0 0))) ; entry 0 = 7
    (pcase-let ((`(,col-to-buf . ,new-pos) (kuro--decode-col-to-buf v 0)))
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
    (pcase-let ((`(,col-to-buf . ,_new-pos) (kuro--decode-col-to-buf v 0)))
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
    (pcase-let ((`(,col-to-buf . ,new-pos) (kuro--decode-col-to-buf v 4)))
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
    (let* ((entry (car result))
           (c2b (cdr entry)))
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
    ;; Each entry: (((row-index . text) . face-list) . col-to-buf)
    ;; row-index = (car (car (car entry)))
    (should (= (car (car (car (car result)))) 10))
    (should (= (car (car (car (cadr result)))) 20))
    (should (= (car (car (car (caddr result)))) 30))))

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
    (should (= (car (car (car (car result)))) row-idx))))

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
    (let* ((entry (car result))
           (face-list (cdr (car entry))))
      (should (= (length face-list) 2))
      ;; First face range must have start_buf=0
      (should (= (nth 0 (car face-list)) 0))
      ;; Second face range must have start_buf=5
      (should (= (nth 0 (cadr face-list)) 5)))))

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
    (should (= (length (cdr (car result))) 0))         ; row 0: empty vector
    (should (= (length (cdr (cadr result))) 1))        ; row 1: 1 entry
    (should (= (aref (cdr (cadr result)) 0) 42))       ; row 1 entry value
    (should (= (length (cdr (caddr result))) 2))       ; row 2: 2 entries
    (should (= (aref (cdr (caddr result)) 0) 10))
    (should (= (aref (cdr (caddr result)) 1) 20))))

(ert-deftest kuro-binary-decoder-decode-updates-result-is-list ()
  "kuro--decode-binary-updates returns a proper list (not a vector or other type)."
  (let* ((frame-bytes
          (append
           (kuro-binary-decoder-test--make-u32-le 1)
           (kuro-binary-decoder-test--make-u32-le 0)
           (kuro-binary-decoder-test--make-u32-le 0)
           (kuro-binary-decoder-test--make-u32-le 0)
           (kuro-binary-decoder-test--make-u32-le 0)))
         (v (apply #'vector frame-bytes))
         (result (kuro--decode-binary-updates v)))
    (should (listp result))
    (should-not (vectorp result))))

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
    (should (equal (cdr (car (car (car result)))) "CUSTOM"))))

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
Each entry has structure (((row-index . text) . face-list) . col-to-buf)."
  (let* ((text-strings (vector "row-text"))
         (vec (kuro-binary-decoder-test--make-v2-frame-no-text 3 0))
         (result (kuro--decode-binary-updates-with-strings text-strings vec))
         (entry (car result)))
    ;; (cdr (caar entry)) = (cdr (row-index . text)) = text
    (should (equal (cdr (caar entry)) "row-text"))))

(ert-deftest kuro-binary-decoder-decode-with-strings-row-index-preserved ()
  "kuro--decode-binary-updates-with-strings preserves the row index from binary data."
  (let* ((text-strings (vector "x"))
         (vec (kuro-binary-decoder-test--make-v2-frame-no-text 7 0))
         (result (kuro--decode-binary-updates-with-strings text-strings vec))
         (entry (car result)))
    ;; (car (caar entry)) = (car (row-index . text)) = row-index
    (should (= (car (caar entry)) 7))))

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
             (entry (car result)))
        (should result)
        (should (= (length result) 1))
        ;; entry structure: (((row-index . text) . face-list) . col-to-buf)
        (should (equal (cdr (caar entry)) "decoded-row"))))))

(provide 'kuro-binary-decoder-ext-test)

;;; kuro-binary-decoder-ext-test.el ends here
