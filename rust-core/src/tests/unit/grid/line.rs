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
    for (i, (a, b)) in plain
        .cells
        .iter()
        .zip(with_default_bg.cells.iter())
        .enumerate()
    {
        assert_eq!(a, b, "cell mismatch at col {i}");
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
    assert!(
        line.is_dirty,
        "update_cell with changed content must set is_dirty"
    );
}

// ── update_cell_with ─────────────────────────────────────────────────────────

#[test]
// NO-OP: update_cell_with a cell equal to the existing one must NOT set is_dirty.
fn test_update_cell_with_same_cell_stays_clean() {
    let mut line = Line::new(10);
    // The line is freshly created with default cells; col 3 already holds Cell::default().
    // Writing the same default cell must not set is_dirty.
    line.mark_clean();
    line.update_cell_with(3, Cell::default());
    assert!(
        !line.is_dirty,
        "update_cell_with identical cell must NOT set is_dirty"
    );
}

#[test]
// DIRTY BRANCH: update_cell_with a different cell must set is_dirty.
fn test_update_cell_with_different_cell_marks_dirty() {
    let mut line = Line::new(10);
    line.mark_clean();
    // Build a different cell by using a scratch line's cell after update_cell.
    let mut scratch = Line::new(1);
    scratch.update_cell(0, 'Z', SgrAttributes::default());
    let z_cell = scratch.cells[0].clone();

    line.update_cell_with(4, z_cell);
    assert!(
        line.is_dirty,
        "update_cell_with a different cell must set is_dirty"
    );
}

#[test]
// BOUNDARY: update_cell_with at an out-of-bounds column must be silently ignored.
fn test_update_cell_with_out_of_bounds_is_noop() {
    let mut line = Line::new(5);
    line.mark_clean();
    line.update_cell_with(10, Cell::default()); // col 10 >= len 5
    assert!(
        !line.is_dirty,
        "update_cell_with out-of-bounds must be a no-op"
    );
}

// ── get_cell_mut ─────────────────────────────────────────────────────────────

#[test]
// get_cell_mut returns Some for valid col, None for out-of-bounds.
fn test_get_cell_mut_bounds() {
    let mut line = Line::new(8);
    assert!(line.get_cell_mut(0).is_some());
    assert!(line.get_cell_mut(7).is_some());
    assert!(line.get_cell_mut(8).is_none());
}

#[test]
// Mutating via get_cell_mut must be observable through get_cell.
fn test_get_cell_mut_modifies_cell() {
    let mut line = Line::new(8);
    // Write 'Z' through the normal update_cell path so we have a non-default cell,
    // then verify the same data is accessible via get_cell_mut.
    line.update_cell(3, 'Z', SgrAttributes::default());
    {
        let cell = line.get_cell_mut(3).unwrap();
        assert_eq!(
            cell.grapheme.as_str(),
            "Z",
            "get_cell_mut must return the same cell previously written"
        );
        // Mutate attrs via the mutable reference — change background color.
        cell.attrs.background = crate::types::Color::Indexed(1);
    }
    assert_eq!(
        line.get_cell(3).unwrap().attrs.background,
        crate::types::Color::Indexed(1),
        "mutation via get_cell_mut must be visible through get_cell"
    );
}

// ── Display (fmt::Display) ────────────────────────────────────────────────────

#[test]
// Display renders the concatenated graphemes of all cells.
fn test_display_renders_graphemes() {
    let mut line = Line::new(5);
    line.update_cell(0, 'H', SgrAttributes::default());
    line.update_cell(1, 'i', SgrAttributes::default());
    // cols 2-4 remain default (' ').
    let s = line.to_string();
    assert_eq!(
        &s[..2],
        "Hi",
        "first two chars of Display output must be 'Hi'"
    );
    assert_eq!(
        s.len(),
        5,
        "Display output length must equal the line column count"
    );
}

// ── resize same-size ──────────────────────────────────────────────────────────

#[test]
// resize to the same width must be a no-op except that is_dirty is set.
fn test_resize_same_size_marks_dirty() {
    let mut line = Line::new(10);
    assert!(!line.is_dirty);
    line.resize(10); // same size
                     // The impl sets is_dirty unconditionally in resize, so it must be true.
    assert!(
        line.is_dirty,
        "resize (even no-op size) must set is_dirty per current implementation"
    );
    assert_eq!(
        line.cells.len(),
        10,
        "cell count must not change on same-size resize"
    );
}

