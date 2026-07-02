use super::*;

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
    let face_ranges = vec![face_range(0, 3, fg, bg, flags, ul_color)];
    let lines = vec![encoded_line(0, "ABC", face_ranges, vec![])];
    let result = encode_screen_binary_ok(&lines);

    // header(8) + row_idx(4) + num_fr(4) + text_len(4) + text(3) = 23; face range starts at 23
    assert_binary_face!(&result, 23, buf 0, 3, fg fg, bg bg, flags flags, ul ul_color);
}

/// Two consecutive rows in one binary frame: row indices are written in order.
#[test]
fn encode_screen_binary_two_rows_row_indices_in_order() {
    let lines: Vec<EncodedLine> = vec![
        encoded_line(7, "X", vec![], vec![]),
        encoded_line(15, "Y", vec![], vec![]),
    ];
    let result = encode_screen_binary_ok(&lines);
    // format_version at offset 0, num_rows at offset 4
    assert_binary_header!(&result, rows 2);
    // First row header at offset 8: row_index = 7
    assert_eq!(read_u32_le(&result, 8), 7, "first row_index must be 7");
    // First row: 4(idx) + 4(ranges) + 4(text_len) + 1(text) + 4(ctb_len) = 17 bytes; next at 8+17=25
    let row2_offset = 8 + binary_row_len(1, 0, 0);
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
    let lines = vec![encoded_line(0, text, vec![], col_to_buf)];
    let result = encode_screen_binary_ok(&lines);

    // Header(8) + row_idx(4) + num_face_ranges(4) + text_byte_len(4) + text(3) + ctb_len(4) + ctb[0](4) + ctb[1](4) = 35
    assert_eq!(result.len(), 35);
    let ctb_offset = 8 + binary_row_len(text_len, 0, 0) - 4;
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
        face_range(0, 2, fg1, bg1, flags1, ul1),
        face_range(2, 4, fg2, bg2, flags2, ul2),
    ];
    let lines = vec![encoded_line(0, "ABCD", face_ranges, vec![])];
    let result = encode_screen_binary_ok(&lines);

    // num_face_ranges header (at byte 12 = header[8]+row_idx[4]) must be 2.
    assert_eq!(read_u32_le(&result, 12), 2, "num_face_ranges must be 2");

    // First face range: header(8) + row_idx(4) + num_face(4) + text_len(4) + text(4) = offset 24
    // Layout: start_buf(4) + end_buf(4) + fg(4) + bg(4) + flags(8) + ul_color(4) = 28 bytes per face range
    assert_binary_face!(&result, 24, buf 0, 2, fg fg1, bg bg1, flags flags1, ul ul1);

    // Second face range starts at 24 + 28 = 52.
    assert_binary_face!(&result, 52, buf 2, 4, fg fg2, bg bg2, flags flags2, ul ul2);
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
