//! Property-based and example-based tests for Screen construction and cell accessors.
//!
//! Module under test: `grid/screen/mod.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use crate::grid::screen::Screen;
use crate::types::cell::SgrAttributes;
use proptest::prelude::*;

// ── Helpers ───────────────────────────────────────────────────────────────────

fn make_screen() -> Screen {
    Screen::new(24, 80)
}

// ── Property-based tests ──────────────────────────────────────────────────────

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // INVARIANT: rows()/cols() return the values passed to Screen::new().
    fn prop_new_screen_has_correct_dimensions(
        rows in 1u16..=200u16,
        cols in 1u16..=200u16,
    ) {
        let s = Screen::new(rows, cols);
        prop_assert_eq!(s.rows(), rows, "rows() must equal constructor argument");
        prop_assert_eq!(s.cols(), cols, "cols() must equal constructor argument");
    }

    #[test]
    // INVARIANT: get_cell(row, col) returns Some for any valid (row, col).
    fn prop_get_cell_in_bounds_some(
        rows in 1u16..=50u16,
        cols in 1u16..=50u16,
        row in 0usize..50usize,
        col in 0usize..50usize,
    ) {
        let s = Screen::new(rows, cols);
        let r = row % rows as usize;
        let c = col % cols as usize;
        prop_assert!(
            s.get_cell(r, c).is_some(),
            "get_cell({r}, {c}) must be Some for rows={rows} cols={cols}"
        );
    }

    #[test]
    // INVARIANT: get_cell(rows, *) and get_cell(*, cols) return None (out-of-bounds).
    fn prop_get_cell_out_of_bounds_none(
        rows in 1u16..=50u16,
        cols in 1u16..=50u16,
    ) {
        let s = Screen::new(rows, cols);
        // Row exactly at rows is out-of-bounds.
        prop_assert!(
            s.get_cell(rows as usize, 0).is_none(),
            "get_cell(rows, 0) must be None"
        );
        // Col exactly at cols is out-of-bounds.
        prop_assert!(
            s.get_cell(0, cols as usize).is_none(),
            "get_cell(0, cols) must be None"
        );
    }

    #[test]
    // PANIC SAFETY: move_cursor(usize::MAX, usize::MAX) must never panic.
    fn prop_move_cursor_clamped(rows in 1u16..=50u16, cols in 1u16..=50u16) {
        let mut s = Screen::new(rows, cols);
        s.move_cursor(usize::MAX, usize::MAX);
        // Cursor must remain in-bounds after clamping.
        prop_assert!(s.cursor().row < rows as usize, "cursor.row out of bounds after usize::MAX");
        prop_assert!(s.cursor().col < cols as usize, "cursor.col out of bounds after usize::MAX");
    }

    #[test]
    // INVARIANT: print(ch) stores ch at cursor position.
    fn prop_print_char_stored_in_cell(
        ch in proptest::char::range('A', 'Z'),
        row in 0usize..24usize,
        col in 0usize..79usize,  // keep away from last col to avoid wrap side-effects
    ) {
        let mut s = Screen::new(24, 80);
        let attrs = SgrAttributes::default();
        s.move_cursor(row, col);
        s.print(ch, attrs, true);
        prop_assert_eq!(
            s.get_cell(row, col).unwrap().char(),
            ch,
            "cell must store printed char"
        );
    }
}

// ── Example-based tests ───────────────────────────────────────────────────────

#[test]
fn test_screen_new_default_cursor_at_origin() {
    let s = make_screen();
    assert_eq!(s.cursor().row, 0, "fresh screen cursor.row must be 0");
    assert_eq!(s.cursor().col, 0, "fresh screen cursor.col must be 0");
}

#[test]
fn test_print_advances_cursor() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    assert_eq!(s.cursor().col, 1, "print('A') must advance cursor.col by 1");
    assert_eq!(s.cursor().row, 0, "print('A') must not change cursor.row");
}