// ── new_with_bg — all cells carry the bg color ───────────────────────────────

/// Assert that every cell in `line` carries `expected_bg` as its background.
#[inline]
fn assert_all_cells_have_bg(line: &Line, expected_bg: Color, label: &str) {
    assert!(!line.cells.is_empty(), "{label}: line must be non-empty");
    for (i, cell) in line.cells.iter().enumerate() {
        assert_eq!(
            cell.attrs.background, expected_bg,
            "{label}: cell at col {i} must have background {expected_bg:?}"
        );
    }
}

/// Macro: `assert_new_with_bg!(name, cols, bg_expr, label)` — constructs a
/// `Line::new_with_bg` and asserts every cell carries the expected background.
macro_rules! assert_new_with_bg {
    ($name:ident, $cols:expr, $bg:expr, $label:expr) => {
        #[test]
        fn $name() {
            let bg = $bg;
            let line = Line::new_with_bg($cols, bg);
            assert_eq!(line.cells.len(), $cols);
            assert_all_cells_have_bg(&line, bg, $label);
        }
    };
}

assert_new_with_bg!(
    test_new_with_bg_all_cells_carry_bg,
    8,
    Color::Indexed(42),
    "new_with_bg(Indexed(42))"
);
assert_new_with_bg!(
    test_new_with_bg_rgb_first_and_last,
    5,
    Color::Rgb(10, 20, 30),
    "new_with_bg(Rgb(10,20,30))"
);

// ── clear_with_bg edge cases ──────────────────────────────────────────────────

/// Macro: `assert_clear_with_bg!(name, setup_fn, bg_expr, expected_cell_check)`
/// — builds a line, optionally modifies it, calls `clear_with_bg`, then
/// checks every cell using a per-cell closure `|cell| assert!(...)`.
macro_rules! assert_clear_with_bg_cells {
    ($name:ident, $setup:expr, $bg:expr, $check:expr, $msg:expr) => {
        #[test]
        fn $name() {
            let bg = $bg;
            let mut line = $setup;
            line.clear_with_bg(bg);
            assert!(line.is_dirty, "clear_with_bg() must set is_dirty");
            for (i, cell) in line.cells.iter().enumerate() {
                let check: &dyn Fn(&crate::types::Cell, usize) = &$check;
                check(cell, i);
            }
        }
    };
}

assert_clear_with_bg_cells!(
    test_clear_with_bg_default_equals_cell_default,
    {
        let mut l = Line::new(6);
        l.update_cell(2, 'Q', SgrAttributes::default());
        l
    },
    Color::Default,
    |cell, i| {
        assert_eq!(
            cell,
            &Cell::default(),
            "cell at col {i} must equal Cell::default() after clear_with_bg(Default)"
        );
    },
    "clear_with_bg(Default)"
);

assert_clear_with_bg_cells!(
    test_clear_with_bg_overwrites_existing_bg,
    Line::new_with_bg(4, Color::Indexed(1)),
    Color::Indexed(7),
    |cell, i| {
        assert_eq!(
            cell.attrs.background,
            Color::Indexed(7),
            "cell at col {i} must have new bg Indexed(7) after clear_with_bg"
        );
    },
    "clear_with_bg overwrite"
);

// ── update_cell — out-of-bounds silent ignore ─────────────────────────────────

#[test]
// update_cell at col == len must be silently ignored (no panic, is_dirty stays false).
fn test_update_cell_out_of_bounds_is_noop() {
    let mut line = Line::new(5);
    line.mark_clean();
    line.update_cell(5, 'X', SgrAttributes::default()); // col 5 == len 5 → OOB
    assert!(
        !line.is_dirty,
        "update_cell at out-of-bounds column must not set is_dirty"
    );
    line.update_cell(999, 'Y', SgrAttributes::default()); // far OOB
    assert!(
        !line.is_dirty,
        "update_cell at far out-of-bounds column must not set is_dirty"
    );
}

// ── update_cell — attrs-only change ──────────────────────────────────────────

