//! Color and attribute encoding for FFI data transfer
//!
//! This module provides encoding functions for converting terminal state
//! (colors, SGR attributes, cell data) into compact integer representations
//! suitable for FFI transfer to Emacs Lisp.
//!
//! # Encoding formats
//!
//! ## Color encoding (u32)
//! - `0xFF000000` ([`COLOR_DEFAULT_SENTINEL`]): `Color::Default` (distinct from true black)
//! - Bit 31 set ([`COLOR_NAMED_MARKER`] `| index`): Named color (index 0-15)
//! - Bit 30 set ([`COLOR_INDEXED_MARKER`] `| index`): Indexed color (index 0-255)
//! - Lower 24 bits only: RGB packed as `(R << 16) | (G << 8) | B`
//!
//! ## Attribute encoding (u64)
//! Bitmask of SGR boolean flags:
//! - Bit 0 (`0x001`): bold
//! - Bit 1 (`0x002`): dim
//! - Bit 2 (`0x004`): italic
//! - Bit 3 (`0x008`, [`ATTRS_UNDERLINE_BIT`]): underline (any style)
//! - Bits 9-11 (shift [`ATTRS_STYLE_SHIFT`]): underline style (0-5)
//! - Bit 4 (`0x010`): blink slow
//! - Bit 5 (`0x020`): blink fast
//! - Bit 6 (`0x040`): inverse
//! - Bit 7 (`0x080`): hidden
//! - Bit 8 (`0x100`): strikethrough

use crate::grid::line::Line;
use crate::types::cell::{Cell, CellWidth, SgrAttributes, UnderlineStyle};
use crate::types::color::Color;
use std::hash::{Hash, Hasher};

// -------------------------------------------------------------------------
// Color encoding constants
// -------------------------------------------------------------------------

/// Sentinel value for `Color::Default` in the u32 FFI encoding.
///
/// Cannot be confused with any RGB value because the upper byte `0xFF` is
/// never set by RGB (`r << 16 | g << 8 | b` uses at most 24 bits) and the
/// named/indexed markers use bits 31 and 30 respectively, not `0xFF…`.
pub const COLOR_DEFAULT_SENTINEL: u32 = 0xFF00_0000;

/// Bit-31 marker for `Color::Named` in the u32 FFI encoding.
///
/// `encode_color(Color::Named(c))` produces `COLOR_NAMED_MARKER | (c as u8)`.
pub const COLOR_NAMED_MARKER: u32 = 0x8000_0000;

/// Bit-30 marker for `Color::Indexed` in the u32 FFI encoding.
///
/// `encode_color(Color::Indexed(i))` produces `COLOR_INDEXED_MARKER | i`.
pub const COLOR_INDEXED_MARKER: u32 = 0x4000_0000;

/// Bit shift for the red channel in RGB packing: `r << RGB_R_SHIFT`.
pub const RGB_R_SHIFT: u32 = 16;

/// Bit shift for the green channel in RGB packing: `g << RGB_G_SHIFT`.
pub const RGB_G_SHIFT: u32 = 8;

// -------------------------------------------------------------------------
// Attribute encoding constants
// -------------------------------------------------------------------------

/// Bitmask that selects the three SGR flag bits that map directly (bold, dim,
/// italic) before the underline-bit insertion gap.
///
/// `SgrFlags` bits 0-2 (BOLD, DIM, ITALIC) map to encode bits 0-2 unchanged.
const ATTRS_LOW_BITS_MASK: u64 = 0x07;

/// Right-shift applied to the upper `SgrFlags` bits (BLINK_SLOW … STRIKETHROUGH,
/// i.e. original bits 3-7) before they are placed at encode bits 4-8, making
/// room for the underline flag at bit 3.
const ATTRS_HIGH_BITS_RSHIFT: u32 = 3;

/// Left-shift that moves the upper `SgrFlags` bits into their final encode
/// positions (bits 4-8) after the right-shift above.
const ATTRS_HIGH_BITS_LSHIFT: u32 = 4;

/// Bit position of the "any underline active" flag in the encoded `u64`.
pub const ATTRS_UNDERLINE_BIT: u64 = 0x008;

