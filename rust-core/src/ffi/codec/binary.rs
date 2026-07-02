//! Binary frame encoding and row hash computation.
//!
//! [`encode_screen_binary`] serialises a list of dirty lines into the flat
//! binary frame format consumed by the Emacs decoder.  The hash functions
//! ([`compute_row_hash_from_pool`], [`compute_row_hash_from_encoded`]) detect
//! unchanged rows so the render path can skip redundant FFI calls.

use ahash::AHasher;
use std::hash::{Hash, Hasher};

use super::line::{
    encode_line_into_buf, write_face_range, EncodePool, EncodedFaceRange, EncodedLine,
};

/// Current binary frame format version.
///
/// Version 1: 8-byte header `[format_version: u32 LE][num_rows: u32 LE]`,
/// with 24-byte face ranges: `start_buf(u32) end_buf(u32) fg(u32) bg(u32) flags(u64)`.
///
/// Version 2: extends each face range to 28 bytes by appending a 4-byte
/// `underline_color` field: `start_buf(u32) end_buf(u32) fg(u32) bg(u32) flags(u64) ul_color(u32)`.
pub(crate) const BINARY_FORMAT_VERSION: u32 = 2;

/// Encode a list of dirty lines into a flat binary frame for FFI transfer.
///
/// # Binary frame format
///
/// ```text
/// Header (8 bytes):
///   [0..4]  format_version: u32 LE  (always BINARY_FORMAT_VERSION = 2)
///   [4..8]  num_rows: u32 LE
///
/// Per row:
///   [0..4]   row_index: u32 LE
///   [4..8]   num_face_ranges: u32 LE
///   [8..12]  text_byte_len: u32 LE
///   [12..12+text_byte_len]  UTF-8 text bytes
///
///   Per face range (28 bytes each, version 2):
///     [0..4]   start_buf: u32 LE
///     [4..8]   end_buf: u32 LE
///     [8..12]  fg: u32 LE
///     [12..16] bg: u32 LE
///     [16..24] flags: u64 LE
///     [24..28] ul_color: u32 LE
///
///   col_to_buf section:
///     [0..4]   col_to_buf_len: u32 LE
///     [4..4+col_to_buf_len*4]  u32 LE entries
/// ```
#[cfg_attr(
    fuzzing,
    expect(
        dead_code,
        reason = "called only from ffi::bridge::render which is excluded in fuzz builds"
    )
)]
#[must_use = "encode result must be used for FFI transfer to Emacs Lisp"]
pub(crate) fn encode_screen_binary(lines: &[EncodedLine]) -> Vec<u8> {
    // Pre-compute total capacity to avoid repeated reallocation.
    let capacity = {
        let mut cap = 8usize; // format_version + num_rows header
        for line in lines {
            cap += 12; // row_index + num_face_ranges + text_byte_len
            cap += line.text.len();
            cap += line.face_ranges.len() * 28; // 28 bytes per face range (version 2)
            cap += 4; // col_to_buf_len
            cap += line.col_to_buf.len() * 4;
        }
        cap
    };
    let mut buf = Vec::with_capacity(capacity);

    // Header: format_version + num_rows
    buf.extend_from_slice(&BINARY_FORMAT_VERSION.to_le_bytes());
    #[expect(
        clippy::cast_possible_truncation,
        reason = "number of dirty rows is bounded by terminal height (≤ 65535); fits u32"
    )]
    buf.extend_from_slice(&(lines.len() as u32).to_le_bytes());

    for line in lines {
        // row_index
        #[expect(
            clippy::cast_possible_truncation,
            reason = "row index is a terminal row (≤ 65535); fits u32"
        )]
        buf.extend_from_slice(&(line.row_index as u32).to_le_bytes());

        // num_face_ranges
        #[expect(
            clippy::cast_possible_truncation,
            reason = "face range count is bounded by terminal width (≤ 65535); fits u32"
        )]
        buf.extend_from_slice(&(line.face_ranges.len() as u32).to_le_bytes());

        // text_byte_len + text bytes
        #[expect(
            clippy::cast_possible_truncation,
            reason = "UTF-8 text byte length for one terminal line fits u32"
        )]
        buf.extend_from_slice(&(line.text.len() as u32).to_le_bytes());
        buf.extend_from_slice(line.text.as_bytes());

        // Per face range: coalesce into single 28-byte stack write via write_face_range.
        for range in &line.face_ranges {
            write_face_range(&mut buf, range);
        }

        // col_to_buf section: length header + u32 entries
        #[expect(
            clippy::cast_possible_truncation,
            reason = "col_to_buf length is bounded by terminal width (≤ 65535); fits u32"
        )]
        buf.extend_from_slice(&(line.col_to_buf.len() as u32).to_le_bytes());
        for &offset in &line.col_to_buf {
            #[expect(
                clippy::cast_possible_truncation,
                reason = "col_to_buf entries are buffer char offsets (≤ terminal width ≤ 65535); fit u32"
            )]
            buf.extend_from_slice(&(offset as u32).to_le_bytes());
        }
    }

    buf
}