#[test]
// Changing only the attrs (same grapheme) must still set is_dirty.
fn test_update_cell_attrs_change_marks_dirty() {
    let mut line = Line::new(10);
    // Write 'A' with default attrs.
    line.update_cell(3, 'A', SgrAttributes::default());
    line.mark_clean();
    // Write 'A' again but with a different background color in attrs.
    let new_attrs = SgrAttributes {
        background: Color::Indexed(5),
        ..Default::default()
    };
    line.update_cell(3, 'A', new_attrs);
    assert!(
        line.is_dirty,
        "update_cell with same grapheme but different attrs must set is_dirty"
    );
    assert_eq!(
        line.get_cell(3).unwrap().attrs.background,
        Color::Indexed(5),
        "attrs must be updated after update_cell with changed attrs"
    );
}

// ── Line::new(0) — zero-column line ──────────────────────────────────────────

#[test]
// Line::new(0) must construct without panic and have an empty cell vec.
fn test_new_zero_cols_is_empty_line() {
    let line = Line::new(0);
    assert_eq!(line.cells.len(), 0, "zero-col line must have no cells");
    assert!(!line.is_dirty, "zero-col line must start clean");
    // get_cell on a zero-col line must return None.
    assert!(
        line.get_cell(0).is_none(),
        "get_cell(0) on zero-col line must return None"
    );
}

// ── get_cell boundary indices ─────────────────────────────────────────────────

#[test]
// get_cell at index 0 and at the last valid index must both return Some.
fn test_get_cell_first_and_last_valid_indices() {
    let cols = 8usize;
    let line = Line::new(cols);
    assert!(
        line.get_cell(0).is_some(),
        "get_cell(0) must return Some for a non-empty line"
    );
    assert!(
        line.get_cell(cols - 1).is_some(),
        "get_cell(last) must return Some"
    );
    assert!(
        line.get_cell(cols).is_none(),
        "get_cell(cols) must return None (one past the end)"
    );
}

// ── clear() on a never-modified (clean) line ──────────────────────────────────

#[test]
// clear() called on an already-clean line must still set is_dirty.
fn test_clear_on_clean_line_sets_dirty() {
    let mut line = Line::new(4);
    assert!(!line.is_dirty, "line must start clean");
    line.clear();
    assert!(
        line.is_dirty,
        "clear() must set is_dirty even when the line was already clean"
    );
}

// ── Display with multibyte Unicode ────────────────────────────────────────────

#[test]
// Display output for a line whose cells contain ASCII must equal the char sequence.
fn test_display_single_char_sequence() {
    let mut line = Line::new(3);
    line.update_cell(0, 'A', SgrAttributes::default());
    line.update_cell(1, 'B', SgrAttributes::default());
    line.update_cell(2, 'C', SgrAttributes::default());
    assert_eq!(
        line.to_string(),
        "ABC",
        "Display must concatenate grapheme strings of all cells"
    );
}

// ── resize to zero ────────────────────────────────────────────────────────────

#[test]
// resize(0) must truncate all cells and set is_dirty.
fn test_resize_to_zero_truncates_all_cells() {
    let mut line = Line::new(10);
    line.resize(0);
    assert_eq!(
        line.cells.len(),
        0,
        "resize(0) must leave no cells in the line"
    );
    assert!(line.is_dirty, "resize(0) must set is_dirty");
    // get_cell must return None on the now-empty line.
    assert!(
        line.get_cell(0).is_none(),
        "get_cell(0) must return None after resize(0)"
    );
}

// ── resize shrink — content of kept cells ────────────────────────────────────

#[test]
// After shrink, cells 0..new_cols must retain their original content.
fn test_resize_shrink_preserves_remaining_cells() {
    let mut line = Line::new(10);
    // Write distinct chars to all cells.
    for i in 0..10 {
        line.update_cell(
            i,
            char::from_u32(b'A' as u32 + i as u32).unwrap(),
            SgrAttributes::default(),
        );
    }
    line.resize(4);
    assert_eq!(line.cells.len(), 4);
    // Cells 0-3 must still hold 'A'-'D'.
    for i in 0..4 {
        let expected = char::from_u32(b'A' as u32 + i as u32).unwrap();
        assert_eq!(
            line.get_cell(i).unwrap().grapheme.as_str(),
            expected.to_string(),
            "cell at col {i} must preserve its content after shrink"
        );
    }
}
