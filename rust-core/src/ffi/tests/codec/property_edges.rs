use super::*;

#[test]
// LAYOUT: row_index and text byte length are correctly encoded as u32 LE.
fn test_pbt_encode_screen_binary_row_index_and_text_len() {
    let lines: &[ScreenLine] = &[(42, "Hello".to_string(), vec![], vec![])];
    let out = encode_screen_binary(lines);

    assert_eq!(pbt_read_u32(&out, 0), 2, "format_version must be 2");
    assert_eq!(pbt_read_u32(&out, 4), 1, "num_rows must be 1");
    assert_eq!(pbt_read_u32(&out, 8), 42, "row_index must be 42");
    assert_eq!(pbt_read_u32(&out, 12), 0, "num_face_ranges must be 0");
    assert_eq!(
        pbt_read_u32(&out, 16),
        5,
        "text_byte_len must be 5 for 'Hello'"
    );
    assert_eq!(&out[20..25], b"Hello", "text bytes must match 'Hello'");
    assert_eq!(pbt_read_u32(&out, 25), 0, "col_to_buf_len must be 0");
}

#[test]
// LAYOUT: 1 face range -> 28 bytes of face range data; verify all 6 fields.
fn test_pbt_encode_screen_binary_one_face_range() {
    let lines: &[ScreenLine] = &[(0, "AB".to_string(), vec![(0, 2, 1, 2, 3, 4)], vec![])];
    let out = encode_screen_binary(lines);

    assert_eq!(pbt_read_u32(&out, 12), 1, "num_face_ranges must be 1");
    let fr_base = 8 + 4 + 4 + 4 + 2;
    assert_eq!(
        pbt_read_u32(&out, fr_base),
        0,
        "face range start_buf must be 0"
    );
    assert_eq!(
        pbt_read_u32(&out, fr_base + 4),
        2,
        "face range end_buf must be 2"
    );
    assert_eq!(
        pbt_read_u32(&out, fr_base + 8),
        1,
        "face range fg must be 1"
    );
    assert_eq!(
        pbt_read_u32(&out, fr_base + 12),
        2,
        "face range bg must be 2"
    );
    assert_eq!(
        pbt_read_u64(&out, fr_base + 16),
        3,
        "face range flags must be 3"
    );
    assert_eq!(
        pbt_read_u32(&out, fr_base + 24),
        4,
        "face range ul_color must be 4"
    );
}

#[test]
// LAYOUT: col_to_buf length header and entries are correctly encoded.
fn test_pbt_encode_screen_binary_col_to_buf_entries() {
    let lines: &[ScreenLine] = &[(0, "X".to_string(), vec![], vec![0, 0, 1])];
    let out = encode_screen_binary(lines);

    let ctb_base = 8 + 4 + 4 + 4 + 1;
    assert_eq!(pbt_read_u32(&out, ctb_base), 3, "col_to_buf_len must be 3");
    assert_eq!(
        pbt_read_u32(&out, ctb_base + 4),
        0,
        "col_to_buf[0] must be 0"
    );
    assert_eq!(
        pbt_read_u32(&out, ctb_base + 8),
        0,
        "col_to_buf[1] must be 0"
    );
    assert_eq!(
        pbt_read_u32(&out, ctb_base + 12),
        1,
        "col_to_buf[2] must be 1"
    );
    assert_eq!(out.len(), ctb_base + 4 + 3 * 4, "total byte count mismatch");
}

#[test]
// LAYOUT: 2 rows -> num_rows header = 2, and both rows appear sequentially.
fn test_pbt_encode_screen_binary_two_rows() {
    let lines: &[ScreenLine] = &[
        (0, "A".to_string(), vec![], vec![]),
        (1, "B".to_string(), vec![], vec![]),
    ];
    let out = encode_screen_binary(lines);

    assert_eq!(pbt_read_u32(&out, 0), 2, "format_version must be 2");
    assert_eq!(pbt_read_u32(&out, 4), 2, "num_rows must be 2");

    assert_eq!(pbt_read_u32(&out, 8), 0, "row 0 row_index must be 0");
    assert_eq!(pbt_read_u32(&out, 12), 0, "row 0 num_face_ranges must be 0");
    assert_eq!(pbt_read_u32(&out, 16), 1, "row 0 text_byte_len must be 1");
    assert_eq!(out[20], b'A', "row 0 text must be b'A'");
    assert_eq!(pbt_read_u32(&out, 21), 0, "row 0 col_to_buf_len must be 0");

    assert_eq!(pbt_read_u32(&out, 25), 1, "row 1 row_index must be 1");
    assert_eq!(pbt_read_u32(&out, 29), 0, "row 1 num_face_ranges must be 0");
    assert_eq!(pbt_read_u32(&out, 33), 1, "row 1 text_byte_len must be 1");
    assert_eq!(out[37], b'B', "row 1 text must be b'B'");
    assert_eq!(pbt_read_u32(&out, 38), 0, "row 1 col_to_buf_len must be 0");
}

