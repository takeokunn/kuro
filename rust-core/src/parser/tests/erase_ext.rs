#[test]
fn test_el_mode1_splits_wide_char() {
    let mut term = crate::TerminalCore::new(5, 20);
    for c in 0..4 {
        if let Some(line) = term.screen.get_line_mut(0) {
            line.update_cell_with(c, Cell::new('A'));
        }
    }
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

/// Test that an EL sequence with a non-default SGR background applies BCE.
///
/// Sets `current_attrs` to the given color, fills `$row` with `$fill_ch`,
/// positions the cursor at (`$row`, `$cursor_col`), advances `$seq`, then
/// runs `$assertions` (a block receiving `term` and `row`).
macro_rules! test_el_bce {
    (
        $name:ident,
        color $color:expr,
        row $row:expr, fill $fill_ch:expr,
        cursor_col $cursor_col:expr,
        seq $seq:expr,
        $assertions:expr
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(5, 10);
            let attrs = SgrAttributes {
                background: Color::Named($color),
                ..Default::default()
            };
            term.current_attrs = attrs;
            let row = $row;
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

/// Fill a `term_filled!($rows x $cols, $fill_ch)` screen, set the current
/// background to `Color::Named($color)`, position the cursor at
/// `($cursor_row, $cursor_col)`, advance `$seq`, then run `$assertions` (a
/// closure receiving `&term`).  Used to consolidate ED BCE background tests.
macro_rules! test_ed_bce {
    (
        $name:ident,
        grid $rows:literal x $cols:literal, fill $fill_ch:expr,
        color $color:expr,
        cursor ($cursor_row:expr, $cursor_col:expr),
        seq $seq:expr,
        $assertions:expr
    ) => {
        #[test]
        fn $name() {
            let mut term = term_filled!($rows x $cols, $fill_ch);
            term.current_attrs.background = Color::Named($color);
            term.screen.move_cursor($cursor_row, $cursor_col);
            term.advance($seq);
            $assertions(&term);
        }
    };
}

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
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('S'));
        }
    }
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
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('T'));
        }
    }
    term.screen.move_cursor(row, 0);
    term.advance(b"\x1b[1K");

    assert_cell!(term, row row, col 0, char ' ');
    assert_line_char!(term, row row, cols 1..10, 'T', "EL mode 1 at col 0: cols 1-9 unchanged");
}

include!("erase_minimal_terminal.rs");

use proptest::prelude::*;

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

include!("erase_character_fill.rs");

// ── DECCARA ────────────────────────────────────────────────────────────────

#[test]
fn deccara_applies_bold_to_rectangle() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill rows 1-3, cols 2-5 via: CSI 2;3;4;6;1 $ r  (1-indexed, bold=1)
    term.advance(b"\x1b[2;3;4;6;1$r");
    for r in 1..4usize {
        let line = term.screen.get_line(r).unwrap();
        for c in 2..6usize {
            assert!(
                line.cells[c].attrs.flags.contains(SgrFlags::BOLD),
                "cell ({r},{c}) must be bold after DECCARA"
            );
        }
    }
    // cells outside rect must NOT be bold
    let line0 = term.screen.get_line(0).unwrap();
    assert!(!line0.cells[0].attrs.flags.contains(SgrFlags::BOLD), "row 0 outside rect");
}

#[test]
fn deccara_applies_red_foreground() {
    use crate::types::{Color, NamedColor};
    let mut term = crate::TerminalCore::new(4, 8);
    // CSI 1;1;2;8;31 $ r  → rows 0-1, cols 0-7, SGR 31 (red fg)
    term.advance(b"\x1b[1;1;2;8;31$r");
    for r in 0..2usize {
        let line = term.screen.get_line(r).unwrap();
        for c in 0..8usize {
            assert_eq!(
                line.cells[c].attrs.foreground,
                Color::Named(NamedColor::Red),
                "cell ({r},{c}) must have red fg"
            );
        }
    }
    // row 2 unaffected
    let line2 = term.screen.get_line(2).unwrap();
    for c in 0..8usize {
        assert_ne!(
            line2.cells[c].attrs.foreground,
            Color::Named(NamedColor::Red),
            "row 2 outside rect must not be red"
        );
    }
}

