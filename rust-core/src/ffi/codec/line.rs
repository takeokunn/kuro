//! Line encoding: cell data → strongly typed FFI line payloads.
//!
//! The core encoding kernel [`fill_encode_pool`] populates a reusable
//! [`EncodePool`] from a cell slice.  Higher-level entry points
//! ([`encode_line`], [`encode_line_with_pool`], [`encode_line_into_buf`])
//! provide different ownership/serialisation tradeoffs for callers.

use crate::types::cell::{Cell, CellWidth};
use std::mem;

use super::color::{encode_attrs, encode_color, COLOR_DEFAULT_SENTINEL};

/// Encoded face range in buffer offsets.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub(crate) struct EncodedFaceRange {
    pub(crate) start_buf: usize,
    pub(crate) end_buf: usize,
    pub(crate) fg: u32,
    pub(crate) bg: u32,
    pub(crate) flags: u64,
    pub(crate) underline_color: u32,
}

/// Encoded line data without row index.
///
/// `col_to_buf` maps grid columns to buffer offsets. An empty vector means
/// identity mapping for the ASCII/non-wide fast path.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EncodedLineData {
    pub(crate) text: String,
    pub(crate) face_ranges: Vec<EncodedFaceRange>,
    pub(crate) col_to_buf: Vec<usize>,
}

impl EncodedLineData {
    #[inline]
    pub(crate) fn empty() -> Self {
        Self {
            text: String::new(),
            face_ranges: Vec::new(),
            col_to_buf: Vec::new(),
        }
    }

    #[inline]
    pub(crate) fn with_row_index(self, row_index: usize) -> EncodedLine {
        EncodedLine {
            row_index,
            text: self.text,
            face_ranges: self.face_ranges,
            col_to_buf: self.col_to_buf,
        }
    }
}

/// Encoded line data for FFI transfer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct EncodedLine {
    pub(crate) row_index: usize,
    pub(crate) text: String,
    pub(crate) face_ranges: Vec<EncodedFaceRange>,
    pub(crate) col_to_buf: Vec<usize>,
}

impl EncodedLine {
    #[inline]
    pub(crate) fn empty(row_index: usize) -> Self {
        Self {
            row_index,
            text: String::new(),
            face_ranges: Vec::new(),
            col_to_buf: Vec::new(),
        }
    }
}

/// Reusable allocation pool for encoding dirty lines.
///
/// Holds a single `String`, `face_ranges` `Vec`, and `col_to_buf` `Vec` that
/// are cleared and refilled on each call to [`encode_line_with_pool`].
/// After encoding the caller clones the contents into the result `Vec`; the
/// pool retains its heap capacity for the next row.  This eliminates one
/// `String::with_capacity` + one `Vec::with_capacity` allocation per dirty
/// line per frame.
pub(crate) struct EncodePool {
    pub text: String,
    pub face_ranges: Vec<EncodedFaceRange>,
    pub col_to_buf: Vec<usize>,
    /// Kitty text-sizing (OSC 66) per-cell effective multiplier in permille.
    ///
    /// One entry per emitted (non-placeholder) cell in `text`, mirroring the
    /// buffer-offset layout of `face_ranges`.  `1000` is the normal size; any
    /// other value marks a text-size change.  Folded into the row hash so that
    /// a cell differing **only** by text size still re-renders.  Empty when no
    /// cell on the line carries a text size (the overwhelming default), so
    /// ordinary lines pay nothing.
    pub text_sizes: Vec<u32>,
}

impl EncodePool {
    #[inline]
    pub(crate) fn new() -> Self {
        Self {
            text: String::new(),
            face_ranges: Vec::new(),
            col_to_buf: Vec::new(),
            text_sizes: Vec::new(),
        }
    }

    #[inline]
    pub(crate) fn clear(&mut self) {
        self.text.clear();
        self.face_ranges.clear();
        self.col_to_buf.clear();
        self.text_sizes.clear();
    }
}

impl Default for EncodePool {
    fn default() -> Self {
        Self::new()
    }
}

/// Count Unicode scalars in a grapheme cluster with ≥ 3 UTF-8 bytes.
///
/// This path is cold: only reached for multi-scalar graphemes (ZWJ sequences,
/// combining diacritics on non-ASCII bases, etc.).  Marking it `#[cold]`
/// moves it off the hot-path instruction cache and lets the compiler optimise
/// the `len ≤ 2` fast path more aggressively.
#[cold]
#[inline(never)]
pub(super) fn grapheme_scalar_count(s: &str) -> usize {
    s.chars().count().max(1)
}

