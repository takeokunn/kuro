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
