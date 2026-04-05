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