/// Core cell-encoding kernel: populate `pool` from `cells`.
///
/// Caller is responsible for calling `pool.clear()` and handling the empty
/// fast path before invoking this function.  Both `encode_line_with_pool`
/// and `encode_line_into_buf` satisfy those preconditions.
#[inline]
#[expect(
    clippy::similar_names,
    reason = "current_fg/current_bg are intentional parallel names for foreground and background color sentinels"
)]
pub(super) fn fill_encode_pool(cells: &[Cell], has_wide: bool, pool: &mut EncodePool) {
    // Reserve 2 bytes/cell: Latin Extended, Greek, Cyrillic are 2 UTF-8 bytes each.
    // Avoids a mid-loop realloc on non-ASCII terminals with ~50% overhead vs 1x reserve.
    pool.text.reserve(cells.len() * 2);
    // Reserve for face ranges: 8 is too few for syntax-highlighted terminals
    // (neovim, helix) where every cell can have a distinct color.  Cap at 64
    // to avoid over-allocation on wide terminals (240 cols) with few colors.
    pool.face_ranges.reserve(cells.len().min(64));

    let mut buf_offset = 0usize;
    let mut current_start_buf = 0usize;
    let mut current_fg = u32::MAX;
    let mut current_bg = u32::MAX;
    let mut current_flags = u64::MAX;
    let mut current_ul_color = u32::MAX;
    let mut col = 0usize;
    // Track the buf_offset where the most recent wide character started.
    // Used by wide placeholder cells to point back to the correct position,
    // which matters for multi-codepoint characters (e.g. emoji ZWJ sequences)
    // where buf_offset.saturating_sub(1) would be wrong.
    let mut last_wide_char_start = 0usize;

    // Pre-scan eliminated: `has_wide` is maintained incrementally on `Line`
    // via `update_cell_with`, so callers pass it here without an O(cols) scan.
    // The `col_to_buf` identity mapping is only initialized when actually needed.
    if has_wide {
        // resize(n, 0) is a single memset — every entry is overwritten in the loop
        // below anyway, so the identity pre-fill of extend(0..n) is redundant.
        pool.col_to_buf.resize(cells.len(), 0);
    }

    for cell in cells {
        // `match` on a 3-variant enum lets the compiler emit a single discriminant
        // dispatch instead of two sequential `if` checks.  On the dominant Half path
        // the compiler can prove the second check is unreachable, eliminating it.
        match cell.width {
            CellWidth::Wide => {
                debug_assert!(col > 0, "Wide placeholder cannot appear at column 0");
                // Override the pre-filled identity entry with the wide char position.
                pool.col_to_buf[col] = last_wide_char_start;
                col += 1;
                continue;
            }
            CellWidth::Full => {
                last_wide_char_start = buf_offset;
            }
            _ => {} // Half — no special action needed
        }

        if has_wide {
            pool.col_to_buf[col] = buf_offset;
        }
        col += 1;

        pool.text.push_str(cell.grapheme.as_str());

        // Text-sizing (OSC 66): record this cell's effective multiplier so a
        // text-size-only change folds into the row hash.  Sparse encoding —
        // only sized cells push `(buf_offset, permille)` — keeps ordinary lines
        // (no text size anywhere) at an empty Vec and zero hashing cost.
        if let Some(ts) = cell.text_size() {
            #[expect(
                clippy::cast_possible_truncation,
                reason = "buf_offset is a buffer char offset (≤ terminal width ≤ 65535); fits u32"
            )]
            let off = buf_offset as u32;
            pool.text_sizes.push(off);
            pool.text_sizes.push(ts.scaled_permille());
        }

        // Fast path: skip four encode_color/encode_attrs calls for default-styled
        // cells (no color, no SGR flags).  Shell prompts, man-page output, and
        // plain text workloads are overwhelmingly default-styled, so branch
        // prediction strongly favours this path.  Sentinel constants are used
        // directly rather than recomputing them through the encode functions.
        let (fg, bg, flags, ul_color) = if cell.attrs.is_all_default() {
            (
                COLOR_DEFAULT_SENTINEL,
                COLOR_DEFAULT_SENTINEL,
                0u64,
                COLOR_DEFAULT_SENTINEL,
            )
        } else {
            (
                encode_color(&cell.attrs.foreground),
                encode_color(&cell.attrs.background),
                encode_attrs(&cell.attrs),
                encode_color(&cell.attrs.underline_color),
            )
        };

        if fg != current_fg
            || bg != current_bg
            || flags != current_flags
            || ul_color != current_ul_color
        {
            if buf_offset > current_start_buf {
                pool.face_ranges.push(EncodedFaceRange {
                    start_buf: current_start_buf,
                    end_buf: buf_offset,
                    fg: current_fg,
                    bg: current_bg,
                    flags: current_flags,
                    underline_color: current_ul_color,
                });
                current_start_buf = buf_offset;
            }
            current_fg = fg;
            current_bg = bg;
            current_flags = flags;
            current_ul_color = ul_color;
        }

        // A grapheme of len ≤ 2 is always exactly one Unicode scalar:
        // len=1 → ASCII; len=2 → U+0080..U+07FF (Latin Extended, Greek,
        // Cyrillic, etc.).  No grapheme cluster can be 2 bytes with 2 scalars
        // because combining characters start at U+0300 (2 bytes), requiring
        // a base ≥ 1 byte → minimum multi-scalar length = 3 bytes.
        buf_offset += if cell.grapheme.len() <= 2 {
            1
        } else {
            grapheme_scalar_count(&cell.grapheme)
        };
    }

    if current_start_buf < buf_offset {
        pool.face_ranges.push(EncodedFaceRange {
            start_buf: current_start_buf,
            end_buf: buf_offset,
            fg: current_fg,
            bg: current_bg,
            flags: current_flags,
            underline_color: current_ul_color,
        });
    }
}

