//! Property-based and example-based tests for `erase` parsing.
//!
//! Module under test: `parser/erase.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;
use crate::types::cell::CellWidth;
use crate::types::{Cell, Color, NamedColor, SgrAttributes};

// ── Local test-only macros ─────────────────────────────────────────────────

/// Create a `TerminalCore` and flood every cell with `$ch`.
macro_rules! term_filled {
    ($rows:literal x $cols:literal, $ch:expr) => {{
        let mut _t = crate::TerminalCore::new($rows, $cols);
        for _r in 0..$rows {
            for _c in 0..$cols {
                if let Some(_line) = _t.screen.get_line_mut(_r) {
                    _line.update_cell_with(_c, Cell::new($ch));
                }
            }
        }
        _t
    }};
}

/// Assert that every cell in `$row_range × $col_range` has char `$ch`.
macro_rules! assert_row_range_char {
    ($term:expr, rows $rr:expr, cols $cr:expr, $ch:expr, $msg:literal) => {
        for _r in $rr {
            let _line = $term.screen.get_line(_r).unwrap();
            for _c in $cr {
                assert_eq!(
                    _line.cells[_c].char(),
                    $ch,
                    concat!($msg, " (row={}, col={})"),
                    _r,
                    _c
                );
            }
        }
    };
}

/// Assert every cell in a single `$row` across `$col_range` has char `$ch`.
macro_rules! assert_line_char {
    ($term:expr, row $r:expr, cols $cr:expr, $ch:expr, $msg:literal) => {
        let _line = $term.screen.get_line($r).unwrap();
        for _c in $cr {
            assert_eq!(_line.cells[_c].char(), $ch, concat!($msg, " (col={})"), _c);
        }
    };
}

/// Assert every cell in a single `$row` across `$col_range` has background color `$bg`.
macro_rules! assert_line_bg {
    ($term:expr, row $r:expr, cols $cr:expr, $bg:expr, $msg:literal) => {
        let _line = $term.screen.get_line($r).unwrap();
        for _c in $cr {
            assert_eq!(
                _line.cells[_c].attrs.background, $bg,
                concat!($msg, " (col={})"),
                _c
            );
        }
    };
}

/// Assert every cell in `$row_range × $col_range` has background `$bg`.
macro_rules! assert_row_range_bg {
    ($term:expr, rows $rr:expr, cols $cr:expr, $bg:expr, $msg:literal) => {
        for _r in $rr {
            let _line = $term.screen.get_line(_r).unwrap();
            for _c in $cr {
                assert_eq!(
                    _line.cells[_c].attrs.background, $bg,
                    concat!($msg, " (row={}, col={})"),
                    _r, _c
                );
            }
        }
    };
}

/// Assert a single cell's char and width.
macro_rules! assert_cell {
    ($term:expr, row $r:expr, col $c:expr, char $ch:expr, width $w:expr) => {{
        let _line = $term.screen.get_line($r).unwrap();
        assert_eq!(_line.cells[$c].char(), $ch);
        assert_eq!(_line.cells[$c].width, $w);
    }};
    ($term:expr, row $r:expr, col $c:expr, char $ch:expr) => {{
        let _line = $term.screen.get_line($r).unwrap();
        assert_eq!(_line.cells[$c].char(), $ch);
    }};
}

// ── Tests ──────────────────────────────────────────────────────────────────

#[test]
fn test_ed_default() {
    let mut term = term_filled!(5 x 20, 'X');
    term.screen.move_cursor(2, 5);

    let params = vte::Params::default();
    csi_ed(&mut term, &params);

    assert_line_char!(term, row 2, cols 0..5, 'X', "before cursor col unchanged");
    assert_line_char!(term, row 2, cols 5..20, ' ', "from cursor col cleared");
    assert_row_range_char!(term, rows 3..5, cols 0..20, ' ', "rows below cleared");
    assert_row_range_char!(term, rows 0..2, cols 0..20, 'X', "rows above unchanged");
}

#[test]
fn test_ed_mode0() {
    let mut term = term_filled!(3 x 10, 'A');
    term.screen.move_cursor(1, 5);

    let params = vte::Params::default();
    csi_ed(&mut term, &params);

    assert_cell!(term, row 0, col 0, char 'A');
    assert_cell!(term, row 1, col 4, char 'A');
    assert_cell!(term, row 1, col 5, char ' ');
    assert_cell!(term, row 2, col 0, char ' ');
}

#[test]
fn test_ed_mode1() {
    let mut term = term_filled!(3 x 10, 'B');
    term.screen.move_cursor(1, 5);

    term.advance(b"\x1b[1J");

    assert_cell!(term, row 0, col 0, char ' ');
    assert_cell!(term, row 1, col 5, char ' ');
    assert_cell!(term, row 1, col 6, char 'B');
    assert_cell!(term, row 2, col 0, char 'B');
}

#[test]
fn test_ed_mode2() {
    let mut term = term_filled!(3 x 10, 'C');
    term.advance(b"\x1b[2J");

    assert_row_range_char!(term, rows 0..3, cols 0..10, ' ', "entire screen cleared");
}

