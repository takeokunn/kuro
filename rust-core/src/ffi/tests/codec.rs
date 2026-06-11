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

// --- Property-based tests (migrated from src/tests/unit/ffi/codec.rs) ---

use proptest::prelude::*;

/// Tuple type for a single binary-encoded screen row:
/// `(row_index, text, face_ranges, col_to_buf)`.
type ScreenLine = (
    usize,
    String,
    Vec<(usize, usize, u32, u32, u64, u32)>,
    Vec<usize>,
);

// -------------------------------------------------------------------------
// Arbitrary generators
// -------------------------------------------------------------------------

/// Generate a cell containing a printable ASCII character.
fn arb_ascii_cell() -> impl Strategy<Value = Cell> {
    prop::char::range('\u{0020}', '\u{007E}').prop_map(Cell::new)
}

// -------------------------------------------------------------------------
// encode_color property tests
// -------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(1000))]

    #[test]
    // ROUNDTRIP: encode_color(Rgb(r,g,b)) packs the three 8-bit components
    // into the lower 24 bits with no marker bits set in bits 30-31.
    fn prop_encode_color_rgb_lossless(r in 0u8..=255u8, g in 0u8..=255u8, b in 0u8..=255u8) {
        let encoded = encode_color(&Color::Rgb(r, g, b));
        let expected = u32::from(r) << 16 | u32::from(g) << 8 | u32::from(b);
        prop_assert_eq!(
            encoded,
            expected,
            "RGB({},{},{}) must encode to {:#010x}, got {:#010x}",
            r, g, b, expected, encoded
        );
        // Verify no marker bits bleed into the RGB encoding
        prop_assert_eq!(
            encoded & 0xC000_0000,
            0,
            "RGB encoding must have bits 30-31 clear (got {:#010x})",
            encoded
        );
    }

    #[test]
    // INVARIANT: encode_color(Indexed(idx)) must have bit 30 set (0x4000_0000
    // marker) and the lower 8 bits equal to idx.
    fn prop_encode_color_indexed_marker(idx in 0u8..=255u8) {
        let encoded = encode_color(&Color::Indexed(idx));
        let expected = 0x4000_0000u32 | u32::from(idx);
        prop_assert_eq!(
            encoded,
            expected,
            "Indexed({}) must encode to {:#010x}, got {:#010x}",
            idx, expected, encoded
        );
        // Marker bit 30 must be set
        prop_assert_ne!(encoded & 0x4000_0000, 0, "bit 30 must be set for Indexed (idx={})", idx);
        // Bit 31 must be clear (Named marker)
        prop_assert_eq!(encoded & 0x8000_0000, 0, "bit 31 must be clear for Indexed (idx={})", idx);
    }

    #[test]
    // INVARIANT: encode_attrs with only one boolean field set must produce
    // exactly the expected bit value with all other bits clear.
    fn prop_encode_attrs_single_bool_correct_bit(
        field_idx in 0usize..=7usize,
    ) {
        let expected_bit: u64 = match field_idx {
            0 => 0x001, // bold
            1 => 0x002, // dim
            2 => 0x004, // italic
            3 => 0x010, // blink_slow
            4 => 0x020, // blink_fast
            5 => 0x040, // inverse
            6 => 0x080, // hidden
            7 => 0x100, // strikethrough
            _ => unreachable!(),
        };
        let attrs = match field_idx {
            0 => SgrAttributes { flags: SgrFlags::BOLD,          ..Default::default() },
            1 => SgrAttributes { flags: SgrFlags::DIM,           ..Default::default() },
            2 => SgrAttributes { flags: SgrFlags::ITALIC,        ..Default::default() },
            3 => SgrAttributes { flags: SgrFlags::BLINK_SLOW,    ..Default::default() },
            4 => SgrAttributes { flags: SgrFlags::BLINK_FAST,    ..Default::default() },
            5 => SgrAttributes { flags: SgrFlags::INVERSE,       ..Default::default() },
            6 => SgrAttributes { flags: SgrFlags::HIDDEN,        ..Default::default() },
            7 => SgrAttributes { flags: SgrFlags::STRIKETHROUGH, ..Default::default() },
            _ => unreachable!(),
        };
        let encoded = encode_attrs(&attrs);
        prop_assert_eq!(
            encoded,
            expected_bit,
            "field_idx={}: expected {:#x}, got {:#x}",
            field_idx, expected_bit, encoded
        );
    }

    #[test]
    // INVARIANT: When underline_style != None, bit 3 of encode_attrs must be
    // set; when style == None, bit 3 must be clear.
    fn prop_encode_attrs_bit3_when_underline(
        style in prop_oneof![
            Just(UnderlineStyle::None),
            Just(UnderlineStyle::Straight),
            Just(UnderlineStyle::Double),
            Just(UnderlineStyle::Curly),
            Just(UnderlineStyle::Dotted),
            Just(UnderlineStyle::Dashed),
        ]
    ) {
        let attrs = SgrAttributes { underline_style: style, ..Default::default() };
        let encoded = encode_attrs(&attrs);
        let bit3_set = (encoded & 0x8) != 0;
        let should_be_set = style != UnderlineStyle::None;
        prop_assert_eq!(
            bit3_set,
            should_be_set,
            "bit3 (underline) must match underline_style != None for {:?}",
            style
        );
    }

    #[test]
    // INVARIANT: For ASCII-only cells (no Wide cells), col_to_buf must be
    // empty (identity fast path) and text.chars().count() == cells.len().
    fn prop_encode_line_ascii_invariants(
        cells in proptest::collection::vec(arb_ascii_cell(), 0..=80),
    ) {
        let n = cells.len();
        let (text, face_ranges, col_to_buf) = encode_line(&cells);

        // col_to_buf must be empty for pure ASCII (identity fast path)
        prop_assert!(
            col_to_buf.is_empty(),
            "pure ASCII must produce empty col_to_buf, got len={}",
            col_to_buf.len()
        );

        if n == 0 {
            prop_assert_eq!(text, "");
            prop_assert!(face_ranges.is_empty());
        } else {
            // text must contain exactly n chars (one per ASCII cell)
            let char_count = text.chars().count();
            prop_assert_eq!(
                char_count,
                n,
                "ASCII line of {} cells must produce {} chars in text",
                n, n
            );
            // face_ranges must cover [0, n) completely: first start == 0,
            // last end == n, and adjacent ranges are contiguous.
            prop_assert!(
                !face_ranges.is_empty(),
                "non-empty cell slice must produce at least one face range"
            );
            prop_assert_eq!(
                face_ranges[0].0,
                0,
                "first face range must start at buffer offset 0"
            );
            let last_end = face_ranges.last().unwrap().1;
            prop_assert_eq!(
                last_end,
                n,
                "last face range must end at buffer offset {}",
                n
            );
            for w in face_ranges.windows(2) {
                prop_assert_eq!(
                    w[0].1, w[1].0,
                    "face ranges must be contiguous: [{},{}] then [{},{}]",
                    w[0].0, w[0].1, w[1].0, w[1].1
                );
            }
        }
    }

    #[test]
    // INVARIANT: All face_ranges produced by encode_line are non-empty
    // (start < end) for any non-empty cell slice.
    fn prop_encode_line_face_ranges_non_empty(
        cells in proptest::collection::vec(arb_ascii_cell(), 1..=40),
    ) {
        let (_, face_ranges, _) = encode_line(&cells);
        for (s, e, _, _, _, _) in &face_ranges {
            prop_assert!(s < e, "face range [{},{}] must be non-empty", s, e);
        }
    }

    #[test]
    // VARIANTS: For any two distinct Color variants, encode_color must produce
    // distinct values (no collisions across the tag space).
    fn prop_encode_color_rgb_vs_indexed_no_collision(
        r in 0u8..=255u8,
        g in 0u8..=255u8,
        b in 0u8..=255u8,
        idx in 0u8..=255u8,
    ) {
        let rgb_enc = encode_color(&Color::Rgb(r, g, b));
        let idx_enc = encode_color(&Color::Indexed(idx));
        prop_assert_ne!(
            rgb_enc,
            idx_enc,
            "Rgb({},{},{}) and Indexed({}) must not collide",
            r, g, b, idx
        );
    }
}

// -------------------------------------------------------------------------
// Example-based tests (exhaustive enumeration over small variant sets)
// -------------------------------------------------------------------------

include!("codec_pbt.rs");