/// Encode a slice of cells into [`EncodedLineData`] for FFI transfer.
///
/// ## Wide character handling
///
/// CJK characters and other wide glyphs occupy two terminal grid columns but
/// are represented as a single Unicode scalar in the Emacs buffer.  The second
/// "placeholder" cell (`CellWidth::Wide` with a space grapheme) is therefore
/// **skipped** when building `text`.
///
/// The returned `col_to_buf` vector maps every grid column index to its
/// corresponding buffer character offset (0-based from line start):
/// - For the first cell of a wide char: `col_to_buf[col] = buf_offset`.
/// - For the placeholder cell:          `col_to_buf[col+1] = buf_offset` (same).
/// - For normal half-width cells:       `col_to_buf[col] = buf_offset`.
///
/// **ASCII fast path**: when the line contains no `CellWidth::Wide` cells,
/// an **empty** `col_to_buf` is returned.  The Emacs side falls back to
/// using `col` directly when the vector is shorter than `col`.
///
/// `face_ranges` uses **buffer offsets** (not grid column indices) so that
/// `kuro--apply-faces-from-ffi` can apply them directly.
#[inline]
pub fn encode_line(cells: &[Cell]) -> EncodedLineData {
    let mut pool = EncodePool::new();
    let has_wide = cells.iter().any(|c| c.width == CellWidth::Wide);
    encode_line_with_pool(cells, has_wide, &mut pool)
}

/// Encode a slice of cells into the provided [`EncodePool`], then clone the
/// results into an [`EncodedLineData`].
///
/// This is a pool-aware variant of [`encode_line`].  The pool's `String` and
/// `Vec` allocations are reused across calls (cleared then refilled), so only
/// one clone-into-result allocation happens per line instead of one fresh
/// allocation plus a clone.
#[inline]
pub(crate) fn encode_line_with_pool(
    cells: &[Cell],
    has_wide: bool,
    pool: &mut EncodePool,
) -> EncodedLineData {
    pool.clear();
    if cells.is_empty() {
        return EncodedLineData::empty();
    }
    fill_encode_pool(cells, has_wide, pool);
    // mem::take moves each field out in O(1) (pointer swap), leaving the pool
    // with empty-but-valid fields.  Avoids three heap malloc+memcpy per dirty row.
    EncodedLineData {
        text: mem::take(&mut pool.text),
        face_ranges: mem::take(&mut pool.face_ranges),
        col_to_buf: mem::take(&mut pool.col_to_buf),
    }
}

