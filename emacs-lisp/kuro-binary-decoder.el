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
;;   [num_rows: u32 LE]
;;   For each row:
;;     [row_index: u32 LE] [num_face_ranges: u32 LE] [text_byte_len: u32 LE]
;;     [text: text_byte_len bytes (UTF-8)]
;;     For each face range (24 bytes each):
;;       [start_buf: u32 LE] [end_buf: u32 LE]
;;       [fg: u32 LE] [bg: u32 LE] [flags: u64 LE]
;;     [col_to_buf_len: u32 LE]
;;     [col_to_buf entries: col_to_buf_len × u32 LE]

;;; Code:

;; Declare the binary FFI function provided by the Rust dynamic module.
(declare-function kuro-core-poll-updates-binary "ext:kuro-core" (session-id))

;;; Low-level byte readers

(defun kuro--read-u32-le (vec offset)
  "Read a u32 little-endian integer from VEC at byte OFFSET.
VEC must be an Emacs vector of integer byte values (0–255).
Returns a non-negative integer."
  (logior (aref vec offset)
          (ash (aref vec (+ offset 1)) 8)
          (ash (aref vec (+ offset 2)) 16)
          (ash (aref vec (+ offset 3)) 24)))

(defun kuro--read-u64-le (vec offset)
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

(defun kuro--decode-face-ranges (vec pos num-face-ranges)
  "Decode NUM-FACE-RANGES face tuples from VEC starting at byte offset POS.
Each tuple is 24 bytes: start-buf(u32) end-buf(u32) fg(u32) bg(u32) flags(u64).
Returns a cons cell (FACE-LIST . NEW-POS) where FACE-LIST is in original order."
  (let (face-list)
    (dotimes (_ num-face-ranges)
      (push (list (kuro--read-u32-le vec pos)
                  (kuro--read-u32-le vec (+ pos 4))
                  (kuro--read-u32-le vec (+ pos 8))
                  (kuro--read-u32-le vec (+ pos 12))
                  (kuro--read-u64-le vec (+ pos 16)))
            face-list)
      (setq pos (+ pos 24)))
    (cons (nreverse face-list) pos)))

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

;;; Top-level frame decoder

(defun kuro--decode-binary-updates (vec)
  "Decode a binary update VEC (Emacs vector of byte integers) into
the same format as `kuro--poll-updates-with-faces' returns.

Format: see `encode_screen_binary' in rust-core/src/ffi/codec.rs.
Each element of the returned list has the structure:
  (((row . text) . face-list) . col-to-buf-vector)
which is identical to what `kuro--apply-dirty-lines' expects."
  (let ((num-rows (kuro--read-u32-le vec 0))
        (pos 4)
        result)
    (dotimes (_ num-rows)
      (let* ((row-index       (kuro--read-u32-le vec pos))
             (num-face-ranges (kuro--read-u32-le vec (+ pos 4)))
             (text-byte-len   (kuro--read-u32-le vec (+ pos 8))))
        (setq pos (+ pos 12))
        (let* ((text-pair (kuro--decode-row-text vec pos text-byte-len))
               (text (car text-pair)))
          (setq pos (cdr text-pair))
          (let* ((face-pair (kuro--decode-face-ranges vec pos num-face-ranges))
                 (face-list (car face-pair)))
            (setq pos (cdr face-pair))
            (let* ((ctb-pair (kuro--decode-col-to-buf vec pos))
                   (col-to-buf (car ctb-pair)))
              (setq pos (cdr ctb-pair))
              (push (cons (cons (cons row-index text) face-list) col-to-buf)
                    result))))))
    (nreverse result)))

(provide 'kuro-binary-decoder)

;;; kuro-binary-decoder.el ends here
