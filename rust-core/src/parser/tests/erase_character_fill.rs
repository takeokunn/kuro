// ── New tests (Round 34) ──────────────────────────────────────────────────────

/// Fill row 0 of a `TerminalCore::new(3, $cols)` with `$fill_ch`, position the
/// cursor at `(0, $cursor_col)`, advance `$seq`, then run `$assertions` (a
/// closure receiving `&term`).  Used to consolidate ECH tests.
macro_rules! test_ech {
    (
        $name:ident,
        cols $cols:literal, fill $fill_ch:expr,
        cursor_col $cursor_col:expr,
        seq $seq:expr,
        $assertions:expr
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(3, $cols);
            for c in 0..$cols {
                if let Some(line) = term.screen.get_line_mut(0) {
                    line.update_cell_with(c, Cell::new($fill_ch));
                }
            }
            term.screen.move_cursor(0, $cursor_col);
            term.advance($seq);
            $assertions(&term);
        }
    };
}

/// Fill row `$row` of a `TerminalCore::new(3, 10)` with `$fill_ch`, position
/// the cursor at `($row, $cursor_col)`, advance `$seq`, then run `$assertions`
/// (a closure receiving `&term` and `row: usize`).  Used to consolidate EL
/// cursor-position tests.
macro_rules! test_el_r34 {
    (
        $name:ident,
        row $row:expr, fill $fill_ch:expr,
        cursor_col $cursor_col:expr,
        seq $seq:expr,
        $assertions:expr
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(3, 10);
            let row: usize = $row;
            for c in 0..10 {
                if let Some(line) = term.screen.get_line_mut(row) {
                    line.update_cell_with(c, Cell::new($fill_ch));
                }
            }
            term.screen.move_cursor(row, $cursor_col);
            term.advance($seq);
            $assertions(&term, row);
        }
    };
}

// ED 0 erases from cursor to end of screen; rows above cursor and cols left
// of cursor on the cursor row are untouched.
#[test]
fn test_ed0_erases_from_cursor_to_end_of_screen() {
    let mut term = term_filled!(4 x 8, 'P');
    term.screen.move_cursor(1, 3);
    let params = vte::Params::default();
    csi_ed(&mut term, &params); // ED 0

    // Rows above cursor: all untouched
    assert_row_range_char!(term, rows 0..1, cols 0..8, 'P', "row 0 fully unchanged");
    // Cursor row: cols before cursor unchanged; from cursor cleared
    assert_line_char!(term, row 1, cols 0..3, 'P', "row 1 before cursor unchanged");
    assert_line_char!(term, row 1, cols 3..8, ' ', "row 1 from cursor cleared");
    // Rows below cursor: all cleared
    assert_row_range_char!(term, rows 2..4, cols 0..8, ' ', "rows 2-3 cleared");
}

// ED 1 erases from start of screen to cursor (inclusive); rows below cursor
// and cols right of cursor on the cursor row are untouched.
#[test]
fn test_ed1_erases_from_start_to_cursor() {
    let mut term = term_filled!(4 x 8, 'Q');
    term.screen.move_cursor(2, 4);
    term.advance(b"\x1b[1J");

    // Rows fully above cursor: all cleared
    assert_row_range_char!(term, rows 0..2, cols 0..8, ' ', "rows 0-1 fully cleared");
    // Cursor row: up to and including cursor cleared; after cursor unchanged
    assert_line_char!(term, row 2, cols 0..=4, ' ', "row 2 up to cursor cleared");
    assert_line_char!(term, row 2, cols 5..8, 'Q', "row 2 after cursor unchanged");
    // Row below cursor: untouched
    assert_row_range_char!(term, rows 3..4, cols 0..8, 'Q', "row 3 unchanged");
}

// ED 2 erases the entire screen; cursor position is NOT changed.
#[test]
fn test_ed2_erases_entire_screen_without_moving_cursor() {
    let mut term = term_filled!(4 x 8, 'R');
    term.screen.move_cursor(2, 5);
    term.advance(b"\x1b[2J");

    assert_row_range_char!(term, rows 0..4, cols 0..8, ' ', "all cells cleared");
    // Cursor must remain at (2, 5)
    assert_eq!(term.screen.cursor().row, 2, "ED 2 must not move cursor row");
    assert_eq!(term.screen.cursor().col, 5, "ED 2 must not move cursor col");
}

// EL 0 erases from cursor to end of line; cells to the left are untouched;
// cursor position is unchanged.
test_el_r34!(
    test_el0_erases_from_cursor_to_end_of_line,
    row 1, fill 'S',
    cursor_col 4,
    seq b"\x1b[K",
    |term: &crate::TerminalCore, row: usize| {
        assert_line_char!(term, row row, cols 0..4, 'S', "cols before cursor unchanged");
        assert_line_char!(term, row row, cols 4..10, ' ', "cols from cursor cleared");
        assert_eq!(term.screen.cursor().col, 4, "EL 0 must not move cursor");
    }
);