/// Bit position (shift) of the 3-bit underline style field in the encoded `u64`.
pub const ATTRS_STYLE_SHIFT: u32 = 9;

/// Encoded line data for FFI transfer: `(row, text, face_ranges, col_to_buf)`.
///
/// - `row`: grid row index
/// - `text`: UTF-8 content with wide-placeholder cells removed
/// - `face_ranges`: `(start_buf, end_buf, fg, bg, flags, ul_color)` in buffer offsets
/// - `col_to_buf`: maps grid column → buffer char offset (empty = identity)
pub(crate) type EncodedLine = (
    usize,
    String,
    Vec<(usize, usize, u32, u32, u64, u32)>,
    Vec<usize>,
);

/// Inner line data without row index: `(text, face_ranges, col_to_buf)`.
///
/// Used as the return type of [`encode_line`]. [`EncodedLine`] prepends the
/// row index (`usize`) to produce the full FFI transfer tuple.
pub(crate) type EncodedLineData = (String, Vec<(usize, usize, u32, u32, u64, u32)>, Vec<usize>);

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
    pub face_ranges: Vec<(usize, usize, u32, u32, u64, u32)>,
    pub col_to_buf: Vec<usize>,
}

impl EncodePool {
    #[inline]
    pub(crate) fn new() -> Self {
        Self {
            text: String::new(),
            face_ranges: Vec::new(),
            col_to_buf: Vec::new(),
        }
    }

    #[inline]
    pub(crate) fn clear(&mut self) {
        self.text.clear();
        self.face_ranges.clear();
        self.col_to_buf.clear();
    }
}

/// Encode a `Color` value as a `u32` for FFI transfer.
///
/// The encoding uses sentinel/marker bits to distinguish color variants
/// without ambiguity:
/// - `Color::Default` → [`COLOR_DEFAULT_SENTINEL`]
/// - `Color::Named(c)` → [`COLOR_NAMED_MARKER`] `| index`
/// - `Color::Indexed(i)` → [`COLOR_INDEXED_MARKER`] `| i`
/// - `Color::Rgb(r, g, b)` → `(r << RGB_R_SHIFT) | (g << RGB_G_SHIFT) | b` (can be 0 = true black)
#[inline(always)]
#[must_use = "encode result must be used for FFI transfer to Emacs Lisp"]
pub fn encode_color(color: &Color) -> u32 {
    match color {
        Color::Default => COLOR_DEFAULT_SENTINEL,
        // NamedColor is #[repr(u8)] with discriminants 0..=15,
        // so a direct cast replaces the 16-arm match with a single instruction.
        Color::Named(named) => COLOR_NAMED_MARKER | u32::from(*named as u8),
        Color::Indexed(idx) => COLOR_INDEXED_MARKER | u32::from(*idx),
        Color::Rgb(r, g, b) => {
            (u32::from(*r) << RGB_R_SHIFT) | (u32::from(*g) << RGB_G_SHIFT) | u32::from(*b)
        }
    }
}

/// Encode `SgrAttributes` as a `u64` bitmask for FFI transfer.
///
/// Each boolean SGR attribute maps to a dedicated bit position.
/// The underline style is encoded in bits [`ATTRS_STYLE_SHIFT`]-11 as a 3-bit integer.
#[inline]
#[must_use = "encode result must be used for FFI transfer to Emacs Lisp"]
pub fn encode_attrs(attrs: &SgrAttributes) -> u64 {
    // SgrFlags layout:  BOLD=0, DIM=1, ITALIC=2, BLINK_SLOW=3, BLINK_FAST=4, INVERSE=5, HIDDEN=6, STRIKETHROUGH=7
    // Encode layout:    bold=0, dim=1,  italic=2, underline=3,  blink_slow=4, blink_fast=5, inverse=6, hidden=7, strike=8
    // Bits 0-2 (ATTRS_LOW_BITS_MASK) map directly; bits 3-7 shift left by 1
    // (ATTRS_HIGH_BITS_RSHIFT / ATTRS_HIGH_BITS_LSHIFT) to make room for the underline flag at bit 3.
    let raw = u64::from(attrs.flags.bits());
    let mut bits =
        (raw & ATTRS_LOW_BITS_MASK) | ((raw >> ATTRS_HIGH_BITS_RSHIFT) << ATTRS_HIGH_BITS_LSHIFT);
    if attrs.underline() {
        bits |= ATTRS_UNDERLINE_BIT;
    }
    let style_bits: u64 = match attrs.underline_style {
        UnderlineStyle::None => 0,
        UnderlineStyle::Straight => 1,
        UnderlineStyle::Double => 2,
        UnderlineStyle::Curly => 3,
        UnderlineStyle::Dotted => 4,
        UnderlineStyle::Dashed => 5,
    };
    bits |= style_bits << ATTRS_STYLE_SHIFT;
    bits
}