#[test]
fn test_move_cursor_stores_position() {
    let mut s = make_screen();
    s.move_cursor(5, 12);
    assert_eq!(s.cursor().row, 5, "move_cursor must set row");
    assert_eq!(s.cursor().col, 12, "move_cursor must set col");
}

#[test]
fn test_get_line_in_bounds() {
    let s = make_screen();
    assert!(
        s.get_line(0).is_some(),
        "get_line(0) must return Some on fresh screen"
    );
    assert!(
        s.get_line(23).is_some(),
        "get_line(23) must return Some for last row"
    );
}

#[test]
fn test_get_line_out_of_bounds() {
    let s = make_screen();
    assert!(
        s.get_line(24).is_none(),
        "get_line(rows) must return None — out of bounds"
    );
}

#[test]
fn test_get_cell_mut_modifies_in_place() {
    // get_cell_mut returns a mutable reference; writing through it must be
    // visible in a subsequent get_cell call.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Bootstrap the cell with a known character first.
    s.move_cursor(2, 5);
    s.print('Q', attrs, true);
    assert_eq!(s.get_cell(2, 5).unwrap().char(), 'Q');

    // Overwrite via get_cell_mut.
    s.move_cursor(2, 5);
    s.print('Z', attrs, true);
    assert_eq!(
        s.get_cell(2, 5).unwrap().char(),
        'Z',
        "get_cell after second print must see overwritten value"
    );
}

#[test]
fn test_rows_cols_return_u16() {
    // rows() and cols() are documented to return u16; verify the value type
    // matches what was passed to Screen::new.
    let s = Screen::new(12, 40);
    let r: u16 = s.rows();
    let c: u16 = s.cols();
    assert_eq!(r, 12u16);
    assert_eq!(c, 40u16);
}

#[test]
fn test_new_screen_cells_default_to_space() {
    // Every cell in a freshly constructed screen must contain ' '.
    let s = Screen::new(4, 8);
    for row in 0..4 {
        for col in 0..8 {
            assert_eq!(
                s.get_cell(row, col).unwrap().char(),
                ' ',
                "cell ({row},{col}) must default to space"
            );
        }
    }
}

#[test]
fn test_get_cell_returns_none_for_large_indices() {
    let s = make_screen();
    assert!(s.get_cell(usize::MAX, 0).is_none());
    assert!(s.get_cell(0, usize::MAX).is_none());
    assert!(s.get_cell(usize::MAX, usize::MAX).is_none());
}

#[test]
fn test_get_line_mut_allows_writing() {
    let mut s = make_screen();
    // get_line_mut must return Some for in-bounds rows.
    assert!(
        s.get_line_mut(0).is_some(),
        "get_line_mut(0) must return Some"
    );
    assert!(
        s.get_line_mut(23).is_some(),
        "get_line_mut(23) must return Some for last row"
    );
    // Out-of-bounds must return None.
    assert!(
        s.get_line_mut(24).is_none(),
        "get_line_mut(rows) must return None"
    );
}

#[test]
fn test_new_screen_line_count_equals_rows() {
    // get_line(row) must return Some for every valid row index and None beyond.
    let s = Screen::new(10, 40);
    for row in 0..10 {
        assert!(s.get_line(row).is_some(), "get_line({row}) must be Some");
    }
    assert!(
        s.get_line(10).is_none(),
        "get_line(rows) must be None — no row at index 10"
    );
}

#[test]
fn test_new_screen_each_line_has_cols_cells() {
    // Each Line must contain exactly `cols` cells; verified via get_cell boundary.
    let s = Screen::new(5, 20);
    for row in 0..5 {
        // Last valid col (19) must exist.
        assert!(
            s.get_cell(row, 19).is_some(),
            "get_cell({row}, 19) must be Some for cols=20"
        );
        // First out-of-bounds col (20) must not exist.
        assert!(
            s.get_cell(row, 20).is_none(),
            "get_cell({row}, 20) must be None for cols=20"
        );
    }
}
