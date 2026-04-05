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
        let (start, end, fg, bg, flags, _ul_color) = $ranges[$idx];
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
    ($buf:expr, $base:literal, buf $s:expr, $e:expr, fg $fg:expr, bg $bg:expr, flags $f:expr) => {{
        assert_eq!(read_u32_le($buf, $base), $s as u32, "binary face start_buf");
        assert_eq!(
            read_u32_le($buf, $base + 4),
            $e as u32,
            "binary face end_buf"
        );
        assert_eq!(read_u32_le($buf, $base + 8), $fg, "binary face fg");
        assert_eq!(read_u32_le($buf, $base + 12), $bg, "binary face bg");
        assert_eq!(read_u64_le($buf, $base + 16), $f, "binary face flags");
        // ul_color at offset +24 (version 2: 28 bytes per face range)
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

include!("codec_color.rs");
include!("codec_attrs.rs");
include!("codec_line.rs");
include!("codec_binary.rs");
include!("codec_hyperlink.rs");
