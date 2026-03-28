// ── IL (Insert Lines) ──────────────────────────────────────────────────

#[test]
fn test_il_basic() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..5 {
        fill_line(&mut term, r, (b'A' + r as u8) as char);
    }
    term.screen.move_cursor(2, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    assert_eq!(char_at(&term, 2, 0), ' '); // newly inserted blank
    assert_eq!(char_at(&term, 3, 0), 'C'); // original row 2 shifted down
    assert_eq!(char_at(&term, 4, 0), 'D'); // original row 3 shifted down
}

#[test]
fn test_il_default_param_is_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    fill_line(&mut term, 1, 'B');
    term.screen.move_cursor(0, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params);

    assert_eq!(char_at(&term, 0, 0), ' '); // new blank
    assert_eq!(char_at(&term, 1, 0), 'A'); // shifted
    assert_eq!(char_at(&term, 2, 0), 'B'); // shifted
}

#[test]
fn test_il_respects_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'0');
    // scroll region rows [2, 7)
    term.screen.set_scroll_region(2, 7);
    term.screen.move_cursor(3, 0);

    term.advance(b"\x1b[2L"); // IL 2

    // Above scroll region: untouched
    assert_eq!(char_at(&term, 0, 0), '0');
    assert_eq!(char_at(&term, 1, 0), '1');
    assert_eq!(char_at(&term, 2, 0), '2'); // cursor was below this row
                                           // Two blank lines inserted at row 3
    assert_eq!(char_at(&term, 3, 0), ' ');
    assert_eq!(char_at(&term, 4, 0), ' ');
    // Original rows 3,4 shifted to 5,6
    assert_eq!(char_at(&term, 5, 0), '3');
    assert_eq!(char_at(&term, 6, 0), '4');
    // Below scroll region: untouched
    assert_eq!(char_at(&term, 7, 0), '7');
    assert_eq!(char_at(&term, 9, 0), '9');
}

test_noop_outside_scroll_region!(
    test_il_noop_when_cursor_above_scroll_region,
    test_dl_noop_when_cursor_above_scroll_region,
    region (3, 8),
    cursor 1,
);

test_noop_outside_scroll_region!(
    test_il_noop_when_cursor_below_scroll_region,
    test_dl_noop_when_cursor_below_scroll_region,
    region (2, 6),
    cursor 8,
);

test_dirty_tracking!(
    test_il_dirty_tracking,
    csi_il,
    rows 5, cursor 1,
    dirty [1, 2, 4]
);

#[test]
fn test_il_integration_via_advance() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_line(&mut term, 0, 'A');
    fill_line(&mut term, 1, 'B');
    fill_line(&mut term, 2, 'C');
    term.screen.move_cursor(1, 0);

    term.advance(b"\x1b[L"); // CSI L (default 1)

    assert_eq!(char_at(&term, 1, 0), ' ');
    assert_eq!(char_at(&term, 2, 0), 'B');
    assert_eq!(char_at(&term, 3, 0), 'C');
}

// ── DL (Delete Lines) ──────────────────────────────────────────────────

#[test]
fn test_dl_basic() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..5 {
        fill_line(&mut term, r, (b'A' + r as u8) as char);
    }
    term.screen.move_cursor(1, 0);

    let params = vte::Params::default();
    csi_dl(&mut term, &params); // DL 1

    // 'B' (row 1) is deleted; 'C' shifts up
    assert_eq!(char_at(&term, 1, 0), 'C');
    assert_eq!(char_at(&term, 2, 0), 'D');
    assert_eq!(char_at(&term, 9, 0), ' '); // blank filled at bottom
}