/// Serialise one 28-byte v2 face range into `buf`.
///
/// Coalesces 6 separate `extend_from_slice` calls into a single 28-byte
/// stack-buffer write.  Used by both [`encode_line_into_buf`] and
/// `encode_screen_binary` to avoid code duplication.
#[inline]
#[expect(
    clippy::cast_possible_truncation,
    reason = "start_buf/end_buf are buffer char offsets (≤ line length ≤ 65535); fit u32"
)]
pub(super) fn write_face_range(buf: &mut Vec<u8>, range: &EncodedFaceRange) {
    let mut range_buf = [0u8; 28];
    range_buf[0..4].copy_from_slice(&(range.start_buf as u32).to_le_bytes());
    range_buf[4..8].copy_from_slice(&(range.end_buf as u32).to_le_bytes());
    range_buf[8..12].copy_from_slice(&range.fg.to_le_bytes());
    range_buf[12..16].copy_from_slice(&range.bg.to_le_bytes());
    range_buf[16..24].copy_from_slice(&range.flags.to_le_bytes());
    range_buf[24..28].copy_from_slice(&range.underline_color.to_le_bytes());
    buf.extend_from_slice(&range_buf);
}

/// Encode a cell slice into the pool, then serialise face ranges and
/// `col_to_buf` directly into `buf` — without cloning either collection.
///
/// `buf` must already contain the global 8-byte header
/// (`format_version + num_rows`).  Each call appends one complete row entry:
///
/// ```text
/// row_index(u32) num_face_ranges(u32) text_byte_len(u32)=0
/// [28-byte face ranges …]
/// col_to_buf_len(u32) [u32 entries …]
/// ```
#[inline]
pub(crate) fn encode_line_into_buf(
    cells: &[Cell],
    has_wide: bool,
    pool: &mut EncodePool,
    row_index: usize,
    buf: &mut Vec<u8>,
) -> String {
    pool.clear();

    #[expect(
        clippy::cast_possible_truncation,
        reason = "row index is a terminal row (≤ 65535); fits u32"
    )]
    let row_index_u32 = row_index as u32;

    if cells.is_empty() {
        // Coalesce 4 × 4-byte writes into a single 16-byte stack-buffer write.
        let mut empty_row = [0u8; 16];
        empty_row[0..4].copy_from_slice(&row_index_u32.to_le_bytes());
        // bytes 4–15 remain zero: num_face_ranges=0, text_byte_len=0, col_to_buf_len=0
        buf.extend_from_slice(&empty_row);
        return String::new();
    }

    fill_encode_pool(cells, has_wide, pool);

    // Pre-reserve: 12-byte row header + 28 bytes/face-range + 4 bytes/col_to_buf entry + 4-byte count.
    let row_bytes = 12 + 28 * pool.face_ranges.len() + 4 + 4 * pool.col_to_buf.len();
    buf.reserve(row_bytes);

    // Serialise directly into buf — no clone of face_ranges or col_to_buf.
    buf.extend_from_slice(&row_index_u32.to_le_bytes());

    #[expect(
        clippy::cast_possible_truncation,
        reason = "face range count is bounded by terminal width (≤ 65535); fits u32"
    )]
    buf.extend_from_slice(&(pool.face_ranges.len() as u32).to_le_bytes());

    buf.extend_from_slice(&0u32.to_le_bytes()); // text_byte_len = 0 (text supplied as native Emacs strings)

    // Coalesce 6 separate extend_from_slice calls into a single 28-byte stack-buffer write.
    // At 30 dirty rows × 6 ranges × 120fps = 21,600 range writes/sec.
    for range in &pool.face_ranges {
        write_face_range(buf, range);
    }

    #[expect(
        clippy::cast_possible_truncation,
        reason = "col_to_buf length is bounded by terminal width (≤ 65535); fits u32"
    )]
    buf.extend_from_slice(&(pool.col_to_buf.len() as u32).to_le_bytes());

    for &offset in &pool.col_to_buf {
        #[expect(
            clippy::cast_possible_truncation,
            reason = "col_to_buf entries are buffer char offsets (≤ terminal width ≤ 65535); fit u32"
        )]
        buf.extend_from_slice(&(offset as u32).to_le_bytes());
    }

    let mut text = String::new();
    mem::swap(&mut text, &mut pool.text);
    text
}