/// Encode a slice of cells into `(text, face_ranges, col_to_buf)` for FFI transfer.
///
/// ## Wide character handling
///
/// CJK characters and other wide glyphs occupy two terminal grid columns but
/// are represented as a single Unicode scalar in the Emacs buffer.  The second
/// "placeholder" cell (`CellWidth::Wide` with a space grapheme) is therefore
/// **skipped** when building `text`; Emacs already renders each wide scalar at
/// double width natively.
///
/// The returned `col_to_buf` vector maps every grid column index to its
/// corresponding buffer character offset (0-based from line start):
/// - For the first cell of a wide char: `col_to_buf[col] = buf_offset`.
/// - For the placeholder cell:          `col_to_buf[col+1] = buf_offset` (same).
/// - For normal half-width cells:       `col_to_buf[col] = buf_offset`.
///
/// **ASCII fast path**: when the line contains no `CellWidth::Wide` cells
/// (the overwhelming majority for English/ASCII output), `col_to_buf[i] == i`
/// for every column, so an **empty** `col_to_buf` is returned instead.  The
/// Emacs side falls back to using `col` directly when the vector is shorter
/// than `col`, which is always the case for an empty vector — matching the
/// identity mapping exactly.  This eliminates 80+ FFI calls per dirty ASCII
/// line (89% of the per-line cost).
///
/// `face_ranges` uses **buffer offsets** (not grid column indices) so that
/// `kuro--apply-faces-from-ffi` can apply them directly with
/// `(+ line-start start-buf)`.
///
/// ## Cursor placement
///
/// `kuro--update-cursor` must now use `col_to_buf[cursor_col]` instead of
/// `cursor_col` directly.  The FFI returns `col_to_buf` alongside the dirty
/// line data so Emacs has the mapping available each frame.
///
/// ## Trailing spaces
///
/// Trailing spaces are preserved so that the cursor can be placed at any
/// column, including past the last visible character.
#[must_use = "encode result must be used for FFI transfer to Emacs Lisp"]
#[expect(
    clippy::similar_names,
    reason = "current_fg/current_bg are intentional parallel names for foreground and background color sentinels"
)]
pub fn encode_line(cells: &[Cell]) -> EncodedLineData {
    if cells.is_empty() {
        return (String::new(), Vec::new(), Vec::new());
    }

    let mut text = String::with_capacity(cells.len());
    // face_ranges use buf_offset (not col) for start/end
    let mut face_ranges: Vec<(usize, usize, u32, u32, u64, u32)> = Vec::with_capacity(8);
    // col_to_buf[col] = buffer char offset; lazily built on the first Wide cell.
    // Stays empty for pure-ASCII lines (identity mapping implied on Emacs side).
    let mut col_to_buf: Vec<usize> = Vec::new();
    let mut buf_offset = 0usize;
    let mut current_start_buf = 0usize;
    // Sentinel values that cannot match any valid encoded color/flags.
    // This ensures the very first cell always triggers a face-range boundary,
    // correctly starting accumulation with the cell's actual attributes.
    // Previously 0 (true black) — which collided with Color::Rgb(0,0,0).
    let mut current_fg = u32::MAX;
    let mut current_bg = u32::MAX;
    let mut current_flags = u64::MAX;
    let mut current_ul_color = u32::MAX;
    // Column counter for lazy col_to_buf backfill.
    let mut col = 0usize;

    for cell in cells {
        // Any CellWidth::Wide cell is a placeholder for the second column of a wide
        // (CJK/emoji) character.  Skip it: the base character was already emitted and
        // advances the Emacs buffer by exactly one char position.
        if cell.width == CellWidth::Wide {
            // Lazily initialise col_to_buf on the first Wide cell encountered.
            // Backfill identity mappings (0,1,2,…) for all columns already processed.
            if col_to_buf.is_empty() {
                col_to_buf.reserve(cells.len());
                col_to_buf.extend(0..col);
            }
            // Map this grid column to the same buf_offset as the wide char (one behind).
            debug_assert!(col > 0, "Wide placeholder cannot appear at column 0");
            col_to_buf.push(buf_offset.saturating_sub(1));
            col += 1;
            // Do NOT advance buf_offset or write to text.
            continue;
        }

        // Record col → buf mapping for this cell (only when col_to_buf was activated).
        if !col_to_buf.is_empty() {
            col_to_buf.push(buf_offset);
        }
        col += 1;

        // Push the full grapheme cluster (covers combining chars too)
        text.push_str(cell.grapheme.as_str());

        let fg = encode_color(&cell.attrs.foreground);
        let bg = encode_color(&cell.attrs.background);
        let flags = encode_attrs(&cell.attrs);
        let ul_color = encode_color(&cell.attrs.underline_color);

        if fg != current_fg
            || bg != current_bg
            || flags != current_flags
            || ul_color != current_ul_color
        {
            if buf_offset > current_start_buf {
                face_ranges.push((
                    current_start_buf,
                    buf_offset,
                    current_fg,
                    current_bg,
                    current_flags,
                    current_ul_color,
                ));
                current_start_buf = buf_offset;
            }
            current_fg = fg;
            current_bg = bg;
            current_flags = flags;
            current_ul_color = ul_color;
        }

        // Advance by the number of Unicode scalar values in the grapheme cluster.
        // A plain ASCII/CJK cell has grapheme.chars().count() == 1.
        // A cell with an attached combining character (e.g. "é" = U+0065 U+0301)
        // has count == 2, which is exactly the number of Emacs buffer positions
        // that `(insert grapheme)` will consume.  Using a hard-coded 1 here caused
        // col_to_buf entries after any combining-char cell to point to the wrong
        // buffer position, corrupting cursor placement and face application.
        buf_offset += if cell.grapheme.len() <= 1 {
            1
        } else {
            cell.grapheme.chars().count().max(1)
        };
    }

    // Push the final face segment
    if current_start_buf < buf_offset {
        face_ranges.push((
            current_start_buf,
            buf_offset,
            current_fg,
            current_bg,
            current_flags,
            current_ul_color,
        ));
    }

    (text, face_ranges, col_to_buf)
}

