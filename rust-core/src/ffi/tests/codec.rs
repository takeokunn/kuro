use std::sync::Arc;

use super::*;
use crate::grid::line::Line;
use crate::types::cell::{Cell, CellWidth, SgrAttributes, SgrFlags, UnderlineStyle};
use crate::types::color::{Color, NamedColor};
use compact_str::CompactString;

// -------------------------------------------------------------------------
// Test helpers
// -------------------------------------------------------------------------

#[inline]
fn read_u32_le(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap())
}

#[inline]
fn read_u64_le(bytes: &[u8], offset: usize) -> u64 {
    u64::from_le_bytes(bytes[offset..offset + 8].try_into().unwrap())
}

#[inline]
fn face_range(
    start_buf: usize,
    end_buf: usize,
    fg: u32,
    bg: u32,
    flags: u64,
    underline_color: u32,
) -> EncodedFaceRange {
    EncodedFaceRange {
        start_buf,
        end_buf,
        fg,
        bg,
        flags,
        underline_color,
    }
}

#[inline]
fn encoded_line(
    row: usize,
    text: impl Into<String>,
    face_ranges: Vec<EncodedFaceRange>,
    col_to_buf: Vec<usize>,
) -> EncodedLine {
    EncodedLine {
        row_index: row,
        text: text.into(),
        face_ranges,
        col_to_buf,
    }
}

#[inline]
fn encode_screen_binary_ok(lines: &[EncodedLine]) -> Vec<u8> {
    encode_screen_binary(lines).expect("binary frame encoding should fit u32 fields")
}

#[inline]
fn test_usize_to_u32(value: usize, context: &str) -> u32 {
    u32::try_from(value).expect(context)
}

/// Return the byte length of one encoded row payload.
#[inline]
fn binary_row_len(text_len: usize, num_face_ranges: usize, col_to_buf_len: usize) -> usize {
    4 + 4 + 4 + text_len + (28 * num_face_ranges) + 4 + (4 * col_to_buf_len)
}

/// Build a `Line` of `chars.len()` columns with default SGR attributes.
#[inline]
fn make_line(chars: &[char]) -> Line {
    let mut line = Line::new(chars.len());
    for (col, &c) in chars.iter().enumerate() {
        line.update_cell(col, c, SgrAttributes::default());
    }
    line
}

/// Construct `SgrAttributes` with a single flags field; all other fields default.
macro_rules! attrs_flags {
    ($flag:expr) => {
        SgrAttributes {
            flags: $flag,
            ..Default::default()
        }
    };
}

/// Construct `SgrAttributes` with a custom underline style; flags default to empty.
macro_rules! attrs_underline {
    ($style:expr) => {
        SgrAttributes {
            underline_style: $style,
            ..Default::default()
        }
    };
}

/// Assert the face range at `$idx` inside an `EncodedLine`'s `face_ranges` vec.
///
/// Usage: `assert_face_range!(ranges, 0: buf 0, 5, fg 0xFF000000, bg 0x00000000, flags 0x01)`
macro_rules! assert_face_range {
    ($ranges:expr, $idx:literal: buf $s:expr, $e:expr, fg $fg:expr, bg $bg:expr, flags $f:expr) => {{
        let range = &$ranges[$idx];
        let start = range.start_buf;
        let end = range.end_buf;
        let fg = range.fg;
        let bg = range.bg;
        let flags = range.flags;
        assert_eq!(start, $s, "face_range[{}] start_buf", $idx);
        assert_eq!(end, $e, "face_range[{}] end_buf", $idx);
        assert_eq!(fg, $fg, "face_range[{}] fg", $idx);
        assert_eq!(bg, $bg, "face_range[{}] bg", $idx);
        assert_eq!(flags, $f, "face_range[{}] flags", $idx);
    }};
}

/// Assert a face range in a binary frame at a given byte offset.
///
/// Usage: `assert_binary_face!(result, BASE, buf 0, 5, fg 0xFF000000, bg 0x00, flags 0x01)`
macro_rules! assert_binary_face {
    ($buf:expr, $base:expr, buf $s:expr, $e:expr, fg $fg:expr, bg $bg:expr, flags $f:expr, ul $ul:expr) => {{
        assert_eq!(
            read_u32_le($buf, $base),
            test_usize_to_u32($s, "binary face start_buf test value fits u32"),
            "binary face start_buf"
        );
        assert_eq!(
            read_u32_le($buf, $base + 4),
            test_usize_to_u32($e, "binary face end_buf test value fits u32"),
            "binary face end_buf"
        );
        assert_eq!(read_u32_le($buf, $base + 8), $fg, "binary face fg");
        assert_eq!(read_u32_le($buf, $base + 12), $bg, "binary face bg");
        assert_eq!(read_u64_le($buf, $base + 16), $f, "binary face flags");
        assert_eq!(read_u32_le($buf, $base + 24), $ul, "binary face ul_color");
    }};
}

