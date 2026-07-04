use super::*;

#[test]
fn test_el_mode1_splits_wide_char() {
    let mut term = crate::TerminalCore::new(5, 20);
    fill_cells!(term, row 0, cols 0..4, 'A');
    term.screen.move_cursor(0, 4);
    term.screen
        .print('\u{65E5}', SgrAttributes::default(), true);

    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[4].width, CellWidth::Full);
    assert_eq!(line.cells[5].width, CellWidth::Wide);

    term.screen.move_cursor(0, 4);
    term.advance(b"\x1b[1K");

    let line = term.screen.get_line(0).unwrap();
    for c in 0..=5 {
        assert_eq!(line.cells[c].char(), ' ', "col {c} should be cleared");
        assert_eq!(
            line.cells[c].width,
            CellWidth::Half,
            "col {c} should be Half after clearing"
        );
    }
}

#[test]
fn test_ed_mode0_splits_wide_char() {
    let mut term = crate::TerminalCore::new(3, 20);
    term.screen
        .print('\u{65E5}', SgrAttributes::default(), true);
    term.screen.move_cursor(0, 1);

    let params = vte::Params::default();
    csi_ed(&mut term, &params);

    assert_cell!(term, row 0, col 0, char ' ', width CellWidth::Half);
}

#[test]
fn test_ed_mode1_splits_wide_char() {
    let mut term = crate::TerminalCore::new(3, 20);
    term.screen.move_cursor(0, 4);
    term.screen
        .print('\u{65E5}', SgrAttributes::default(), true);
    term.screen.move_cursor(0, 4);

    term.advance(b"\x1b[1J");

    assert_cell!(term, row 0, col 5, char ' ', width CellWidth::Half);
}

test_el_bce!(
    test_el_mode1_with_colored_bg_applies_bce,
    color NamedColor::Red,
    row 2, fill 'Q',
    cursor_col 5,
    seq b"\x1b[1K",
    |term: &crate::TerminalCore, row: usize| {
        assert_line_bg!(term, row row, cols 0..=5, Color::Named(NamedColor::Red), "EL mode 1: Red bg for cleared cols");
        assert_line_char!(term, row row, cols 0..=5, ' ', "EL mode 1: cleared cells are blank");
        assert_line_char!(term, row row, cols 6..10, 'Q', "EL mode 1: untouched cols keep 'Q'");
    }
);

test_el_bce!(
    test_el_mode2_with_colored_bg_applies_bce,
    color NamedColor::Green,
    row 1, fill 'P',
    cursor_col 3,
    seq b"\x1b[2K",
    |term: &crate::TerminalCore, row: usize| {
        assert_line_bg!(term, row row, cols 0..10, Color::Named(NamedColor::Green), "EL mode 2: Green bg");
        assert_line_char!(term, row row, cols 0..10, ' ', "EL mode 2: all blank");
    }
);

test_ed_bce!(
    test_ed_mode1_with_colored_bg_applies_bce,
    grid 5 x 10, fill 'M',
    color NamedColor::Cyan,
    cursor (2, 5),
    seq b"\x1b[1J",
    |term: &crate::TerminalCore| {
        assert_row_range_bg!(term, rows 0..2, cols 0..10, Color::Named(NamedColor::Cyan), "ED mode 1: fully-erased rows have Cyan bg");
        assert_line_bg!(term, row 2, cols 0..=5, Color::Named(NamedColor::Cyan), "ED mode 1: partial row 2 has Cyan bg");
    }
);

test_ed_bce!(
    test_ed_mode2_with_colored_bg_applies_bce,
    grid 3 x 8, fill 'N',
    color NamedColor::Magenta,
    cursor (0, 0),
    seq b"\x1b[2J",
    |term: &crate::TerminalCore| {
        assert_row_range_bg!(term, rows 0..3, cols 0..8, Color::Named(NamedColor::Magenta), "ED mode 2: Magenta bg");
        assert_row_range_char!(term, rows 0..3, cols 0..8, ' ', "ED mode 2: all blank");
    }
);

/// ED mode 0 with cursor at (0, 0) must clear the entire screen.
#[test]
fn test_ed_mode0_at_origin_clears_whole_screen() {
    let mut term = term_filled!(3 x 10, 'Q');
    term.screen.move_cursor(0, 0);
    term.advance(b"\x1b[J");

    assert_row_range_char!(term, rows 0..3, cols 0..10, ' ', "ED mode 0 at origin: everything blank");
}

/// ED with an unknown mode (e.g. mode 9) must be silently ignored — no panic,
/// screen content unchanged.
#[test]
fn test_ed_unknown_mode_is_noop() {
    let mut term = term_filled!(3 x 10, 'R');
    term.advance(b"\x1b[9J");

    assert_row_range_char!(term, rows 0..3, cols 0..10, 'R', "ED unknown mode: all cells unchanged");
}

/// EL mode 0 with cursor at the last column must erase exactly that one cell.
#[test]
fn test_el_mode0_at_last_column() {
    let mut term = crate::TerminalCore::new(3, 10);
    let row = 1;
    fill_cells!(term, row row, cols 0..10, 'S');
    term.screen.move_cursor(row, 9);
    let params = vte::Params::default();
    csi_el(&mut term, &params);

    assert_line_char!(term, row row, cols 0..9, 'S', "EL mode 0 at last col: cols 0-8 unchanged");
    assert_cell!(term, row row, col 9, char ' ');
}

/// EL mode 1 with cursor at column 0 must erase exactly that one cell.
#[test]
fn test_el_mode1_at_column_zero() {
    let mut term = crate::TerminalCore::new(3, 10);
    let row = 0;
    fill_cells!(term, row row, cols 0..10, 'T');
    term.screen.move_cursor(row, 0);
    term.advance(b"\x1b[1K");

    assert_cell!(term, row row, col 0, char ' ');
    assert_line_char!(term, row row, cols 1..10, 'T', "EL mode 1 at col 0: cols 1-9 unchanged");
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: ED (CSI n J) with any parameter never panics
    fn prop_ed_no_panic(ps in 0u16..=10u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{ps}J").as_bytes());
        prop_assert_eq!(term.screen.rows() as usize, 10);
    }

    #[test]
    // PANIC SAFETY: EL (CSI n K) with any parameter never panics
    fn prop_el_no_panic(ps in 0u16..=10u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{ps}K").as_bytes());
        prop_assert_eq!(term.screen.rows() as usize, 10);
    }

    #[test]
    // PANIC SAFETY: ECH (CSI n X) with any parameter never panics; line width preserved
    fn prop_ech_no_panic(n in 0u16..=300u16, col in 0usize..20usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{n}X").as_bytes());
        prop_assert_eq!(
            term.screen.get_line(0).unwrap().cells.len(),
            20,
            "line width must be preserved after ECH"
        );
    }

    #[test]
    // INVARIANT: ED 2 (erase entire display) leaves all cells blank
    fn prop_ed2_clears_all_cells(row in 0usize..10usize, col in 0usize..20usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        // Write something first
        term.screen.move_cursor(row, col);
        term.screen.print('X', crate::types::cell::SgrAttributes::default(), true);
        // Erase display
        term.advance(b"\x1b[2J");
        for r in 0..10usize {
            for c in 0..20usize {
                prop_assert_eq!(
                    term.screen.get_cell(r, c).unwrap().char(), ' ',
                    "cell ({},{}) must be blank after ED 2", r, c
                );
            }
        }
    }
}