/// Encode a slice of cells into the provided [`EncodePool`], then clone the
/// results into an [`EncodedLine`].
///
/// This is a pool-aware variant of [`encode_line`].  The pool's `String` and
/// `Vec` allocations are reused across calls (cleared then refilled), so only
/// one clone-into-result allocation happens per line instead of one fresh
/// allocation plus a clone.
///
/// # Panics
///
/// Does not panic; identical logic to [`encode_line`].
#[inline]
#[expect(
    clippy::similar_names,
    reason = "current_fg/current_bg are intentional parallel names for foreground and background color sentinels"
)]
pub(crate) fn encode_line_with_pool(cells: &[Cell], pool: &mut EncodePool) -> EncodedLineData {
    pool.clear();

    if cells.is_empty() {
        return (String::new(), Vec::new(), Vec::new());
    }

    pool.text.reserve(cells.len());
    pool.face_ranges.reserve(8);

    let mut buf_offset = 0usize;
    let mut current_start_buf = 0usize;
    let mut current_fg = u32::MAX;
    let mut current_bg = u32::MAX;
    let mut current_flags = u64::MAX;
    let mut current_ul_color = u32::MAX;
    let mut col = 0usize;

    for cell in cells {
        if cell.width == CellWidth::Wide {
            if pool.col_to_buf.is_empty() {
                pool.col_to_buf.reserve(cells.len());
                pool.col_to_buf.extend(0..col);
            }
            debug_assert!(col > 0, "Wide placeholder cannot appear at column 0");
            pool.col_to_buf.push(buf_offset.saturating_sub(1));
            col += 1;
            continue;
        }

        if !pool.col_to_buf.is_empty() {
            pool.col_to_buf.push(buf_offset);
        }
        col += 1;

        pool.text.push_str(cell.grapheme.as_str());

        let fg = encode_color(&cell.attrs.foreground);
        let bg = encode_color(&cell.attrs.background);
        let flags = encode_attrs(&cell.attrs);
        let ul_color = encode_color(&cell.attrs.underline_color);

        if fg != current_fg
            || bg != current_bg
            || flags != current_flags
            || ul_color != current_ul_color
        {
            if buf_offset > current_start_buf {
                pool.face_ranges.push((
                    current_start_buf,
                    buf_offset,
                    current_fg,
                    current_bg,
                    current_flags,
                    current_ul_color,
                ));
                current_start_buf = buf_offset;
            }
            current_fg = fg;
            current_bg = bg;
            current_flags = flags;
            current_ul_color = ul_color;
        }

        buf_offset += if cell.grapheme.len() <= 1 {
            1
        } else {
            cell.grapheme.chars().count().max(1)
        };
    }

    if current_start_buf < buf_offset {
        pool.face_ranges.push((
            current_start_buf,
            buf_offset,
            current_fg,
            current_bg,
            current_flags,
            current_ul_color,
        ));
    }

    (
        pool.text.clone(),
        pool.face_ranges.clone(),
        pool.col_to_buf.clone(),
    )
}

