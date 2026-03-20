//! Property-based tests for `Line`.
//!
//! These tests complement the 5 example-based unit tests embedded in
//! `src/grid/line.rs` by verifying invariants across randomly generated
//! inputs (proptest T2 tier: 500 cases each).

use crate::grid::line::Line;
use crate::types::{Cell, Color, SgrAttributes};
use proptest::prelude::*;

/// Generate an arbitrary `Color` from the three non-`Default` variants
/// plus `Default` itself.
fn arb_color() -> impl Strategy<Value = Color> {
    prop_oneof![
        Just(Color::Default),
        Just(Color::Indexed(1)),
        Just(Color::Rgb(255, 0, 128)),
        Just(Color::Indexed(200)),
    ]
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    // INVARIANT: Line::new(cols) produces exactly cols cells.
    fn prop_new_cell_count(cols in 1usize..200usize) {
        let line = Line::new(cols);
        prop_assert_eq!(line.cells.len(), cols);
    }

    #[test]
    // INVARIANT: Freshly created lines (both constructors) are clean (is_dirty == false).
    fn prop_new_is_clean(cols in 1usize..200usize, bg in arb_color()) {
        let line_plain = Line::new(cols);
        prop_assert!(!line_plain.is_dirty, "Line::new must start clean");

        let line_bg = Line::new_with_bg(cols, bg);
        prop_assert!(!line_bg.is_dirty, "Line::new_with_bg must start clean");
    }

    #[test]
    // BOUNDARY: get_cell returns Some for col < len and None for col >= len.
    fn prop_get_cell_bounds(cols in 1usize..100usize, col in 0usize..200usize) {
        let line = Line::new(cols);
        if col < cols {
            prop_assert!(line.get_cell(col).is_some(),
                "get_cell({}) must be Some for a line of {} cols", col, cols);
        } else {
            prop_assert!(line.get_cell(col).is_none(),
                "get_cell({}) must be None for a line of {} cols", col, cols);
        }
    }

    #[test]
    // INVARIANT: update_cell on a valid column marks the line dirty.
    fn prop_update_cell_marks_dirty(cols in 1usize..100usize, col in 0usize..100usize) {
        // Only test columns that are in-bounds.
        let col = col % cols;
        let mut line = Line::new(cols);
        // Default cell holds ' '; writing 'X' is guaranteed to differ.
        line.update_cell(col, 'X', SgrAttributes::default());
        prop_assert!(line.is_dirty,
            "update_cell must set is_dirty after changing grapheme");
    }

    #[test]
    // INVARIANT: After clear(), every cell equals Cell::default() and is_dirty == true.
    fn prop_clear_all_default(cols in 1usize..100usize) {
        let mut line = Line::new(cols);
        // Dirty up some cells so clear() has real work to do.
        for i in 0..cols {
            if i % 3 == 0 {
                line.update_cell(i, 'Q', SgrAttributes::default());
            }
        }
        line.clear();
        prop_assert!(line.is_dirty, "clear() must set is_dirty");
        let expected = Cell::default();
        for (i, cell) in line.cells.iter().enumerate() {
            prop_assert_eq!(cell, &expected,
                "cell at col {} is not Cell::default() after clear()", i);
        }
    }

    #[test]
    // INVARIANT: After clear_with_bg(bg), all cells carry attrs.background == bg,
    // and is_dirty == true.
    fn prop_clear_with_bg_applies_background(
        cols in 1usize..100usize,
        bg in arb_color(),
    ) {
        let mut line = Line::new(cols);
        line.clear_with_bg(bg);
        prop_assert!(line.is_dirty, "clear_with_bg() must set is_dirty");
        for (i, cell) in line.cells.iter().enumerate() {
            prop_assert_eq!(cell.attrs.background, bg,
                "cell at col {} has wrong background after clear_with_bg()", i);
        }
    }

    #[test]
    // INVARIANT: resize(n) where n >= current_len expands cells to exactly n.
    fn prop_resize_up_preserves_len(
        cols in 1usize..100usize,
        extra in 0usize..100usize,
    ) {
        let mut line = Line::new(cols);
        let new_cols = cols + extra;
        line.resize(new_cols);
        prop_assert_eq!(line.cells.len(), new_cols,
            "resize({}) on a {}-col line must yield {} cells", new_cols, cols, new_cols);
    }

    #[test]
    // INVARIANT: resize(n) where n < current_len truncates cells to exactly n.
    fn prop_resize_down_truncates(
        cols in 2usize..100usize,
        shrink in 1usize..100usize,
    ) {
        // Clamp so new_cols is at least 1 and strictly less than cols.
        let new_cols = (cols.saturating_sub(shrink)).max(1);
        prop_assume!(new_cols < cols);
        let mut line = Line::new(cols);
        line.resize(new_cols);
        prop_assert_eq!(line.cells.len(), new_cols,
            "resize({}) on a {}-col line must yield {} cells", new_cols, cols, new_cols);
    }

    #[test]
    // INVARIANT: mark_dirty() sets is_dirty=true; mark_clean() sets is_dirty=false.
    fn prop_mark_dirty_clean_toggle(cols in 1usize..100usize) {
        let mut line = Line::new(cols);
        prop_assert!(!line.is_dirty, "new line must start clean");
        line.mark_dirty();
        prop_assert!(line.is_dirty, "mark_dirty() must set is_dirty");
        line.mark_clean();
        prop_assert!(!line.is_dirty, "mark_clean() must clear is_dirty");
        // Second round: start from dirty state.
        line.mark_dirty();
        prop_assert!(line.is_dirty);
        line.mark_clean();
        prop_assert!(!line.is_dirty);
    }
}

// ── Example-based regression ────────────────────────────────────────────────

#[test]
// new_with_bg(Color::Default) must produce a line identical to Line::new.
fn new_with_bg_default_equals_new() {
    let cols = 40usize;
    let plain = Line::new(cols);
    let with_default_bg = Line::new_with_bg(cols, Color::Default);
    assert_eq!(plain.cells.len(), with_default_bg.cells.len());
    assert_eq!(plain.is_dirty, with_default_bg.is_dirty);
    for (i, (a, b)) in plain.cells.iter().zip(with_default_bg.cells.iter()).enumerate() {
        assert_eq!(a, b, "cell mismatch at col {}", i);
    }
}

#[test]
// NO-OP BRANCH: Writing the same grapheme+attrs that a cell already holds
// must NOT set is_dirty (the early-return guard on line 65 of line.rs).
fn test_update_cell_same_content_stays_clean() {
    let cols = 10usize;
    let mut line = Line::new(cols);
    let attrs = SgrAttributes::default();

    // Write 'A' to col 3 — this makes the line dirty.
    line.update_cell(3, 'A', attrs);
    // Reset the dirty flag so we can observe the no-op.
    line.mark_clean();
    assert!(!line.is_dirty, "mark_clean must clear is_dirty");

    // Write the same 'A' + same attrs again — must be a no-op.
    line.update_cell(3, 'A', attrs);
    assert!(
        !line.is_dirty,
        "update_cell with identical content must NOT set is_dirty"
    );
}

#[test]
// CHANGE BRANCH: Writing a *different* grapheme after mark_clean must set is_dirty.
fn test_update_cell_different_content_marks_dirty() {
    let mut line = Line::new(10);
    let attrs = SgrAttributes::default();
    line.update_cell(5, 'X', attrs);
    line.mark_clean();
    line.update_cell(5, 'Y', attrs); // different char
    assert!(line.is_dirty, "update_cell with changed content must set is_dirty");
}
