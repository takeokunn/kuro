use super::*;
use crate::ffi::codec::binary::compute_row_hash_from_pool;

// -------------------------------------------------------------------------
// encode_screen_binary tests
// -------------------------------------------------------------------------

#[test]
fn encode_screen_binary_empty_input_produces_16_byte_header() {
    let result = encode_screen_binary_ok(&[]);
    assert_eq!(
        result.len(),
        16,
        "empty input must produce a 16-byte header only (format_version + num_rows + scroll shift)"
    );
    assert_binary_header!(&result, rows 0);
}

/// An explicit empty `Vec` (0 rows) must also produce only the 16-byte header,
/// identical to passing an empty slice.  This covers the `Vec::new()` call site.
#[test]
fn encode_screen_binary_explicit_empty_vec_produces_16_byte_header() {
    let lines: Vec<EncodedLine> = Vec::new();
    let result = encode_screen_binary_ok(&lines);
    assert_eq!(
        result.len(),
        16,
        "explicit empty Vec must produce a 16-byte header only (format_version + num_rows + scroll shift)"
    );
    assert_binary_header!(&result, rows 0);
}

#[test]
fn encode_screen_binary_single_row_no_text_no_faces_no_col_to_buf() {
    // A row with empty text, no face ranges, and no col_to_buf.
    let lines: &[EncodedLine] = &[EncodedLine {
        row_index: 0,
        text: String::new(),
        face_ranges: vec![],
        col_to_buf: vec![],
    }];
    let result = encode_screen_binary_ok(lines);

    // Header (16) + row_index (4) + num_face_ranges (4) + text_byte_len (4)
    // + col_to_buf_len (4) = 32 bytes total
    assert_eq!(result.len(), 32);
    assert_binary_header!(&result, rows 1);
    assert_eq!(read_u32_le(&result, 16), 0, "row_index must be 0");
    assert_eq!(read_u32_le(&result, 20), 0, "num_face_ranges must be 0");
    assert_eq!(read_u32_le(&result, 24), 0, "text_byte_len must be 0");
    assert_eq!(read_u32_le(&result, 28), 0, "col_to_buf_len must be 0");
}

#[test]
fn encode_screen_binary_single_row_ascii_text_byte_layout() {
    // A row with 5-byte ASCII text "Hello", no face ranges, no col_to_buf.
    let text = String::from("Hello");
    let text_len = text.len(); // 5
    let lines: &[EncodedLine] = &[EncodedLine {
        row_index: 3,
        text,
        face_ranges: vec![],
        col_to_buf: vec![],
    }];
    let result = encode_screen_binary_ok(lines);

    // Header (16) + row_index (4) + num_face_ranges (4) + text_byte_len (4)
    // + text_bytes (5) + col_to_buf_len (4) = 37 bytes total
    assert_eq!(result.len(), 37);
    assert_binary_header!(&result, rows 1);
    assert_eq!(read_u32_le(&result, 16), 3, "row_index must be 3");
    assert_eq!(read_u32_le(&result, 20), 0, "num_face_ranges must be 0");
    assert_eq!(
        read_u32_le(&result, 24),
        test_usize_to_u32(text_len, "text length test value fits u32"),
        "text_byte_len must match"
    );
    assert_eq!(&result[28..33], b"Hello", "raw text bytes must be correct");
    assert_eq!(read_u32_le(&result, 33), 0, "col_to_buf_len must be 0");
}

