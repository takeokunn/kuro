;;; kuro-binary-decoder.el --- Binary FFI frame decoder for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 takeokunn

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
  "Binary frame format version 2: 8-byte header, 28-byte face ranges (adds underline_color).")

;;; Low-level byte readers

(defsubst kuro--read-u32-le (vec offset)
  "Read a u32 little-endian integer from VEC at byte OFFSET.
VEC must be an Emacs vector of integer byte values (0–255).
Returns a non-negative integer."
  (logior (aref vec offset)
          (ash (aref vec (+ offset 1)) 8)
          (ash (aref vec (+ offset 2)) 16)
          (ash (aref vec (+ offset 3)) 24)))

(defsubst kuro--read-u64-le (vec offset)
  "Read a u64 little-endian integer from VEC at byte OFFSET.
VEC must be an Emacs vector of integer byte values (0–255).
Returns a non-negative integer (Emacs bignums handle values > 2^62)."
  (logior (kuro--read-u32-le vec offset)
          (ash (kuro--read-u32-le vec (+ offset 4)) 32)))

;;; Per-section decoders

(defun kuro--decode-row-text (vec pos text-byte-len)
  "Decode TEXT-BYTE-LEN raw UTF-8 bytes from VEC at byte offset POS.
Returns a cons cell (TEXT . NEW-POS) where TEXT is the decoded Emacs string
and NEW-POS is the byte offset after the text data."
  (let ((text-bytes (make-string text-byte-len 0)))
    (dotimes (i text-byte-len)
      (aset text-bytes i (aref vec (+ pos i))))
    (cons (decode-coding-string text-bytes 'utf-8-unix)
          (+ pos text-byte-len))))

(defun kuro--decode-face-ranges (vec pos num-face-ranges format-version)
  "Decode NUM-FACE-RANGES face tuples from VEC starting at byte offset POS.
FORMAT-VERSION controls the stride and presence of the ul-color field:
  version 1: 24 bytes per range — start-buf(u32) end-buf(u32) fg(u32) bg(u32) flags(u64)
  version 2: 28 bytes per range — adds ul-color(u32) at offset 24.
Returns a cons cell (FACE-LIST . NEW-POS) where FACE-LIST is in original order."
  (if (>= format-version 2)
      ;; Fast path: v2 (always emitted by current Rust encoder).
      ;; Stride and ul-color presence are constants — no per-iteration branching.
      (let ((result nil))
        (dotimes (_ num-face-ranges)
          (let* ((start-buf (kuro--read-u32-le vec pos))
                 (end-buf   (kuro--read-u32-le vec (+ pos 4)))
                 (fg        (kuro--read-u32-le vec (+ pos 8)))
                 (bg        (kuro--read-u32-le vec (+ pos 12)))
                 (flags     (kuro--read-u64-le vec (+ pos 16)))
                 (ul-color  (kuro--read-u32-le vec (+ pos 24))))
            (push (list start-buf end-buf fg bg flags ul-color) result)
            (setq pos (+ pos 28))))
        (cons (nreverse result) pos))
    ;; Slow path: v1 legacy frames (24-byte face ranges, no ul-color field).
    (let ((result nil))
      (dotimes (_ num-face-ranges)
        (let* ((start-buf (kuro--read-u32-le vec pos))
               (end-buf   (kuro--read-u32-le vec (+ pos 4)))
               (fg        (kuro--read-u32-le vec (+ pos 8)))
               (bg        (kuro--read-u32-le vec (+ pos 12)))
               (flags     (kuro--read-u64-le vec (+ pos 16))))
          (push (list start-buf end-buf fg bg flags 0) result)
          (setq pos (+ pos 24))))
      (cons (nreverse result) pos))))

(defun kuro--decode-col-to-buf (vec pos)
  "Decode a col-to-buf vector from VEC starting at byte offset POS.
Format: u32 length followed by that many u32 entries.
Returns a cons cell (VECTOR . NEW-POS).  An empty vector is returned
when length is zero (no CJK wide characters on this row)."
  (let* ((ctb-len (kuro--read-u32-le vec pos))
         (pos (+ pos 4)))
    (if (zerop ctb-len)
        (cons [] pos)
      (let ((v (make-vector ctb-len 0)))
        (dotimes (i ctb-len)
          (aset v i (kuro--read-u32-le vec pos))
          (setq pos (+ pos 4)))
        (cons v pos)))))

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
           (result (make-vector num-rows nil))
           (idx 0))
      (dotimes (_ num-rows)
        (let* ((row-index       (kuro--read-u32-le vec pos))
               (num-face-ranges (kuro--read-u32-le vec (+ pos 4)))
               (text-byte-len   (kuro--read-u32-le vec (+ pos 8))))
          (setq pos (+ pos 12))
          ;; Use distinct names p1/p2/p3 so pcase-let* does not shadow the
          ;; outer `pos'.  Shadowing would leave pos frozen at (+ pos 12)
          ;; for all subsequent rows — the bug this test was written to catch.
          (pcase-let* ((`(,text      . ,p1) (funcall text-fn idx pos text-byte-len))
                       (`(,face-list . ,p2) (kuro--decode-face-ranges vec p1 num-face-ranges format-version))
                       (`(,col-to-buf . ,p3) (kuro--decode-col-to-buf vec p2)))
            (setq pos p3)
            (aset result idx (cons (cons (cons row-index text) face-list) col-to-buf))
            (setq idx (1+ idx)))))
      (append result nil))))

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
  "Decode a binary update VEC using pre-supplied native TEXT-STRINGS.
TEXT-STRINGS is an Emacs vector of strings (one per dirty row) as returned
by `kuro-core-poll-updates-binary-with-strings'.  VEC carries face/col-to-buf
data only; `text_byte_len' is always 0.

This avoids the triple-copy `make-string' + `dotimes aset' +
`decode-coding-string' path: Rust supplies native Emacs strings directly via
`env.into_lisp(text)', so the text continuation simply indexes TEXT-STRINGS."
  (kuro--decode-binary-frame-rows
   vec
   (lambda (idx pos _text-byte-len)
     (cons (aref text-strings idx) pos))))

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