#[test]
fn test_dl_respects_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'0');
    // scroll region rows [2, 7)
    term.screen.set_scroll_region(2, 7);
    term.screen.move_cursor(3, 0);

    term.advance(b"\x1b[2M"); // DL 2

    // Above region: untouched
    assert_eq!(char_at(&term, 0, 0), '0');
    assert_eq!(char_at(&term, 1, 0), '1');
    assert_eq!(char_at(&term, 2, 0), '2');
    // Rows 3,4 deleted; original row 5 shifts to 3
    assert_eq!(char_at(&term, 3, 0), '5');
    assert_eq!(char_at(&term, 4, 0), '6');
    // Bottom of region filled with blanks
    assert_eq!(char_at(&term, 5, 0), ' ');
    assert_eq!(char_at(&term, 6, 0), ' ');
    // Below region: untouched
    assert_eq!(char_at(&term, 7, 0), '7');
}

test_dirty_tracking!(
    test_dl_dirty_tracking,
    csi_dl,
    rows 5, cursor 1,
    dirty [1, 4]
);

// ── IL/DL zero-count and large-count guard tests ──────────────────────

#[test]
fn test_il_zero_count_is_noop() {
    // IL with explicit 0 is promoted to 1 by get_param() (.max(1)).
    // But CSI 0 L actually inserts 1 line (the standard "0 = default = 1" rule).
    // Verify it inserts exactly one blank line (not zero, not a panic).
    let mut term = crate::TerminalCore::new(10, 10);
    fill_line(&mut term, 0, 'A');
    fill_line(&mut term, 1, 'B');
    term.screen.move_cursor(0, 0);

    term.advance(b"\x1b[0L"); // CSI 0 L — treated as 1

    // One blank line must have been inserted at row 0; 'A' shifts to row 1.
    assert_eq!(char_at(&term, 0, 0), ' ');
    assert_eq!(char_at(&term, 1, 0), 'A');
    assert_eq!(char_at(&term, 2, 0), 'B');
}

#[test]
fn test_dl_zero_count_is_noop() {
    // DL with explicit 0 → promoted to 1 by get_param().
    let mut term = crate::TerminalCore::new(10, 10);
    fill_line(&mut term, 0, 'A');
    fill_line(&mut term, 1, 'B');
    term.screen.move_cursor(0, 0);

    term.advance(b"\x1b[0M"); // CSI 0 M — treated as 1

    // One line deleted; 'B' shifts up to row 0.
    assert_eq!(char_at(&term, 0, 0), 'B');
    assert_eq!(char_at(&term, 9, 0), ' ');
}

// IL/DL large-count clamp: count > remaining rows must clamp, not panic.
// Cursor at row 7; default scroll region bottom = 10; remaining = 3.
test_line_op_large_count!(
    test_il_count_larger_than_remaining_rows_clamps,
    test_dl_count_larger_than_remaining_rows_clamps,
    rows 10, cursor 7, seq_char b'0',
    untouched_above 6,
    blanked_range (7, 10),
);

#[test]
fn test_ich_at_column_zero() {
    // ICH 1 at column 0 should insert a blank at col 0 and shift everything right.
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 0);

    term.advance(b"\x1b[@"); // ICH 1

    assert_eq!(char_at(&term, 0, 0), ' '); // inserted blank
    assert_eq!(char_at(&term, 0, 1), 'A'); // original col 0 shifted right
    assert_eq!(
        term.screen.get_line(0).unwrap().cells.len(),
        10,
        "line width must be preserved"
    );
}

#[test]
fn test_dch_at_last_column() {
    // DCH 1 at the last column should delete that cell and fill with blank at right end.
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    // Put a distinct char at the last col
    if let Some(line) = term.screen.get_line_mut(0) {
        line.update_cell_with(9, crate::types::Cell::new('Z'));
    }
    term.screen.move_cursor(0, 9); // last column

    term.advance(b"\x1b[P"); // DCH 1

    assert_eq!(char_at(&term, 0, 9), ' '); // deleted cell becomes blank
    assert_eq!(
        term.screen.get_line(0).unwrap().cells.len(),
        10,
        "line width must be preserved"
    );
}

// ── clear_lines tests ──────────────────────────────────────────────────

