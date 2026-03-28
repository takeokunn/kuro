use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: IL (CSI n L) never panics; row count preserved
    fn prop_il_no_panic(n in 0u16..=100u16, row in 0usize..10usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(row, 0);
        term.advance(format!("\x1b[{n}L").as_bytes());
        prop_assert_eq!(term.screen.rows() as usize, 10, "rows must be unchanged after IL");
    }

    #[test]
    // PANIC SAFETY: DL (CSI n M) never panics; row count preserved
    fn prop_dl_no_panic(n in 0u16..=100u16, row in 0usize..10usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(row, 0);
        term.advance(format!("\x1b[{n}M").as_bytes());
        prop_assert_eq!(term.screen.rows() as usize, 10, "rows must be unchanged after DL");
    }

    #[test]
    // PANIC SAFETY: ICH (CSI n @) never panics; line width preserved
    fn prop_ich_no_panic(n in 0u16..=100u16, col in 0usize..20usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}@").as_bytes());
        prop_assert_eq!(
            term.screen.get_line(0).unwrap().cells.len(), 20,
            "line width must be preserved after ICH"
        );
    }

    #[test]
    // PANIC SAFETY: DCH (CSI n P) never panics; line width preserved
    fn prop_dch_no_panic(n in 0u16..=100u16, col in 0usize..20usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}P").as_bytes());
        prop_assert_eq!(
            term.screen.get_line(0).unwrap().cells.len(), 20,
            "line width must be preserved after DCH"
        );
    }

    #[test]
    // INVARIANT: IL + DL cancel out — row count stays the same
    fn prop_il_dl_preserves_row_count(n in 1u16..=8u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{n}L").as_bytes());
        term.advance(format!("\x1b[{n}M").as_bytes());
        prop_assert_eq!(term.screen.rows() as usize, 10);
    }

    #[test]
    // INVARIANT: ECH (CSI n X) never panics; line width and cursor col preserved
    fn prop_ech_no_panic_preserves_width_and_cursor(
        n in 0u16..=100u16,
        col in 0usize..20usize,
    ) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}X").as_bytes());
        prop_assert_eq!(
            term.screen.get_line(0).unwrap().cells.len(), 20,
            "line width must be preserved after ECH"
        );
        prop_assert_eq!(term.screen.cursor().col, col, "ECH must not move the cursor");
    }

    #[test]
    // INVARIANT: ICH then DCH with equal count at same column preserves line width
    fn prop_ich_dch_preserves_line_width(
        n in 1u16..=10u16,
        col in 0usize..10usize,
    ) {
        let mut term = crate::TerminalCore::new(5, 20);
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}@").as_bytes()); // ICH n
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}P").as_bytes()); // DCH n
        prop_assert_eq!(
            term.screen.get_line(0).unwrap().cells.len(), 20,
            "line width must be preserved after ICH+DCH"
        );
    }
}

// ── New tests (Round 34) ──────────────────────────────────────────────────────

// DCH at column 0 shifts the entire row left: col 0 is deleted, col 1
// moves to col 0, and the last column becomes blank.
#[test]
fn test_dch_at_column_zero_shifts_row_left() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill row 0 with '0'..'9'
    if let Some(line) = term.screen.get_line_mut(0) {
        for (i, cell) in line.cells.iter_mut().enumerate() {
            cell.grapheme = compact_str::CompactString::new(((b'0' + i as u8) as char).to_string());
        }
    }
    term.screen.move_cursor(0, 0);

    let params = vte::Params::default();
    csi_dch(&mut term, &params); // DCH 1

    // '0' deleted; '1' now at col 0, '2' at col 1, etc.
    assert_eq!(char_at(&term, 0, 0), '1', "col 0 must hold former col 1");
    assert_eq!(char_at(&term, 0, 1), '2', "col 1 must hold former col 2");
    assert_eq!(char_at(&term, 0, 8), '9', "col 8 must hold former col 9");
    assert_eq!(char_at(&term, 0, 9), ' ', "last col must be blank");
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

// ICH at column 0 shifts the entire row right: a blank is inserted at col 0
// and all existing chars shift right; the original last char falls off.
#[test]
fn test_ich_at_column_zero_shifts_entire_row_right() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill row 0 with '0'..'9'
    if let Some(line) = term.screen.get_line_mut(0) {
        for (i, cell) in line.cells.iter_mut().enumerate() {
            cell.grapheme = compact_str::CompactString::new(((b'0' + i as u8) as char).to_string());
        }
    }
    term.screen.move_cursor(0, 0);

    let params = vte::Params::default();
    csi_ich(&mut term, &params); // ICH 1

    assert_eq!(char_at(&term, 0, 0), ' ', "col 0 must be blank (inserted)");
    assert_eq!(char_at(&term, 0, 1), '0', "col 1 must hold former col 0");
    // '9' at col 9 is pushed off; col 9 holds '8'
    assert_eq!(
        char_at(&term, 0, 9),
        '8',
        "col 9 must hold former col 8 ('9' falls off)"
    );
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

