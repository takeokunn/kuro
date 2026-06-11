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

include!("codec_binary_faces.rs");

