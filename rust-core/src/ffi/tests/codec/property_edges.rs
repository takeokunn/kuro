use super::*;

#[test]
// LAYOUT: row_index and text byte length are correctly encoded as u32 LE.
fn test_pbt_encode_screen_binary_row_index_and_text_len() {
    let lines: &[EncodedLine] = &[EncodedLine {
        row_index: 42,
        text: "Hello".to_string(),
        face_ranges: vec![],
        col_to_buf: vec![],
    }];
    let out = encode_screen_binary(lines);

    let next = assert_binary_row!(&out, 8, row 42, text "Hello", faces 0, ctb []);
    assert_eq!(
        next,
        8 + binary_row_len(5, 0, 0),
        "row payload length mismatch"
    );
}

#[test]
// LAYOUT: 1 face range -> 28 bytes of face range data; verify all 6 fields.
fn test_pbt_encode_screen_binary_one_face_range() {
    let lines: &[EncodedLine] = &[EncodedLine {
        row_index: 0,
        text: "AB".to_string(),
        face_ranges: vec![EncodedFaceRange {
            start_buf: 0,
            end_buf: 2,
            fg: 1,
            bg: 2,
            flags: 3,
            underline_color: 4,
        }],
        col_to_buf: vec![],
    }];
    let out = encode_screen_binary(lines);

    let next = assert_binary_row!(&out, 8, row 0, text "AB", faces 1, ctb []);
    let fr_base = 8 + 12 + 2;
    assert_binary_face!(&out, fr_base, buf 0, 2, fg 1, bg 2, flags 3, ul 4);
    assert_eq!(
        next,
        8 + binary_row_len(2, 1, 0),
        "row payload length mismatch"
    );
}

#[test]
// LAYOUT: col_to_buf length header and entries are correctly encoded.
fn test_pbt_encode_screen_binary_col_to_buf_entries() {
    let lines: &[EncodedLine] = &[EncodedLine {
        row_index: 0,
        text: "X".to_string(),
        face_ranges: vec![],
        col_to_buf: vec![0, 0, 1],
    }];
    let out = encode_screen_binary(lines);

    let next = assert_binary_row!(&out, 8, row 0, text "X", faces 0, ctb [0, 0, 1]);
    assert_eq!(next, out.len(), "row payload length mismatch");
    assert_eq!(
        out.len(),
        8 + binary_row_len(1, 0, 3),
        "total byte count mismatch"
    );
}

#[test]
// LAYOUT: 2 rows -> num_rows header = 2, and both rows appear sequentially.
fn test_pbt_encode_screen_binary_two_rows() {
    let lines: &[EncodedLine] = &[
        EncodedLine {
            row_index: 0,
            text: "A".to_string(),
            face_ranges: vec![],
            col_to_buf: vec![],
        },
        EncodedLine {
            row_index: 1,
            text: "B".to_string(),
            face_ranges: vec![],
            col_to_buf: vec![],
        },
    ];
    let out = encode_screen_binary(lines);

    assert_binary_header!(&out, rows 2);
    let next = assert_binary_row!(&out, 8, row 0, text "A", faces 0, ctb []);
    let next = assert_binary_row!(&out, next, row 1, text "B", faces 0, ctb []);
    assert_eq!(next, out.len(), "row payload length mismatch");
    assert_eq!(
        out.len(),
        8 + 2 * binary_row_len(1, 0, 0),
        "total byte count mismatch"
    );
}

#[test]
// LAYOUT: Unicode text "arrow" (3 UTF-8 bytes) -> text_byte_len field must be 3.
fn test_pbt_encode_screen_binary_unicode_text() {
    let arrow = "\u{2192}"; // U+2192, encodes to [0xE2, 0x86, 0x92] in UTF-8
    assert_eq!(arrow.len(), 3, "sanity: arrow must be 3 bytes");
    let lines: &[EncodedLine] = &[EncodedLine {
        row_index: 0,
        text: arrow.to_string(),
        face_ranges: vec![],
        col_to_buf: vec![],
    }];
    let out = encode_screen_binary(lines);

    let next = assert_binary_row!(&out, 8, row 0, text arrow, faces 0, ctb []);
    assert_eq!(next, out.len(), "row payload length mismatch");
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