/// Test that `clear_lines(start, end)` is a no-op when all rows are filled
/// with a single character (both empty-range and inverted-range variants).
macro_rules! test_clear_lines_noop {
    ($name:ident, fill $ch:expr, call clear_lines($start:expr, $end:expr)) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(10, 10);
            for r in 0..10 {
                fill_line(&mut term, r, $ch);
            }
            term.screen.clear_lines($start, $end);
            for r in 0..10 {
                assert_eq!(
                    char_at(&term, r, 0),
                    $ch,
                    "row {r} should be untouched"
                );
            }
        }
    };
}

#[test]
fn test_clear_lines_basic() {
    // clear_lines(start, end) should blank rows [start, end).
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        fill_line(&mut term, r, (b'A' + r as u8) as char);
    }

    term.screen.clear_lines(2, 5); // clear rows 2, 3, 4

    // Rows below and above the range are untouched.
    assert_eq!(char_at(&term, 1, 0), 'B');
    assert_eq!(char_at(&term, 2, 0), ' ');
    assert_eq!(char_at(&term, 3, 0), ' ');
    assert_eq!(char_at(&term, 4, 0), ' ');
    assert_eq!(char_at(&term, 5, 0), 'F');
}

test_clear_lines_noop!(
    test_clear_lines_start_equals_end_is_noop,
    fill 'X',
    call clear_lines(3, 3)
);

test_clear_lines_noop!(
    test_clear_lines_start_greater_than_end_is_noop,
    fill 'Z',
    call clear_lines(5, 2)
);

/// Generate a dirty-tracking test for a character-column operation (ICH/DCH/ECH).
/// The sequence is sent via `advance`, and the specified row must appear dirty.
///
/// Syntax:
/// ```text
/// test_char_dirty_tracking!(fn_name, seq SEQ, rows ROWS, cursor (ROW, COL), dirty_row ROW)
/// ```
macro_rules! test_char_dirty_tracking {
    ($name:ident, seq $seq:expr, rows $rows:expr, cursor ($crow:expr, $ccol:expr), dirty_row $dirty:expr) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new($rows, 10);
            term.screen.take_dirty_lines();
            term.screen.move_cursor($crow, $ccol);
            term.advance($seq);
            let dirty = term.screen.take_dirty_lines();
            assert!(dirty.contains(&$dirty), "expected row {} to be dirty", $dirty);
        }
    };
}

// ── ICH (Insert Characters) ────────────────────────────────────────────

#[test]
fn test_ich_basic() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 2);

    let params = vte::Params::default();
    csi_ich(&mut term, &params); // ICH 1

    assert_eq!(char_at(&term, 0, 1), 'A'); // left of cursor: untouched
    assert_eq!(char_at(&term, 0, 2), ' '); // inserted blank
    assert_eq!(char_at(&term, 0, 3), 'A'); // original col 2 shifted right
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10); // width preserved
}

// ICH/DCH clip to right margin: count exceeds remaining cols → blanks only the
// reachable cols, line width preserved.
// Cursor at col 8 on a 10-col terminal; 2 cols remain (8 and 9).
test_char_op_clips!(
    test_ich_clips_to_right_margin,
    test_dch_clips_to_right_margin_macro,
    cols 10, cursor_col 8,
    ich_seq b"\x1b[5@",
    dch_seq b"\x1b[5P",
    blanked_cols [8, 9],
);

test_char_dirty_tracking!(
    test_ich_dirty_tracking,
    seq b"\x1b[@",
    rows 5, cursor (2, 3), dirty_row 2
);

// ── DCH (Delete Characters) ────────────────────────────────────────────

#[test]
fn test_dch_basic() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill row 0 with '0'..'9'
    if let Some(line) = term.screen.get_line_mut(0) {
        for (i, cell) in line.cells.iter_mut().enumerate() {
            cell.grapheme = compact_str::CompactString::new(((b'0' + i as u8) as char).to_string());
        }
    }
    term.screen.move_cursor(0, 2);

    let params = vte::Params::default();
    csi_dch(&mut term, &params); // DCH 1

    assert_eq!(char_at(&term, 0, 2), '3'); // '3' shifted left to col 2
    assert_eq!(char_at(&term, 0, 9), ' '); // blank fills right end
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

