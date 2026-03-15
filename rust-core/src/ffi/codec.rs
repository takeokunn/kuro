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
use crate::types::color::{Color, NamedColor};

/// Encode a `Color` value as a `u32` for FFI transfer.
///
/// The encoding uses sentinel/marker bits to distinguish color variants
/// without ambiguity:
/// - `Color::Default` → `0xFF000000` (cannot be confused with any RGB value)
/// - `Color::Named(c)` → `0x80000000 | index`
/// - `Color::Indexed(i)` → `0x40000000 | i`
/// - `Color::Rgb(r, g, b)` → `(r << 16) | (g << 8) | b` (can be 0 = true black)
pub fn encode_color(color: &Color) -> u32 {
    match color {
        Color::Default => 0xFF000000u32,
        Color::Named(named) => {
            let idx: u32 = match named {
                NamedColor::Black => 0,
                NamedColor::Red => 1,
                NamedColor::Green => 2,
                NamedColor::Yellow => 3,
                NamedColor::Blue => 4,
                NamedColor::Magenta => 5,
                NamedColor::Cyan => 6,
                NamedColor::White => 7,
                NamedColor::BrightBlack => 8,
                NamedColor::BrightRed => 9,
                NamedColor::BrightGreen => 10,
                NamedColor::BrightYellow => 11,
                NamedColor::BrightBlue => 12,
                NamedColor::BrightMagenta => 13,
                NamedColor::BrightCyan => 14,
                NamedColor::BrightWhite => 15,
            };
            0x80000000u32 | idx
        }
        Color::Indexed(idx) => 0x40000000u32 | (*idx as u32),
        Color::Rgb(r, g, b) => ((*r as u32) << 16) | ((*g as u32) << 8) | (*b as u32),
    }
}

