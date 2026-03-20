//! Property-based and example-based tests for Screen dirty-tracking methods.
//!
//! Module under test: `grid/screen/dirty.rs`
//! Tier: T2 — `ProptestConfig::with_cases(500)`
//!
//! NOTE on `take_dirty_lines()`: returns `Vec<usize>` (sorted row indices).
//! NOTE on `attach_combining`: inserts into `dirty_set` but does NOT set
//!   `line.is_dirty`; only `mark_line_dirty` sets both.
//! NOTE on `mark_all_dirty`: sets `full_dirty = true`; individual `line.is_dirty`
//!   flags are NOT touched — only `take_dirty_lines()` reflects the full range.

use crate::grid::screen::Screen;
use proptest::prelude::*;

fn make_screen() -> Screen {
    Screen::new(24, 80)
}

// ---------------------------------------------------------------------------
// attach_combining
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: attach_combining inserts the row into the dirty set
fn test_attach_combining_marks_row_in_dirty_set() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines(); // drain any initial dirty state
    s.attach_combining(0, 0, '\u{0301}'); // combining acute — row exists even if cell is default
    let dirty = s.take_dirty_lines();
    assert!(
        dirty.contains(&0),
        "attach_combining must insert row 0 into dirty set"
    );
}

#[test]
// PANIC SAFETY: attach_combining with out-of-bounds row must not panic
fn test_attach_combining_oob_row_no_panic() {
    let mut s = make_screen();
    s.attach_combining(999, 0, '\u{0301}');
    // No panic is the pass condition
}

#[test]
// PANIC SAFETY: attach_combining with out-of-bounds col must not panic
fn test_attach_combining_oob_col_no_panic() {
    let mut s = make_screen();
    s.attach_combining(0, 999, '\u{0301}');
    // No panic is the pass condition
}

#[test]
// PANIC SAFETY: both row and col out of bounds must not panic
fn test_attach_combining_oob_both_no_panic() {
    let mut s = make_screen();
    s.attach_combining(999, 999, '\u{0301}');
    // No panic is the pass condition
}

// ---------------------------------------------------------------------------
// mark_line_dirty
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: mark_line_dirty sets is_dirty on the line
fn test_mark_line_dirty_sets_line_flag() {
    let mut s = make_screen();
    if let Some(line) = s.get_line_mut(5) {
        line.is_dirty = false;
    }
    s.mark_line_dirty(5);
    assert!(
        s.get_line(5).unwrap().is_dirty,
        "mark_line_dirty must set is_dirty on the line"
    );
}

#[test]
// INVARIANT: mark_line_dirty causes row to appear in take_dirty_lines()
fn test_mark_line_dirty_appears_in_dirty_set() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines(); // drain first
    s.mark_line_dirty(7);
    let dirty = s.take_dirty_lines();
    assert!(
        dirty.contains(&7),
        "row 7 must appear in dirty set after mark_line_dirty"
    );
}

#[test]
// INVARIANT: take_dirty_lines drains — second call returns empty vec (no new marks)
fn test_mark_line_dirty_drain_on_take() {
    let mut s = make_screen();
    s.mark_line_dirty(3);
    let first = s.take_dirty_lines();
    assert!(first.contains(&3));
    let second = s.take_dirty_lines();
    assert!(
        !second.contains(&3),
        "take_dirty_lines must drain the dirty set"
    );
}

#[test]
// INVARIANT: marking multiple distinct rows produces all of them in dirty set
fn test_mark_line_dirty_multiple_rows() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines();
    s.mark_line_dirty(1);
    s.mark_line_dirty(10);
    s.mark_line_dirty(23);
    let dirty = s.take_dirty_lines();
    assert!(dirty.contains(&1));
    assert!(dirty.contains(&10));
    assert!(dirty.contains(&23));
}

#[test]
// IDEMPOTENCY: marking the same row twice still appears exactly once-or-more in result
// (DirtySet deduplicates; result must contain row 4)
fn test_mark_line_dirty_idempotent() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines();
    s.mark_line_dirty(4);
    s.mark_line_dirty(4);
    let dirty = s.take_dirty_lines();
    assert!(dirty.contains(&4), "row 4 must be present after double mark");
}

