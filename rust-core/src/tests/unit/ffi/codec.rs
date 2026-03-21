//! Property-based tests for `crate::ffi::codec` (`encode_color`, `encode_attrs`, `encode_line`)
//!
//! Tests in this file complement the 19 example-based tests in
//! `src/ffi/tests/codec.rs` and add property-based coverage for encoding
//! invariants, bit-mapping correctness, and structural guarantees of the
//! FFI wire format.

use crate::ffi::codec::{encode_attrs, encode_color, encode_line};
use crate::types::cell::{Cell, SgrAttributes, SgrFlags, UnderlineStyle};
use crate::types::color::{Color, NamedColor};
use proptest::prelude::*;

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
    // This covers bold(0), dim(1), italic(2), blink_slow(4), blink_fast(5),
    // inverse(6), hidden(7), strikethrough(8) in a single parametric test.
    fn prop_encode_attrs_single_bool_correct_bit(
        // Pick one of 8 boolean fields: 0=bold,1=dim,2=italic,3=blink_slow,
        // 4=blink_fast,5=inverse,6=hidden,7=strikethrough
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
        for (s, e, _, _, _) in &face_ranges {
            prop_assert!(s < e, "face range [{},{}] must be non-empty", s, e);
        }
    }

    #[test]
    // VARIANTS: For any two distinct Color variants, encode_color must produce
    // distinct values (no collisions across the tag space).
    // We test Rgb vs Indexed and Rgb vs Named specifically here.
    fn prop_encode_color_rgb_vs_indexed_no_collision(
        r in 0u8..=255u8,
        g in 0u8..=255u8,
        b in 0u8..=255u8,
        idx in 0u8..=255u8,
    ) {
        let rgb_enc = encode_color(&Color::Rgb(r, g, b));
        let idx_enc = encode_color(&Color::Indexed(idx));
        // Indexed encoding always has bit 30 set; pure RGB never does.
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

#[test]
// INVARIANT: All 16 Named color encodings have bit 31 set.
fn test_encode_color_named_marker() {
    let all_named = [
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
    for named in &all_named {
        let encoded = encode_color(&Color::Named(*named));
        assert_ne!(
            encoded & 0x8000_0000,
            0,
            "bit 31 must be set for Named({named:?}): got {encoded:#010x}"
        );
    }
}

#[test]
// DISTINCTNESS: Color::Default sentinel (0xFF00_0000) must not be producible
// by Named, Indexed, or Rgb color paths.
fn test_encode_color_default_sentinel_unique() {
    const SENTINEL: u32 = 0xFF00_0000;
    assert_eq!(encode_color(&Color::Default), SENTINEL);

    // Named: bit 31 set, bits 0-3 index (0-15) — range 0x8000_0000..=0x8000000F
    for i in 0u32..=15u32 {
        assert_ne!(
            0x8000_0000u32 | i,
            SENTINEL,
            "Named({i}) must not equal sentinel"
        );
    }

    // Indexed: bit 30 set, bits 0-7 index (0-255) — range 0x4000_0000..=0x400000FF
    for i in 0u32..=255u32 {
        assert_ne!(
            0x4000_0000u32 | i,
            SENTINEL,
            "Indexed({i}) must not equal sentinel"
        );
    }

    // Rgb: lower 24 bits only; 0xFF00_0000 has no lower-24 bits, so it cannot
    // arise from any (r,g,b) encoding (which only uses bits 0-23).
    // Verify the boundary: max RGB encoding is 0x00FF_FFFF (all 255).
    assert_eq!(encode_color(&Color::Rgb(255, 255, 255)), 0x00FF_FFFF);
    assert_ne!(encode_color(&Color::Rgb(255, 0, 0)), SENTINEL);
}

#[test]
// MAPPING: encode_attrs bits 9-11 must encode UnderlineStyle as 0–5.
fn test_encode_attrs_underline_style_bits() {
    let cases: &[(UnderlineStyle, u64)] = &[
        (UnderlineStyle::None, 0),
        (UnderlineStyle::Straight, 1),
        (UnderlineStyle::Double, 2),
        (UnderlineStyle::Curly, 3),
        (UnderlineStyle::Dotted, 4),
        (UnderlineStyle::Dashed, 5),
    ];
    for (style, expected_style_val) in cases {
        let attrs = SgrAttributes {
            underline_style: *style,
            ..Default::default()
        };
        let encoded = encode_attrs(&attrs);
        let bits_9_11 = (encoded >> 9) & 0x7;
        assert_eq!(
            bits_9_11, *expected_style_val,
            "bits 9-11 for {style:?} must be {expected_style_val}, got {bits_9_11}"
        );
    }
}

#[test]
// INVARIANT: text.chars().count() == cells.len() for ASCII-only cells.
fn test_encode_line_text_length_matches_cells() {
    let ascii: &str = "The quick brown fox";
    let cells: Vec<Cell> = ascii.chars().map(Cell::new).collect();
    let (text, _, _) = encode_line(&cells);
    assert_eq!(
        text.chars().count(),
        cells.len(),
        "ASCII cell count must equal text char count"
    );
}

#[test]
// INVARIANT: face_ranges cover the full buffer range [0, text_len).
// First range starts at 0; last range ends at text.chars().count().
fn test_encode_line_face_ranges_cover_full() {
    // Use three cells with distinct attrs to force three separate ranges.
    let cells = vec![
        Cell::with_attrs(
            'A',
            SgrAttributes {
                flags: SgrFlags::BOLD,
                ..Default::default()
            },
        ),
        Cell::with_attrs(
            'B',
            SgrAttributes {
                flags: SgrFlags::ITALIC,
                ..Default::default()
            },
        ),
        Cell::with_attrs(
            'C',
            SgrAttributes {
                flags: SgrFlags::DIM,
                ..Default::default()
            },
        ),
    ];
    let (text, ranges, _) = encode_line(&cells);
    assert_eq!(ranges[0].0, 0, "first range must start at 0");
    assert_eq!(
        ranges.last().unwrap().1,
        text.chars().count(),
        "last range must end at text length"
    );
}

#[test]
// INVARIANT: Contiguous face_ranges — ranges[i].end == ranges[i+1].start.
fn test_encode_line_face_ranges_contiguous() {
    // Each cell gets a distinct SGR attribute to ensure individual ranges.
    let cells = vec![
        Cell::with_attrs(
            'X',
            SgrAttributes {
                flags: SgrFlags::BOLD,
                ..Default::default()
            },
        ),
        Cell::with_attrs(
            'Y',
            SgrAttributes {
                flags: SgrFlags::ITALIC,
                ..Default::default()
            },
        ),
        Cell::with_attrs(
            'Z',
            SgrAttributes {
                flags: SgrFlags::STRIKETHROUGH,
                ..Default::default()
            },
        ),
        Cell::with_attrs(
            'W',
            SgrAttributes {
                flags: SgrFlags::INVERSE,
                ..Default::default()
            },
        ),
    ];
    let (_, ranges, _) = encode_line(&cells);
    for w in ranges.windows(2) {
        assert_eq!(
            w[0].1, w[1].0,
            "face ranges must be contiguous: [{},{}] then [{},{}]",
            w[0].0, w[0].1, w[1].0, w[1].1
        );
    }
}