/// Encode a cell slice into the pool, then serialise **face ranges and
/// `col_to_buf`** directly into `buf` — without cloning either collection.
///
/// This is a single-pass, zero-intermediate-clone variant of
/// [`encode_line_with_pool`] used by the Protocol-B `-with-strings` FFI path.
/// Only the text `String` is cloned (once) and returned, because the caller
/// must hand it to Emacs as a native string.  The two `Vec` clones that
/// [`encode_line_with_pool`] performs are replaced by a direct serialisation
/// loop into `buf`.
///
/// `buf` must already contain the global 8-byte header
/// (`format_version + num_rows`).  Each call appends one complete row entry:
///
/// ```text
/// row_index(u32) num_face_ranges(u32) text_byte_len(u32)=0
/// [28-byte face ranges …]
/// col_to_buf_len(u32) [u32 entries …]
/// ```
///
/// # Panics
///
/// Does not panic; identical encoding logic to [`encode_line_with_pool`].
#[inline]
#[expect(
    clippy::similar_names,
    reason = "current_fg/current_bg are intentional parallel names for foreground and background color sentinels"
)]
pub(crate) fn encode_line_into_buf(
    cells: &[Cell],
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
        buf.extend_from_slice(&row_index_u32.to_le_bytes());
        buf.extend_from_slice(&0u32.to_le_bytes()); // num_face_ranges
        buf.extend_from_slice(&0u32.to_le_bytes()); // text_byte_len = 0
        buf.extend_from_slice(&0u32.to_le_bytes()); // col_to_buf_len
        return String::new();
    }

    // Same encoding logic as encode_line_with_pool, filling pool.{text,face_ranges,col_to_buf}.
    pool.text.reserve(cells.len());
    pool.face_ranges.reserve(8);

    let mut buf_offset = 0usize;
    let mut current_start_buf = 0usize;
    let mut current_fg = u32::MAX;
    let mut current_bg = u32::MAX;
    let mut current_flags = u64::MAX;
    let mut current_ul_color = u32::MAX;
    let mut col = 0usize;

    for cell in cells {
        if cell.width == CellWidth::Wide {
            if pool.col_to_buf.is_empty() {
                pool.col_to_buf.reserve(cells.len());
                pool.col_to_buf.extend(0..col);
            }
            debug_assert!(col > 0, "Wide placeholder cannot appear at column 0");
            pool.col_to_buf.push(buf_offset.saturating_sub(1));
            col += 1;
            continue;
        }

        if !pool.col_to_buf.is_empty() {
            pool.col_to_buf.push(buf_offset);
        }
        col += 1;

        pool.text.push_str(cell.grapheme.as_str());

        let fg = encode_color(&cell.attrs.foreground);
        let bg = encode_color(&cell.attrs.background);
        let flags = encode_attrs(&cell.attrs);
        let ul_color = encode_color(&cell.attrs.underline_color);

        if fg != current_fg
            || bg != current_bg
            || flags != current_flags
            || ul_color != current_ul_color
        {
            if buf_offset > current_start_buf {
                pool.face_ranges.push((
                    current_start_buf,
                    buf_offset,
                    current_fg,
                    current_bg,
                    current_flags,
                    current_ul_color,
                ));
                current_start_buf = buf_offset;
            }
            current_fg = fg;
            current_bg = bg;
            current_flags = flags;
            current_ul_color = ul_color;
        }

        buf_offset += if cell.grapheme.len() <= 1 {
            1
        } else {
            cell.grapheme.chars().count().max(1)
        };
    }

    if current_start_buf < buf_offset {
        pool.face_ranges.push((
            current_start_buf,
            buf_offset,
            current_fg,
            current_bg,
            current_flags,
            current_ul_color,
        ));
    }

    // Serialise directly into buf — no clone of face_ranges or col_to_buf.
    buf.extend_from_slice(&row_index_u32.to_le_bytes());

    #[expect(
        clippy::cast_possible_truncation,
        reason = "face range count is bounded by terminal width (≤ 65535); fits u32"
    )]
    buf.extend_from_slice(&(pool.face_ranges.len() as u32).to_le_bytes());

    buf.extend_from_slice(&0u32.to_le_bytes()); // text_byte_len = 0 (text supplied as native Emacs strings)

    for &(start_buf, end_buf, fg, bg, flags, ul_color) in &pool.face_ranges {
        #[expect(
            clippy::cast_possible_truncation,
            reason = "start_buf/end_buf are buffer char offsets (≤ line length ≤ 65535); fit u32"
        )]
        {
            buf.extend_from_slice(&(start_buf as u32).to_le_bytes());
            buf.extend_from_slice(&(end_buf as u32).to_le_bytes());
        }
        buf.extend_from_slice(&fg.to_le_bytes());
        buf.extend_from_slice(&bg.to_le_bytes());
        buf.extend_from_slice(&flags.to_le_bytes());
        buf.extend_from_slice(&ul_color.to_le_bytes());
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

    pool.text.clone()
}

