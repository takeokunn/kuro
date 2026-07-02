;;; kuro-binary-decoder.el --- Binary FFI frame decoder for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn

;;; Commentary:

;; This file implements the binary FFI frame decoder for Kuro.
;;
;; # Responsibilities
;;
;; - Decode the compact binary frame format produced by `encode_screen_binary'
;;   in rust-core/src/ffi/codec.rs into the same structure that
;;   `kuro--apply-dirty-lines' expects.
;; - Provide low-level byte readers (`kuro--read-u32-le') and per-section
;;   decoders (`kuro--decode-face-ranges', `kuro--decode-col-to-buf').
;;
;; # Binary Frame Format
;;
;; See `encode_screen_binary' in rust-core/src/ffi/codec.rs for the canonical
;; layout.  Each frame is a flat vector of byte integers (0–255) structured as:
;;
;;   [format_version: u32 LE]  (version 1 = current; version 2 = 28-byte face ranges)
;;   [num_rows: u32 LE]
;;   For each row:
;;     [row_index: u32 LE] [num_face_ranges: u32 LE] [text_byte_len: u32 LE]
;;     [text: text_byte_len bytes (UTF-8)]
;;     For each face range (28 bytes, version 2; 24 bytes, version 1):
;;       [start_buf: u32 LE] [end_buf: u32 LE]
;;       [fg: u32 LE] [bg: u32 LE] [flags: u64 LE]
;;       [ul_color: u32 LE]  (version 2 only)
;;     [col_to_buf_len: u32 LE]
;;     [col_to_buf entries: col_to_buf_len × u32 LE]
;;
;; # Hot Path
;;
;; The production path is `kuro--poll-updates-binary-optimised', which calls
;; `kuro-core-poll-updates-binary-with-strings' (text supplied as a separate
;; string vector) and decodes via `kuro--decode-binary-updates-with-strings'.
;; The text_byte_len field is always 0 on this path.

;;; Code:

