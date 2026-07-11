;;; kuro-binary-decoder.el --- Binary FFI frame decoder for Kuro  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 takeokunn

;; Author: takeokunn <bararararatty@gmail.com>

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
;; layout.  Each frame is a flat byte array — a unibyte string (current .so:
;; one `make_string' FFI call for the whole payload) or a vector of byte
;; integers 0–255 (older .so builds) — structured as:
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

(defconst kuro--binary-format-version-v3 3
  "Binary frame format version 3: 16-byte header, 28-byte face ranges.
Appends scroll_up(u32) and scroll_down(u32) to the header: the
full-screen scroll shift consumed atomically with the dirty rows.
The renderer applies the shift as a buffer-level delete+insert BEFORE
rewriting dirty rows, so a scrolling stream (AI agent output) costs
O(newly exposed rows) per frame instead of a full-screen repaint.")

;;; Scratch variable for decoder position advancement

(defvar kuro--decode-pos 0
  "Scratch variable for decoder position advancement.
`kuro--decode-face-ranges' and `kuro--decode-col-to-buf' set this to the
byte offset immediately after the decoded section, eliminating the cons
cell that would otherwise allocate a (RESULT . NEW-POS) pair at 3,600+
calls/sec in the hot decode path.")

(defvar kuro--decode-scroll-up 0
  "Scroll-up shift decoded from the last version-3 binary frame header.
Number of full-screen upward scrolls to replay as a buffer edit (delete
the first N lines, append N blanks) BEFORE applying the frame's dirty
rows.  Zero for v1/v2 frames and frames without a shift.  A scratch
defvar rather than a return value, matching the `kuro--decode-pos'
pattern: the poll path runs at up to 120 calls/sec and the extra cons
of a richer return shape is measurable there.")

(defvar kuro--decode-scroll-down 0
  "Scroll-down shift decoded from the last version-3 binary frame header.
See `kuro--decode-scroll-up'; the Rust core guarantees at most one of
the two shift fields is non-zero per frame (opposite-direction scroll
interleaves degrade to a full repaint on the Rust side because they
cannot be replayed from aggregate counts).")

;;; Low-level byte readers

(defun kuro--binary-decode-error (format-string &rest args)
  "Signal a malformed binary frame error using FORMAT-STRING and ARGS."
  (apply #'error (concat "Kuro: malformed binary frame: " format-string) args))

(defsubst kuro--binary-byte-p (value)
  "Return non-nil when VALUE is an integer byte."
  (and (integerp value) (<= 0 value) (<= value #xff)))

(defun kuro--binary-require-array (vec section)
  "Require VEC to be a byte array (vector or string) while decoding SECTION."
  (unless (or (stringp vec) (vectorp vec))
    (kuro--binary-decode-error
     "%s must be a vector or string, got %S" section vec)))

(defun kuro--binary-require-count (count section)
  "Require COUNT to be a non-negative integer while decoding SECTION."
  (unless (and (integerp count) (<= 0 count))
    (kuro--binary-decode-error "%s count must be a non-negative integer, got %S"
                               section count)))

(defun kuro--binary-require-available (vec pos byte-count section)
  "Require BYTE-COUNT bytes to be available in VEC at POS for SECTION.
Pure arithmetic bounds check — element values are validated once per
frame by `kuro--binary-normalize-frame', not here."
  (unless (and (integerp pos) (<= 0 pos))
    (kuro--binary-decode-error "%s offset must be a non-negative integer, got %S"
                               section pos))
  (unless (and (integerp byte-count) (<= 0 byte-count))
    (kuro--binary-decode-error "%s byte count must be a non-negative integer, got %S"
                               section byte-count))
  (let ((end (+ pos byte-count)))
    (when (> end (length vec))
      (kuro--binary-decode-error
       "%s truncated: need bytes [%d,%d), frame has %d bytes"
       section pos end (length vec)))))

(defun kuro--binary-require-byte-range (vec pos byte-count section)
  "Require BYTE-COUNT validated byte values in VEC at POS for SECTION.
Only needed for vector payloads (older .so builds): a unibyte string's
elements are 0–255 by construction and never require this scan."
  (kuro--binary-require-available vec pos byte-count section)
  (let ((end (+ pos byte-count)))
    (while (< pos end)
      (unless (kuro--binary-byte-p (aref vec pos))
        (kuro--binary-decode-error
         "%s byte at offset %d must be an integer in 0..255, got %S"
         section pos (aref vec pos)))
      (setq pos (1+ pos)))))

(defun kuro--binary-normalize-frame (payload)
  "Normalize PAYLOAD to a byte array ready for raw `aref' decoding.
A string payload (current .so: Latin-1 chars, one per frame byte) is
converted to a unibyte string with a single `encode-coding-string' call;
its elements are 0–255 by construction so no per-byte validation runs.
A vector payload (older .so builds) is validated element-wise ONCE here,
so the hot per-read path can use raw `aref' + `logior' with no checks.
Anything else signals a malformed-frame error."
  (cond
   ((stringp payload)
    (if (multibyte-string-p payload)
        (encode-coding-string payload 'latin-1 t)
      payload))
   ((vectorp payload)
    (kuro--binary-require-byte-range payload 0 (length payload) "frame")
    payload)
   (t
    (kuro--binary-decode-error
     "Frame payload must be a string or vector, got %S" payload))))

(defun kuro--binary-require-text-strings (text-strings num-rows)
  "Require TEXT-STRINGS to contain exactly NUM-ROWS strings."
  (unless (vectorp text-strings)
    (kuro--binary-decode-error "Text strings must be a vector, got %S" text-strings))
  (unless (= (length text-strings) num-rows)
    (kuro--binary-decode-error
     "Text string count mismatch: frame has %d rows, text vector has %d"
     num-rows (length text-strings)))
  (let ((i 0))
    (while (< i num-rows)
      (unless (stringp (aref text-strings i))
        (kuro--binary-decode-error
         "Text string at row slot %d must be a string, got %S"
         i (aref text-strings i)))
      (setq i (1+ i)))))

(defsubst kuro--read-u32-le (vec offset)
  "Read a u32 little-endian integer from VEC at byte OFFSET.
VEC is a byte array — a unibyte string (current .so) or a vector of byte
values (older builds) — already validated by `kuro--binary-normalize-frame'.
Returns a non-negative integer.

Raw `aref' reads with no per-call validation: byte-range validity is
guaranteed once per frame at normalization, and section decoders bound
their reads with `kuro--binary-require-available' before looping, so the
former per-read bounds check + 4 per-byte range checks (≈40 bytecode ops
per u32, ~1,440 u32 reads/frame) collapse to 4 `aref' + 3 `ash' + 1
`logior'.  Out-of-range offsets still signal via `aref' itself.
Chained `1+' avoids three generic `+' bytecodes."
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
Returns FACE-RANGES-FLAT-VECTOR directly: an empty vector when
NUM-FACE-RANGES is 0, or a FLAT vector of (* 6 NUM-FACE-RANGES) integers
otherwise.  Sets `kuro--decode-pos' to the byte offset immediately after
the decoded section — eliminates the (RESULT . NEW-POS) cons at
~3,600/sec.
Layout: [s0 e0 fg0 bg0 f0 ul0 s1 e1 fg1 bg1 f1 ul1 ...] — stride 6.
Stride-6 eliminates the N inner-vector allocations that the old
vector-of-vectors layout required, cutting ~21,600 allocs/sec at 120fps
× 30 dirty rows × 6 face ranges/row.

`flags' is read as u32 (not u64) because `encode_attrs' in Rust produces
values in 0..=0xBFF (9 SGR flag bits + 3 underline-style bits — 12 bits
total).  The upper 4 bytes on the wire are always 0x00000000.  Reading only
the low u32 avoids the `(ash high-word 32)' bignum allocation that
`kuro--read-u64-le' would otherwise incur on every face range decoded."
  (kuro--binary-require-count num-face-ranges "face ranges")
  (let ((byte-count (* num-face-ranges (if v2-p 28 24))))
    ;; Arithmetic bounds check only: byte values were validated (vector
    ;; payloads) or are guaranteed 0-255 (unibyte strings) at frame entry
    ;; by `kuro--binary-normalize-frame'.  The former per-byte re-scan here
    ;; read every face byte twice per frame.
    (kuro--binary-require-available vec pos byte-count "face ranges"))
  (if (zerop num-face-ranges)
      ;; Zero-range fast exit: an empty vector (not nil) so callers that check
      ;; `(vectorp face-list)' see a consistent return type.  No allocation needed.
      (progn (setq kuro--decode-pos pos) [])
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
  (kuro--binary-require-available vec pos 4 "col-to-buf length")
  (let* ((ctb-len (kuro--read-u32-le vec pos))
         (pos (+ pos 4)))
    (kuro--binary-require-available vec pos (* ctb-len 4) "col-to-buf entries")
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
VEC is a Latin-1 string (current .so) or a byte vector (older builds);
`kuro--binary-normalize-frame' converts/validates it exactly once so
every downstream read is a raw `aref'.

Inlines the text acquisition step (was `funcall text-fn') to eliminate
one closure dispatch per dirty row — allows the bytecode compiler to inline
the direct `aref text-strings idx' without going through an indirect call.
At 30 dirty rows × 120fps = 3600 saved funcall frames/sec."
  (setq vec (kuro--binary-normalize-frame vec))
  (kuro--binary-require-available vec 0 8 "header")
  (let ((format-version (kuro--read-u32-le vec 0)))
    (unless (or (= format-version kuro--binary-format-version-v1)
                (= format-version kuro--binary-format-version-v2)
                (= format-version kuro--binary-format-version-v3))
      (error "Kuro: unsupported binary format version %d" format-version))
    (let* ((v3-p             (>= format-version kuro--binary-format-version-v3))
           (num-rows         (kuro--read-u32-le vec 4))
           (pos              (if v3-p 16 8))
           (face-ranges-v2-p (>= format-version 2)))
      ;; v3: scroll shift fields occupy header bytes 8..16.  v1/v2 frames
      ;; (and old .so modules) never carry a shift, so the scratch vars are
      ;; explicitly zeroed for them.
      (if v3-p
          (progn
            (kuro--binary-require-available vec 8 8 "scroll shift header")
            (setq kuro--decode-scroll-up   (kuro--read-u32-le vec 8)
                  kuro--decode-scroll-down (kuro--read-u32-le vec 12)))
        (setq kuro--decode-scroll-up 0
              kuro--decode-scroll-down 0))
      (kuro--binary-require-text-strings text-strings num-rows)
      ;; Every row must at least contain row-index, face-count, text-byte-len,
      ;; and col-to-buf-len.  This prevents huge count fields from allocating
      ;; the result vector before the frame can possibly contain that many rows.
      (kuro--binary-require-available vec pos (* num-rows 16) "minimum row data")
      ;; `while' with explicit counter produces tighter bytecode than `dotimes'
      ;; (consistent with kuro--apply-dirty-lines, kuro--decode-face-ranges, etc.)
      (let ((i 0)
            ;; Pre-allocate result vector (same pattern as kuro--decode-binary-frame-rows).
            ;; Return nil for 0-row frames (not []) so (when updates ...) callers skip correctly.
            (result (when (> num-rows 0) (make-vector num-rows nil))))
        (while (< i num-rows)
          (let* ((row-index       (kuro--read-u32-le vec pos))
                 (num-face-ranges (kuro--read-u32-le vec (+ pos 4)))
                 (text-byte-len   (kuro--read-u32-le vec (+ pos 8))))
            (unless (zerop text-byte-len)
              (kuro--binary-decode-error
               "With-strings row %d has non-zero text_byte_len %d"
               i text-byte-len))
            (setq pos (+ pos 12))
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
          (kuro--binary-decode-error
           "Trailing bytes after decoded frame: stopped at %d of %d"
           pos (length vec)))
        result))))

(defun kuro--poll-updates-binary-optimised (session-id)
  "Poll dirty lines for SESSION-ID using the text-string-optimised FFI path.
Calls `kuro-core-poll-updates-binary-with-strings', which returns a cons
cell `(TEXT-STRINGS . BINARY-DATA)', then decodes it with
`kuro--decode-binary-updates-with-strings'.

Returns nil when there are no dirty lines (FFI returned nil).
Otherwise returns the decoded dirty-line list in the same format as
the render pipeline expects.

Side effect: `kuro--decode-scroll-up' and `kuro--decode-scroll-down'
are set to the frame's scroll shift (v3 header) or zeroed when the FFI
returned nil or an older frame version.  The render pipeline reads them
immediately after this call, before applying the dirty rows."
  (setq kuro--decode-scroll-up 0
        kuro--decode-scroll-down 0)
  (let ((result (kuro-core-poll-updates-binary-with-strings session-id)))
    (cond
     ((null result) nil)
     ((not (consp result))
      (kuro--binary-decode-error
       "Binary FFI result must be nil or a cons cell, got %S" result))
     ((not (vectorp (car result)))
      (kuro--binary-decode-error
       "Binary FFI text payload must be a vector, got %S" (car result)))
     ((not (or (stringp (cdr result)) (vectorp (cdr result))))
      (kuro--binary-decode-error
       "Binary FFI byte payload must be a string or vector, got %S" (cdr result)))
     (t
      (kuro--decode-binary-updates-with-strings (car result) (cdr result))))))

(provide 'kuro-binary-decoder)

;;; kuro-binary-decoder.el ends here
