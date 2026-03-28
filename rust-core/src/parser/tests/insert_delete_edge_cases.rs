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

// ── New edge-case tests (Round 29+) ───────────────────────────────────────────

/// IL at the boundary row that is exactly the scroll region top: the cursor IS
/// inside the region (it equals top), so the operation should NOT be a noop.
/// One blank line is inserted at the cursor row and content shifts down within the region.
#[test]
fn test_il_cursor_at_scroll_region_top_is_not_noop() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'0');
    // Scroll region: top=3, bottom=8
    term.screen.set_scroll_region(3, 8);
    // Move cursor to exactly the region top (row 3)
    term.screen.move_cursor(3, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    // Row 3 (cursor) should now be blank (newly inserted)
    assert_eq!(
        char_at(&term, 3, 0),
        ' ',
        "row 3 (region top) must have a blank inserted"
    );
    // Original row 3 ('3') should have shifted to row 4
    assert_eq!(
        char_at(&term, 4, 0),
        '3',
        "former row 3 should shift down to row 4"
    );
    // Rows above region must be untouched
    assert_eq!(
        char_at(&term, 2, 0),
        '2',
        "row 2 above region must be unchanged"
    );
    // Rows below region must be untouched
    assert_eq!(
        char_at(&term, 8, 0),
        '8',
        "row 8 below region must be unchanged"
    );
}

/// DL with 2 lines starting at the first row of a custom scroll region: the two
/// deleted rows' successors shift up, and the bottom two rows of the region become blank.
#[test]
fn test_dl_multi_line_partial_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'A');
    // Scroll region: top=2, bottom=7 (0-indexed, exclusive bottom)
    term.screen.set_scroll_region(2, 7);
    // Cursor at region top
    term.screen.move_cursor(2, 0);

    term.advance(b"\x1b[2M"); // DL 2

    // Rows 2 and 3 are deleted; rows 4,5,6 shift up to 2,3,4
    assert_eq!(
        char_at(&term, 2, 0),
        'E',
        "row 2 should now be former row 4 ('E')"
    );
    assert_eq!(
        char_at(&term, 3, 0),
        'F',
        "row 3 should now be former row 5 ('F')"
    );
    assert_eq!(
        char_at(&term, 4, 0),
        'G',
        "row 4 should now be former row 6 ('G')"
    );
    // Bottom 2 rows of the region (rows 5,6) become blank
    assert_eq!(char_at(&term, 5, 0), ' ', "row 5 (blanked) should be space");
    assert_eq!(char_at(&term, 6, 0), ' ', "row 6 (blanked) should be space");
    // Rows outside the region are untouched
    assert_eq!(
        char_at(&term, 1, 0),
        'B',
        "row 1 above region must be unchanged"
    );
    assert_eq!(
        char_at(&term, 7, 0),
        'H',
        "row 7 below region must be unchanged"
    );
}

/// ICH does NOT affect rows other than the cursor row — sibling rows must remain
/// unchanged even when multiple rows share the same fill character.
#[test]
fn test_ich_only_modifies_cursor_row() {
    let mut term = crate::TerminalCore::new(5, 10);
    for r in 0..5 {
        fill_line(&mut term, r, 'X');
    }
    term.screen.move_cursor(2, 3); // cursor on row 2

    let params = vte::Params::default();
    csi_ich(&mut term, &params); // ICH 1

    // Row 2: col 3 becomes blank, col 4 gets 'X'
    assert_eq!(char_at(&term, 2, 3), ' ');
    assert_eq!(char_at(&term, 2, 4), 'X');
    // All other rows must still start with 'X' at col 0 (untouched by ICH)
    for r in [0, 1, 3, 4] {
        assert_eq!(
            char_at(&term, r, 0),
            'X',
            "row {r} must be untouched by ICH on row 2"
        );
    }
}