#[test]
fn test_dch_clips_to_right_margin() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 8); // 2 cols from right

    term.advance(b"\x1b[10P"); // DCH 10: clamped to 2

    assert_eq!(char_at(&term, 0, 8), ' ');
    assert_eq!(char_at(&term, 0, 9), ' ');
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

test_char_dirty_tracking!(
    test_dch_dirty_tracking,
    seq b"\x1b[P",
    rows 5, cursor (3, 1), dirty_row 3
);

// ── ECH (Erase Characters) ─────────────────────────────────────────────

#[test]
fn test_ech_basic() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 3);

    let params = vte::Params::default();
    csi_ech(&mut term, &params); // ECH 1

    assert_eq!(char_at(&term, 0, 2), 'A'); // left: untouched
    assert_eq!(char_at(&term, 0, 3), ' '); // erased
    assert_eq!(char_at(&term, 0, 4), 'A'); // right: untouched
                                           // Cursor must NOT move
    assert_eq!(term.screen.cursor().col, 3);
}

#[test]
fn test_ech_clips_to_right_margin() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 8);

    term.advance(b"\x1b[20X"); // ECH 20: clamped to cols 8-9

    assert_eq!(char_at(&term, 0, 7), 'A'); // left: untouched
    assert_eq!(char_at(&term, 0, 8), ' '); // erased
    assert_eq!(char_at(&term, 0, 9), ' '); // erased
}

#[test]
fn test_ech_uses_sgr_background() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.advance(b"\x1b[41m"); // SGR 41: red background
    term.screen.move_cursor(0, 2);

    term.advance(b"\x1b[3X"); // ECH 3

    let cell = term.screen.get_cell(0, 2).unwrap();
    assert_eq!(cell.char(), ' ');
    // Erased cell must carry the current SGR background (not the default)
    assert_ne!(cell.attrs.background, crate::Color::Default);
}

test_char_dirty_tracking!(
    test_ech_dirty_tracking,
    seq b"\x1b[X",
    rows 5, cursor (1, 0), dirty_row 1
);

// ── New edge-case tests ───────────────────────────────────────────────────────

/// IL at row 0 (top of screen, no scroll region): inserts blank at row 0,
/// existing content shifts down, last row is lost.
#[test]
fn test_il_at_top_row_shifts_content_down() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'A');
    term.screen.move_cursor(0, 0);

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    assert_eq!(char_at(&term, 0, 0), ' '); // new blank at top
    assert_eq!(char_at(&term, 1, 0), 'A'); // former row 0 shifted to row 1
    assert_eq!(char_at(&term, 2, 0), 'B'); // former row 1 shifted to row 2
    assert_eq!(char_at(&term, 4, 0), 'D'); // former row 3 shifted to row 4
}

/// DL at the last row of the scroll region: deletes that row and fills
/// the bottom of the region with blank.
#[test]
fn test_dl_at_last_row_of_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'0');
    // scroll region: rows 0..5 (0-indexed top=0, bottom=5)
    term.screen.set_scroll_region(0, 5);
    term.screen.move_cursor(4, 0); // last row inside region

    let params = vte::Params::default();
    csi_dl(&mut term, &params); // DL 1

    // Row 4 was '4'; it is deleted, row 5 (bottom of region) becomes blank
    assert_eq!(char_at(&term, 4, 0), ' ');
    // Rows outside region (5..10) are untouched
    for r in 5..10 {
        let ch = (b'0' + r as u8) as char;
        assert_eq!(
            char_at(&term, r, 0),
            ch,
            "row {r} below region must be unchanged"
        );
    }
}

/// ICH 0 is treated as ICH 1 (parameter 0 → default 1).
#[test]
fn test_ich_zero_param_treated_as_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    term.screen.move_cursor(0, 3);

    term.advance(b"\x1b[0@"); // CSI 0 @ → treated as 1

    assert_eq!(char_at(&term, 0, 3), ' '); // blank inserted
    assert_eq!(char_at(&term, 0, 4), 'A'); // shifted right
}