// IL inside a scroll region shifts content down within the region boundary.
// Content above and below the region must be unaffected.
#[test]
fn test_il_inside_scroll_region_shifts_content_down() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'A');
    // Set scroll region: rows 2..7 (0-indexed top=2, bottom=7)
    term.screen.set_scroll_region(2, 7);
    term.screen.move_cursor(3, 0); // cursor inside region

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    // Content above the region: untouched
    assert_eq!(char_at(&term, 0, 0), 'A', "row 0 above region unchanged");
    assert_eq!(char_at(&term, 1, 0), 'B', "row 1 above region unchanged");
    assert_eq!(
        char_at(&term, 2, 0),
        'C',
        "row 2 (region top, above cursor) unchanged"
    );
    // Blank inserted at cursor row
    assert_eq!(char_at(&term, 3, 0), ' ', "row 3 must be blank (inserted)");
    // Former row 3 shifted down
    assert_eq!(char_at(&term, 4, 0), 'D', "row 4 must hold former row 3");
    // Content below the region: untouched
    assert_eq!(char_at(&term, 7, 0), 'H', "row 7 below region unchanged");
}

// IL at the bottom row of the scroll region: the content at that row is
// pushed off, leaving the bottom row blank. Rows outside the region untouched.
#[test]
fn test_il_at_bottom_of_scroll_region_pushes_off() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'0');
    // Scroll region: rows 2..6 (0-indexed exclusive bottom=6)
    term.screen.set_scroll_region(2, 6);
    term.screen.move_cursor(5, 0); // last row of region (bottom-1)

    let params = vte::Params::default();
    csi_il(&mut term, &params); // IL 1

    // Row 5 was '5'; after IL it's blank (content pushed off)
    assert_eq!(
        char_at(&term, 5, 0),
        ' ',
        "bottom row of region must be blank"
    );
    // Rows above the cursor inside the region: unchanged
    assert_eq!(
        char_at(&term, 2, 0),
        '2',
        "row 2 inside region but above cursor: unchanged"
    );
    // Rows outside the region: unchanged
    assert_eq!(char_at(&term, 6, 0), '6', "row 6 below region unchanged");
    assert_eq!(char_at(&term, 9, 0), '9', "row 9 unchanged");
}

// DL inside a scroll region: the deleted row causes rows below it (inside the
// region) to shift up, and the region bottom is filled with blank.
#[test]
fn test_dl_inside_scroll_region_shifts_content_up() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'A');
    // Scroll region: rows 3..8 (0-indexed top=3, bottom=8 exclusive)
    term.screen.set_scroll_region(3, 8);
    term.screen.move_cursor(4, 0); // inside region

    let params = vte::Params::default();
    csi_dl(&mut term, &params); // DL 1

    // Row 4 ('E') deleted; row 5 ('F') shifts to row 4
    assert_eq!(
        char_at(&term, 4, 0),
        'F',
        "row 4 must hold former row 5 after DL"
    );
    assert_eq!(char_at(&term, 5, 0), 'G', "row 5 must hold former row 6");
    // Bottom of region (row 7) is now blank
    assert_eq!(
        char_at(&term, 7, 0),
        ' ',
        "region bottom must be blank after DL"
    );
    // Rows outside region: unchanged
    assert_eq!(char_at(&term, 2, 0), 'C', "row 2 above region unchanged");
    assert_eq!(char_at(&term, 8, 0), 'I', "row 8 below region unchanged");
}

// DL at the bottom row of the scroll region: deleting the last region row
// produces a blank there; rows above it inside the region are untouched.
#[test]
fn test_dl_at_bottom_of_scroll_region_clears_last_row() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows_seq!(term, rows 10, base b'0');
    // Scroll region: rows 1..5 (0-indexed top=1, bottom=5 exclusive)
    term.screen.set_scroll_region(1, 5);
    term.screen.move_cursor(4, 0); // last row inside region

    let params = vte::Params::default();
    csi_dl(&mut term, &params); // DL 1

    // Row 4 was the last in the region; it becomes blank
    assert_eq!(
        char_at(&term, 4, 0),
        ' ',
        "last region row must be blank after DL"
    );
    // Rows 1..4 inside region above cursor: unchanged
    assert_eq!(char_at(&term, 1, 0), '1', "row 1 inside region unchanged");
    assert_eq!(char_at(&term, 3, 0), '3', "row 3 inside region unchanged");
    // Rows outside the region: unchanged
    assert_eq!(char_at(&term, 0, 0), '0', "row 0 above region unchanged");
    assert_eq!(char_at(&term, 5, 0), '5', "row 5 below region unchanged");
}

