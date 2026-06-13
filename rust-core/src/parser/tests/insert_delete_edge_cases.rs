// ── Additional edge-case tests ────────────────────────────────────────────────

/// IL with cursor above the scroll region (using a region that starts at row 4,
/// cursor at row 2): the scroll region must be completely unaffected.
/// This variant uses a wider margin (cursor is 2 rows above the region top)
/// to complement the existing test that places the cursor 2 rows above top=3.
#[test]
fn test_il_cursor_above_scroll_region_is_noop() {
    let mut term = crate::TerminalCore::new(24, 80);
    // Fill rows with distinct content
    fill_rows_seq!(term, rows 10, base b'A');
    // Scroll region: 1-indexed CSI 5;20 r → 0-indexed top=4, bottom=20
    term.advance(b"\x1b[5;20r");
    // Cursor is now at (0,0) after DECSTBM; move it to row 2 (above region top=4)
    term.screen.move_cursor(2, 0);
    assert_eq!(term.screen.cursor().row, 2);

    // IL 1: cursor is above the scroll region top → no-op
    term.advance(b"\x1b[L");

    // Rows that were inside the scroll region must be untouched
    // (rows 4-9 in our filled content have chars 'E'..'J')
    assert_eq!(
        char_at(&term, 4, 0),
        'E',
        "row 4 (region top) must be unchanged when cursor is above region"
    );
    assert_eq!(
        char_at(&term, 5, 0),
        'F',
        "row 5 must be unchanged when IL is a noop"
    );
    assert_eq!(
        char_at(&term, 6, 0),
        'G',
        "row 6 must be unchanged when IL is a noop"
    );
}

/// DL with cursor below the scroll region (region rows 3-10 in 1-indexed,
/// cursor at row 12): the scroll region must not be affected.
#[test]
fn test_dl_cursor_below_scroll_region_is_noop() {
    let mut term = crate::TerminalCore::new(24, 80);
    fill_rows_seq!(term, rows 15, base b'0');
    // Scroll region: 1-indexed CSI 3;10 r → 0-indexed top=2, bottom=10
    term.advance(b"\x1b[3;10r");
    // Move cursor to row 12, which is below the region end (0-indexed bottom=10)
    term.screen.move_cursor(12, 0);
    assert_eq!(term.screen.cursor().row, 12);

    // DL 1: cursor is below the scroll region → no-op
    term.advance(b"\x1b[M");

    // Rows inside the scroll region must be untouched
    assert_eq!(
        char_at(&term, 2, 0),
        '2',
        "row 2 (region top) must be unchanged when cursor is below region"
    );
    assert_eq!(
        char_at(&term, 5, 0),
        '5',
        "row 5 must be unchanged when DL is a noop"
    );
    assert_eq!(
        char_at(&term, 9, 0),
        '9',
        "row 9 (last in region) must be unchanged when DL is a noop"
    );
}

/// ICH at the last column (col 79 on an 80-col terminal): inserting characters
/// at the last column inserts a blank there, pushing the existing char off screen.
/// Columns to the LEFT of the cursor are NOT affected by ICH.
/// Cursor stays at column 79.
#[test]
fn test_ich_at_last_column() {
    let mut term = crate::TerminalCore::new(5, 80);
    fill_line(&mut term, 0, 'A');
    // Put distinct chars at cols 77, 78, 79
    if let Some(line) = term.screen.get_line_mut(0) {
        line.update_cell_with(77, crate::types::Cell::new('W'));
        line.update_cell_with(78, crate::types::Cell::new('Y'));
        line.update_cell_with(79, crate::types::Cell::new('Z'));
    }
    // Move cursor to last column (col 79)
    term.screen.move_cursor(0, 79);
    assert_eq!(term.screen.cursor().col, 79);

    // ICH 2 at the last column: blanks inserted starting at col 79.
    // ICH only affects cols >= cursor; col 79 is the last, so only col 79 is blanked.
    // The original 'Z' at col 79 is pushed off screen.
    term.advance(b"\x1b[2@");

    // Col 79 (cursor position) must be blank — the inserted blank
    assert_eq!(
        char_at(&term, 0, 79),
        ' ',
        "col 79 must be blank after ICH 2 at last column"
    );
    // Cols 78 and 77 are to the LEFT of the cursor and must be untouched
    assert_eq!(
        char_at(&term, 0, 78),
        'Y',
        "col 78 (left of cursor) must be untouched by ICH"
    );
    assert_eq!(
        char_at(&term, 0, 77),
        'W',
        "col 77 (left of cursor) must be untouched by ICH"
    );
    // Cursor must remain at col 79
    assert_eq!(term.screen.cursor().col, 79, "ICH must not move the cursor");
    // Line width must be preserved
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 80);
}

/// DCH with a count much larger than the remaining columns (from col 5, count=200
/// on a 10-col terminal): no panic, and the line from col 5 onward becomes spaces.
#[test]
fn test_dch_more_than_columns_is_noop_with_spaces() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'X');
    term.screen.move_cursor(0, 5);

    // DCH 200: far more than the 5 remaining columns (10 - 5)
    term.advance(b"\x1b[200P");

    // Columns 0..5 (before cursor) must be untouched
    for col in 0..5 {
        assert_eq!(
            char_at(&term, 0, col),
            'X',
            "col {col} (before cursor) must be untouched after DCH 200"
        );
    }
    // Columns 5..10 must all be space (deleted and filled with blanks)
    for col in 5..10 {
        assert_eq!(
            char_at(&term, 0, col),
            ' ',
            "col {col} must be blank after DCH 200"
        );
    }
    // No panic and line width preserved
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

/// ECH at a position where cells have a non-default background color set via SGR:
/// erased cells become space characters AND carry the current SGR background color.
/// This complements test_ech_uses_sgr_background by also verifying the character is space.
#[test]
fn test_ech_clears_to_default_background() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'Q');

    // Set a non-default background color (SGR 42 = green background)
    term.advance(b"\x1b[42m");
    term.screen.move_cursor(0, 4);

    // ECH 3: erase 3 characters starting at col 4
    term.advance(b"\x1b[3X");

    // Erased cells must be space
    assert_eq!(
        char_at(&term, 0, 4),
        ' ',
        "erased cell at col 4 must be space"
    );
    assert_eq!(
        char_at(&term, 0, 5),
        ' ',
        "erased cell at col 5 must be space"
    );
    assert_eq!(
        char_at(&term, 0, 6),
        ' ',
        "erased cell at col 6 must be space"
    );
    // Erased cells must carry the current SGR background (not Color::Default)
    let cell4 = term.screen.get_cell(0, 4).unwrap();
    assert_ne!(
        cell4.attrs.background,
        crate::Color::Default,
        "erased cell must carry SGR background color (not Color::Default)"
    );
    // Cells outside the erased range must be untouched
    assert_eq!(
        char_at(&term, 0, 3),
        'Q',
        "col 3 (before erased range) must be untouched"
    );
    assert_eq!(
        char_at(&term, 0, 7),
        'Q',
        "col 7 (after erased range) must be untouched"
    );
    // Cursor must not move
    assert_eq!(term.screen.cursor().col, 4, "ECH must not move the cursor");
}

include!("insert_delete_edge_cases2.rs");
include!("insert_delete_proptest.rs");
include!("insert_delete_decic_decdc.rs");
