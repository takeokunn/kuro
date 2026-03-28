// ── New edge-case tests (made feasible by macros) ──────────────────────────

/// ED mode 2 on a 1×1 terminal must not panic and leaves a blank cell.
#[test]
fn test_ed_mode2_minimal_terminal() {
    let mut term = crate::TerminalCore::new(1, 1);
    if let Some(line) = term.screen.get_line_mut(0) {
        line.update_cell_with(0, Cell::new('X'));
    }
    term.advance(b"\x1b[2J");
    assert_cell!(term, row 0, col 0, char ' ');
}

/// EL mode 2 on a 1-column terminal must not panic and leaves a blank cell.
#[test]
fn test_el_mode2_single_column() {
    let mut term = crate::TerminalCore::new(3, 1);
    if let Some(line) = term.screen.get_line_mut(1) {
        line.update_cell_with(0, Cell::new('Z'));
    }
    term.screen.move_cursor(1, 0);
    term.advance(b"\x1b[2K");
    assert_cell!(term, row 1, col 0, char ' ');
}

/// ED mode 0 from the last cell of the last row must erase exactly that cell.
#[test]
fn test_ed_mode0_at_last_cell() {
    let mut term = term_filled!(3 x 5, 'L');
    term.screen.move_cursor(2, 4); // last row, last col
    let params = vte::Params::default();
    csi_ed(&mut term, &params);

    // All cells before last must still be 'L'
    assert_row_range_char!(term, rows 0..2, cols 0..5, 'L', "rows above unchanged");
    assert_line_char!(term, row 2, cols 0..4, 'L', "row 2 cols 0-3 unchanged");
    assert_cell!(term, row 2, col 4, char ' ');
}

/// ED mode 1 from the first cell of the first row erases exactly that one cell (inclusive).
#[test]
fn test_ed_mode1_at_first_cell_clears_origin_only() {
    let mut term = term_filled!(3 x 5, 'M');
    term.screen.move_cursor(0, 0);
    term.advance(b"\x1b[1J");

    // Only cell (0,0) is erased; all other cells remain 'M'
    assert_cell!(term, row 0, col 0, char ' ');
    assert_line_char!(term, row 0, cols 1..5, 'M', "ED 1 at origin: cols 1+ unchanged on row 0");
    assert_row_range_char!(term, rows 1..3, cols 0..5, 'M', "ED 1 at origin: rows 1-2 unchanged");
}

/// EL mode 0 on a freshly-created (already blank) line must be a no-op
/// (no panic, cells remain blank).
#[test]
fn test_el_mode0_on_blank_line_is_noop() {
    let mut term = crate::TerminalCore::new(3, 10);
    term.screen.move_cursor(1, 3);
    let params = vte::Params::default();
    csi_el(&mut term, &params);

    assert_line_char!(term, row 1, cols 0..10, ' ', "blank line stays blank after EL 0");
}

/// EL mode 2 applied to multiple rows in succession — each is independently cleared.
#[test]
fn test_el_mode2_successive_rows() {
    let mut term = term_filled!(4 x 8, 'K');

    for row in 0..4usize {
        term.screen.move_cursor(row, 4);
        term.advance(b"\x1b[2K");
    }

    assert_row_range_char!(term, rows 0..4, cols 0..8, ' ', "all rows cleared by successive EL 2");
}

/// ED mode 0 with a non-default background color (BCE) — only the erased region
/// gets the color; the region above the cursor retains default background.
#[test]
fn test_ed_mode0_bce_does_not_taint_above_cursor() {
    let mut term = term_filled!(4 x 6, 'F');
    term.current_attrs.background = Color::Named(NamedColor::Yellow);
    term.screen.move_cursor(2, 0);
    term.advance(b"\x1b[J");

    // Rows above cursor must still have default (not Yellow) background
    assert_row_range_bg!(term, rows 0..2, cols 0..6, Color::Default, "rows above cursor have default bg");
    // Erased region (rows 2-3) must have Yellow background
    assert_row_range_bg!(term, rows 2..4, cols 0..6, Color::Named(NamedColor::Yellow), "erased rows have Yellow bg");
}