/// ECH at column 0 erases only the specified count starting at col 0,
/// and does not affect other rows or columns beyond the count.
#[test]
fn test_ech_at_column_zero() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'M');
    fill_line(&mut term, 1, 'M'); // other row with same content
    term.screen.move_cursor(0, 0);

    term.advance(b"\x1b[2X"); // ECH 2: erase cols 0 and 1 on row 0

    // Cols 0 and 1 on row 0 become space
    assert_eq!(char_at(&term, 0, 0), ' ', "col 0 must be erased");
    assert_eq!(char_at(&term, 0, 1), ' ', "col 1 must be erased");
    // Col 2 onward on row 0 must be untouched
    assert_eq!(char_at(&term, 0, 2), 'M', "col 2 must be untouched");
    // Row 1 must be completely untouched
    assert_eq!(
        char_at(&term, 1, 0),
        'M',
        "row 1 col 0 must be untouched by ECH on row 0"
    );
    // Cursor must not have moved
    assert_eq!(term.screen.cursor().col, 0, "ECH must not move the cursor");
}

// ── IL/DL blank-line character and line-count invariants ─────────────────────
//
// NOTE: IL and DL use `Line::new()` for inserted blank lines, which always
// produces cells with `Color::Default` background — they do NOT propagate the
// current SGR background (no BCE). This is distinct from SU/SD (scroll_up /
// scroll_down) which accept an explicit background argument.

/// IL inserts a blank line (space character, default background) at the cursor
/// row. Even when a non-default SGR background is active, the inserted line
/// uses the default background because IL does not apply BCE.
#[test]
fn test_il_blank_line_has_default_background() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'A');

    term.advance(b"\x1b[46m"); // SGR 46 = cyan background (active but not used by IL)
    term.screen.move_cursor(1, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    let cell = term.screen.get_cell(1, 0).unwrap();
    assert_eq!(cell.char(), ' ', "IL blank line must be space");
    // IL does NOT propagate the SGR background — it uses Color::Default
    assert_eq!(
        cell.attrs.background,
        crate::Color::Default,
        "IL blank line must have Color::Default background (no BCE)"
    );
    assert_eq!(
        char_at(&term, 2, 0),
        'B',
        "former row 1 must shift to row 2"
    );
}

/// DL fills the bottom of the scroll region with blank lines (space character,
/// default background). Even when a non-default SGR background is active, DL
/// uses the default background because it does not apply BCE.
#[test]
fn test_dl_blank_line_has_default_background() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'0');

    term.advance(b"\x1b[45m"); // SGR 45 = magenta background (active but not used by DL)
    term.screen.move_cursor(1, 0);

    let params = vte::Params::default();
    csi_dl(&mut term, &params); // DL 1

    let cell = term.screen.get_cell(4, 0).unwrap();
    assert_eq!(cell.char(), ' ', "DL trailing blank line must be space");
    // DL does NOT propagate the SGR background — it uses Color::Default
    assert_eq!(
        cell.attrs.background,
        crate::Color::Default,
        "DL blank line must have Color::Default background (no BCE)"
    );
}

/// ECH dirty tracking is isolated to the cursor row — sibling rows must not
/// be marked dirty.
#[test]
fn test_ech_dirty_is_isolated_to_cursor_row() {
    let mut term = crate::TerminalCore::new(5, 10);
    for r in 0..5 {
        fill_line(&mut term, r, 'Q');
    }
    term.screen.take_dirty_lines();

    term.screen.move_cursor(2, 3);
    term.advance(b"\x1b[2X"); // ECH 2

    let dirty = term.screen.take_dirty_lines();
    assert!(dirty.contains(&2), "ECH must mark cursor row 2 dirty");
    for r in [0usize, 1, 3, 4] {
        assert!(
            !dirty.contains(&r),
            "row {r} must not be marked dirty by ECH on row 2"
        );
    }
}

/// IL at the last row of the scroll region: the inserted blank pushes the
/// existing content off-screen, leaving the last row blank.
#[test]
fn test_il_at_region_bottom_minus_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'A');
    term.screen.move_cursor(4, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    assert_eq!(
        char_at(&term, 4, 0),
        ' ',
        "row 4 must be blank after IL at last row"
    );
    assert_eq!(char_at(&term, 0, 0), 'A');
    assert_eq!(char_at(&term, 1, 0), 'B');
    assert_eq!(char_at(&term, 3, 0), 'D');
}

include!("insert_delete_proptest.rs");