#[test]
fn deccara_reset_clears_attributes() {
    use crate::types::cell::SgrFlags;
    let mut term = crate::TerminalCore::new(3, 6);
    // First apply bold
    term.advance(b"\x1b[1;1;3;6;1$r");
    // Then reset with SGR 0
    term.advance(b"\x1b[1;1;3;6;0$r");
    for r in 0..3usize {
        let line = term.screen.get_line(r).unwrap();
        for c in 0..6usize {
            assert!(
                !line.cells[c].attrs.flags.contains(SgrFlags::BOLD),
                "cell ({r},{c}) must not be bold after DECCARA reset"
            );
        }
    }
}

#[test]
fn deccara_oob_coords_clamped() {
    // Out-of-bounds coordinates must not panic; they are clamped to screen size.
    let mut term = crate::TerminalCore::new(5, 10);
    term.advance(b"\x1b[0;0;999;999;1$r");
}

#[test]
fn deccara_inverted_rect_is_noop() {
    // When bottom < top (inverted row order), DECCARA must be a silent no-op.
    // CSI 4;1;2;5;1 $ r  → top=3, left=0, bottom=1, right=4 (bottom < top).
    // No cell should become bold.
    let mut term = crate::TerminalCore::new(5, 10);
    term.advance(b"\x1b[4;1;2;5;1$r");
    for r in 0..5usize {
        if let Some(line) = term.screen.get_line(r) {
            for c in 0..10usize {
                assert!(
                    !line.cells[c].attrs.flags.contains(SgrFlags::BOLD),
                    "cell ({r},{c}) must not be bold after inverted-rect DECCARA"
                );
            }
        }
    }
}

// ── XTPUSHCOLORS / XTPOPCOLORS ─────────────────────────────────────────────

#[test]
fn xtpushcolors_saves_palette_and_xtpopcolors_restores_it() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Set palette index 1 via OSC 4
    term.advance(b"\x1b]4;1;rgb:ff/00/00\x07");
    assert_eq!(term.osc_data.palette[1], Some([0xff, 0x00, 0x00]));

    // Push palette
    term.advance(b"\x1b[#P");
    assert_eq!(term.osc_data.palette_stack.len(), 1);

    // Change palette entry 1
    term.advance(b"\x1b]4;1;rgb:00/ff/00\x07");
    assert_eq!(term.osc_data.palette[1], Some([0x00, 0xff, 0x00]));

    // Pop restores original
    term.advance(b"\x1b[#Q");
    assert_eq!(term.osc_data.palette_stack.len(), 0);
    assert_eq!(term.osc_data.palette[1], Some([0xff, 0x00, 0x00]));
    assert!(term.osc_data.palette_dirty);
}

#[test]
fn xtreportcolors_reports_stack_depth() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Initially depth 0
    term.advance(b"\x1b[#R");
    assert_eq!(term.meta.pending_responses.last().unwrap(), b"\x1b[0#S");

    // Push once
    term.advance(b"\x1b[#P");
    term.advance(b"\x1b[#R");
    assert_eq!(term.meta.pending_responses.last().unwrap(), b"\x1b[1#S");
}

#[test]
fn xtpushcolors_capped_at_10() {
    let mut term = crate::TerminalCore::new(5, 10);
    for _ in 0..15 {
        term.advance(b"\x1b[#P");
    }
    assert_eq!(
        term.osc_data.palette_stack.len(),
        10,
        "palette stack must be capped at 10"
    );
}

#[test]
fn xtpopcolors_on_empty_stack_is_noop() {
    // XTPOPCOLORS (CSI # Q) on an empty stack must be a no-op: no panic,
    // palette unchanged, palette_dirty stays false.
    let mut term = crate::TerminalCore::new(5, 10);
    // Set a known palette entry so we can confirm it is unchanged.
    term.advance(b"\x1b]4;7;rgb:aa/bb/cc\x07");
    assert_eq!(term.osc_data.palette[7], Some([0xaa, 0xbb, 0xcc]));
    assert!(term.osc_data.palette_stack.is_empty());
    // Pop on empty stack — must not panic and palette must survive.
    term.advance(b"\x1b[#Q");
    assert_eq!(
        term.osc_data.palette[7],
        Some([0xaa, 0xbb, 0xcc]),
        "palette must be unchanged after XTPOPCOLORS on empty stack"
    );
}
