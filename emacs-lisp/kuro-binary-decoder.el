;;; kuro-binary-decoder.el --- Binary FFI frame decoder for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn
;; Version: 1.0.0

;;; Commentary:

;; This file implements the binary FFI frame decoder for Kuro.
;;
;; # Responsibilities
;;
;; - Decode the compact binary frame format produced by `encode_screen_binary'
;;   in rust-core/src/ffi/codec.rs into the same structure that
;;   `kuro--apply-dirty-lines' expects.
;; - Provide low-level byte readers (`kuro--read-u32-le', `kuro--read-u64-le')
;;   and per-section decoders (`kuro--decode-row-text', `kuro--decode-face-ranges',
;;   `kuro--decode-col-to-buf').
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

;;; Code:

;; Declare the binary FFI functions provided by the Rust dynamic module.
(declare-function kuro-core-poll-updates-binary "ext:kuro-core" (session-id))
(declare-function kuro-core-poll-updates-binary-with-strings "ext:kuro-core" (session-id))

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

(defsubst kuro--read-u32-le (vec offset)
  "Read a u32 little-endian integer from VEC at byte OFFSET.
VEC must be an Emacs vector of integer byte values (0–255).
Returns a non-negative integer.
Chained `1+' avoids three generic `+' bytecodes; at 1,440 calls/frame this
saves ~4,320 add operations per frame vs the `(+ offset N)' form."
  (let* ((o1 (1+ offset))
         (o2 (1+ o1))
         (o3 (1+ o2)))
    (logior (aref vec offset)
            (ash (aref vec o1) 8)
            (ash (aref vec o2) 16)
            (ash (aref vec o3) 24))))

;;; Per-section decoders

(defun kuro--decode-row-text (vec pos text-byte-len)
  "Decode TEXT-BYTE-LEN raw UTF-8 bytes from VEC at byte offset POS.
Returns a cons cell (TEXT . NEW-POS) where TEXT is the decoded Emacs string
and NEW-POS is the byte offset after the text data.
Note: this function is only active on the non-with-strings fallback path;
the `kuro--poll-updates-binary-optimised' hot path bypasses it entirely."
  (let ((text-bytes (make-string text-byte-len 0))
        (p pos)
        (i 0))
    (while (< i text-byte-len)
      (aset text-bytes i (aref vec p))
      (setq i (1+ i) p (1+ p)))
    (cons (decode-coding-string text-bytes 'utf-8-unix)
          (+ pos text-byte-len))))

(defun kuro--decode-face-ranges (vec pos num-face-ranges v2-p)
  "Decode NUM-FACE-RANGES face tuples from VEC starting at byte offset POS.
V2-P is a pre-computed boolean (non-nil when format-version ≥ 2) that the
caller evaluates once per frame rather than once per row, eliminating a
redundant integer comparison per dirty row.
  v2-p non-nil: 28 bytes per range — adds ul-color(u32) at offset 24.
  v2-p nil:     24 bytes — start-buf(u32) end-buf(u32) fg(u32) bg(u32) flags(u64)
Returns FACE-RANGES-FLAT-VECTOR directly: nil when NUM-FACE-RANGES is 0
(callers may guard on null), or a FLAT vector of (* 6 NUM-FACE-RANGES)
integers otherwise.  Sets `kuro--decode-pos' to the byte offset immediately
after the decoded section — eliminates the (RESULT . NEW-POS) cons at ~3,600/sec.
Layout: [s0 e0 fg0 bg0 f0 ul0 s1 e1 fg1 bg1 f1 ul1 ...] — stride 6.
Stride-6 eliminates the N inner-vector allocations that the old
vector-of-vectors layout required, cutting ~21,600 allocs/sec at 120fps
× 30 dirty rows × 6 face ranges/row.

`flags' is read as u32 (not u64) because `encode_attrs' in Rust produces
values in 0..=0xBFF (9 SGR flag bits + 3 underline-style bits — 12 bits
total).  The upper 4 bytes on the wire are always 0x00000000.  Reading only
the low u32 avoids the `(ash high-word 32)' bignum allocation that
`kuro--read-u64-le' would otherwise incur on every face range decoded."
  (if (zerop num-face-ranges)
      ;; Zero-range fast exit: nil preserves backward compatibility with callers
      ;; that guard on (null face-list).  No allocation needed.
      (progn (setq kuro--decode-pos pos) nil)
    ;; Non-zero: pre-allocate a FLAT vector of (* 6 num-face-ranges) slots.
    ;; Each range occupies 6 consecutive elements: [start end fg bg flags ul].
    (let ((result (make-vector (* 6 num-face-ranges) 0))
          (base 0))
      (if v2-p
          ;; Fast path: v2 — 28-byte wire stride; ul-color present.
          ;; Advancing `base' avoids the `(* i 6)' multiply per iteration.
          (let ((end (* 6 num-face-ranges)))
            (while (< base end)
              (let* ((b1  (1+ base))
                     (b2  (1+ b1))
                     (b3  (1+ b2))
                     (b4  (1+ b3))
                     (b5  (1+ b4))
                     (p4  (+ pos  4))
                     (p8  (+ p4   4))
                     (p12 (+ p8   4))
                     (p16 (+ p12  4))
                     (p24 (+ p16  8)))
                (aset result base (kuro--read-u32-le vec pos))
                (aset result b1   (kuro--read-u32-le vec p4))
                (aset result b2   (kuro--read-u32-le vec p8))
                (aset result b3   (kuro--read-u32-le vec p12))
                ;; Low u32 only — upper 4 bytes (pos+20..23) are always zero.
                (aset result b4   (kuro--read-u32-le vec p16))
                (aset result b5   (kuro--read-u32-le vec p24))
                (setq base (1+ b5))
                (setq pos  (+ p24 4)))))
        ;; Slow path: v1 — 24-byte wire stride; no ul-color (pad slot with 0).
        (let ((end (* 6 num-face-ranges)))
          (while (< base end)
            (let* ((b1  (1+ base))
                   (b2  (1+ b1))
                   (b3  (1+ b2))
                   (b4  (1+ b3))
                   (p4  (+ pos 4))
                   (p8  (+ p4  4))
                   (p12 (+ p8  4))
                   (p16 (+ p12 4)))
              (aset result base (kuro--read-u32-le vec pos))
              (aset result b1   (kuro--read-u32-le vec p4))
              (aset result b2   (kuro--read-u32-le vec p8))
              (aset result b3   (kuro--read-u32-le vec p12))
              ;; Low u32 only — upper 4 bytes (pos+20..23) are always zero.
              (aset result b4   (kuro--read-u32-le vec p16))
              ;; ul-color (b5) absent in v1: slot already initialised to 0 by make-vector.
              (setq base (+ base 6))
              (setq pos  (+ p16 8))))))
      (setq kuro--decode-pos pos)
      result)))

(defsubst kuro--decode-col-to-buf (vec pos)
  "Decode a col-to-buf vector from VEC starting at byte offset POS.
Format: u32 length followed by that many u32 entries.
Returns the VECTOR directly (empty vector when length is zero; no CJK
wide characters on this row).  Sets `kuro--decode-pos' to the byte offset
immediately after the decoded section — eliminates the (VECTOR . NEW-POS)
cons cell allocation at ~3,600 calls/sec in the hot decode path."
  (let* ((ctb-len (kuro--read-u32-le vec pos))
         (pos (+ pos 4)))
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

;;; Shared frame decoder (CPS: text acquisition passed as continuation)

(defun kuro--decode-binary-frame-rows (vec text-fn)
  "Decode all dirty rows from binary frame VEC into the dirty-line list format.
TEXT-FN is a continuation called as (TEXT-FN idx pos text-byte-len) for each
row, returning a cons cell (TEXT . NEW-POS) with the decoded row text and the
byte offset after text data.  This separates text acquisition strategy from
the shared frame-parsing logic, allowing both byte-decoding and pre-supplied
native string paths to share one implementation.

Validates the frame header (format version 1 or 2), then iterates over rows,
decoding face ranges and col-to-buf entries via the section decoders.
Each result element has the structure expected by `kuro--apply-dirty-lines':
  (((row . text) . face-list) . col-to-buf-vector)"
  (let ((format-version (kuro--read-u32-le vec 0)))
    (unless (or (= format-version kuro--binary-format-version-v1)
                (= format-version kuro--binary-format-version-v2))
      (error "kuro: unsupported binary format version %d" format-version))
    (let* ((num-rows (kuro--read-u32-le vec 4))
           (pos 8)
           ;; Pre-compute once per frame: eliminates one >= integer comparison
           ;; per dirty row inside the hot dotimes loop below.
           (face-ranges-v2-p (>= format-version 2))
           ;; Pre-allocate result vector using num-rows from the frame header.
           ;; aset in forward order removes push+nreverse: no list spine allocation,
           ;; no O(N) pointer-chain reversal.  Each slot holds a flat 4-element
           ;; vector [row text face-ranges col-to-buf] — replaces the 3-deep nested
           ;; cons (((row . text) . face-ranges) . col-to-buf), saving 3 cons cells
           ;; per dirty row (~10,800 cons cells/sec at 30 rows × 120fps).
           ;; Return nil (not []) for 0-row frames so callers using (when updates ...)
           ;; skip the apply loop entirely without a redundant (length updates) check.
           (result (when (> num-rows 0) (make-vector num-rows nil))))
      (let ((idx 0))
        (while (< idx num-rows)
          (let* ((pos4            (+ pos 4))
                 (pos8            (+ pos4 4))
                 (row-index       (kuro--read-u32-le vec pos))
                 (num-face-ranges (kuro--read-u32-le vec pos4))
                 (text-byte-len   (kuro--read-u32-le vec pos8)))
            (setq pos (+ pos8 4))
            ;; Use direct car/cdr instead of pcase-let* cons patterns.
            ;; pcase-let* installs a pattern-fail branch; let*/car/cdr compiles to
            ;; straightforward bytecodes with no dispatch overhead.
            ;; Distinct names p1/p2/p3 avoid shadowing the outer `pos'.
            (let* ((cell1      (funcall text-fn idx pos text-byte-len))
                   (text       (car cell1))
                   (p1         (cdr cell1))
                   (face-list  (kuro--decode-face-ranges vec p1 num-face-ranges face-ranges-v2-p))
                   (p2         kuro--decode-pos)
                   (col-to-buf (kuro--decode-col-to-buf vec p2))
                   (p3         kuro--decode-pos))
              (setq pos p3)
              (aset result idx (vector row-index text face-list col-to-buf))))
          (setq idx (1+ idx))))
      result)))

;;; Top-level frame decoders

(defun kuro--decode-binary-updates (vec)
  "Decode a binary update VEC into the dirty-line list format.
Decodes row text from UTF-8 bytes embedded in VEC.
See `encode_screen_binary' in rust-core/src/ffi/codec.rs for the wire format."
  (kuro--decode-binary-frame-rows
   vec
   (lambda (_idx pos text-byte-len)
     (kuro--decode-row-text vec pos text-byte-len))))

;;; Optimised decoder using native Emacs strings from Rust

(defun kuro--decode-binary-updates-with-strings (text-strings vec)
  "Decode binary VEC using pre-supplied native TEXT-STRINGS, without funcall overhead.
TEXT-STRINGS is a vector of strings (one per dirty row) from
`kuro-core-poll-updates-binary-with-strings'.  VEC carries only
face/col-to-buf data; `text_byte_len' is always 0 in this path.

Inlines the text acquisition step (was `funcall text-fn') to eliminate
one closure dispatch per dirty row — allows the bytecode compiler to inline
the direct `aref text-strings idx' without going through an indirect call.
At 30 dirty rows × 120fps = 3600 saved funcall frames/sec."
  (let ((format-version (kuro--read-u32-le vec 0)))
    (unless (or (= format-version kuro--binary-format-version-v1)
                (= format-version kuro--binary-format-version-v2))
      (error "kuro: unsupported binary format version %d" format-version))
    (let* ((num-rows         (kuro--read-u32-le vec 4))
           (pos              8)
           (face-ranges-v2-p (>= format-version 2))
           ;; Pre-allocate result vector (same pattern as kuro--decode-binary-frame-rows).
           ;; Return nil for 0-row frames (not []) so (when updates ...) callers skip correctly.
           (result           (when (> num-rows 0) (make-vector num-rows nil))))
      ;; `while' with explicit counter produces tighter bytecode than `dotimes'
      ;; (consistent with kuro--apply-dirty-lines, kuro--decode-face-ranges, etc.)
      (let ((i 0))
        (while (< i num-rows)
          (let* ((pos4            (+ pos 4))
                 (row-index       (kuro--read-u32-le vec pos))
                 (num-face-ranges (kuro--read-u32-le vec pos4)))
            ;; text_byte_len is always 0 in the with-strings frame; skip that u32.
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
          (setq i (1+ i))))
      result)))

(defun kuro--poll-updates-binary-optimised (session-id)
  "Poll dirty lines for SESSION-ID using the text-string-optimised FFI path.
Calls `kuro-core-poll-updates-binary-with-strings', which returns a cons
cell `(TEXT-STRINGS . BINARY-DATA)', then decodes it with
`kuro--decode-binary-updates-with-strings'.

Returns nil when there are no dirty lines (FFI returned nil).
Otherwise returns the decoded dirty-line list in the same format as
`kuro--decode-binary-updates'."
  (let ((result (kuro-core-poll-updates-binary-with-strings session-id)))
    (when result
      (kuro--decode-binary-updates-with-strings (car result) (cdr result)))))

(provide 'kuro-binary-decoder)

;;; kuro-binary-decoder.el ends here