#[test]
fn test_ed_mode3_clears_scrollback() {
    let mut term = crate::TerminalCore::new(5, 10);
    for _ in 0..5 {
        term.screen
            .scroll_up(1, crate::types::color::Color::Default);
    }
    assert_eq!(term.screen.scrollback_line_count, 5);
    term.advance(b"\x1b[3J");
    assert_eq!(term.screen.scrollback_line_count, 0);
}

#[test]
fn test_el_default() {
    let mut term = crate::TerminalCore::new(5, 20);
    let row = 2;
    for c in 0..20 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('Y'));
        }
    }
    term.screen.move_cursor(row, 5);

    let params = vte::Params::default();
    csi_el(&mut term, &params);

    assert_line_char!(term, row row, cols 0..5, 'Y', "before cursor unchanged");
    assert_line_char!(term, row row, cols 5..20, ' ', "from cursor cleared");
}

#[test]
fn test_el_mode0() {
    let mut term = crate::TerminalCore::new(5, 10);
    let row = 2;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('Z'));
        }
    }
    term.screen.move_cursor(row, 3);

    let params = vte::Params::default();
    csi_el(&mut term, &params);

    assert_cell!(term, row row, col 2, char 'Z');
    assert_cell!(term, row row, col 3, char ' ');
}

#[test]
fn test_el_mode1() {
    let mut term = crate::TerminalCore::new(5, 10);
    let row = 2;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('W'));
        }
    }
    term.screen.move_cursor(row, 5);
    term.advance(b"\x1b[1K");

    assert_cell!(term, row row, col 5, char ' ');
    assert_cell!(term, row row, col 6, char 'W');
}

#[test]
fn test_el_mode2() {
    let mut term = crate::TerminalCore::new(5, 10);
    let row = 2;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('V'));
        }
    }
    term.screen.move_cursor(row, 5);
    term.advance(b"\x1b[2K");

    assert_line_char!(term, row row, cols 0..10, ' ', "entire line cleared");
}

#[test]
fn test_erase_with_default_bg_preserves_default() {
    let mut term = crate::TerminalCore::new(5, 10);
    term.screen.print('A', SgrAttributes::default(), true);
    term.screen.move_cursor(0, 0);
    let params = vte::Params::default();
    csi_el(&mut term, &params);
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), ' ');
    assert_eq!(line.cells[0].attrs.background, Color::Default);
}

#[test]
fn test_erase_with_colored_bg_applies_bce() {
    let mut term = crate::TerminalCore::new(5, 10);
    let attrs = SgrAttributes {
        background: Color::Named(NamedColor::Blue),
        ..Default::default()
    };
    term.current_attrs = attrs;
    term.screen.print('A', attrs, true);
    term.screen.move_cursor(0, 0);
    let params = vte::Params::default();
    csi_el(&mut term, &params);
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), ' ');
    assert_eq!(
        line.cells[0].attrs.background,
        Color::Named(NamedColor::Blue)
    );
}

#[test]
fn test_ed_with_colored_bg_applies_bce() {
    let mut term = term_filled!(5 x 10, 'X');
    term.screen.move_cursor(2, 0);
    term.current_attrs.background = Color::Named(NamedColor::Blue);
    term.advance(b"\x1b[J");

    // Erased rows have Blue background
    assert_row_range_bg!(term, rows 2..5, cols 0..10, Color::Named(NamedColor::Blue), "erased rows have Blue bg");
    assert_row_range_char!(term, rows 2..5, cols 0..10, ' ', "erased rows are blank");
    // Rows above cursor retain original char and default background
    assert_row_range_char!(term, rows 0..2, cols 0..10, 'X', "above-cursor rows unchanged");
    assert_row_range_bg!(term, rows 0..2, cols 0..10, Color::Default, "above-cursor rows have default bg");
}

#[test]
fn test_erase_marks_dirty() {
    let mut term = crate::TerminalCore::new(5, 10);

    let dirty1 = term.screen.take_dirty_lines();
    assert_eq!(dirty1.len(), 0);

    let row = 2;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('T'));
            line.is_dirty = false;
        }
    }

    term.screen.move_cursor(row, 0);
    let params = vte::Params::default();
    csi_el(&mut term, &params);

    let line = term.screen.get_line(row).unwrap();
    assert!(line.is_dirty);

    term.screen.move_cursor(0, 0);
    let params = vte::Params::default();
    csi_ed(&mut term, &params);

    let dirty = term.screen.take_dirty_lines();
    assert!(!dirty.is_empty());
}

#[test]
fn test_el_mode0_splits_wide_char() {
    let mut term = crate::TerminalCore::new(5, 20);
    term.screen
        .print('\u{65E5}', SgrAttributes::default(), true);

    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].width, CellWidth::Full);
    assert_eq!(line.cells[1].width, CellWidth::Wide);

    term.screen.move_cursor(0, 1);
    let params = vte::Params::default();
    csi_el(&mut term, &params);

    assert_cell!(term, row 0, col 0, char ' ', width CellWidth::Half);
    assert_cell!(term, row 0, col 1, char ' ', width CellWidth::Half);
}

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

