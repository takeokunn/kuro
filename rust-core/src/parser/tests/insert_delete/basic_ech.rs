use super::*;

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
