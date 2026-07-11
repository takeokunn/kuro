//! Binary frame encoding and row hash computation.
//!
//! [`encode_screen_binary`] serialises a list of dirty lines into the flat
//! binary frame format consumed by the Emacs decoder. `compute_row_hash_from_encoded`
//! detects unchanged rows so the render path can skip redundant FFI calls.

use ahash::AHasher;
use std::hash::{Hash, Hasher};

use super::line::{
    encode_line_into_buf, write_face_range, BinaryFrameResult, BinaryFrameU32, BinaryFrameU32Field,
    EncodePool, EncodedFaceRange, EncodedLine,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct HashedEncodedText {
    pub(crate) text: String,
    pub(crate) content_hash: u64,
}

impl HashedEncodedText {
    #[inline]
    const fn new(text: String, content_hash: u64) -> Self {
        Self { text, content_hash }
    }
}

/// Current binary frame format version.
///
/// Version 1: 8-byte header `[format_version: u32 LE][num_rows: u32 LE]`,
/// with 24-byte face ranges: `start_buf(u32) end_buf(u32) fg(u32) bg(u32) flags(u64)`.
///
/// Version 2: extends each face range to 28 bytes by appending a 4-byte
/// `underline_color` field: `start_buf(u32) end_buf(u32) fg(u32) bg(u32) flags(u64) ul_color(u32)`.
///
/// Version 3: extends the header to 16 bytes by appending
/// `[scroll_up: u32 LE][scroll_down: u32 LE]` — the full-screen scroll shift
/// consumed atomically with the dirty rows.  Emacs applies the shift
/// (delete N edge lines + insert N blanks at the opposite edge) before
/// rewriting the dirty rows, turning per-scroll render cost from O(rows)
/// into O(newly-exposed rows).  Row payload layout is unchanged from v2.
///
/// Version 4: extends the header to 28 bytes by appending
/// `[cursor_row: u32 LE][cursor_col: u32 LE][cursor_meta: u32 LE]` — the
/// cursor state (and bell event) consumed atomically with the dirty rows.
/// `cursor_meta` bit layout: bit 0 = cursor visible (DECTCEM), bits 1–3 =
/// DECSCUSR shape (0–6), bit 4 = bell pending.  Carrying the cursor in the
/// frame lets Emacs drop its per-frame `kuro-core-get-cursor-state` and
/// `kuro-core-take-bell-pending` FFI calls (3 mutex round-trips per frame
/// → 1); the Rust side emits a header-only frame whenever the cursor state
/// changes or a bell fires with no dirty rows.  Row payload layout is
/// unchanged from v2.
pub(crate) const BINARY_FORMAT_VERSION: u32 = 4;

/// Encode a list of dirty lines into a flat binary frame for FFI transfer.
///
/// # Binary frame format
///
/// ```text
/// Header (16 bytes):
///   [0..4]   format_version: u32 LE  (always BINARY_FORMAT_VERSION = 3)
///   [4..8]   num_rows: u32 LE
///   [8..12]  scroll_up: u32 LE    (always 0 on this legacy encode path)
///   [12..16] scroll_down: u32 LE  (always 0 on this legacy encode path)
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
pub(crate) fn encode_screen_binary(lines: &[EncodedLine]) -> BinaryFrameResult<Vec<u8>> {
    /// This legacy encode path is frozen at format version 3: it never
    /// carries a scroll shift (degraded to full repaint by its drains) and
    /// has no cursor source, so emitting a v4 header would force fake
    /// cursor fields on the decoder.  The production path
    /// (`get_dirty_lines_binary_payload`) emits `BINARY_FORMAT_VERSION`.
    const LEGACY_FORMAT_VERSION: u32 = 3;

    // Pre-compute total capacity to avoid repeated reallocation.
    let capacity = {
        let mut cap = 16usize; // format_version + num_rows + scroll_up + scroll_down header
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

    // Header: format_version + num_rows + scroll shift (always zero here:
    // this encode path is fed by the legacy drains, which degrade pending
    // scroll shifts to a full repaint instead of transmitting them).
    buf.extend_from_slice(&LEGACY_FORMAT_VERSION.to_le_bytes());
    BinaryFrameU32::from_usize(lines.len(), BinaryFrameU32Field::RowCount)?.write_le(&mut buf);
    buf.extend_from_slice(&0u32.to_le_bytes());
    buf.extend_from_slice(&0u32.to_le_bytes());

    for line in lines {
        // row_index
        BinaryFrameU32::from_usize(line.row_index, BinaryFrameU32Field::RowIndex)?
            .write_le(&mut buf);

        // num_face_ranges
        BinaryFrameU32::from_usize(line.face_ranges.len(), BinaryFrameU32Field::FaceRangeCount)?
            .write_le(&mut buf);

        // text_byte_len + text bytes
        BinaryFrameU32::from_usize(line.text.len(), BinaryFrameU32Field::TextByteLen)?
            .write_le(&mut buf);
        buf.extend_from_slice(line.text.as_bytes());

        // Per face range: coalesce into single 28-byte stack write via write_face_range.
        for range in &line.face_ranges {
            write_face_range(&mut buf, range)?;
        }

        // col_to_buf section: length header + u32 entries
        BinaryFrameU32::from_usize(line.col_to_buf.len(), BinaryFrameU32Field::ColToBufLen)?
            .write_le(&mut buf);
        for &offset in &line.col_to_buf {
            BinaryFrameU32::from_usize(offset, BinaryFrameU32Field::ColToBufOffset)?
                .write_le(&mut buf);
        }
    }

    Ok(buf)
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
#[cfg(test)]
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
) -> BinaryFrameResult<HashedEncodedText> {
    let text = encode_line_into_buf(cells, has_wide, pool, row_index, buf)?;
    let content_hash =
        compute_row_hash_from_encoded(&text, &pool.face_ranges, &pool.col_to_buf, &pool.text_sizes);
    Ok(HashedEncodedText::new(text, content_hash))
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
/// Production call sites use `compute_row_hash_from_encoded` over already-encoded
/// typed line data.
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
        let width_code = match cell.width {
            crate::types::cell::CellWidth::Half => 0_u8,
            crate::types::cell::CellWidth::Full => 1,
            crate::types::cell::CellWidth::Wide => 2,
        };
        width_code.hash(&mut h);
    }
    col_to_buf.hash(&mut h);
    h.finish()
}