#[test]
fn encode_screen_binary_single_row_one_face_range_28_byte_encoding() {
    // One face range: (start_buf=0, end_buf=5, fg=0xFF000000, bg=0x00000000, flags=0x01, ul_color=0xFF000000)
    let fg: u32 = 0xFF00_0000;
    let bg: u32 = 0x0000_0000;
    let flags: u64 = 0x0000_0001;
    let ul_color: u32 = 0xFF00_0000; // Color::Default sentinel
    let face_ranges = vec![EncodedFaceRange {
        start_buf: 0,
        end_buf: 5,
        fg,
        bg,
        flags,
        underline_color: ul_color,
    }];
    let lines: &[EncodedLine] = &[EncodedLine {
        row_index: 0,
        text: String::from("Hello"),
        face_ranges,
        col_to_buf: vec![],
    }];
    let result = encode_screen_binary_ok(lines);

    // Header (16) + row_index (4) + num_face_ranges (4) + text_byte_len (4)
    // + text (5) + face_range (28) + col_to_buf_len (4) = 65 bytes
    assert_eq!(result.len(), 65);
    assert_binary_header!(&result, rows 1);
    assert_eq!(read_u32_le(&result, 20), 1, "num_face_ranges must be 1");

    // Face range starts at offset 16(header)+4(row_idx)+4(num_fr)+4(text_len)+5(text) = 33
    let face_base = 33usize;
    assert_binary_face!(&result, face_base, buf 0, 5, fg fg, bg bg, flags flags, ul ul_color);

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
    let lines: &[EncodedLine] = &[EncodedLine {
        row_index: 0,
        text: String::from("AB"),
        face_ranges: vec![],
        col_to_buf,
    }];
    let result = encode_screen_binary_ok(lines);

    // Header (16) + row_index (4) + num_face_ranges (4) + text_byte_len (4)
    // + text (2) + col_to_buf_len (4) + col_to_buf_entries (3*4=12) = 46 bytes
    assert_eq!(result.len(), 46);

    // col_to_buf_len is at offset 16+4+4+4+2 = 30
    let ctb_base = 30usize;
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
        .map(|i| EncodedLine {
            row_index: i,
            text: String::from("x"),
            face_ranges: vec![],
            col_to_buf: vec![],
        })
        .collect();
    let result = encode_screen_binary_ok(&lines);
    assert_binary_header!(&result, rows 5);
}

#[cfg(target_pointer_width = "64")]
#[inline]
fn above_binary_frame_u32_max() -> usize {
    usize::try_from(u64::from(u32::MAX) + 1).expect("64-bit usize fits u32::MAX + 1")
}

#[cfg(target_pointer_width = "64")]
#[test]
fn encode_screen_binary_rejects_row_index_above_u32() {
    let value = above_binary_frame_u32_max();
    let lines = vec![encoded_line(value, "", vec![], vec![])];
    let error = encode_screen_binary(&lines).expect_err("row index above u32 must be rejected");
    assert_eq!(error.field, BinaryFrameU32Field::RowIndex);
    assert_eq!(error.value, value);
}

#[cfg(target_pointer_width = "64")]
#[test]
fn encode_screen_binary_rejects_face_start_above_u32() {
    let value = above_binary_frame_u32_max();
    let lines = vec![encoded_line(
        0,
        "",
        vec![face_range(value, 0, 0, 0, 0, 0)],
        vec![],
    )];
    let error = encode_screen_binary(&lines).expect_err("face start above u32 must be rejected");
    assert_eq!(error.field, BinaryFrameU32Field::FaceStartBuf);
    assert_eq!(error.value, value);
}

#[cfg(target_pointer_width = "64")]
#[test]
fn encode_screen_binary_rejects_face_end_above_u32() {
    let value = above_binary_frame_u32_max();
    let lines = vec![encoded_line(
        0,
        "",
        vec![face_range(0, value, 0, 0, 0, 0)],
        vec![],
    )];
    let error = encode_screen_binary(&lines).expect_err("face end above u32 must be rejected");
    assert_eq!(error.field, BinaryFrameU32Field::FaceEndBuf);
    assert_eq!(error.value, value);
}