/// DCH 0 is treated as DCH 1.
#[test]
fn test_dch_zero_param_treated_as_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'A');
    // Put a distinct char at col 3
    if let Some(line) = term.screen.get_line_mut(0) {
        line.update_cell_with(3, crate::types::Cell::new('Z'));
    }
    term.screen.move_cursor(0, 3);

    term.advance(b"\x1b[0P"); // CSI 0 P → treated as 1

    // 'Z' at col 3 is deleted; col 3 now holds 'A' (from col 4)
    assert_eq!(char_at(&term, 0, 3), 'A');
    assert_eq!(char_at(&term, 0, 9), ' '); // blank at right end
}

/// ECH 0 is treated as ECH 1.
#[test]
fn test_ech_zero_param_treated_as_one() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'B');
    term.screen.move_cursor(0, 5);

    term.advance(b"\x1b[0X"); // CSI 0 X → treated as 1

    assert_eq!(char_at(&term, 0, 5), ' '); // erased
    assert_eq!(char_at(&term, 0, 6), 'B'); // right neighbor untouched
    assert_eq!(char_at(&term, 0, 4), 'B'); // left neighbor untouched
                                           // Cursor must not move
    assert_eq!(term.screen.cursor().col, 5);
}

/// Generate a pair of tests (one IL, one DL) for the case where the count
/// exactly equals the remaining rows in the region — all rows from the cursor
/// onwards are blanked and no panic occurs.
///
/// Both tests fill rows with `fill_rows_seq!(term, rows ROWS, base BASE)` so
/// the expected character at row `r` is `(BASE as u8 + r as u8) as char`.
///
/// Syntax:
/// ```text
/// test_line_op_exact_count!(
///     il_name, dl_name,
///     rows ROWS, cursor CURSOR, base BASE_CHAR,
///     untouched_rows [R0, R1, ...],
///     il_seq IL_SEQ, dl_seq DL_SEQ,
///     blanked_range (BLANK_START, BLANK_END),
/// )
/// ```
macro_rules! test_line_op_exact_count {
    (
        $il_name:ident, $dl_name:ident,
        rows $rows:expr, cursor $cursor:expr, base $base:expr,
        untouched_rows [$($urow:expr),+],
        il_seq $il_seq:expr, dl_seq $dl_seq:expr,
        blanked_range ($blank_start:expr, $blank_end:expr),
    ) => {
        #[test]
        fn $il_name() {
            let mut term = crate::TerminalCore::new($rows, 10);
            fill_rows_seq!(term, rows $rows, base $base);
            term.screen.move_cursor($cursor, 0);
            term.advance($il_seq);
            $(assert_eq!(char_at(&term, $urow, 0), ($base as u8 + $urow as u8) as char,
                         "row {} must be untouched", $urow);)+
            for r in $blank_start..$blank_end {
                assert_eq!(char_at(&term, r, 0), ' ', "row {r} must be blank after IL");
            }
        }

        #[test]
        fn $dl_name() {
            let mut term = crate::TerminalCore::new($rows, 10);
            fill_rows_seq!(term, rows $rows, base $base);
            term.screen.move_cursor($cursor, 0);
            term.advance($dl_seq);
            $(assert_eq!(char_at(&term, $urow, 0), ($base as u8 + $urow as u8) as char,
                         "row {} must be untouched", $urow);)+
            for r in $blank_start..$blank_end {
                assert_eq!(char_at(&term, r, 0), ' ', "row {r} must be blank after DL");
            }
        }
    };
}

test_line_op_exact_count!(
    test_il_count_exact_remaining_rows,
    test_dl_count_exact_remaining_rows,
    rows 5, cursor 2, base b'A',
    untouched_rows [0, 1],
    il_seq b"\x1b[3L", dl_seq b"\x1b[3M",
    blanked_range (2, 5),
);