// SU (CSI S) with the primary screen advances scrollback: after scrolling up
// by N lines the scrollback line count must increase.
#[test]
fn test_su_increases_scrollback_count() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'X');
    fill_line(&mut term, 1, 'Y');

    // Scrollback starts at 0
    assert_eq!(
        term.screen.scrollback_line_count, 0,
        "scrollback must be empty initially"
    );

    // SU 2: scrolls up 2 lines; the top 2 rows ('X', 'Y') go into scrollback
    term.advance(b"\x1b[2S");

    assert!(
        term.screen.scrollback_line_count > 0,
        "scrollback_line_count must be > 0 after SU"
    );
}

// SD (CSI T) shifts visible content down; row 0 becomes blank and former
// row 0 content appears at row 1.  Scrollback count is not affected by SD.
#[test]
fn test_sd_shifts_content_into_visible_area() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_rows_seq!(term, rows 5, base b'A');

    let before_scrollback = term.screen.scrollback_line_count;

    // SD 1: top row becomes blank, former row 0 ('A') appears at row 1
    term.advance(b"\x1b[T");

    assert_eq!(
        char_at(&term, 0, 0),
        ' ',
        "SD: row 0 must be blank after scroll down"
    );
    assert_eq!(
        char_at(&term, 1, 0),
        'A',
        "SD: row 1 must hold former row 0 content"
    );
    assert_eq!(
        term.screen.scrollback_line_count, before_scrollback,
        "SD must not change scrollback count"
    );
}

// ICH multiple characters: inserting 3 blanks at col 2 shifts cols 2..9 right
// by 3; the last 3 chars at cols 7..9 are pushed off.
#[test]
fn test_ich_multi_char_insert() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill row 0 with 'A'..'J'
    if let Some(line) = term.screen.get_line_mut(0) {
        for (i, cell) in line.cells.iter_mut().enumerate() {
            cell.grapheme = compact_str::CompactString::new(((b'A' + i as u8) as char).to_string());
        }
    }
    term.screen.move_cursor(0, 2);

    term.advance(b"\x1b[3@"); // ICH 3

    // Cols 0 and 1 (left of cursor): untouched
    assert_eq!(char_at(&term, 0, 0), 'A', "col 0 untouched");
    assert_eq!(char_at(&term, 0, 1), 'B', "col 1 untouched");
    // 3 blanks inserted at cols 2, 3, 4
    assert_eq!(char_at(&term, 0, 2), ' ', "col 2 blank (inserted)");
    assert_eq!(char_at(&term, 0, 3), ' ', "col 3 blank (inserted)");
    assert_eq!(char_at(&term, 0, 4), ' ', "col 4 blank (inserted)");
    // Former col 2 ('C') shifted to col 5
    assert_eq!(char_at(&term, 0, 5), 'C', "col 5 holds former col 2");
    // Cols 7..10: former cols 5,6 and one more; last 3 cols pushed off
    assert_eq!(
        char_at(&term, 0, 9),
        'G',
        "col 9 holds former col 6 (H,I,J pushed off)"
    );
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}

// DCH with count exceeding the columns from cursor to right margin: all cols
// from cursor to end become blank; no panic; line width preserved.
#[test]
fn test_dch_count_exceeds_remaining_cols() {
    let mut term = crate::TerminalCore::new(5, 10);
    fill_line(&mut term, 0, 'Z');
    term.screen.move_cursor(0, 3); // 7 cols remain (3..10)

    term.advance(b"\x1b[100P"); // DCH 100: clamped to 7

    // Cols 0..3 (before cursor): unchanged
    for col in 0..3 {
        assert_eq!(
            char_at(&term, 0, col),
            'Z',
            "col {col} before cursor must be unchanged"
        );
    }
    // Cols 3..10: blank
    for col in 3..10 {
        assert_eq!(
            char_at(&term, 0, col),
            ' ',
            "col {col} must be blank after DCH 100"
        );
    }
    assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
}