/// EL mode 1 cursor at the last column erases the entire line.
#[test]
fn test_el_mode1_at_last_column_clears_entire_line() {
    let mut term = crate::TerminalCore::new(3, 10);
    let row = 0;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('U'));
        }
    }
    term.screen.move_cursor(row, 9);
    term.advance(b"\x1b[1K");

    assert_line_char!(term, row row, cols 0..10, ' ', "EL mode 1 at last col clears whole line");
}

// ── New edge-case tests: boundaries, round-trips, ECH/REP interactions ────────

/// EL mode 0 with cursor at column 0 must erase the entire line (all cols).
#[test]
fn test_el_mode0_at_column_zero_clears_entire_line() {
    let mut term = crate::TerminalCore::new(3, 10);
    let row = 1;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('G'));
        }
    }
    term.screen.move_cursor(row, 0);
    let params = vte::Params::default();
    csi_el(&mut term, &params);

    assert_line_char!(term, row row, cols 0..10, ' ', "EL mode 0 at col 0: entire line cleared");
}

/// EL mode 0 / mode 1 / mode 2 round-trip on the same row: after each erase,
/// re-fill and re-verify so the modes are tested in sequence against the same line.
#[test]
fn test_el_modes_round_trip_on_same_row() {
    let row = 0;

    // Mode 0: erase from cursor (col 4) to end of line.
    let mut term = crate::TerminalCore::new(3, 10);
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('A'));
        }
    }
    term.screen.move_cursor(row, 4);
    term.advance(b"\x1b[K"); // EL 0
    assert_line_char!(term, row row, cols 0..4, 'A', "EL0: before cursor unchanged");
    assert_line_char!(term, row row, cols 4..10, ' ', "EL0: from cursor cleared");

    // Mode 1: erase from start to cursor (col 4 inclusive) on a freshly-filled line.
    let mut term2 = crate::TerminalCore::new(3, 10);
    for c in 0..10 {
        if let Some(line) = term2.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('B'));
        }
    }
    term2.screen.move_cursor(row, 4);
    term2.advance(b"\x1b[1K"); // EL 1
    assert_line_char!(term2, row row, cols 0..=4, ' ', "EL1: up to cursor cleared");
    assert_line_char!(term2, row row, cols 5..10, 'B', "EL1: after cursor unchanged");

    // Mode 2: entire line erased regardless of cursor position.
    let mut term3 = crate::TerminalCore::new(3, 10);
    for c in 0..10 {
        if let Some(line) = term3.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('C'));
        }
    }
    term3.screen.move_cursor(row, 7);
    term3.advance(b"\x1b[2K"); // EL 2
    assert_line_char!(term3, row row, cols 0..10, ' ', "EL2: entire line cleared");
}

/// ED mode 0 / mode 1 / mode 2 round-trip: each mode tested on a fresh terminal.
#[test]
fn test_ed_modes_round_trip() {
    // Mode 0: erase from (1,5) to end of screen.
    let mut t0 = term_filled!(3 x 10, 'D');
    t0.screen.move_cursor(1, 5);
    t0.advance(b"\x1b[J"); // ED 0
    assert_row_range_char!(t0, rows 0..1, cols 0..10, 'D', "ED0: row 0 unchanged");
    assert_line_char!(t0, row 1, cols 0..5, 'D', "ED0: row 1 before cursor unchanged");
    assert_line_char!(t0, row 1, cols 5..10, ' ', "ED0: row 1 from cursor cleared");
    assert_row_range_char!(t0, rows 2..3, cols 0..10, ' ', "ED0: row 2 cleared");

    // Mode 1: erase from start of screen to (1,5) inclusive.
    let mut t1 = term_filled!(3 x 10, 'E');
    t1.screen.move_cursor(1, 5);
    t1.advance(b"\x1b[1J"); // ED 1
    assert_row_range_char!(t1, rows 0..1, cols 0..10, ' ', "ED1: row 0 cleared");
    assert_line_char!(t1, row 1, cols 0..=5, ' ', "ED1: row 1 up to cursor cleared");
    assert_line_char!(t1, row 1, cols 6..10, 'E', "ED1: row 1 after cursor unchanged");
    assert_row_range_char!(t1, rows 2..3, cols 0..10, 'E', "ED1: row 2 unchanged");

    // Mode 2: entire screen cleared.
    let mut t2 = term_filled!(3 x 10, 'F');
    t2.advance(b"\x1b[2J"); // ED 2
    assert_row_range_char!(t2, rows 0..3, cols 0..10, ' ', "ED2: all cells blank");
}

