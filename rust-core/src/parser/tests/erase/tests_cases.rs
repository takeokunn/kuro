//! Property-based and example-based tests for `erase` parsing.
//!
//! Module under test: `parser/erase.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;
use crate::types::cell::CellWidth;
use crate::types::{Color, NamedColor, SgrAttributes};

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
    fill_cells!(term, row row, cols 0..20, 'Y');
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
    fill_cells!(term, row row, cols 0..10, 'Z');
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
    fill_cells!(term, row row, cols 0..10, 'W');
    term.screen.move_cursor(row, 5);
    term.advance(b"\x1b[1K");

    assert_cell!(term, row row, col 5, char ' ');
    assert_cell!(term, row row, col 6, char 'W');
}

#[test]
fn test_el_mode2() {
    let mut term = crate::TerminalCore::new(5, 10);
    let row = 2;
    fill_cells!(term, row row, cols 0..10, 'V');
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
    assert_row_range_bg!(
        term,
        rows 2..5,
        cols 0..10,
        Color::Named(NamedColor::Blue),
        "erased rows have Blue bg"
    );
    assert_row_range_char!(term, rows 2..5, cols 0..10, ' ', "erased rows are blank");
    // Rows above cursor retain original char and default background
    assert_row_range_char!(term, rows 0..2, cols 0..10, 'X', "above-cursor rows unchanged");
    assert_row_range_bg!(
        term,
        rows 0..2,
        cols 0..10,
        Color::Default,
        "above-cursor rows have default bg"
    );
}

#[test]
fn test_erase_marks_dirty() {
    let mut term = crate::TerminalCore::new(5, 10);

    let dirty1 = term.screen.take_dirty_lines();
    assert_eq!(dirty1.len(), 0);

    let row = 2;
    fill_cells!(term, row row, cols 0..10, 'T');
    if let Some(line) = term.screen.get_line_mut(row) {
        line.is_dirty = false;
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