/// Assert the shared frame header fields in an `encode_screen_binary` result.
///
/// The version-3 header is 16 bytes: format_version, num_rows, scroll_up,
/// scroll_down.  The legacy `encode_screen_binary` path never carries a
/// scroll shift, so both scroll fields must be zero.
macro_rules! assert_binary_header {
    ($buf:expr, rows $rows:expr) => {{
        assert_eq!(read_u32_le($buf, 0), 3, "format_version must be 3");
        assert_eq!(
            read_u32_le($buf, 4),
            test_usize_to_u32($rows, "num_rows test value fits u32"),
            "num_rows must match"
        );
        assert_eq!(read_u32_le($buf, 8), 0, "scroll_up must be 0");
        assert_eq!(read_u32_le($buf, 12), 0, "scroll_down must be 0");
    }};
}

/// Assert one encoded screen row layout and return the next byte offset.
///
/// Usage: `let next = assert_binary_row!(out, 8, row 42, text "Hello", faces 0, ctb []);`
macro_rules! assert_binary_row {
    ($buf:expr, $base:expr, row $row:expr, text $text:expr, faces $faces:expr, ctb [$($ctb:expr),* $(,)?]) => {{
        let text = $text.as_bytes();
        let ctb = &[$(test_usize_to_u32($ctb, "col_to_buf test value fits u32")),*];
        let faces: usize = $faces;
        let ctb_base = $base + 12 + text.len() + (28 * faces);

        assert_eq!(
            read_u32_le($buf, $base),
            test_usize_to_u32($row, "row index test value fits u32"),
            "row_index"
        );
        assert_eq!(
            read_u32_le($buf, $base + 4),
            test_usize_to_u32(faces, "face count test value fits u32"),
            "num_face_ranges"
        );
        assert_eq!(
            read_u32_le($buf, $base + 8),
            test_usize_to_u32(text.len(), "text length test value fits u32"),
            "text_byte_len"
        );
        assert_eq!(
            &$buf[$base + 12..$base + 12 + text.len()],
            text,
            "text bytes"
        );
        assert_eq!(
            read_u32_le($buf, ctb_base),
            test_usize_to_u32(ctb.len(), "col_to_buf length test value fits u32"),
            "col_to_buf_len"
        );
        for (i, expected) in ctb.iter().copied().enumerate() {
            assert_eq!(
                read_u32_le($buf, ctb_base + 4 + (4 * i)),
                expected,
                "col_to_buf[{i}]"
            );
        }

        ctb_base + 4 + (4 * ctb.len())
    }};
}

/// Assert two `compute_row_hash` calls on the same inputs produce equal results.
macro_rules! assert_hash_stable {
    ($line:expr, $ctb:expr) => {{
        let h1 = compute_row_hash($line, $ctb);
        let h2 = compute_row_hash($line, $ctb);
        assert_eq!(h1, h2, "hash must be stable across calls");
        h1
    }};
}

/// Assert that `encode_color` on a given `Color` produces the expected `u32`.
///
/// Usage:
/// ```
/// test_encode_color!(test_name, Color::Default, 0xFF00_0000u32);
/// test_encode_color!(test_name, Color::Named(NamedColor::Black), 0x8000_0000u32);
/// ```
macro_rules! test_encode_color {
    ($name:ident, $color:expr, $expected:expr) => {
        #[test]
        fn $name() {
            assert_eq!(
                encode_color(&$color),
                $expected,
                concat!(stringify!($name), ": encode_color value mismatch")
            );
        }
    };
}

/// Assert that `encode_attrs` on a given `SgrAttributes` produces a result where
/// `(result >> $shift) & $mask == $expected_field`, along with an overall
/// non-zero check when `$nonzero` is true.
///
/// Usage:
/// ```
/// test_encode_attrs!(test_name, attrs_flags!(SgrFlags::BOLD), shift 0, mask 0x1, eq 0x1);
/// ```
macro_rules! test_encode_attrs {
    ($name:ident, $attrs:expr, shift $shift:expr, mask $mask:expr, eq $expected:expr) => {
        #[test]
        fn $name() {
            let bits = encode_attrs(&$attrs);
            assert_eq!(
                (bits >> $shift) & $mask,
                $expected,
                concat!(
                    stringify!($name),
                    ": encode_attrs field (>> ",
                    stringify!($shift),
                    ") & ",
                    stringify!($mask),
                    " mismatch"
                )
            );
        }
    };
}

#[path = "codec/attrs.rs"]
mod attrs;
#[path = "codec/binary.rs"]
mod binary;
#[path = "codec/binary_faces.rs"]
mod binary_faces;
#[path = "codec/color.rs"]
mod color;
#[path = "codec/hyperlink.rs"]
mod hyperlink;
#[path = "codec/line.rs"]
mod line;
#[path = "codec/properties.rs"]
mod properties;
#[path = "codec/property_edges.rs"]
mod property_edges;
#[path = "codec/text_size.rs"]
mod text_size;