/// Current binary frame format version.
///
/// Version 1: 8-byte header `[format_version: u32 LE][num_rows: u32 LE]`,
/// with 24-byte face ranges: `start_buf(u32) end_buf(u32) fg(u32) bg(u32) flags(u64)`.
///
/// Version 2: extends each face range to 28 bytes by appending a 4-byte
/// `underline_color` field: `start_buf(u32) end_buf(u32) fg(u32) bg(u32) flags(u64) ul_color(u32)`.
/// The Emacs decoder validates this field and signals an error for any
/// unrecognised version, preventing silent corruption when the `.so` and
/// byte-compiled `.elc` are mismatched.
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
///
/// The Emacs side decodes this with `kuro--decode-binary-updates`, which uses
/// `aref` + `logior`/`ash` to reconstruct little-endian integers.
#[must_use = "encode result must be used for FFI transfer to Emacs Lisp"]
pub(crate) fn encode_screen_binary(lines: &[EncodedLine]) -> Vec<u8> {
    // Pre-compute total capacity to avoid repeated reallocation.
    let capacity = {
        let mut cap = 8usize; // format_version + num_rows header
        for (_, text, face_ranges, col_to_buf) in lines {
            cap += 12; // row_index + num_face_ranges + text_byte_len
            cap += text.len();
            cap += face_ranges.len() * 28; // 28 bytes per face range (version 2)
            cap += 4; // col_to_buf_len
            cap += col_to_buf.len() * 4;
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

    for (row_index, text, face_ranges, col_to_buf) in lines {
        // row_index
        #[expect(
            clippy::cast_possible_truncation,
            reason = "row index is a terminal row (≤ 65535); fits u32"
        )]
        buf.extend_from_slice(&(*row_index as u32).to_le_bytes());

        // num_face_ranges
        #[expect(
            clippy::cast_possible_truncation,
            reason = "face range count is bounded by terminal width (≤ 65535); fits u32"
        )]
        buf.extend_from_slice(&(face_ranges.len() as u32).to_le_bytes());

        // text_byte_len + text bytes
        #[expect(
            clippy::cast_possible_truncation,
            reason = "UTF-8 text byte length for one terminal line fits u32"
        )]
        buf.extend_from_slice(&(text.len() as u32).to_le_bytes());
        buf.extend_from_slice(text.as_bytes());

        // Per face range: start_buf (u32), end_buf (u32), fg (u32), bg (u32), flags (u64), ul_color (u32)
        for &(start_buf, end_buf, fg, bg, flags, ul_color) in face_ranges {
            #[expect(
                clippy::cast_possible_truncation,
                reason = "start_buf/end_buf are buffer char offsets (≤ line length ≤ 65535); fit u32"
            )]
            {
                buf.extend_from_slice(&(start_buf as u32).to_le_bytes());
                buf.extend_from_slice(&(end_buf as u32).to_le_bytes());
            }
            buf.extend_from_slice(&fg.to_le_bytes());
            buf.extend_from_slice(&bg.to_le_bytes());
            buf.extend_from_slice(&flags.to_le_bytes());
            buf.extend_from_slice(&ul_color.to_le_bytes());
        }

        // col_to_buf section: length header + u32 entries
        #[expect(
            clippy::cast_possible_truncation,
            reason = "col_to_buf length is bounded by terminal width (≤ 65535); fits u32"
        )]
        buf.extend_from_slice(&(col_to_buf.len() as u32).to_le_bytes());
        for &offset in col_to_buf {
            #[expect(
                clippy::cast_possible_truncation,
                reason = "col_to_buf entries are buffer char offsets (≤ terminal width ≤ 65535); fit u32"
            )]
            buf.extend_from_slice(&(offset as u32).to_le_bytes());
        }
    }

    buf
}