// ---------------------------------------------------------------------------
// mark_all_dirty
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: mark_all_dirty causes take_dirty_lines to return all rows
fn test_mark_all_dirty_returns_all_rows() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines(); // drain
    s.mark_all_dirty();
    let dirty = s.take_dirty_lines();
    assert_eq!(
        dirty.len(),
        24,
        "mark_all_dirty must dirty all 24 rows"
    );
}

#[test]
// INVARIANT: mark_all_dirty result is sorted (0..rows)
fn test_mark_all_dirty_result_sorted() {
    let mut s = make_screen();
    let _ = s.take_dirty_lines();
    s.mark_all_dirty();
    let dirty = s.take_dirty_lines();
    let expected: Vec<usize> = (0..24).collect();
    assert_eq!(dirty, expected, "mark_all_dirty result must be sorted 0..rows");
}

#[test]
// INVARIANT: take_dirty_lines after mark_all_dirty drains full_dirty flag
fn test_mark_all_dirty_drain_on_take() {
    let mut s = make_screen();
    s.mark_all_dirty();
    let first = s.take_dirty_lines();
    assert_eq!(first.len(), 24);
    // After drain, no new marks → empty
    let second = s.take_dirty_lines();
    assert!(second.is_empty(), "second take must be empty after drain");
}

// ---------------------------------------------------------------------------
// PBT
// ---------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    // PANIC SAFETY: mark_line_dirty with any valid row index never panics
    fn prop_mark_line_dirty_no_panic(row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        s.mark_line_dirty(row);
        prop_assert!(s.get_line(row).unwrap().is_dirty);
    }

    #[test]
    // INVARIANT: mark_line_dirty → dirty set contains the row
    fn prop_mark_line_dirty_in_dirty_set(row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        let _ = s.take_dirty_lines();
        s.mark_line_dirty(row);
        let dirty = s.take_dirty_lines();
        prop_assert!(
            dirty.contains(&row),
            "row {} must be in dirty set after mark_line_dirty", row
        );
    }

    #[test]
    // INVARIANT: mark_all_dirty on any size screen returns `rows` rows
    fn prop_mark_all_dirty_count(rows in 4u16..=30u16, cols in 10u16..=100u16) {
        let mut s = Screen::new(rows, cols);
        let _ = s.take_dirty_lines();
        s.mark_all_dirty();
        let dirty = s.take_dirty_lines();
        prop_assert_eq!(
            dirty.len(), rows as usize,
            "mark_all_dirty must dirty all {} rows", rows
        );
    }

    #[test]
    // PANIC SAFETY: attach_combining with any row/col in-bounds never panics
    fn prop_attach_combining_in_bounds_no_panic(
        row in 0usize..24usize,
        col in 0usize..80usize,
    ) {
        let mut s = Screen::new(24, 80);
        s.attach_combining(row, col, '\u{0301}');
        prop_assert_eq!(s.rows(), 24u16);
    }

    #[test]
    // INVARIANT: attach_combining always inserts row into dirty set (regardless of cell content)
    fn prop_attach_combining_row_in_dirty_set(
        row in 0usize..24usize,
        col in 0usize..80usize,
    ) {
        let mut s = Screen::new(24, 80);
        let _ = s.take_dirty_lines();
        s.attach_combining(row, col, '\u{0301}');
        let dirty = s.take_dirty_lines();
        prop_assert!(
            dirty.contains(&row),
            "row {} must be in dirty set after attach_combining", row
        );
    }

    #[test]
    // INVARIANT: mark_all_dirty result contains every row index in [0, rows)
    fn prop_mark_all_dirty_contains_every_row(rows in 4u16..=20u16) {
        let mut s = Screen::new(rows, 80);
        let _ = s.take_dirty_lines();
        s.mark_all_dirty();
        let dirty = s.take_dirty_lines();
        for expected_row in 0..rows as usize {
            prop_assert!(
                dirty.contains(&expected_row),
                "dirty set must contain row {}", expected_row
            );
        }
    }
}