/// ECH (CSI n X) clears n cells from the cursor position without moving the cursor.
/// Verify that erased cells are blank and the cursor position is unchanged.
#[test]
fn test_ech_clears_cells_from_cursor() {
    let mut term = crate::TerminalCore::new(3, 10);
    let row = 0;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('H'));
        }
    }
    term.screen.move_cursor(row, 3);
    term.advance(b"\x1b[4X"); // ECH 4: erase cols 3, 4, 5, 6
    assert_line_char!(term, row row, cols 0..3, 'H', "ECH: before cursor unchanged");
    assert_line_char!(term, row row, cols 3..7, ' ', "ECH: erased region blank");
    assert_line_char!(term, row row, cols 7..10, 'H', "ECH: after erased region unchanged");
    assert_eq!(term.screen.cursor().col, 3, "ECH must not move cursor");
}

/// ECH with a BCE background color: erased cells carry the current SGR background.
#[test]
fn test_ech_bce_applies_background_color() {
    let mut term = crate::TerminalCore::new(3, 10);
    term.current_attrs.background = Color::Named(NamedColor::Red);
    let row = 1;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('I'));
        }
    }
    term.screen.move_cursor(row, 2);
    term.advance(b"\x1b[3X"); // ECH 3: erase cols 2, 3, 4
    assert_line_char!(term, row row, cols 2..5, ' ', "ECH BCE: erased region blank");
    assert_line_bg!(term, row row, cols 2..5, Color::Named(NamedColor::Red), "ECH BCE: erased region has Red bg");
    assert_line_char!(term, row row, cols 0..2, 'I', "ECH BCE: before cursor unchanged");
    assert_line_char!(term, row row, cols 5..10, 'I', "ECH BCE: after erased region unchanged");
}

/// Writing multiple characters then EL 0 erases from cursor to end; the previously-
/// written region before the cursor is preserved.  This also verifies that the
/// EL erase boundary is exactly at the cursor column, not offset by one.
#[test]
fn test_written_chars_followed_by_el0_preserves_prefix() {
    let mut term = crate::TerminalCore::new(3, 20);
    // Print 6 'J's at cols 0-5; cursor lands at col 6.
    term.advance(b"JJJJJJ");
    assert_line_char!(term, row 0, cols 0..6, 'J', "print: cols 0-5 should be 'J'");
    assert_eq!(
        term.screen.cursor().col,
        6,
        "cursor must be at col 6 after printing 6 chars"
    );
    // Erase from cursor (col 6) to end of line.
    term.advance(b"\x1b[K"); // EL 0
                             // Cols 0-5 were written before cursor — unchanged.
    assert_line_char!(term, row 0, cols 0..6, 'J', "after EL0: written region unchanged");
    // Cols 6-19 should be blank.
    assert_line_char!(term, row 0, cols 6..20, ' ', "after EL0: from cursor to EOL cleared");
}

/// EL unknown mode (e.g. mode 5) must be silently ignored — no panic, line unchanged.
#[test]
fn test_el_unknown_mode_is_noop() {
    let mut term = crate::TerminalCore::new(3, 10);
    let row = 0;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('K'));
        }
    }
    term.screen.move_cursor(row, 5);
    term.advance(b"\x1b[5K"); // EL 5: unknown mode

    assert_line_char!(term, row row, cols 0..10, 'K', "EL unknown mode: all cells unchanged");
}