/// Encode `SgrAttributes` as a `u64` bitmask for FFI transfer.
///
/// Each boolean SGR attribute maps to a dedicated bit position.
/// The underline style is encoded in bits 9-11 as a 3-bit integer.
pub fn encode_attrs(attrs: &SgrAttributes) -> u64 {
    let mut flags = 0u64;
    if attrs.bold {
        flags |= 0x1;
    }
    if attrs.dim {
        flags |= 0x2;
    }
    if attrs.italic {
        flags |= 0x4;
    }
    if attrs.underline() {
        flags |= 0x8;
    }
    let style_bits: u64 = match attrs.underline_style {
        UnderlineStyle::None => 0,
        UnderlineStyle::Straight => 1,
        UnderlineStyle::Double => 2,
        UnderlineStyle::Curly => 3,
        UnderlineStyle::Dotted => 4,
        UnderlineStyle::Dashed => 5,
    };
    flags |= style_bits << 9;
    if attrs.blink_slow {
        flags |= 0x10;
    }
    if attrs.blink_fast {
        flags |= 0x20;
    }
    if attrs.inverse {
        flags |= 0x40;
    }
    if attrs.hidden {
        flags |= 0x80;
    }
    if attrs.strikethrough {
        flags |= 0x100;
    }
    flags
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
#[allow(clippy::type_complexity)]
pub fn encode_line(cells: &[Cell]) -> (String, Vec<(usize, usize, u32, u32, u64)>, Vec<usize>) {
    if cells.is_empty() {
        return (String::new(), Vec::new(), Vec::new());
    }

    let mut text = String::with_capacity(cells.len());
    // face_ranges use buf_offset (not col) for start/end
    let mut face_ranges: Vec<(usize, usize, u32, u32, u64)> = Vec::new();
    // col_to_buf[col] = buffer char offset for that grid column
    let mut col_to_buf: Vec<usize> = Vec::with_capacity(cells.len());
    let mut buf_offset = 0usize;
    let mut current_start_buf = 0usize;
    let mut current_fg = 0u32;
    let mut current_bg = 0u32;
    let mut current_flags = 0u64;

    for cell in cells.iter() {
        let is_wide_placeholder = cell.width == CellWidth::Wide && cell.grapheme.as_str() == " ";

        if is_wide_placeholder {
            // Wide placeholder: same buf_offset as the preceding wide char cell.
            col_to_buf.push(buf_offset.saturating_sub(1));
            // Do NOT advance buf_offset or write to text.
            continue;
        }

        // Record col → buf mapping for this cell
        col_to_buf.push(buf_offset);

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

        buf_offset += 1;
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
mod tests {
    use super::*;
    use crate::types::cell::{Cell, SgrAttributes};
    use crate::types::color::{Color, NamedColor};

    // -------------------------------------------------------------------------
    // encode_color tests
    // -------------------------------------------------------------------------

    #[test]
    fn test_encode_color_default_is_sentinel() {
        assert_eq!(encode_color(&Color::Default), 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_rgb_true_black_is_zero() {
        assert_eq!(encode_color(&Color::Rgb(0, 0, 0)), 0u32);
    }

    #[test]
    fn test_encode_color_named_red() {
        let expected = 0x80000000u32 | 1u32;
        assert_eq!(encode_color(&Color::Named(NamedColor::Red)), expected);
    }

    #[test]
    fn test_encode_color_indexed() {
        let expected = 0x40000000u32 | 16u32;
        assert_eq!(encode_color(&Color::Indexed(16)), expected);
    }

    #[test]
    fn test_named_colors_are_unique() {
        use std::collections::HashSet;
        let colors = [
            NamedColor::Black,
            NamedColor::Red,
            NamedColor::Green,
            NamedColor::Yellow,
            NamedColor::Blue,
            NamedColor::Magenta,
            NamedColor::Cyan,
            NamedColor::White,
            NamedColor::BrightBlack,
            NamedColor::BrightRed,
            NamedColor::BrightGreen,
            NamedColor::BrightYellow,
            NamedColor::BrightBlue,
            NamedColor::BrightMagenta,
            NamedColor::BrightCyan,
            NamedColor::BrightWhite,
        ];
        let encoded: HashSet<u32> = colors
            .iter()
            .map(|c| encode_color(&Color::Named(*c)))
            .collect();
        assert_eq!(
            encoded.len(),
            16,
            "all 16 named colors must have unique encodings"
        );
    }

    // -------------------------------------------------------------------------
    // encode_attrs tests
    // -------------------------------------------------------------------------

    #[test]
    fn test_encode_attrs_default_is_zero() {
        assert_eq!(encode_attrs(&SgrAttributes::default()), 0u64);
    }

    #[test]
    fn test_encode_attrs_bold() {
        let mut a = SgrAttributes::default();
        a.bold = true;
        assert_eq!(encode_attrs(&a), 0x1u64);
    }

    #[test]
    fn test_encode_attrs_all_flags_set() {
        let attrs = SgrAttributes {
            foreground: Color::Default,
            background: Color::Default,
            bold: true,
            dim: true,
            italic: true,
            underline_style: UnderlineStyle::Straight,
            underline_color: Color::Default,
            blink_slow: true,
            blink_fast: true,
            inverse: true,
            hidden: true,
            strikethrough: true,
        };
        let result = encode_attrs(&attrs);
        // All 9 flag bits plus underline-style=1 in bits 9-11 must be set
        assert_eq!(result & 0x1FF, 0x1FFu64, "all 9 flag bits must be set");
        assert_ne!(result, 0);
    }

    // -------------------------------------------------------------------------
    // encode_line tests
    // -------------------------------------------------------------------------

    #[test]
    fn test_encode_line_empty() {
        let (text, ranges, col_to_buf) = encode_line(&[]);
        assert_eq!(text, "");
        assert!(ranges.is_empty());
        assert!(col_to_buf.is_empty());
    }

    #[test]
    fn test_encode_line_single_cell() {
        let cell = Cell::new('A');
        let (text, ranges, col_to_buf) = encode_line(&[cell]);
        assert_eq!(text, "A");
        assert_eq!(ranges.len(), 1);
        let (start, end, _, _, _) = ranges[0];
        assert_eq!(start, 0);
        assert_eq!(end, 1);
        assert_eq!(col_to_buf, vec![0]);
    }

    // REGRESSION TEST — do NOT revert to trimming without updating kuro--update-cursor.
    // Trailing spaces MUST be preserved so that the Emacs cursor can be placed at
    // any column including those that fall inside whitespace.  If spaces were trimmed,
    // `line-end-position` in kuro--update-cursor would be smaller than the terminal
    // cursor column, causing `(min (+ line-start col) line-end)` to clamp the visual
    // cursor to the wrong buffer position (reproduces: SPC doesn't move cursor).
    #[test]
    fn test_encode_line_trailing_spaces_preserved() {
        let cells: Vec<Cell> = vec![Cell::new('A'), Cell::new(' '), Cell::new(' ')];
        let (text, _, _) = encode_line(&cells);
        assert_eq!(
            text, "A  ",
            "trailing spaces must be preserved so cursor can land on them"
        );
    }

    #[test]
    fn test_encode_line_all_spaces_preserved() {
        // A completely blank line (all spaces) must not become an empty string.
        // The Emacs cursor may be placed on any column of such a line.
        let cells: Vec<Cell> = vec![Cell::new(' '); 5];
        let (text, _, _) = encode_line(&cells);
        assert_eq!(
            text, "     ",
            "an all-space line must not be collapsed to empty string"
        );
    }

    #[test]
    fn test_encode_line_coverage_invariant() {
        // Build 3 cells with distinct attributes so each gets its own range
        let mut a1 = SgrAttributes::default();
        a1.bold = true;
        let mut a2 = SgrAttributes::default();
        a2.italic = true;
        let mut a3 = SgrAttributes::default();
        a3.dim = true;

        let cells = vec![
            Cell::with_attrs('A', a1),
            Cell::with_attrs('B', a2),
            Cell::with_attrs('C', a3),
        ];
        let (_, ranges, _) = encode_line(&cells);

        // First range must start at 0
        assert_eq!(ranges[0].0, 0);
        // Last range must end at buf_offset count (= cells.len() for ASCII-only)
        assert_eq!(ranges.last().unwrap().1, 3);
        // Consecutive ranges must be contiguous
        for w in ranges.windows(2) {
            assert_eq!(w[0].1, w[1].0, "ranges must be contiguous");
        }
        // Each range must be non-empty
        for (s, e, _, _, _) in &ranges {
            assert!(s < e, "empty range found: start={s}, end={e}");
        }
    }

    // REGRESSION TEST — CJK wide chars must NOT have a space inserted after them
    // in the Emacs buffer.  The wide placeholder cell (CellWidth::Wide with space
    // grapheme) must be skipped so that `テスト` appears as 3 chars (not `テ ス ト`).
    #[test]
    fn test_encode_line_wide_chars_no_placeholder_space() {
        use crate::types::cell::CellWidth;
        use compact_str::CompactString;

        // Simulate what screen.rs does for CJK: テ at col0 + placeholder at col1
        let mut wide_cell = Cell::new('テ');
        wide_cell.width = CellWidth::Half; // main cell is Half (it's the glyph cell)
                                           // Actually the main cell width is set by unicode_width, not CellWidth::Wide.
                                           // The placeholder is the second cell with CellWidth::Wide and grapheme=" ".
        let mut placeholder = Cell::default();
        placeholder.width = CellWidth::Wide;
        placeholder.grapheme = CompactString::new(" ");

        let cells = vec![wide_cell, placeholder];
        let (text, _, col_to_buf) = encode_line(&cells);

        // text must be just "テ", no extra space
        assert_eq!(
            text, "テ",
            "wide placeholder must not appear in buffer text"
        );
        // col 0 → buf offset 0, col 1 (placeholder) → buf offset 0 (same)
        assert_eq!(col_to_buf[0], 0, "col 0 maps to buf offset 0");
        assert_eq!(
            col_to_buf[1], 0,
            "placeholder col maps to same buf offset as wide char"
        );
    }

    #[test]
    fn test_encode_line_col_to_buf_ascii() {
        // For pure ASCII, col_to_buf[i] == i
        let cells: Vec<Cell> = "Hello".chars().map(Cell::new).collect();
        let (_, _, col_to_buf) = encode_line(&cells);
        for (i, &offset) in col_to_buf.iter().enumerate() {
            assert_eq!(offset, i, "ASCII: col {i} must map to buf offset {i}");
        }
    }
}