/// Compute a stable 64-bit hash for a terminal row.
///
/// Hashes every cell's grapheme bytes, encoded foreground/background colors,
/// encoded SGR flags, and the `col_to_buf` mapping slice.  The result is used
/// by `get_dirty_lines_with_faces` to detect unchanged rows and skip re-encoding
/// them (row-hash skip optimisation, Option A).
///
/// A new [`ahash::AHasher`] is created per call — faster than `DefaultHasher`
/// (SipHash) on the hot render path due to AES-NI acceleration.
#[inline]
pub(crate) fn compute_row_hash(row: &Line, col_to_buf: &[usize]) -> u64 {
    let mut h = ahash::AHasher::default();
    for cell in &row.cells {
        // Hash the grapheme bytes directly — no allocation needed.
        cell.grapheme().as_bytes().hash(&mut h);
        // Encode colors to u32 and hash for a stable, format-independent representation.
        encode_color(&cell.attrs.foreground).hash(&mut h);
        encode_color(&cell.attrs.background).hash(&mut h);
        // Encode all SGR attribute flags (bold/italic/underline/blink/…) as u64.
        encode_attrs(&cell.attrs).hash(&mut h);
        // Hash underline color separately (included in encode_attrs via encode_color).
        encode_color(&cell.attrs.underline_color).hash(&mut h);
        // Hash cell width (Half/Full/Wide) as its discriminant.
        (cell.width as u8).hash(&mut h);
    }
    // Hash the col_to_buf mapping so wide-char layout changes are detected.
    col_to_buf.hash(&mut h);
    h.finish()
}

#[cfg(test)]
#[path = "tests/codec.rs"]
mod tests;