;; Declare the binary FFI functions provided by the Rust dynamic module.
(declare-function kuro-core-poll-updates-binary-with-strings "ext:kuro-core" (session-id))
(require 'kuro-binary-decoder-macros)

;;; Format version constants

(defconst kuro--binary-format-version-v1 1
  "Binary frame format version 1: 8-byte header, 24-byte face ranges.")

(defconst kuro--binary-format-version-v2 2
  "Binary frame format version 2: 8-byte header, 28-byte face ranges.
Adds underline_color field compared to v1.")

;;; Scratch variable for decoder position advancement

(defvar kuro--decode-pos 0
  "Scratch variable for decoder position advancement.
`kuro--decode-face-ranges' and `kuro--decode-col-to-buf' set this to the
byte offset immediately after the decoded section, eliminating the cons
cell that would otherwise allocate a (RESULT . NEW-POS) pair at 3,600+
calls/sec in the hot decode path.")

;;; Low-level byte readers

(defun kuro--binary-decoder-error (format-string &rest args)
  "Signal a malformed binary frame error using FORMAT-STRING and ARGS."
  (apply #'error (concat "Kuro: malformed binary frame: " format-string) args))

(defsubst kuro--require-bytes (vec offset byte-count context)
  "Require BYTE-COUNT bytes from VEC at OFFSET for CONTEXT."
  (let ((end (+ offset byte-count)))
    (when (or (< offset 0) (< byte-count 0) (> end (length vec)))
      (kuro--binary-decoder-error
       "%s requires %d byte(s) at offset %d, frame length %d"
       context byte-count offset (length vec)))))

(defsubst kuro--read-u32-le (vec offset)
  "Read a u32 little-endian integer from VEC at byte OFFSET.
VEC must be an Emacs vector of integer byte values (0–255).
Returns a non-negative integer.
Chained `1+' avoids three generic `+' bytecodes; at 1,440 calls/frame this
saves ~4,320 add operations per frame vs the `(+ offset N)' form."
  (kuro--require-bytes vec offset 4 "u32")
  (let* ((o1 (1+ offset))
         (o2 (1+ o1))
         (o3 (1+ o2)))
    (logior (aref vec offset)
            (ash (aref vec o1) 8)
            (ash (aref vec o2) 16)
            (ash (aref vec o3) 24))))

;;; Per-section decoders

(defun kuro--decode-face-ranges (vec pos num-face-ranges v2-p)
  "Decode NUM-FACE-RANGES face tuples from VEC starting at byte offset POS.
V2-P is a pre-computed boolean (non-nil when format-version ≥ 2) that the
caller evaluates once per frame rather than once per row, eliminating a
redundant integer comparison per dirty row.
  v2-p non-nil: 28 bytes per range — adds ul-color(u32) at offset 24.
  v2-p nil:     24 bytes — start-buf(u32) end-buf(u32) fg(u32)
    bg(u32) flags(u64)
Returns FACE-RANGES-FLAT-VECTOR directly: nil when NUM-FACE-RANGES is 0
\(callers may guard on null), or a FLAT vector of (* 6 NUM-FACE-RANGES)
integers otherwise.  Sets `kuro--decode-pos' to the byte offset
immediately after the decoded section — eliminates the (RESULT .
NEW-POS) cons at ~3,600/sec.
Layout: [s0 e0 fg0 bg0 f0 ul0 s1 e1 fg1 bg1 f1 ul1 ...] — stride 6.
Stride-6 eliminates the N inner-vector allocations that the old
vector-of-vectors layout required, cutting ~21,600 allocs/sec at 120fps
× 30 dirty rows × 6 face ranges/row.

`flags' is read as u32 (not u64) because `encode_attrs' in Rust produces
values in 0..=0xBFF (9 SGR flag bits + 3 underline-style bits — 12 bits
total).  The upper 4 bytes on the wire are always 0x00000000.  Reading only
the low u32 avoids the `(ash high-word 32)' bignum allocation that
`kuro--read-u64-le' would otherwise incur on every face range decoded."
  (let ((required-bytes (* num-face-ranges (if v2-p 28 24))))
    (kuro--require-bytes vec pos required-bytes "face ranges"))
  (if (zerop num-face-ranges)
      ;; Zero-range fast exit: nil is the canonical no-face-ranges value.
      ;; No allocation needed.
      (progn (setq kuro--decode-pos pos) nil)
    (let ((result (make-vector (* 6 num-face-ranges) 0))
          (base 0)
          (end  (* 6 num-face-ranges)))
      (if v2-p
          ;; v2: 28-byte stride; ul-color present.  kuro--decode-face-range-step
          ;; is specialized at compile time with ul-p=t — no runtime branch.
          (while (< base end)
            (kuro--decode-face-range-step result vec pos base t))
        ;; v1: 24-byte stride; ul-color absent (slot stays 0 from make-vector).
        (while (< base end)
          (kuro--decode-face-range-step result vec pos base nil)))
      (setq kuro--decode-pos pos)
      result)))

(defsubst kuro--decode-col-to-buf (vec pos)
  "Decode a col-to-buf vector from VEC starting at byte offset POS.
Format: u32 length followed by that many u32 entries.
Returns the VECTOR directly (empty vector when length is zero; no CJK
wide characters on this row).  Sets `kuro--decode-pos' to the byte offset
immediately after the decoded section — eliminates the (VECTOR . NEW-POS)
cons cell allocation at ~3,600 calls/sec in the hot decode path."
  (kuro--require-bytes vec pos 4 "col-to-buf length")
  (let* ((ctb-len (kuro--read-u32-le vec pos))
         (pos (+ pos 4)))
    (kuro--require-bytes vec pos (* ctb-len 4) "col-to-buf entries")
    (if (zerop ctb-len)
        (progn (setq kuro--decode-pos pos) [])
      (let ((v (make-vector ctb-len 0))
            (i 0))
        (while (< i ctb-len)
          (aset v i (kuro--read-u32-le vec pos))
          ;; Chained 1+ avoids (+ pos 4) generic add; 4 increment bytecodes.
          (setq i (1+ i) pos (1+ (1+ (1+ (1+ pos))))))
        (setq kuro--decode-pos pos)
        v))))

;;; Optimised decoder using native Emacs strings from Rust

(defun kuro--decode-binary-updates-with-strings (text-strings vec)
  "Decode binary VEC using pre-supplied native TEXT-STRINGS.
Without funcall overhead:
TEXT-STRINGS is a vector of strings (one per dirty row) from
`kuro-core-poll-updates-binary-with-strings'.  VEC carries only
face/col-to-buf data; `text_byte_len' is always 0 in this path.

Inlines the text acquisition step (was `funcall text-fn') to eliminate
one closure dispatch per dirty row — allows the bytecode compiler to inline
the direct `aref text-strings idx' without going through an indirect call.
At 30 dirty rows × 120fps = 3600 saved funcall frames/sec."
  (unless (vectorp text-strings)
    (kuro--binary-decoder-error "text-strings must be a vector"))
  (kuro--require-bytes vec 0 8 "frame header")
  (let ((format-version (kuro--read-u32-le vec 0)))
    (unless (or (= format-version kuro--binary-format-version-v1)
                (= format-version kuro--binary-format-version-v2))
      (error "Kuro: unsupported binary format version %d" format-version))
    (let* ((num-rows         (kuro--read-u32-le vec 4))
           (pos              8)
           (face-ranges-v2-p (>= format-version 2)))
      (unless (= (length text-strings) num-rows)
        (kuro--binary-decoder-error
         "text-strings length %d does not match row count %d"
         (length text-strings) num-rows))
      ;; Each row has at least a 12-byte row header and a 4-byte
      ;; col-to-buf length. Validate this lower bound before allocating the
      ;; result vector so hostile row counts cannot force huge allocations.
      (kuro--require-bytes vec pos (* num-rows 16) "row minimum payload")
      ;; `while' with explicit counter produces tighter bytecode than `dotimes'
      ;; (consistent with kuro--apply-dirty-lines, kuro--decode-face-ranges, etc.)
      (let ((result (when (> num-rows 0) (make-vector num-rows nil)))
            (i 0))
        (while (< i num-rows)
          (kuro--require-bytes vec pos 12 "row header")
          (let* ((pos4            (+ pos 4))
                 (row-index       (kuro--read-u32-le vec pos))
                 (num-face-ranges (kuro--read-u32-le vec pos4))
                 (text-byte-len   (kuro--read-u32-le vec (+ pos4 4))))
            (unless (zerop text-byte-len)
              (kuro--binary-decoder-error
               "with-strings row %d has non-zero text_byte_len %d"
               i text-byte-len))
            (setq pos (+ pos4 8))
            ;; Inline text acquisition: direct aref instead of (funcall text-fn ...).
            ;; kuro--decode-face-ranges and kuro--decode-col-to-buf return the primary
            ;; result directly and set kuro--decode-pos (no cons allocation).
            (let* ((text      (aref text-strings i))
                   (face-list (kuro--decode-face-ranges vec pos num-face-ranges face-ranges-v2-p))
                   (p2        kuro--decode-pos)
                   (col-to-buf (kuro--decode-col-to-buf vec p2))
                   (p3        kuro--decode-pos))
              (setq pos p3)
              (aset result i (vector row-index text face-list col-to-buf))))
          (setq i (1+ i)))
        (unless (= pos (length vec))
          (kuro--binary-decoder-error
           "trailing %d byte(s) after %d row(s)"
           (- (length vec) pos) num-rows))
        result))))

(defun kuro--poll-updates-binary-optimised (session-id)
  "Poll dirty lines for SESSION-ID using the text-string-optimised FFI path.
Calls `kuro-core-poll-updates-binary-with-strings', which returns a cons
cell `(TEXT-STRINGS . BINARY-DATA)', then decodes it with
`kuro--decode-binary-updates-with-strings'.

Returns nil when there are no dirty lines (FFI returned nil).
Otherwise returns the decoded dirty-line list in the same format as
the render pipeline expects."
  (let ((result (kuro-core-poll-updates-binary-with-strings session-id)))
    (when result
      (kuro--decode-binary-updates-with-strings (car result) (cdr result)))))

(provide 'kuro-binary-decoder)

;;; kuro-binary-decoder.el ends here
