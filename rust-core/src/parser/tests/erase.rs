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

#[test]
fn test_el_mode1_with_colored_bg_applies_bce() {
    let mut term = crate::TerminalCore::new(5, 10);
    let attrs = SgrAttributes {
        background: Color::Named(NamedColor::Red),
        ..Default::default()
    };
    term.current_attrs = attrs;

    let row = 2;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('Q'));
        }
    }
    term.screen.move_cursor(row, 5);
    term.advance(b"\x1b[1K");

    assert_line_bg!(term, row row, cols 0..=5, Color::Named(NamedColor::Red), "EL mode 1: Red bg for cleared cols");
    assert_line_char!(term, row row, cols 0..=5, ' ', "EL mode 1: cleared cells are blank");
    assert_line_char!(term, row row, cols 6..10, 'Q', "EL mode 1: untouched cols keep 'Q'");
}

#[test]
fn test_el_mode2_with_colored_bg_applies_bce() {
    let mut term = crate::TerminalCore::new(5, 10);
    let attrs = SgrAttributes {
        background: Color::Named(NamedColor::Green),
        ..Default::default()
    };
    term.current_attrs = attrs;

    let row = 1;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('P'));
        }
    }
    term.screen.move_cursor(row, 3);
    term.advance(b"\x1b[2K");

    assert_line_bg!(term, row row, cols 0..10, Color::Named(NamedColor::Green), "EL mode 2: Green bg");
    assert_line_char!(term, row row, cols 0..10, ' ', "EL mode 2: all blank");
}

#[test]
fn test_ed_mode1_with_colored_bg_applies_bce() {
    let mut term = term_filled!(5 x 10, 'M');
    term.current_attrs.background = Color::Named(NamedColor::Cyan);
    term.screen.move_cursor(2, 5);
    term.advance(b"\x1b[1J");

    assert_row_range_bg!(term, rows 0..2, cols 0..10, Color::Named(NamedColor::Cyan), "ED mode 1: fully-erased rows have Cyan bg");
    assert_line_bg!(term, row 2, cols 0..=5, Color::Named(NamedColor::Cyan), "ED mode 1: partial row 2 has Cyan bg");
}

#[test]
fn test_ed_mode2_with_colored_bg_applies_bce() {
    let mut term = term_filled!(3 x 8, 'N');
    term.current_attrs.background = Color::Named(NamedColor::Magenta);
    term.advance(b"\x1b[2J");

    assert_row_range_bg!(term, rows 0..3, cols 0..8, Color::Named(NamedColor::Magenta), "ED mode 2: Magenta bg");
    assert_row_range_char!(term, rows 0..3, cols 0..8, ' ', "ED mode 2: all blank");
}

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