#[test]
// LAYOUT: Unicode text "arrow" (3 UTF-8 bytes) -> text_byte_len field must be 3.
fn test_pbt_encode_screen_binary_unicode_text() {
    let arrow = "\u{2192}"; // U+2192, encodes to [0xE2, 0x86, 0x92] in UTF-8
    assert_eq!(arrow.len(), 3, "sanity: arrow must be 3 bytes");
    let lines: &[ScreenLine] = &[(0, arrow.to_string(), vec![], vec![])];
    let out = encode_screen_binary(lines);

    assert_eq!(
        pbt_read_u32(&out, 16),
        3,
        "text_byte_len must be 3 for arrow"
    );
    assert_eq!(
        &out[20..23],
        arrow.as_bytes(),
        "text bytes must match arrow"
    );
}

// -------------------------------------------------------------------------
// compute_row_hash example-based tests
// -------------------------------------------------------------------------

macro_rules! assert_hash_differs_by_attrs {
    ($name:ident, $attrs_a:expr, $attrs_b:expr, $msg:literal) => {
        #[test]
        fn $name() {
            let mut line_a = Line::new(1);
            line_a.update_cell(0, 'A', $attrs_a);
            let mut line_b = Line::new(1);
            line_b.update_cell(0, 'A', $attrs_b);
            let h_a = compute_row_hash(&line_a, &[]);
            let h_b = compute_row_hash(&line_b, &[]);
            assert_ne!(h_a, h_b, $msg);
        }
    };
}

#[test]
// DETERMINISM: Same row + same col_to_buf -> identical hash on two calls.
fn test_pbt_compute_row_hash_deterministic() {
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
fn test_pbt_compute_row_hash_differs_by_char() {
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
// SENSITIVITY: Same row content but different col_to_buf -> different hashes.
fn test_pbt_compute_row_hash_differs_by_col_to_buf() {
    let mut line = Line::new(4);
    line.update_cell(0, 'X', SgrAttributes::default());
    let col_to_buf_a = vec![0usize, 1, 2, 3];
    let col_to_buf_b = vec![0usize, 1, 2, 99];

    let h_a = compute_row_hash(&line, &col_to_buf_a);
    let h_b = compute_row_hash(&line, &col_to_buf_b);
    assert_ne!(
        h_a, h_b,
        "different col_to_buf must produce different hashes"
    );
}

#[test]
// SAFETY: Empty row (all blank cells) + empty col_to_buf -> does not panic.
fn test_pbt_compute_row_hash_empty_row() {
    let line = Line::new(0);
    let h1 = compute_row_hash(&line, &[]);
    let h2 = compute_row_hash(&line, &[]);
    assert_eq!(h1, h2, "hash of empty row must be consistent");
}

// SENSITIVITY: Same character but different foreground color -> different hashes.
assert_hash_differs_by_attrs!(
    test_pbt_compute_row_hash_differs_by_fg_color,
    SgrAttributes {
        foreground: Color::Rgb(255, 0, 0),
        ..Default::default()
    },
    SgrAttributes {
        foreground: Color::Rgb(0, 0, 255),
        ..Default::default()
    },
    "different fg color must produce different hashes"
);

// SENSITIVITY: Same char, different SGR flags (bold vs default) -> different hashes.
assert_hash_differs_by_attrs!(
    test_pbt_compute_row_hash_differs_by_attrs,
    SgrAttributes::default(),
    SgrAttributes {
        flags: SgrFlags::BOLD,
        ..Default::default()
    },
    "bold vs plain must produce different hashes"
);