// EL 1 erases from start of line to cursor (inclusive); cells after cursor
// are untouched; cursor position is unchanged.
test_el_r34!(
    test_el1_erases_from_start_to_cursor,
    row 0, fill 'T',
    cursor_col 5,
    seq b"\x1b[1K",
    |term: &crate::TerminalCore, row: usize| {
        assert_line_char!(term, row row, cols 0..=5, ' ', "cols 0..=5 cleared");
        assert_line_char!(term, row row, cols 6..10, 'T', "cols after cursor unchanged");
        assert_eq!(term.screen.cursor().col, 5, "EL 1 must not move cursor");
    }
);

// EL 2 erases the entire line regardless of cursor position; cursor is NOT moved.
test_el_r34!(
    test_el2_erases_entire_line_without_moving_cursor,
    row 2, fill 'U',
    cursor_col 7,
    seq b"\x1b[2K",
    |term: &crate::TerminalCore, row: usize| {
        assert_line_char!(term, row row, cols 0..10, ' ', "entire line cleared");
        assert_eq!(term.screen.cursor().row, row, "EL 2 must not move cursor row");
        assert_eq!(term.screen.cursor().col, 7, "EL 2 must not move cursor col");
    }
);

// ECH erases exactly N characters at the cursor position; cells to the
// left and right of the erased range are untouched; cursor does not move.
test_ech!(
    test_ech_erases_n_chars_at_cursor,
    cols 12, fill 'V',
    cursor_col 4,
    seq b"\x1b[3X",
    |term: &crate::TerminalCore| {
        assert_line_char!(term, row 0, cols 0..4, 'V', "before erased range unchanged");
        assert_line_char!(term, row 0, cols 4..7, ' ', "erased range is blank");
        assert_line_char!(term, row 0, cols 7..12, 'V', "after erased range unchanged");
        assert_eq!(term.screen.cursor().col, 4, "ECH must not move cursor");
    }
);

// ECH with count exceeding the line width from cursor: all cols from cursor
// to end of line are erased; no panic; cursor stays at its position.
test_ech!(
    test_ech_count_exceeds_line_width_clamps_to_end,
    cols 10, fill 'W',
    cursor_col 6,
    seq b"\x1b[999X",
    |term: &crate::TerminalCore| {
        assert_line_char!(term, row 0, cols 0..6, 'W', "before cursor unchanged");
        assert_line_char!(term, row 0, cols 6..10, ' ', "cols 6..10 erased");
        assert_eq!(term.screen.cursor().col, 6, "ECH must not move cursor");
        assert_eq!(term.screen.get_line(0).unwrap().cells.len(), 10);
    }
);

// ED 0 with a non-default SGR background (BCE): erased cells carry the
// current background; cells above the cursor retain their default background.
#[test]
fn test_ed0_with_bce_colors_erased_region() {
    let mut term = term_filled!(4 x 6, 'X');
    term.current_attrs.background = Color::Named(NamedColor::Yellow);
    term.screen.move_cursor(2, 3);
    term.advance(b"\x1b[J"); // ED 0

    // Cells above cursor row retain original content and default background
    assert_row_range_char!(term, rows 0..2, cols 0..6, 'X', "above cursor: content unchanged");
    assert_row_range_bg!(
        term,
        rows 0..2,
        cols 0..6,
        Color::Default,
        "above cursor: default bg"
    );
    // Cursor row (partial) and rows below: BCE background applied
    assert_line_char!(term, row 2, cols 3..6, ' ', "cursor row from cursor: cleared");
    assert_line_bg!(
        term,
        row 2,
        cols 3..6,
        Color::Named(NamedColor::Yellow),
        "cursor row from cursor: BCE bg"
    );
    assert_row_range_bg!(
        term,
        rows 3..4,
        cols 0..6,
        Color::Named(NamedColor::Yellow),
        "below cursor: BCE bg"
    );
}

// EL 2 with a non-default SGR background (BCE): the entire line gets erased
// and each erased cell carries the current SGR background color.
#[test]
fn test_el2_with_bce_colors_entire_line() {
    let mut term = crate::TerminalCore::new(3, 8);
    for c in 0..8 {
        if let Some(line) = term.screen.get_line_mut(1) {
            line.update_cell_with(c, Cell::new('Y'));
        }
    }
    term.current_attrs.background = Color::Named(NamedColor::Magenta);
    term.screen.move_cursor(1, 3);
    term.advance(b"\x1b[2K"); // EL 2

    assert_line_char!(term, row 1, cols 0..8, ' ', "entire line cleared");
    assert_line_bg!(
        term,
        row 1,
        cols 0..8,
        Color::Named(NamedColor::Magenta),
        "entire line has BCE bg"
    );
    // Other rows must be unaffected (default bg)
    assert_row_range_bg!(
        term,
        rows 0..1,
        cols 0..8,
        Color::Default,
        "row 0 has default bg"
    );
    assert_row_range_bg!(
        term,
        rows 2..3,
        cols 0..8,
        Color::Default,
        "row 2 has default bg"
    );
}