/// Hash an already-populated [`EncodePool`] to detect row changes.
///
/// Equivalent to [`compute_row_hash`] but avoids re-encoding cell data:
/// `pool.text` encodes all grapheme content; `pool.face_ranges` encodes all
/// color and attribute data as pre-computed u32/u64 values; and
/// `pool.col_to_buf` encodes wide-char column layout.
///
/// Use this at call sites that have already called `fill_encode_pool` or
/// [`encode_line_into_buf`] where the data **remains in the pool** after the
/// call.  For [`encode_line_with_pool`] — which uses `mem::take` — use
/// [`compute_row_hash_from_encoded`] instead.
#[inline]
pub(crate) fn compute_row_hash_from_pool(pool: &EncodePool) -> u64 {
    let mut h = AHasher::default();
    pool.text.as_bytes().hash(&mut h);
    pool.face_ranges.hash(&mut h);
    pool.col_to_buf.hash(&mut h);
    // Kitty text-sizing (OSC 66): a cell differing only by text size must
    // still change the hash so the row re-renders.
    pool.text_sizes.hash(&mut h);
    h.finish()
}

/// Encode a dirty row into the binary frame buffer and compute its hash.
///
/// This keeps the "emit row + update row hash" pairing in one place while
/// preserving the borrow-friendly `EncodePool` / `Vec<u8>` call shape needed by
/// `dirty.rs`.
#[inline]
pub(crate) fn encode_line_into_buf_and_hash(
    cells: &[crate::types::cell::Cell],
    has_wide: bool,
    pool: &mut EncodePool,
    row_index: usize,
    buf: &mut Vec<u8>,
) -> (String, u64) {
    let text = encode_line_into_buf(cells, has_wide, pool, row_index, buf);
    let hash = compute_row_hash_from_pool(pool);
    (text, hash)
}

/// Hash already-returned encoded line data.
///
/// Use this after [`encode_line_with_pool`], which moves data out of the pool
/// via `mem::take`.  Hashes the same representation as [`compute_row_hash_from_pool`]
/// but operates on the caller-owned encoded line data rather than the
/// (now-empty) pool.
#[inline]
pub(crate) fn compute_row_hash_from_encoded(
    text: &str,
    face_ranges: &[EncodedFaceRange],
    col_to_buf: &[usize],
    text_sizes: &[u32],
) -> u64 {
    let mut h = AHasher::default();
    text.as_bytes().hash(&mut h);
    face_ranges.hash(&mut h);
    col_to_buf.hash(&mut h);
    // Kitty text-sizing (OSC 66): fold text-size changes into the hash. See
    // [`compute_row_hash_from_pool`].
    text_sizes.hash(&mut h);
    h.finish()
}

/// Compute a stable 64-bit hash for a terminal row.
///
/// Hashes every cell's grapheme bytes, encoded foreground/background colors,
/// encoded SGR flags, and the `col_to_buf` mapping slice.
///
/// This function re-encodes every cell and is retained only for test assertions.
/// Production call sites use the faster [`compute_row_hash_from_pool`] which
/// hashes already-encoded pool data.
#[cfg(test)]
#[inline]
pub(crate) fn compute_row_hash(row: &crate::grid::line::Line, col_to_buf: &[usize]) -> u64 {
    use super::color::{encode_attrs, encode_color};
    use std::hash::DefaultHasher;
    let mut h = DefaultHasher::new();
    for cell in &row.cells {
        cell.grapheme().as_bytes().hash(&mut h);
        encode_color(&cell.attrs.foreground).hash(&mut h);
        encode_color(&cell.attrs.background).hash(&mut h);
        encode_attrs(&cell.attrs).hash(&mut h);
        encode_color(&cell.attrs.underline_color).hash(&mut h);
        (cell.width as u8).hash(&mut h);
    }
    col_to_buf.hash(&mut h);
    h.finish()
}
