#[test]
// INVARIANT: All 16 Named color encodings have bit 31 set.
fn test_pbt_encode_color_named_marker() {
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
fn test_pbt_encode_color_default_sentinel_unique() {
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

    assert_eq!(encode_color(&Color::Rgb(255, 255, 255)), 0x00FF_FFFF);
    assert_ne!(encode_color(&Color::Rgb(255, 0, 0)), SENTINEL);
}

#[test]
// MAPPING: encode_attrs bits 9-11 must encode UnderlineStyle as 0-5.
fn test_pbt_encode_attrs_underline_style_bits() {
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
fn test_pbt_encode_line_text_length_matches_cells() {
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
fn test_pbt_encode_line_face_ranges_cover_full() {
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
fn test_pbt_encode_line_face_ranges_contiguous() {
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
// encode_screen_binary example-based tests (from codec_binary_encoding.rs)
// -------------------------------------------------------------------------

/// Helper: read a u32 LE from a byte slice at the given byte offset.
fn pbt_read_u32(buf: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(buf[offset..offset + 4].try_into().unwrap())
}

/// Helper: read a u64 LE from a byte slice at the given byte offset.
fn pbt_read_u64(buf: &[u8], offset: usize) -> u64 {
    u64::from_le_bytes(buf[offset..offset + 8].try_into().unwrap())
}

#[test]
// INVARIANT: Empty input -> exactly 8 bytes: format_version=2 LE then num_rows=0 LE.
fn test_pbt_encode_screen_binary_empty() {
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
fn test_pbt_encode_screen_binary_one_row_no_faces() {
    let lines: &[ScreenLine] = &[(0, "A".to_string(), vec![], vec![0])];
    let out = encode_screen_binary(lines);

    assert_eq!(
        out.len(),
        4 + 4 + 4 + 4 + 4 + 1 + 4 + 4,
        "total byte count mismatch"
    );
    assert_eq!(pbt_read_u32(&out, 0), 2, "format_version must be 2");
    assert_eq!(pbt_read_u32(&out, 4), 1, "num_rows must be 1");
    assert_eq!(pbt_read_u32(&out, 8), 0, "row_index must be 0");
    assert_eq!(pbt_read_u32(&out, 12), 0, "num_face_ranges must be 0");
    assert_eq!(pbt_read_u32(&out, 16), 1, "text_byte_len must be 1");
    assert_eq!(out[20], b'A', "text byte must be b'A'");
    assert_eq!(pbt_read_u32(&out, 21), 1, "col_to_buf_len must be 1");
    assert_eq!(pbt_read_u32(&out, 25), 0, "col_to_buf[0] must be 0");
}


include!("codec_pbt2.rs");