#[cfg(target_pointer_width = "64")]
#[test]
fn encode_screen_binary_rejects_col_to_buf_offset_above_u32() {
    let value = above_binary_frame_u32_max();
    let lines = vec![encoded_line(0, "", vec![], vec![value])];
    let error =
        encode_screen_binary(&lines).expect_err("col_to_buf offset above u32 must be rejected");
    assert_eq!(error.field, BinaryFrameU32Field::ColToBufOffset);
    assert_eq!(error.value, value);
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
// compute_row_hash_from_pool / compute_row_hash_from_encoded tests
// -------------------------------------------------------------------------

/// Same pool data produced twice → identical hashes.
#[test]
fn compute_row_hash_from_pool_is_deterministic() {
    let mut pool = EncodePool::new();
    pool.text = String::from("hello");
    pool.face_ranges = vec![EncodedFaceRange {
        start_buf: 0,
        end_buf: 5,
        fg: 0,
        bg: 0,
        flags: 0,
        underline_color: 0,
    }];
    pool.col_to_buf = vec![0, 1, 2, 3, 4];
    let h1 = compute_row_hash_from_pool(&pool);
    let h2 = compute_row_hash_from_pool(&pool);
    assert_eq!(h1, h2, "same pool data must produce identical hashes");
}

/// Changing `pool.text` must change the hash.
#[test]
fn compute_row_hash_from_pool_differs_on_text_change() {
    let mut pool_a = EncodePool::new();
    pool_a.text = String::from("abc");

    let mut pool_b = EncodePool::new();
    pool_b.text = String::from("xyz");

    let ha = compute_row_hash_from_pool(&pool_a);
    let hb = compute_row_hash_from_pool(&pool_b);
    assert_ne!(ha, hb, "different text must produce different hashes");
}

/// Changing `pool.face_ranges` must change the hash.
#[test]
fn compute_row_hash_from_pool_differs_on_face_range_change() {
    let mut pool_a = EncodePool::new();
    pool_a.text = String::from("x");
    pool_a.face_ranges = vec![EncodedFaceRange {
        start_buf: 0,
        end_buf: 1,
        fg: 0xFF_0000,
        bg: 0,
        flags: 0,
        underline_color: 0,
    }]; // red fg

    let mut pool_b = EncodePool::new();
    pool_b.text = String::from("x");
    pool_b.face_ranges = vec![EncodedFaceRange {
        start_buf: 0,
        end_buf: 1,
        fg: 0x00_FF00,
        bg: 0,
        flags: 0,
        underline_color: 0,
    }]; // green fg

    let ha = compute_row_hash_from_pool(&pool_a);
    let hb = compute_row_hash_from_pool(&pool_b);
    assert_ne!(
        ha, hb,
        "different face_ranges must produce different hashes"
    );
}

/// Same encoded data → identical hashes.
#[test]
fn compute_row_hash_from_encoded_is_deterministic() {
    let text = "world";
    let faces = [EncodedFaceRange {
        start_buf: 0,
        end_buf: 5,
        fg: 0,
        bg: 0,
        flags: 1,
        underline_color: 0,
    }];
    let ctb: &[usize] = &[0, 1, 2, 3, 4];
    let h1 = compute_row_hash_from_encoded(text, &faces, ctb, &[]);
    let h2 = compute_row_hash_from_encoded(text, &faces, ctb, &[]);
    assert_eq!(h1, h2, "same encoded inputs must produce identical hashes");
}

/// Changing `text` must change the encoded hash.
#[test]
fn compute_row_hash_from_encoded_differs_on_text_change() {
    let faces: &[EncodedFaceRange] = &[];
    let ctb: &[usize] = &[];
    let ha = compute_row_hash_from_encoded("aaa", faces, ctb, &[]);
    let hb = compute_row_hash_from_encoded("bbb", faces, ctb, &[]);
    assert_ne!(
        ha, hb,
        "different text must produce different encoded hashes"
    );
}

/// `compute_row_hash_from_pool` and `compute_row_hash_from_encoded` must agree
/// when they represent the same data (pool-owned vs. caller-owned post-mem::take).
#[test]
fn compute_row_hash_pool_and_encoded_agree() {
    let text = "rust";
    let faces = vec![EncodedFaceRange {
        start_buf: 0,
        end_buf: 4,
        fg: 1,
        bg: 2,
        flags: 0x3,
        underline_color: 0,
    }];
    let ctb: Vec<usize> = vec![0, 1, 2, 3];

    // Build a pool with the same data.
    let mut pool = EncodePool::new();
    pool.text = String::from(text);
    pool.face_ranges = faces.clone();
    pool.col_to_buf = ctb.clone();

    let h_pool = compute_row_hash_from_pool(&pool);
    let h_encoded = compute_row_hash_from_encoded(text, &faces, &ctb, &pool.text_sizes);
    assert_eq!(
        h_pool, h_encoded,
        "pool-hash and encoded-hash must agree for identical data"
    );
}

/// A `text_sizes` difference must change both hash variants — proving a
/// text-size-only change folds into the row hash (dirty tracking).
#[test]
fn compute_row_hash_differs_on_text_size_change() {
    // Pool path: identical text/faces/col_to_buf, only text_sizes differ.
    let mut pool_a = EncodePool::new();
    pool_a.text = String::from("x");
    let mut pool_b = EncodePool::new();
    pool_b.text = String::from("x");
    pool_b.text_sizes = vec![0, 2000]; // (buf_offset=0, permille=2000)

    assert_ne!(
        compute_row_hash_from_pool(&pool_a),
        compute_row_hash_from_pool(&pool_b),
        "a text-size-only change must change the pool hash"
    );

    // Encoded path: same text/faces/col_to_buf, only text_sizes slice differs.
    let faces: &[EncodedFaceRange] = &[];
    let ctb: &[usize] = &[];
    assert_ne!(
        compute_row_hash_from_encoded("x", faces, ctb, &[]),
        compute_row_hash_from_encoded("x", faces, ctb, &[0, 500]),
        "a text-size-only change must change the encoded hash"
    );
}
