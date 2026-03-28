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

// -------------------------------------------------------------------------
// encode_color tests
// -------------------------------------------------------------------------

test_encode_color!(
    test_encode_color_default_is_sentinel,
    Color::Default,
    0xFF00_0000u32
);

test_encode_color!(
    test_encode_color_rgb_true_black_is_zero,
    Color::Rgb(0, 0, 0),
    0u32
);

test_encode_color!(
    test_encode_color_named_red,
    Color::Named(NamedColor::Red),
    0x8000_0000u32 | 1u32
);

test_encode_color!(
    test_encode_color_indexed,
    Color::Indexed(16),
    0x4000_0000u32 | 16u32
);

test_encode_color!(
    test_encode_color_indexed_zero,
    Color::Indexed(0),
    0x4000_0000u32
);

test_encode_color!(
    test_encode_color_indexed_255,
    Color::Indexed(255),
    0x4000_00FFu32
);

// -------------------------------------------------------------------------
// Named color boundary tests (Black=0, White=7, BrightBlack=8, BrightWhite=15)
// -------------------------------------------------------------------------

test_encode_color!(
    test_encode_color_named_black_boundary,
    Color::Named(NamedColor::Black),
    COLOR_NAMED_MARKER
);

test_encode_color!(
    test_encode_color_named_white_boundary,
    Color::Named(NamedColor::White),
    COLOR_NAMED_MARKER | 7u32
);

test_encode_color!(
    test_encode_color_named_bright_black_boundary,
    Color::Named(NamedColor::BrightBlack),
    COLOR_NAMED_MARKER | 8u32
);

// -------------------------------------------------------------------------
// RGB single-channel boundary tests
// -------------------------------------------------------------------------

test_encode_color!(
    test_encode_color_rgb_single_channel_red,
    Color::Rgb(255, 0, 0),
    0x00FF_0000u32
);

test_encode_color!(
    test_encode_color_rgb_single_channel_green,
    Color::Rgb(0, 255, 0),
    0x0000_FF00u32
);

test_encode_color!(
    test_encode_color_rgb_single_channel_blue,
    Color::Rgb(0, 0, 255),
    0x0000_00FFu32
);

// -------------------------------------------------------------------------
// encode_attrs: flag-bit tests via macro
// -------------------------------------------------------------------------

test_encode_attrs!(
    encode_attrs_bold_sets_bit_0,
    attrs_flags!(SgrFlags::BOLD),
    shift 0,
    mask 0x1,
    eq 1u64
);

test_encode_attrs!(
    encode_attrs_underline_curly_encodes_style_3,
    attrs_underline!(UnderlineStyle::Curly),
    shift 9,
    mask 0x7,
    eq 3u64
);

test_encode_attrs!(
    encode_attrs_underline_double_encodes_style_2,
    attrs_underline!(UnderlineStyle::Double),
    shift 9,
    mask 0x7,
    eq 2u64
);

test_encode_attrs!(
    encode_attrs_underline_dotted_encodes_style_4,
    attrs_underline!(UnderlineStyle::Dotted),
    shift 9,
    mask 0x7,
    eq 4u64
);

test_encode_attrs!(
    encode_attrs_underline_dashed_encodes_style_5,
    attrs_underline!(UnderlineStyle::Dashed),
    shift 9,
    mask 0x7,
    eq 5u64
);

test_encode_attrs!(
    encode_attrs_underline_none_encodes_style_0,
    attrs_underline!(UnderlineStyle::None),
    shift 9,
    mask 0x7,
    eq 0u64
);

// -------------------------------------------------------------------------
// Remaining encode_color tests (structural variants that don't fit the macro)
// -------------------------------------------------------------------------

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
    assert_eq!(encode_attrs(&attrs_flags!(SgrFlags::BOLD)), 0x1u64);
}

