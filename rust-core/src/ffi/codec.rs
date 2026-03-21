//! Color and attribute encoding for FFI data transfer
//!
//! This module provides encoding functions for converting terminal state
//! (colors, SGR attributes, cell data) into compact integer representations
//! suitable for FFI transfer to Emacs Lisp.
//!
//! # Encoding formats
//!
//! ## Color encoding (u32)
//! - `0xFF000000`: `Color::Default` (sentinel, distinct from true black)
//! - Bit 31 set (`0x80000000 | index`): Named color (index 0-15)
//! - Bit 30 set (`0x40000000 | index`): Indexed color (index 0-255)
//! - Lower 24 bits only: RGB packed as `(R << 16) | (G << 8) | B`
//!
//! ## Attribute encoding (u64)
//! Bitmask of SGR boolean flags:
//! - Bit 0 (`0x001`): bold
//! - Bit 1 (`0x002`): dim
//! - Bit 2 (`0x004`): italic
//! - Bit 3 (`0x008`): underline (any style)
//! - Bits 9-11 (`0xE00`, shift 9): underline style (0-5)
//! - Bit 4 (`0x010`): blink slow
//! - Bit 5 (`0x020`): blink fast
//! - Bit 6 (`0x040`): inverse
//! - Bit 7 (`0x080`): hidden
//! - Bit 8 (`0x100`): strikethrough

use crate::types::cell::{Cell, CellWidth, SgrAttributes, UnderlineStyle};
use crate::types::color::Color;

/// Encoded line data for FFI transfer: `(row, text, face_ranges, col_to_buf)`.
///
/// - `row`: grid row index
/// - `text`: UTF-8 content with wide-placeholder cells removed
/// - `face_ranges`: `(start_buf, end_buf, fg, bg, flags)` in buffer offsets
/// - `col_to_buf`: maps grid column → buffer char offset (empty = identity)
pub(crate) type EncodedLine = (
    usize,
    String,
    Vec<(usize, usize, u32, u32, u64)>,
    Vec<usize>,
);

/// Inner line data without row index: `(text, face_ranges, col_to_buf)`.
///
/// Used as the return type of [`encode_line`]. [`EncodedLine`] prepends the
/// row index (`usize`) to produce the full FFI transfer tuple.
pub(crate) type EncodedLineData = (String, Vec<(usize, usize, u32, u32, u64)>, Vec<usize>);

/// Encode a `Color` value as a `u32` for FFI transfer.
///
/// The encoding uses sentinel/marker bits to distinguish color variants
/// without ambiguity:
/// - `Color::Default` → `0xFF000000` (cannot be confused with any RGB value)
/// - `Color::Named(c)` → `0x80000000 | index`
/// - `Color::Indexed(i)` → `0x40000000 | i`
/// - `Color::Rgb(r, g, b)` → `(r << 16) | (g << 8) | b` (can be 0 = true black)
#[inline]
#[must_use = "encode result must be used for FFI transfer to Emacs Lisp"]
pub fn encode_color(color: &Color) -> u32 {
    match color {
        Color::Default => 0xFF00_0000u32,
        // NamedColor is #[repr(u8)] with discriminants 0..=15,
        // so a direct cast replaces the 16-arm match with a single instruction.
        Color::Named(named) => 0x8000_0000u32 | u32::from(*named as u8),
        Color::Indexed(idx) => 0x4000_0000u32 | u32::from(*idx),
        Color::Rgb(r, g, b) => (u32::from(*r) << 16) | (u32::from(*g) << 8) | u32::from(*b),
    }
}

/// Encode `SgrAttributes` as a `u64` bitmask for FFI transfer.
///
/// Each boolean SGR attribute maps to a dedicated bit position.
/// The underline style is encoded in bits 9-11 as a 3-bit integer.
#[inline]
#[must_use = "encode result must be used for FFI transfer to Emacs Lisp"]
pub fn encode_attrs(attrs: &SgrAttributes) -> u64 {
    // SgrFlags layout:  BOLD=0, DIM=1, ITALIC=2, BLINK_SLOW=3, BLINK_FAST=4, INVERSE=5, HIDDEN=6, STRIKETHROUGH=7
    // Encode layout:    bold=0, dim=1,  italic=2, underline=3,  blink_slow=4, blink_fast=5, inverse=6, hidden=7, strike=8
    // Bits 0-2 map directly; bits 3-7 shift left by 1 to make room for the underline flag at bit 3.
    let raw = u64::from(attrs.flags.bits());
    let mut bits = (raw & 0x07) | ((raw >> 3) << 4);
    if attrs.underline() {
        bits |= 0x008;
    }
    let style_bits: u64 = match attrs.underline_style {
        UnderlineStyle::None => 0,
        UnderlineStyle::Straight => 1,
        UnderlineStyle::Double => 2,
        UnderlineStyle::Curly => 3,
        UnderlineStyle::Dotted => 4,
        UnderlineStyle::Dashed => 5,
    };
    bits |= style_bits << 9;
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

    // ASCII fast path: if no wide-placeholder cells exist, col_to_buf[i] == i
    // identically, so skip building the vector entirely.  A CellWidth::Wide
    // entry signals that the line contains at least one CJK/emoji character.
    let has_wide = cells.iter().any(|c| c.width == CellWidth::Wide);

    let mut text = String::with_capacity(cells.len());
    // face_ranges use buf_offset (not col) for start/end
    let mut face_ranges: Vec<(usize, usize, u32, u32, u64)> = Vec::with_capacity(8);
    // col_to_buf[col] = buffer char offset; only built when has_wide is true.
    let mut col_to_buf: Vec<usize> = if has_wide {
        Vec::with_capacity(cells.len())
    } else {
        Vec::new()
    };
    let mut buf_offset = 0usize;
    let mut current_start_buf = 0usize;
    // Sentinel values that cannot match any valid encoded color/flags.
    // This ensures the very first cell always triggers a face-range boundary,
    // correctly starting accumulation with the cell's actual attributes.
    // Previously 0 (true black) — which collided with Color::Rgb(0,0,0).
    let mut current_fg = u32::MAX;
    let mut current_bg = u32::MAX;
    let mut current_flags = u64::MAX;

    for cell in cells {
        // Any CellWidth::Wide cell is a placeholder for the second column of a wide
        // (CJK/emoji) character.  Skip it: the base character was already emitted and
        // advances the Emacs buffer by exactly one char position.
        if cell.width == CellWidth::Wide {
            // Map this grid column to the same buf_offset as the wide char (one behind).
            // Only needed when col_to_buf is being built (has_wide path).
            if has_wide {
                col_to_buf.push(buf_offset.saturating_sub(1));
            }
            // Do NOT advance buf_offset or write to text.
            continue;
        }

        // Record col → buf mapping for this cell (wide path only).
        if has_wide {
            col_to_buf.push(buf_offset);
        }

        // Push the full grapheme cluster (covers combining chars too)
        text.push_str(cell.grapheme.as_str());

        let fg = encode_color(&cell.attrs.foreground);
        let bg = encode_color(&cell.attrs.background);
        let flags = encode_attrs(&cell.attrs);

        if fg != current_fg || bg != current_bg || flags != current_flags {
            if buf_offset > current_start_buf {
                face_ranges.push((
                    current_start_buf,
                    buf_offset,
                    current_fg,
                    current_bg,
                    current_flags,
                ));
                current_start_buf = buf_offset;
            }
            current_fg = fg;
            current_bg = bg;
            current_flags = flags;
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
        ));
    }

    (text, face_ranges, col_to_buf)
}

#[cfg(test)]
#[path = "tests/codec.rs"]
mod tests;
