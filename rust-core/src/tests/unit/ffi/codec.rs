//! Property-based tests for `crate::ffi::codec` (`encode_color`, `encode_attrs`, `encode_line`)
//!
//! Tests in this file complement the 19 example-based tests in
//! `src/ffi/tests/codec.rs` and add property-based coverage for encoding
//! invariants, bit-mapping correctness, and structural guarantees of the
//! FFI wire format.

use crate::ffi::codec::{
    compute_row_hash, encode_attrs, encode_color, encode_line, encode_screen_binary,
};
use crate::grid::line::Line;
use crate::types::cell::{Cell, SgrAttributes, SgrFlags, UnderlineStyle};
use crate::types::color::{Color, NamedColor};
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
        for (s, e, _, _, _, _) in &face_ranges {
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

// -------------------------------------------------------------------------
// encode_screen_binary example-based tests
// -------------------------------------------------------------------------

/// Helper: read a u32 LE from a byte slice at the given byte offset.
fn read_u32(buf: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(buf[offset..offset + 4].try_into().unwrap())
}

/// Helper: read a u64 LE from a byte slice at the given byte offset.
fn read_u64(buf: &[u8], offset: usize) -> u64 {
    u64::from_le_bytes(buf[offset..offset + 8].try_into().unwrap())
}

#[test]
// INVARIANT: Empty input → exactly 8 bytes: format_version=2 LE then num_rows=0 LE.
fn test_encode_screen_binary_empty() {
    let out = encode_screen_binary(&[]);
    assert_eq!(
        out,
        [
            2u8, 0, 0, 0, // format_version = 2 LE
            0u8, 0, 0, 0
        ], // num_rows = 0 LE
        "empty input must produce 8-byte header (version=2, num_rows=0)"
    );
}

#[test]
// LAYOUT: Single row "A", no face ranges, col_to_buf=[0].
// Expected layout:
//   [0..4]   format_version = 2
//   [4..8]   num_rows = 1
//   [8..12]  row_index = 0
//   [12..16] num_face_ranges = 0
//   [16..20] text_byte_len = 1
//   [20]     b'A'
//   [21..25] col_to_buf_len = 1
//   [25..29] col_to_buf[0] = 0
fn test_encode_screen_binary_one_row_no_faces() {
    let lines: &[ScreenLine] = &[(0, "A".to_string(), vec![], vec![0])];
    let out = encode_screen_binary(lines);

    assert_eq!(
        out.len(),
        4 + 4 + 4 + 4 + 4 + 1 + 4 + 4,
        "total byte count mismatch"
    );
    assert_eq!(read_u32(&out, 0), 2, "format_version must be 2");
    assert_eq!(read_u32(&out, 4), 1, "num_rows must be 1");
    assert_eq!(read_u32(&out, 8), 0, "row_index must be 0");
    assert_eq!(read_u32(&out, 12), 0, "num_face_ranges must be 0");
    assert_eq!(read_u32(&out, 16), 1, "text_byte_len must be 1");
    assert_eq!(out[20], b'A', "text byte must be b'A'");
    assert_eq!(read_u32(&out, 21), 1, "col_to_buf_len must be 1");
    assert_eq!(read_u32(&out, 25), 0, "col_to_buf[0] must be 0");
}

#[test]
// LAYOUT: row_index and text byte length are correctly encoded as u32 LE.
fn test_encode_screen_binary_row_index_and_text_len() {
    // Use row_index=42 and text "Hello" (5 bytes).
    let lines: &[ScreenLine] = &[(42, "Hello".to_string(), vec![], vec![])];
    let out = encode_screen_binary(lines);

    assert_eq!(read_u32(&out, 0), 2, "format_version must be 2");
    assert_eq!(read_u32(&out, 4), 1, "num_rows must be 1");
    assert_eq!(read_u32(&out, 8), 42, "row_index must be 42");
    assert_eq!(read_u32(&out, 12), 0, "num_face_ranges must be 0");
    assert_eq!(read_u32(&out, 16), 5, "text_byte_len must be 5 for 'Hello'");
    assert_eq!(&out[20..25], b"Hello", "text bytes must match 'Hello'");
    // col_to_buf_len = 0 (empty vec)
    assert_eq!(read_u32(&out, 25), 0, "col_to_buf_len must be 0");
}

#[test]
// LAYOUT: 1 face range → 28 bytes of face range data; verify all 6 fields.
fn test_encode_screen_binary_one_face_range() {
    // row_index=0, text="AB" (2 bytes), 1 face range: (0,2, fg=1, bg=2, flags=3, ul_color=4)
    let lines: &[ScreenLine] = &[(0, "AB".to_string(), vec![(0, 2, 1, 2, 3, 4)], vec![])];
    let out = encode_screen_binary(lines);

    // Offsets: 0=format_version, 4=num_rows, 8=row_index, 12=num_face_ranges, 16=text_byte_len,
    //          20+2=22 = face range start, then 4+4+4+4+8+4 = 28 bytes
    assert_eq!(read_u32(&out, 12), 1, "num_face_ranges must be 1");
    let fr_base = 8 + 4 + 4 + 4 + 2; // header(8) + row_index(4) + num_face_ranges(4) + text_byte_len(4) + 2 text bytes
    assert_eq!(read_u32(&out, fr_base), 0, "face range start_buf must be 0");
    assert_eq!(
        read_u32(&out, fr_base + 4),
        2,
        "face range end_buf must be 2"
    );
    assert_eq!(read_u32(&out, fr_base + 8), 1, "face range fg must be 1");
    assert_eq!(read_u32(&out, fr_base + 12), 2, "face range bg must be 2");
    assert_eq!(
        read_u64(&out, fr_base + 16),
        3,
        "face range flags must be 3"
    );
    assert_eq!(
        read_u32(&out, fr_base + 24),
        4,
        "face range ul_color must be 4"
    );
}

#[test]
// LAYOUT: col_to_buf length header and entries are correctly encoded.
fn test_encode_screen_binary_col_to_buf_entries() {
    // row_index=0, text="X" (1 byte), no faces, col_to_buf=[0, 0, 1] (3 entries)
    let lines: &[ScreenLine] = &[(0, "X".to_string(), vec![], vec![0, 0, 1])];
    let out = encode_screen_binary(lines);

    // col_to_buf section starts at: header(8) + row_index(4) + num_fr(4) + text_len(4) + 1 text = 21
    let ctb_base = 8 + 4 + 4 + 4 + 1;
    assert_eq!(read_u32(&out, ctb_base), 3, "col_to_buf_len must be 3");
    assert_eq!(read_u32(&out, ctb_base + 4), 0, "col_to_buf[0] must be 0");
    assert_eq!(read_u32(&out, ctb_base + 8), 0, "col_to_buf[1] must be 0");
    assert_eq!(read_u32(&out, ctb_base + 12), 1, "col_to_buf[2] must be 1");
    assert_eq!(out.len(), ctb_base + 4 + 3 * 4, "total byte count mismatch");
}

#[test]
// LAYOUT: 2 rows → num_rows header = 2, and both rows appear sequentially.
fn test_encode_screen_binary_two_rows() {
    let lines: &[ScreenLine] = &[
        (0, "A".to_string(), vec![], vec![]),
        (1, "B".to_string(), vec![], vec![]),
    ];
    let out = encode_screen_binary(lines);

    assert_eq!(read_u32(&out, 0), 2, "format_version must be 2");
    assert_eq!(read_u32(&out, 4), 2, "num_rows must be 2");

    // Row 0 starts at byte 8: header(8) + row_index(4) + num_fr(4) + text_len(4) + 1 text + ctb_len(4) = 25 bytes for row 0
    assert_eq!(read_u32(&out, 8), 0, "row 0 row_index must be 0");
    assert_eq!(read_u32(&out, 12), 0, "row 0 num_face_ranges must be 0");
    assert_eq!(read_u32(&out, 16), 1, "row 0 text_byte_len must be 1");
    assert_eq!(out[20], b'A', "row 0 text must be b'A'");
    assert_eq!(read_u32(&out, 21), 0, "row 0 col_to_buf_len must be 0");

    // Row 1 starts at byte 8+17=25 (17 = row_index(4)+num_fr(4)+text_len(4)+text(1)+ctb_len(4))
    assert_eq!(read_u32(&out, 25), 1, "row 1 row_index must be 1");
    assert_eq!(read_u32(&out, 29), 0, "row 1 num_face_ranges must be 0");
    assert_eq!(read_u32(&out, 33), 1, "row 1 text_byte_len must be 1");
    assert_eq!(out[37], b'B', "row 1 text must be b'B'");
    assert_eq!(read_u32(&out, 38), 0, "row 1 col_to_buf_len must be 0");
}

#[test]
// LAYOUT: Unicode text "→" (3 UTF-8 bytes) → text_byte_len field must be 3.
fn test_encode_screen_binary_unicode_text() {
    let arrow = "→"; // U+2192, encodes to [0xE2, 0x86, 0x92] in UTF-8
    assert_eq!(arrow.len(), 3, "sanity: '→' must be 3 bytes");
    let lines: &[ScreenLine] = &[(0, arrow.to_string(), vec![], vec![])];
    let out = encode_screen_binary(lines);

    // header(8) + row_index(4) + num_face_ranges(4) = 16; text_byte_len at 16
    assert_eq!(read_u32(&out, 16), 3, "text_byte_len must be 3 for '→'");
    assert_eq!(&out[20..23], arrow.as_bytes(), "text bytes must match '→'");
}

// -------------------------------------------------------------------------
// compute_row_hash example-based tests
// -------------------------------------------------------------------------

#[test]
// DETERMINISM: Same row + same col_to_buf → identical hash on two calls.
fn test_compute_row_hash_deterministic() {
    let mut line = Line::new(4);
    line.update_cell(0, 'A', SgrAttributes::default());
    line.update_cell(1, 'B', SgrAttributes::default());
    let col_to_buf = vec![0usize, 1, 2, 3];

    let h1 = compute_row_hash(&line, &col_to_buf);
    let h2 = compute_row_hash(&line, &col_to_buf);
    assert_eq!(h1, h2, "hash must be deterministic across two calls");
}

#[test]
// SENSITIVITY: Two rows differing only in one character must hash differently.
fn test_compute_row_hash_differs_by_char() {
    let mut line_a = Line::new(4);
    line_a.update_cell(0, 'A', SgrAttributes::default());
    let mut line_b = Line::new(4);
    line_b.update_cell(0, 'Z', SgrAttributes::default());
    let col_to_buf: Vec<usize> = vec![];

    let h_a = compute_row_hash(&line_a, &col_to_buf);
    let h_b = compute_row_hash(&line_b, &col_to_buf);
    assert_ne!(
        h_a, h_b,
        "rows differing in character must produce different hashes"
    );
}

#[test]
// SENSITIVITY: Same row content but different col_to_buf → different hashes.
fn test_compute_row_hash_differs_by_col_to_buf() {
    let mut line = Line::new(4);
    line.update_cell(0, 'X', SgrAttributes::default());
    let col_to_buf_a = vec![0usize, 1, 2, 3];
    let col_to_buf_b = vec![0usize, 1, 2, 99]; // last entry differs

    let h_a = compute_row_hash(&line, &col_to_buf_a);
    let h_b = compute_row_hash(&line, &col_to_buf_b);
    assert_ne!(
        h_a, h_b,
        "different col_to_buf must produce different hashes"
    );
}

#[test]
// SAFETY: Empty row (all blank cells) + empty col_to_buf → does not panic,
// and returns the same value on repeated calls.
fn test_compute_row_hash_empty_row() {
    let line = Line::new(0); // zero-column line
    let h1 = compute_row_hash(&line, &[]);
    let h2 = compute_row_hash(&line, &[]);
    assert_eq!(h1, h2, "hash of empty row must be consistent");
}

#[test]
// SENSITIVITY: Same character but different foreground color → different hashes.
fn test_compute_row_hash_differs_by_fg_color() {
    let attrs_red = SgrAttributes {
        foreground: Color::Rgb(255, 0, 0),
        ..Default::default()
    };
    let attrs_blue = SgrAttributes {
        foreground: Color::Rgb(0, 0, 255),
        ..Default::default()
    };

    let mut line_red = Line::new(1);
    line_red.update_cell(0, 'A', attrs_red);
    let mut line_blue = Line::new(1);
    line_blue.update_cell(0, 'A', attrs_blue);

    let h_red = compute_row_hash(&line_red, &[]);
    let h_blue = compute_row_hash(&line_blue, &[]);
    assert_ne!(
        h_red, h_blue,
        "different fg color must produce different hashes"
    );
}

#[test]
// SENSITIVITY: Same char, different SGR flags (bold vs default) → different hashes.
fn test_compute_row_hash_differs_by_attrs() {
    let attrs_plain = SgrAttributes::default();
    let attrs_bold = SgrAttributes {
        flags: SgrFlags::BOLD,
        ..Default::default()
    };

    let mut line_plain = Line::new(1);
    line_plain.update_cell(0, 'A', attrs_plain);
    let mut line_bold = Line::new(1);
    line_bold.update_cell(0, 'A', attrs_bold);

    let h_plain = compute_row_hash(&line_plain, &[]);
    let h_bold = compute_row_hash(&line_bold, &[]);
    assert_ne!(
        h_plain, h_bold,
        "bold vs plain must produce different hashes"
    );
}