#[test]
fn test_encode_attrs_all_flags_set() {
    let attrs = SgrAttributes {
        foreground: Color::Default,
        background: Color::Default,
        flags: SgrFlags::BOLD
            | SgrFlags::DIM
            | SgrFlags::ITALIC
            | SgrFlags::BLINK_SLOW
            | SgrFlags::BLINK_FAST
            | SgrFlags::INVERSE
            | SgrFlags::HIDDEN
            | SgrFlags::STRIKETHROUGH,
        underline_style: UnderlineStyle::Straight,
        underline_color: Color::Default,
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
    assert_face_range!(ranges, 0: buf 0, 1, fg 0xFF00_0000u32, bg 0xFF00_0000u32, flags 0u64);
    // ASCII fast path: col_to_buf is empty (identity mapping; Emacs uses col directly)
    assert!(
        col_to_buf.is_empty(),
        "ASCII line must return empty col_to_buf (identity fast path)"
    );
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
    let a1 = SgrAttributes {
        flags: SgrFlags::BOLD,
        ..Default::default()
    };
    let a2 = SgrAttributes {
        flags: SgrFlags::ITALIC,
        ..Default::default()
    };
    let a3 = SgrAttributes {
        flags: SgrFlags::DIM,
        ..Default::default()
    };

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
    for (s, e, _, _, _, _) in &ranges {
        assert!(s < e, "empty range found: start={s}, end={e}");
    }
}

/// Three cells with distinct bold/italic/dim attributes produce three face ranges
/// with the correct attribute bits verified via `assert_face_range!`.
#[test]
fn test_encode_line_three_distinct_attrs_face_ranges() {
    let cells = vec![
        Cell::with_attrs('A', attrs_flags!(SgrFlags::BOLD)),
        Cell::with_attrs('B', attrs_flags!(SgrFlags::ITALIC)),
        Cell::with_attrs('C', attrs_flags!(SgrFlags::DIM)),
    ];
    let (_, ranges, _) = encode_line(&cells);
    assert_eq!(
        ranges.len(),
        3,
        "3 distinct attrs must produce 3 face ranges"
    );
    // bold = bit 0 = 0x1, italic = bit 2 = 0x4, dim = bit 1 = 0x2
    assert_face_range!(ranges, 0: buf 0, 1, fg 0xFF00_0000u32, bg 0xFF00_0000u32, flags 0x1u64);
    assert_face_range!(ranges, 1: buf 1, 2, fg 0xFF00_0000u32, bg 0xFF00_0000u32, flags 0x4u64);
    assert_face_range!(ranges, 2: buf 2, 3, fg 0xFF00_0000u32, bg 0xFF00_0000u32, flags 0x2u64);
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
    let placeholder = Cell {
        width: CellWidth::Wide,
        grapheme: CompactString::new(" "),
        ..Default::default()
    };

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
    // ASCII fast path: col_to_buf is EMPTY because col == buf_offset always.
    // The Emacs side falls back to col when the vector is shorter than col.
    let cells: Vec<Cell> = "Hello".chars().map(Cell::new).collect();
    let (_, _, col_to_buf) = encode_line(&cells);
    assert!(
        col_to_buf.is_empty(),
        "pure ASCII must use identity fast path (empty col_to_buf)"
    );
}

// -------------------------------------------------------------------------
// encode_line merging and combining-char tests
// -------------------------------------------------------------------------

#[test]
fn test_encode_line_adjacent_identical_attrs_merged() {
    // Two adjacent cells with identical (default) attributes must produce a
    // single face range covering both buffer positions, not two ranges.
    let cells = vec![Cell::new('A'), Cell::new('B')];
    let (text, ranges, _) = encode_line(&cells);
    assert_eq!(text, "AB");
    assert_eq!(
        ranges.len(),
        1,
        "identical adjacent attrs must be merged into one face range"
    );
    let (start, end, _, _, _, _) = ranges[0];
    assert_eq!(start, 0);
    assert_eq!(end, 2);
}

#[test]
fn test_encode_line_combining_char_buf_offset() {
    // A cell whose grapheme is "e\u{0301}" (e + combining acute accent) is two
    // Unicode scalars.  buf_offset after that cell must be 2, not 1, so that
    // subsequent face ranges and col_to_buf entries point to the correct Emacs
    // buffer positions.
    use crate::types::cell::CellWidth;
    use compact_str::CompactString;

    // Build a cell with a combining character grapheme.
    let combining_cell = Cell {
        grapheme: CompactString::new("e\u{0301}"),
        width: CellWidth::Half,
        ..Default::default()
    };
    // Follow with a plain ASCII cell so there are two ranges to inspect.
    let plain_cell = Cell::new('X');

    let cells = vec![combining_cell, plain_cell];
    let (text, ranges, _) = encode_line(&cells);

    // The text must contain the full grapheme cluster followed by 'X'.
    assert_eq!(text, "e\u{0301}X");

    // The second range (for 'X') must start at buf_offset 2, proving that the
    // combining-char cell advanced the offset by 2, not 1.
    assert_eq!(
        ranges.len(),
        1,
        "same default attrs: both cells collapse into one range"
    );
    // With identical attrs the single range covers [0, 3) — base(2) + X(1).
    let (start, end, _, _, _, _) = ranges[0];
    assert_eq!(start, 0);
    assert_eq!(end, 3, "buf_offset after combining cell must be 2 + 1 = 3");
}

// -------------------------------------------------------------------------
// encode_line: wide char at last column
// -------------------------------------------------------------------------

/// A wide char at the last column of a line produces non-empty col_to_buf and
/// the placeholder entry maps to the same buffer offset as the wide char itself.
#[test]
fn test_encode_line_wide_char_at_last_column() {
    // Two-column line: 'A' at col 0, wide char 'テ' (placeholder) at col 1.
    // This exercises the code path where a Wide placeholder is the final cell.
    let plain_cell = Cell::new('A');
    let placeholder = Cell {
        width: CellWidth::Wide,
        grapheme: CompactString::new(" "),
        ..Default::default()
    };
    let cells = vec![plain_cell, placeholder];
    let (text, _, col_to_buf) = encode_line(&cells);

    // The placeholder at col 1 must not contribute to the text.
    assert_eq!(text, "A", "wide placeholder at last column must be skipped");
    // col_to_buf must be non-empty because the placeholder is present.
    assert!(
        !col_to_buf.is_empty(),
        "wide placeholder at last column must produce non-empty col_to_buf"
    );
    // col_to_buf[1] (the placeholder) must map to the same buf offset as col 0.
    assert_eq!(
        col_to_buf[1], col_to_buf[0],
        "wide placeholder col_to_buf entry must equal its predecessor"
    );
}

// -------------------------------------------------------------------------
// encode_screen_binary tests
// -------------------------------------------------------------------------

#[test]
fn encode_screen_binary_empty_input_produces_8_byte_header() {
    let result = encode_screen_binary(&[]);
    assert_eq!(
        result.len(),
        8,
        "empty input must produce an 8-byte header only (format_version + num_rows)"
    );
    assert_eq!(read_u32_le(&result, 0), 2, "format_version must be 2");
    assert_eq!(
        read_u32_le(&result, 4),
        0,
        "num_rows header must be 0 for empty input"
    );
}

/// An explicit empty `Vec` (0 rows) must also produce only the 8-byte header,
/// identical to passing an empty slice.  This covers the `Vec::new()` call site.
#[test]
fn encode_screen_binary_explicit_empty_vec_produces_8_byte_header() {
    let lines: Vec<EncodedLine> = Vec::new();
    let result = encode_screen_binary(&lines);
    assert_eq!(
        result.len(),
        8,
        "explicit empty Vec must produce an 8-byte header only (format_version + num_rows)"
    );
    assert_eq!(read_u32_le(&result, 0), 2, "format_version must be 2");
    assert_eq!(
        read_u32_le(&result, 4),
        0,
        "num_rows header must be 0 for empty Vec"
    );
}

#[test]
fn encode_screen_binary_single_row_no_text_no_faces_no_col_to_buf() {
    // A row with empty text, no face ranges, and no col_to_buf.
    let lines: &[EncodedLine] = &[(0usize, String::new(), vec![], vec![])];
    let result = encode_screen_binary(lines);

    // Header (8) + row_index (4) + num_face_ranges (4) + text_byte_len (4)
    // + col_to_buf_len (4) = 24 bytes total
    assert_eq!(result.len(), 24);
    assert_eq!(read_u32_le(&result, 0), 2, "format_version must be 2");
    assert_eq!(read_u32_le(&result, 4), 1, "num_rows must be 1");
    assert_eq!(read_u32_le(&result, 8), 0, "row_index must be 0");
    assert_eq!(read_u32_le(&result, 12), 0, "num_face_ranges must be 0");
    assert_eq!(read_u32_le(&result, 16), 0, "text_byte_len must be 0");
    assert_eq!(read_u32_le(&result, 20), 0, "col_to_buf_len must be 0");
}

#[test]
fn encode_screen_binary_single_row_ascii_text_byte_layout() {
    // A row with 5-byte ASCII text "Hello", no face ranges, no col_to_buf.
    let text = String::from("Hello");
    let text_len = text.len(); // 5
    let lines: &[EncodedLine] = &[(3usize, text, vec![], vec![])];
    let result = encode_screen_binary(lines);

    // Header (8) + row_index (4) + num_face_ranges (4) + text_byte_len (4)
    // + text_bytes (5) + col_to_buf_len (4) = 29 bytes total
    assert_eq!(result.len(), 29);
    assert_eq!(read_u32_le(&result, 0), 2, "format_version must be 2");
    assert_eq!(read_u32_le(&result, 4), 1, "num_rows must be 1");
    assert_eq!(read_u32_le(&result, 8), 3, "row_index must be 3");
    assert_eq!(read_u32_le(&result, 12), 0, "num_face_ranges must be 0");
    assert_eq!(
        read_u32_le(&result, 16),
        text_len as u32,
        "text_byte_len must match"
    );
    assert_eq!(&result[20..25], b"Hello", "raw text bytes must be correct");
    assert_eq!(read_u32_le(&result, 25), 0, "col_to_buf_len must be 0");
}

#[test]
fn encode_screen_binary_single_row_one_face_range_28_byte_encoding() {
    // One face range: (start_buf=0, end_buf=5, fg=0xFF000000, bg=0x00000000, flags=0x01, ul_color=0xFF000000)
    let fg: u32 = 0xFF00_0000;
    let bg: u32 = 0x0000_0000;
    let flags: u64 = 0x0000_0001;
    let ul_color: u32 = 0xFF00_0000; // Color::Default sentinel
    let face_ranges = vec![(0usize, 5usize, fg, bg, flags, ul_color)];
    let lines: &[EncodedLine] = &[(0usize, String::from("Hello"), face_ranges, vec![])];
    let result = encode_screen_binary(lines);

    // Header (8) + row_index (4) + num_face_ranges (4) + text_byte_len (4)
    // + text (5) + face_range (28) + col_to_buf_len (4) = 57 bytes
    assert_eq!(result.len(), 57);
    assert_eq!(read_u32_le(&result, 0), 2, "format_version must be 2");
    assert_eq!(read_u32_le(&result, 4), 1, "num_rows must be 1");
    assert_eq!(read_u32_le(&result, 12), 1, "num_face_ranges must be 1");

    // Face range starts at offset 8(header)+4(row_idx)+4(num_fr)+4(text_len)+5(text) = 25
    let face_base = 25usize;
    assert_eq!(
        read_u32_le(&result, face_base),
        0,
        "face start_buf must be 0"
    );
    assert_eq!(
        read_u32_le(&result, face_base + 4),
        5,
        "face end_buf must be 5"
    );
    assert_eq!(
        read_u32_le(&result, face_base + 8),
        fg,
        "face fg must match"
    );
    assert_eq!(
        read_u32_le(&result, face_base + 12),
        bg,
        "face bg must match"
    );
    assert_eq!(
        read_u64_le(&result, face_base + 16),
        flags,
        "face flags must match"
    );
    assert_eq!(
        read_u32_le(&result, face_base + 24),
        ul_color,
        "face ul_color must match"
    );

    // col_to_buf_len follows at face_base + 28
    assert_eq!(
        read_u32_le(&result, face_base + 28),
        0,
        "col_to_buf_len must be 0"
    );
}

#[test]
fn encode_screen_binary_single_row_nonempty_col_to_buf() {
    // col_to_buf = [0, 0, 1] (3 entries — one wide char at col 0 + placeholder)
    let col_to_buf = vec![0usize, 0usize, 1usize];
    let lines: &[EncodedLine] = &[(0usize, String::from("AB"), vec![], col_to_buf)];
    let result = encode_screen_binary(lines);

    // Header (8) + row_index (4) + num_face_ranges (4) + text_byte_len (4)
    // + text (2) + col_to_buf_len (4) + col_to_buf_entries (3*4=12) = 38 bytes
    assert_eq!(result.len(), 38);

    // col_to_buf_len is at offset 8+4+4+4+2 = 22
    let ctb_base = 22usize;
    assert_eq!(
        read_u32_le(&result, ctb_base),
        3,
        "col_to_buf_len must be 3"
    );
    assert_eq!(
        read_u32_le(&result, ctb_base + 4),
        0,
        "col_to_buf[0] must be 0"
    );
    assert_eq!(
        read_u32_le(&result, ctb_base + 8),
        0,
        "col_to_buf[1] must be 0"
    );
    assert_eq!(
        read_u32_le(&result, ctb_base + 12),
        1,
        "col_to_buf[2] must be 1"
    );
}

#[test]
fn encode_screen_binary_multiple_rows_num_rows_header() {
    let lines: Vec<EncodedLine> = (0..5)
        .map(|i| (i, String::from("x"), vec![], vec![]))
        .collect();
    let result = encode_screen_binary(&lines);
    assert_eq!(read_u32_le(&result, 0), 2, "format_version must be 2");
    assert_eq!(read_u32_le(&result, 4), 5, "num_rows must be 5");
}

// -------------------------------------------------------------------------
// compute_row_hash tests
// -------------------------------------------------------------------------

#[test]
fn compute_row_hash_same_input_same_hash() {
    let line = make_line(&['H', 'i', '!']);
    let col_to_buf = vec![0usize, 1, 2];
    assert_hash_stable!(&line, &col_to_buf);
}

#[test]
fn compute_row_hash_different_chars_different_hash() {
    let line_a = make_line(&['A', 'B', 'C']);
    let line_b = make_line(&['X', 'Y', 'Z']);
    let ctb: &[usize] = &[];
    let ha = compute_row_hash(&line_a, ctb);
    let hb = compute_row_hash(&line_b, ctb);
    assert_ne!(
        ha, hb,
        "lines with different graphemes must hash differently"
    );
}

#[test]
fn compute_row_hash_empty_line_is_deterministic() {
    let line = Line::new(0);
    assert_hash_stable!(&line, &[]);
}

#[test]
fn compute_row_hash_different_col_to_buf_different_hash() {
    // Same line content, different col_to_buf mappings — hash must differ
    // because the wide-char layout changed.
    let line = make_line(&['A']);
    let h_empty = compute_row_hash(&line, &[]);
    let h_nonempty = compute_row_hash(&line, &[0usize]);
    assert_ne!(
        h_empty, h_nonempty,
        "different col_to_buf mappings must produce different hashes"
    );
}

#[test]
fn compute_row_hash_different_attrs_different_hash() {
    let mut line_bold = Line::new(1);
    line_bold.update_cell(0, 'A', attrs_flags!(SgrFlags::BOLD));

    let mut line_plain = Line::new(1);
    line_plain.update_cell(0, 'A', SgrAttributes::default());

    let h_bold = compute_row_hash(&line_bold, &[]);
    let h_plain = compute_row_hash(&line_plain, &[]);
    assert_ne!(
        h_bold, h_plain,
        "differing SGR attributes must produce different hashes"
    );
}

/// Two rows that differ only in cell order must produce different hashes.
#[test]
fn compute_row_hash_order_sensitive() {
    let line_ab = make_line(&['A', 'B']);
    let line_ba = make_line(&['B', 'A']);
    let ha = compute_row_hash(&line_ab, &[]);
    let hb = compute_row_hash(&line_ba, &[]);
    assert_ne!(ha, hb, "hash must be order-sensitive (AB ≠ BA)");
}

/// A single-cell row with only-wide-char placeholder produces a stable hash.
#[test]
fn compute_row_hash_wide_char_stable() {
    // Simulate a row that has a wide char (テ) followed by its placeholder.
    let mut line = Line::new(2);
    line.update_cell(0, 'テ', SgrAttributes::default());
    // placeholder col is CellWidth::Wide internally — just use space here
    line.update_cell(1, ' ', SgrAttributes::default());
    let ctb = vec![0usize, 0]; // wide-char col_to_buf
    assert_hash_stable!(&line, &ctb);
}

/// Hash differs between an empty row and a row filled with spaces.
#[test]
fn compute_row_hash_empty_vs_spaces_differ() {
    let line_empty = Line::new(0);
    let line_spaces = make_line(&[' ', ' ', ' ']);
    let h_empty = compute_row_hash(&line_empty, &[]);
    let h_spaces = compute_row_hash(&line_spaces, &[]);
    assert_ne!(
        h_empty, h_spaces,
        "empty row and space-only row must hash differently"
    );
}

// -------------------------------------------------------------------------
// encode_attrs boundary tests
// -------------------------------------------------------------------------

#[test]
fn encode_attrs_underline_straight_sets_bit_3_and_style_bits_9_11() {
    let bits = encode_attrs(&attrs_underline!(UnderlineStyle::Straight));
    assert_eq!(bits & 0x008, 0x008, "underline flag must set bit 3");
    let style = (bits >> 9) & 0x7;
    assert_eq!(
        style, 1,
        "Straight underline style must encode to 1 in bits 9-11"
    );
}

/// All underline styles encode to their correct 3-bit style fields.
#[test]
fn encode_attrs_all_underline_styles_correct() {
    let cases: &[(UnderlineStyle, u64)] = &[
        (UnderlineStyle::None, 0),
        (UnderlineStyle::Straight, 1),
        (UnderlineStyle::Double, 2),
        (UnderlineStyle::Curly, 3),
        (UnderlineStyle::Dotted, 4),
        (UnderlineStyle::Dashed, 5),
    ];
    for &(style, expected) in cases {
        let bits = encode_attrs(&attrs_underline!(style));
        let encoded = (bits >> 9) & 0x7;
        assert_eq!(
            encoded, expected,
            "underline style {:?} must encode to {expected}",
            style
        );
    }
}

/// Maximum SGR combination: all flags + Curly underline + underline color produces non-zero, sane bits.
#[test]
fn encode_attrs_max_combination_non_zero() {
    use crate::types::color::Color;
    let attrs = SgrAttributes {
        foreground: Color::Rgb(255, 0, 0),
        background: Color::Rgb(0, 0, 255),
        flags: SgrFlags::BOLD
            | SgrFlags::DIM
            | SgrFlags::ITALIC
            | SgrFlags::BLINK_SLOW
            | SgrFlags::BLINK_FAST
            | SgrFlags::INVERSE
            | SgrFlags::HIDDEN
            | SgrFlags::STRIKETHROUGH,
        underline_style: UnderlineStyle::Curly,
        underline_color: Color::Rgb(0, 255, 0),
    };
    let bits = encode_attrs(&attrs);
    // All 9 flag bits (0x1FF) must be set
    assert_eq!(bits & 0x1FF, 0x1FF, "all 9 flag bits must be set");
    // Underline style = 3 (Curly) in bits 9-11
    assert_eq!((bits >> 9) & 0x7, 3, "Curly style must encode in bits 9-11");
}

/// Each individual SGR flag bit occupies a distinct position (no overlap).
#[test]
fn encode_attrs_flag_bits_are_distinct() {
    let all_flags = [
        SgrFlags::BOLD,
        SgrFlags::DIM,
        SgrFlags::ITALIC,
        SgrFlags::BLINK_SLOW,
        SgrFlags::BLINK_FAST,
        SgrFlags::INVERSE,
        SgrFlags::HIDDEN,
        SgrFlags::STRIKETHROUGH,
    ];
    let encoded: Vec<u64> = all_flags
        .iter()
        .map(|&f| encode_attrs(&attrs_flags!(f)))
        .collect();
    // All values must be unique (each flag maps to exactly one bit).
    let unique: std::collections::HashSet<u64> = encoded.iter().copied().collect();
    assert_eq!(
        unique.len(),
        all_flags.len(),
        "every SGR flag must encode to a distinct bit"
    );
    // Each must be a power of two (single bit set).
    for bits in &encoded {
        assert!(
            bits.count_ones() == 1,
            "each single-flag encoding must be a power of two, got {bits:#x}"
        );
    }
}

#[test]
fn encode_attrs_wide_char_col_to_buf_via_encode_line() {
    // Verify that a line with a wide char placeholder produces non-empty col_to_buf.
    let wide_cell = Cell::new('\u{30C6}'); // テ
    let placeholder = Cell {
        width: CellWidth::Wide,
        grapheme: CompactString::new(" "),
        ..Default::default()
    };
    let cells = vec![wide_cell, placeholder];
    let (_, _, col_to_buf) = encode_line(&cells);
    assert!(
        !col_to_buf.is_empty(),
        "wide char line must produce non-empty col_to_buf"
    );
}

// -------------------------------------------------------------------------
// encode_screen_binary: face range byte layout via assert_binary_face!
// -------------------------------------------------------------------------

/// A binary frame with a bold face range encodes fg/bg/flags correctly.
#[test]
fn encode_screen_binary_face_range_bold_verified_with_macro() {
    let fg: u32 = 0xFF00_0000; // Color::Default sentinel
    let bg: u32 = 0xFF00_0000;
    let flags: u64 = 0x0000_0001; // bold
    let ul_color: u32 = 0xFF00_0000; // Color::Default sentinel
    let face_ranges = vec![(0usize, 3usize, fg, bg, flags, ul_color)];
    let lines: &[EncodedLine] = &[(0usize, String::from("ABC"), face_ranges, vec![])];
    let result = encode_screen_binary(lines);

    // header(8) + row_idx(4) + num_fr(4) + text_len(4) + text(3) = 23; face range starts at 23
    assert_binary_face!(&result, 23, buf 0, 3, fg fg, bg bg, flags flags);
}

/// Two consecutive rows in one binary frame: row indices are written in order.
#[test]
fn encode_screen_binary_two_rows_row_indices_in_order() {
    let lines: Vec<EncodedLine> = vec![
        (7usize, String::from("X"), vec![], vec![]),
        (15usize, String::from("Y"), vec![], vec![]),
    ];
    let result = encode_screen_binary(&lines);
    // format_version at offset 0, num_rows at offset 4
    assert_eq!(read_u32_le(&result, 0), 2, "format_version must be 2");
    assert_eq!(read_u32_le(&result, 4), 2, "num_rows must be 2");
    // First row header at offset 8: row_index = 7
    assert_eq!(read_u32_le(&result, 8), 7, "first row_index must be 7");
    // First row: 4(idx) + 4(ranges) + 4(text_len) + 1(text) + 4(ctb_len) = 17 bytes; next at 8+17=25
    let row2_offset = 8 + 4 + 4 + 4 + 1 + 4;
    assert_eq!(
        read_u32_le(&result, row2_offset),
        15,
        "second row_index must be 15"
    );
}

// -------------------------------------------------------------------------
// Named constant value tests
// -------------------------------------------------------------------------

/// `COLOR_DEFAULT_SENTINEL` must equal `0xFF00_0000` — the value documented in
/// module-level comments and used by the Emacs decoder to detect `Color::Default`.
#[test]
fn color_default_sentinel_value() {
    assert_eq!(
        super::COLOR_DEFAULT_SENTINEL,
        0xFF00_0000u32,
        "COLOR_DEFAULT_SENTINEL must be 0xFF00_0000"
    );
}

/// `COLOR_NAMED_MARKER` must have only bit 31 set.
#[test]
fn color_named_marker_is_bit_31() {
    let marker = super::COLOR_NAMED_MARKER;
    assert_eq!(
        marker, 0x8000_0000u32,
        "COLOR_NAMED_MARKER must be 0x80000000"
    );
    assert_eq!(
        marker.count_ones(),
        1,
        "COLOR_NAMED_MARKER must be a single bit"
    );
    assert_eq!(
        marker.leading_zeros(),
        0,
        "COLOR_NAMED_MARKER must be bit 31"
    );
}

/// `COLOR_INDEXED_MARKER` must have only bit 30 set.
#[test]
fn color_indexed_marker_is_bit_30() {
    let marker = super::COLOR_INDEXED_MARKER;
    assert_eq!(
        marker, 0x4000_0000u32,
        "COLOR_INDEXED_MARKER must be 0x40000000"
    );
    assert_eq!(
        marker.count_ones(),
        1,
        "COLOR_INDEXED_MARKER must be a single bit"
    );
    assert_eq!(
        marker.leading_zeros(),
        1,
        "COLOR_INDEXED_MARKER must be bit 30"
    );
}

/// Named and indexed markers must not overlap with each other.
/// The sentinel `0xFF00_0000` shares bit 31 with the named marker by design —
/// it is distinguished from named colors by having a non-zero high byte (bits
/// 24-31 = `0xFF`), which no named-color encoding can produce (index ≤ 15).
#[test]
fn color_markers_are_disjoint() {
    assert_eq!(
        super::COLOR_NAMED_MARKER & super::COLOR_INDEXED_MARKER,
        0,
        "named and indexed markers must not share bits"
    );
    // The sentinel is distinct from any named-color encoding because the named
    // marker ORed with any index 0..=15 gives 0x8000_0000..=0x8000_000F,
    // none of which equal 0xFF00_0000.
    assert_ne!(
        super::COLOR_DEFAULT_SENTINEL,
        super::COLOR_NAMED_MARKER,
        "sentinel must not equal the bare named marker"
    );
    assert_ne!(
        super::COLOR_DEFAULT_SENTINEL,
        super::COLOR_INDEXED_MARKER,
        "sentinel must not equal the bare indexed marker"
    );
    // Verify the sentinel cannot be produced by any named color (index 0-15)
    for idx in 0u32..=15 {
        assert_ne!(
            super::COLOR_NAMED_MARKER | idx,
            super::COLOR_DEFAULT_SENTINEL,
            "sentinel must not collide with any named color (index {idx})"
        );
    }
}

/// `RGB_R_SHIFT` and `RGB_G_SHIFT` must be 16 and 8 respectively —
/// the standard RGB packing convention documented in the module header.
#[test]
fn rgb_shift_values() {
    assert_eq!(
        super::RGB_R_SHIFT,
        16u32,
        "red channel must shift left by 16"
    );
    assert_eq!(
        super::RGB_G_SHIFT,
        8u32,
        "green channel must shift left by 8"
    );
}

/// `ATTRS_UNDERLINE_BIT` must equal `0x008` (bit 3), as documented in the module header.
#[test]
fn attrs_underline_bit_is_bit_3() {
    assert_eq!(
        super::ATTRS_UNDERLINE_BIT,
        0x008u64,
        "ATTRS_UNDERLINE_BIT must be 0x008 (bit 3)"
    );
    assert_eq!(
        super::ATTRS_UNDERLINE_BIT.count_ones(),
        1,
        "ATTRS_UNDERLINE_BIT must be a single bit"
    );
    assert_eq!(
        super::ATTRS_UNDERLINE_BIT.trailing_zeros(),
        3,
        "ATTRS_UNDERLINE_BIT must be at bit position 3"
    );
}

/// `ATTRS_STYLE_SHIFT` must be 9 — underline style occupies bits 9-11.
#[test]
fn attrs_style_shift_is_9() {
    assert_eq!(
        super::ATTRS_STYLE_SHIFT,
        9u32,
        "ATTRS_STYLE_SHIFT must be 9 (bits 9-11 for underline style)"
    );
}

/// The constants compose correctly: encoding `Color::Default` via the constant
/// produces the same result as calling `encode_color` directly.
#[test]
fn constants_compose_with_encode_color() {
    assert_eq!(
        encode_color(&Color::Default),
        super::COLOR_DEFAULT_SENTINEL,
        "encode_color(Default) must equal COLOR_DEFAULT_SENTINEL"
    );
    // Named(Black) = index 0 → marker | 0 = marker alone
    assert_eq!(
        encode_color(&Color::Named(NamedColor::Black)),
        super::COLOR_NAMED_MARKER,
        "encode_color(Named(Black)) must equal COLOR_NAMED_MARKER (index 0)"
    );
    // Indexed(0) → indexed marker | 0 = marker alone
    assert_eq!(
        encode_color(&Color::Indexed(0)),
        super::COLOR_INDEXED_MARKER,
        "encode_color(Indexed(0)) must equal COLOR_INDEXED_MARKER"
    );
}

/// `ATTRS_UNDERLINE_BIT` is set in the encoded output when an underline style
/// is active, and is clear when no underline is active.
#[test]
fn attrs_underline_bit_set_iff_underline_active() {
    let with_ul = encode_attrs(&attrs_underline!(UnderlineStyle::Straight));
    assert_ne!(
        with_ul & super::ATTRS_UNDERLINE_BIT,
        0,
        "ATTRS_UNDERLINE_BIT must be set when underline is active"
    );

    let without_ul = encode_attrs(&SgrAttributes::default());
    assert_eq!(
        without_ul & super::ATTRS_UNDERLINE_BIT,
        0,
        "ATTRS_UNDERLINE_BIT must be clear when no underline is active"
    );
}

/// An all-wide-char row produces correct binary encoding (col_to_buf section populated).
#[test]
fn encode_screen_binary_wide_char_row_col_to_buf_section() {
    // Simulate one wide char: text "テ" (3 UTF-8 bytes), col_to_buf = [0, 0]
    let text = String::from("テ");
    let text_len = text.len(); // 3 bytes
    let col_to_buf = vec![0usize, 0usize];
    let lines: &[EncodedLine] = &[(0usize, text, vec![], col_to_buf)];
    let result = encode_screen_binary(lines);

    // Header(8) + row_idx(4) + num_face_ranges(4) + text_byte_len(4) + text(3) + ctb_len(4) + ctb[0](4) + ctb[1](4) = 35
    assert_eq!(result.len(), 35);
    let ctb_offset = 8 + 4 + 4 + 4 + text_len;
    assert_eq!(
        read_u32_le(&result, ctb_offset),
        2,
        "col_to_buf_len must be 2"
    );
    assert_eq!(
        read_u32_le(&result, ctb_offset + 4),
        0,
        "col_to_buf[0] must be 0"
    );
    assert_eq!(
        read_u32_le(&result, ctb_offset + 8),
        0,
        "col_to_buf[1] must be 0 (wide placeholder)"
    );
}

// -------------------------------------------------------------------------
// Additional uncovered-path tests (Round 44)
// -------------------------------------------------------------------------

/// `Color::Named(BrightWhite)` (index 15, the highest named-color index) must
/// encode distinctly from all other named colors and from any indexed color.
#[test]
fn test_encode_color_named_bright_white_index_15() {
    let encoded = encode_color(&Color::Named(NamedColor::BrightWhite));
    // BrightWhite is repr(u8) == 15
    assert_eq!(
        encoded,
        COLOR_NAMED_MARKER | 15u32,
        "BrightWhite must encode to COLOR_NAMED_MARKER | 15"
    );
    // Must differ from Indexed(15) which uses the indexed marker.
    assert_ne!(
        encoded,
        COLOR_INDEXED_MARKER | 15u32,
        "Named(BrightWhite) must not collide with Indexed(15)"
    );
}

/// `encode_line` on a line whose only cell has default attributes must produce
/// exactly one face range starting at buf_offset 0 (the sentinel-init guard
/// must trigger on the very first cell, not leave the first cell orphaned).
#[test]
fn test_encode_line_first_cell_face_range_always_emitted() {
    // A single cell with default attributes: the face range must cover [0, 1).
    let cell = Cell::new('Z');
    let (_, ranges, _) = encode_line(&[cell]);
    assert_eq!(
        ranges.len(),
        1,
        "single cell must produce exactly one face range"
    );
    let (start, end, _, _, _, _) = ranges[0];
    assert_eq!(start, 0, "face range must start at buf_offset 0");
    assert_eq!(
        end, 1,
        "face range must end at buf_offset 1 for a 1-char cell"
    );
}

/// `encode_screen_binary` with two face ranges in the same row encodes both in
/// order and the `num_face_ranges` header reflects the correct count.
#[test]
fn encode_screen_binary_two_face_ranges_same_row() {
    let fg1: u32 = 0xFF00_0000;
    let bg1: u32 = 0xFF00_0000;
    let flags1: u64 = 0x0000_0001; // bold
    let ul1: u32 = 0xFF00_0000; // Color::Default sentinel
    let fg2: u32 = 0x0000_0000; // Rgb true-black
    let bg2: u32 = 0xFF00_0000;
    let flags2: u64 = 0x0000_0004; // italic
    let ul2: u32 = 0x00FF_0000; // Rgb red as underline color
    let face_ranges = vec![
        (0usize, 2usize, fg1, bg1, flags1, ul1),
        (2usize, 4usize, fg2, bg2, flags2, ul2),
    ];
    let lines: &[EncodedLine] = &[(0usize, String::from("ABCD"), face_ranges, vec![])];
    let result = encode_screen_binary(lines);

    // num_face_ranges header (at byte 12 = header[8]+row_idx[4]) must be 2.
    assert_eq!(read_u32_le(&result, 12), 2, "num_face_ranges must be 2");

    // First face range: header(8) + row_idx(4) + num_face(4) + text_len(4) + text(4) = offset 24
    // Layout: start_buf(4) + end_buf(4) + fg(4) + bg(4) + flags(8) + ul_color(4) = 28 bytes per face range
    assert_eq!(read_u32_le(&result, 24), 0u32, "face1 start_buf");
    assert_eq!(read_u32_le(&result, 28), 2u32, "face1 end_buf");
    assert_eq!(read_u32_le(&result, 32), fg1, "face1 fg");
    assert_eq!(read_u32_le(&result, 36), bg1, "face1 bg");
    assert_eq!(read_u64_le(&result, 40), flags1, "face1 flags");
    assert_eq!(read_u32_le(&result, 48), ul1, "face1 ul_color");

    // Second face range starts at 24 + 28 = 52.
    assert_eq!(read_u32_le(&result, 52), 2u32, "face2 start_buf");
    assert_eq!(read_u32_le(&result, 56), 4u32, "face2 end_buf");
    assert_eq!(read_u32_le(&result, 60), fg2, "face2 fg");
    assert_eq!(read_u32_le(&result, 64), bg2, "face2 bg");
    assert_eq!(read_u64_le(&result, 68), flags2, "face2 flags");
    assert_eq!(read_u32_le(&result, 76), ul2, "face2 ul_color");
}

/// `compute_row_hash` must differ when only the underline color changes, because
/// `encode_color(&cell.attrs.underline_color)` is included in the hash.
#[test]
fn compute_row_hash_underline_color_affects_hash() {
    let mut line_red_ul = Line::new(1);
    let attrs_red = SgrAttributes {
        underline_color: Color::Rgb(255, 0, 0),
        ..Default::default()
    };
    line_red_ul.update_cell(0, 'A', attrs_red);

    let mut line_blue_ul = Line::new(1);
    let attrs_blue = SgrAttributes {
        underline_color: Color::Rgb(0, 0, 255),
        ..Default::default()
    };
    line_blue_ul.update_cell(0, 'A', attrs_blue);

    let h_red = compute_row_hash(&line_red_ul, &[]);
    let h_blue = compute_row_hash(&line_blue_ul, &[]);
    assert_ne!(
        h_red, h_blue,
        "different underline colors must produce different hashes"
    );
}

/// `encode_attrs` with no underline style but a non-default underline color
/// must NOT set `ATTRS_UNDERLINE_BIT` — the underline flag only reflects style,
/// not the mere presence of a color.
#[test]
fn encode_attrs_underline_bit_not_set_for_color_only() {
    let attrs = SgrAttributes {
        underline_color: Color::Rgb(255, 128, 0),
        underline_style: UnderlineStyle::None,
        ..Default::default()
    };
    let bits = encode_attrs(&attrs);
    assert_eq!(
        bits & ATTRS_UNDERLINE_BIT,
        0,
        "ATTRS_UNDERLINE_BIT must be clear when underline_style is None, even with a color set"
    );
}

/// A multi-cell line where the grapheme cluster at the last position is a
/// combining sequence ("e\u{0301}") must produce a face range ending at the
/// correct buf_offset (scalar count of the cluster, not 1).
#[test]
fn test_encode_line_combining_char_at_last_position_face_range_end() {
    use crate::types::cell::CellWidth;

    // Two cells: plain 'A' followed by a combining-char grapheme "e\u{0301}".
    let plain_cell = Cell::new('A');
    let combining_cell = Cell {
        grapheme: compact_str::CompactString::new("e\u{0301}"),
        width: CellWidth::Half,
        ..Default::default()
    };
    let cells = vec![plain_cell, combining_cell];
    let (text, ranges, _) = encode_line(&cells);

    assert_eq!(text, "Ae\u{0301}");
    // Both cells have default attrs → one merged range.
    assert_eq!(ranges.len(), 1, "identical attrs must merge into one range");
    let (start, end, _, _, _, _) = ranges[0];
    assert_eq!(start, 0, "range must start at 0");
    // 'A' contributes 1, "e\u{0301}" contributes 2 scalars → end = 3
    assert_eq!(
        end, 3,
        "combining-char grapheme at end must advance buf_offset by its scalar count"
    );
}

// -------------------------------------------------------------------------
// Additional encode_color tests (Round 35) — named, indexed, RGB, default
// -------------------------------------------------------------------------

// Named color 8: BrightBlack — first bright variant (index 8).
test_encode_color!(
    test_encode_color_named_bright_black_is_8,
    Color::Named(NamedColor::BrightBlack),
    COLOR_NAMED_MARKER | 8u32
);

// Named color 14: BrightCyan (index 14).
test_encode_color!(
    test_encode_color_named_bright_cyan_is_14,
    Color::Named(NamedColor::BrightCyan),
    COLOR_NAMED_MARKER | 14u32
);

// Named color 15: BrightWhite (index 15, the highest named index).
test_encode_color!(
    test_encode_color_named_bright_white_is_15,
    Color::Named(NamedColor::BrightWhite),
    COLOR_NAMED_MARKER | 15u32
);

// Indexed color 127: mid-range indexed color.
test_encode_color!(
    test_encode_color_indexed_127,
    Color::Indexed(127),
    COLOR_INDEXED_MARKER | 127u32
);

// Indexed color 128: one past mid-point — must not collide with 127.
test_encode_color!(
    test_encode_color_indexed_128,
    Color::Indexed(128),
    COLOR_INDEXED_MARKER | 128u32
);

// RGB (0, 0, 0): true black — lower 24 bits all zero, no marker bits.
test_encode_color!(
    test_encode_color_rgb_black_is_zero,
    Color::Rgb(0, 0, 0),
    0u32
);

// RGB (255, 255, 255): true white — lower 24 bits all one, no marker bits.
test_encode_color!(
    test_encode_color_rgb_white_is_0x00ffffff,
    Color::Rgb(255, 255, 255),
    0x00FF_FFFFu32
);

// Color::Default sentinel value via macro.
test_encode_color!(
    test_encode_color_default_sentinel_via_macro,
    Color::Default,
    COLOR_DEFAULT_SENTINEL
);

// -------------------------------------------------------------------------
// Additional encode_attrs tests (Round 35) — individual flags + combined
// -------------------------------------------------------------------------

// Italic only: SgrFlags::ITALIC is raw bit 2; maps directly to encode bit 2 (0x4).
test_encode_attrs!(
    encode_attrs_italic_only_sets_bit_2,
    attrs_flags!(SgrFlags::ITALIC),
    shift 2,
    mask 0x1,
    eq 1u64
);

// Underline only (Straight style): sets ATTRS_UNDERLINE_BIT (bit 3 = 0x8).
test_encode_attrs!(
    encode_attrs_underline_straight_sets_underline_bit,
    attrs_underline!(UnderlineStyle::Straight),
    shift 3,
    mask 0x1,
    eq 1u64
);

// Blink (slow) only: SgrFlags::BLINK_SLOW is raw bit 3; maps to encode bit 4 (0x10).
test_encode_attrs!(
    encode_attrs_blink_slow_sets_bit_4,
    attrs_flags!(SgrFlags::BLINK_SLOW),
    shift 4,
    mask 0x1,
    eq 1u64
);

// Blink (rapid/fast) only: SgrFlags::BLINK_FAST is raw bit 4; maps to encode bit 5 (0x20).
test_encode_attrs!(
    encode_attrs_blink_fast_sets_bit_5,
    attrs_flags!(SgrFlags::BLINK_FAST),
    shift 5,
    mask 0x1,
    eq 1u64
);

// Crossed-out (strikethrough) only: SgrFlags::STRIKETHROUGH is raw bit 7; maps to encode bit 8 (0x100).
test_encode_attrs!(
    encode_attrs_strikethrough_sets_bit_8,
    attrs_flags!(SgrFlags::STRIKETHROUGH),
    shift 8,
    mask 0x1,
    eq 1u64
);

// Inverse only: SgrFlags::INVERSE is raw bit 5; maps to encode bit 6 (0x40).
test_encode_attrs!(
    encode_attrs_inverse_sets_bit_6,
    attrs_flags!(SgrFlags::INVERSE),
    shift 6,
    mask 0x1,
    eq 1u64
);

// Bold + italic + underline (Straight) combined: bits 0 (bold), 2 (italic), 3 (underline) → 0xD.
test_encode_attrs!(
    encode_attrs_bold_italic_underline_combined,
    SgrAttributes {
        flags: SgrFlags::BOLD | SgrFlags::ITALIC,
        underline_style: UnderlineStyle::Straight,
        ..Default::default()
    },
    shift 0,
    mask 0xF,
    eq 0xDu64
);

/// `encode_color` for `Color::Rgb(255, 255, 255)` (true white) must produce
/// `0x00FFFFFF` with no marker bits set — this is the maximum RGB value and
/// must not be confused with any sentinel or named-color encoding.
#[test]
fn test_encode_color_rgb_true_white_no_marker_bits() {
    let encoded = encode_color(&Color::Rgb(255, 255, 255));
    assert_eq!(
        encoded, 0x00FF_FFFFu32,
        "Rgb(255,255,255) must be 0x00FFFFFF"
    );
    // Must not have named-color marker (bit 31).
    assert_eq!(
        encoded & COLOR_NAMED_MARKER,
        0,
        "true white must not set bit 31"
    );
    // Must not have indexed-color marker (bit 30).
    assert_eq!(
        encoded & COLOR_INDEXED_MARKER,
        0,
        "true white must not set bit 30"
    );
    // Must not equal the default sentinel.
    assert_ne!(
        encoded, COLOR_DEFAULT_SENTINEL,
        "true white must not equal default sentinel"
    );
}
