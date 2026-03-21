//! Unit tests for `Screen::resize` (resize.rs).
//! Example-based tests + T2-tier PBT (500 cases) for boundary and invariant coverage.

use crate::grid::screen::Screen;
use crate::types::cell::SgrAttributes;
use proptest::prelude::*;

fn make_screen() -> Screen {
    Screen::new(24, 80)
}

// ---------------------------------------------------------------------------
// Example-based tests
// ---------------------------------------------------------------------------

#[test]
fn resize_updates_rows_and_cols() {
    let mut s = make_screen();
    s.resize(10, 40);
    assert_eq!(s.rows(), 10);
    assert_eq!(s.cols(), 40);
}

#[test]
fn resize_larger_grows_line_count() {
    let mut s = Screen::new(5, 20);
    s.resize(10, 20);
    assert_eq!(s.rows() as usize, 10);
    // Active screen must have 10 lines
    assert!(s.get_line(9).is_some());
}

#[test]
fn resize_smaller_shrinks_line_count() {
    let mut s = make_screen();
    s.resize(5, 40);
    assert_eq!(s.rows(), 5);
    // Lines beyond new_rows must no longer exist
    assert!(s.get_line(5).is_none());
}

#[test]
fn resize_clamps_cursor_row_when_shrinking() {
    let mut s = make_screen();
    s.move_cursor(23, 0); // last row of 24-row screen
    s.resize(10, 80);
    assert!(
        s.cursor().row < 10,
        "cursor.row {} must be < 10 after shrink",
        s.cursor().row
    );
}

#[test]
fn resize_clamps_cursor_col_when_shrinking() {
    let mut s = make_screen();
    s.move_cursor(0, 79); // last col of 80-col screen
    s.resize(24, 30);
    assert!(
        s.cursor().col < 30,
        "cursor.col {} must be < 30 after shrink",
        s.cursor().col
    );
}

#[test]
fn resize_clears_pending_wrap() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    // Move to last col and print to trigger pending_wrap
    s.move_cursor(0, 79);
    s.print('X', attrs, false); // auto_wrap=false keeps cursor at col 79 with pending_wrap
                                // Force pending_wrap directly (safest: just resize and check the invariant)
    s.resize(24, 80);
    assert!(
        !s.cursor().pending_wrap,
        "pending_wrap must be false after resize"
    );
}

#[test]
fn resize_to_1x1_does_not_panic() {
    let mut s = make_screen();
    s.move_cursor(23, 79);
    s.resize(1, 1);
    assert_eq!(s.rows(), 1);
    assert_eq!(s.cols(), 1);
    assert_eq!(s.cursor().row, 0);
    assert_eq!(s.cursor().col, 0);
}

#[test]
fn resize_preserves_content_within_new_bounds() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    // Write 'A' at (0, 0), 'B' at (1, 1) — both within new bounds after resize
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.move_cursor(1, 1);
    s.print('B', attrs, true);

    s.resize(20, 60);

    assert_eq!(
        s.get_cell(0, 0).unwrap().char(),
        'A',
        "cell (0,0) must survive resize to smaller dimensions"
    );
    assert_eq!(
        s.get_cell(1, 1).unwrap().char(),
        'B',
        "cell (1,1) must survive resize to smaller dimensions"
    );
}

#[test]
fn resize_while_alternate_active_updates_both_screens() {
    let mut s = Screen::new(10, 10);
    s.switch_to_alternate();
    assert!(s.is_alternate_screen_active());

    s.resize(20, 40);

    // Alternate screen dimensions
    assert_eq!(s.rows(), 20);
    assert_eq!(s.cols(), 40);

    // Switch back: primary must also be at new dimensions
    s.switch_to_primary();
    assert_eq!(s.rows(), 20);
    assert_eq!(s.cols(), 40);
}

// ---------------------------------------------------------------------------
// PBT — T2 tier (500 cases)
// ---------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    // INVARIANT: After resize(r, c), rows()==r and cols()==c
    fn prop_resize_updates_dimensions(
        r in 1u16..=200u16,
        c in 1u16..=200u16,
    ) {
        let mut s = Screen::new(24, 80);
        s.resize(r, c);
        prop_assert_eq!(s.rows(), r);
        prop_assert_eq!(s.cols(), c);
    }

    #[test]
    // PANIC SAFETY: resize(rows, cols) with arbitrary values in 1..200 never panics
    fn prop_resize_no_panic(
        r in 1u16..=200u16,
        c in 1u16..=200u16,
    ) {
        let mut s = Screen::new(24, 80);
        s.resize(r, c);
        // If we reach here, no panic occurred.
        prop_assert!(s.rows() == r && s.cols() == c);
    }

    #[test]
    // BOUNDARY: After resize(new_rows, 80), cursor.row <= new_rows - 1
    fn prop_resize_clamps_cursor_row(new_rows in 1u16..=200u16) {
        let mut s = Screen::new(24, 80);
        // Position cursor at the last possible row
        s.move_cursor(23, 0);
        s.resize(new_rows, 80);
        prop_assert!(
            s.cursor().row <= (new_rows - 1) as usize,
            "cursor.row {} must be <= {}",
            s.cursor().row,
            new_rows - 1
        );
    }

    #[test]
    // BOUNDARY: After resize(24, new_cols), cursor.col <= new_cols - 1
    fn prop_resize_clamps_cursor_col(new_cols in 1u16..=200u16) {
        let mut s = Screen::new(24, 80);
        // Position cursor at the last possible col
        s.move_cursor(0, 79);
        s.resize(24, new_cols);
        prop_assert!(
            s.cursor().col <= (new_cols - 1) as usize,
            "cursor.col {} must be <= {}",
            s.cursor().col,
            new_cols - 1
        );
    }

    #[test]
    // INVARIANT: After resize, cursor.pending_wrap == false
    fn prop_resize_clears_pending_wrap(
        r in 1u16..=200u16,
        c in 1u16..=200u16,
    ) {
        let mut s = Screen::new(24, 80);
        // Set pending_wrap directly via the cursor field
        s.cursor_mut().pending_wrap = true;
        s.resize(r, c);
        prop_assert!(
            !s.cursor().pending_wrap,
            "pending_wrap must be false after resize"
        );
    }

    #[test]
    // INVARIANT: After resize(r, c), active screen has exactly r lines accessible
    fn prop_resize_line_count_correct(
        r in 1u16..=100u16,
        c in 1u16..=100u16,
    ) {
        let mut s = Screen::new(24, 80);
        s.resize(r, c);
        // Row (r-1) must be accessible; row r must not
        prop_assert!(
            s.get_line((r - 1) as usize).is_some(),
            "last row must exist after resize({})", r
        );
        prop_assert!(
            s.get_line(r as usize).is_none(),
            "row beyond new_rows must not exist after resize({})", r
        );
    }

    #[test]
    // INVARIANT: Content at (0, 0) is preserved when new dimensions >= 1x1
    fn prop_resize_preserves_content_within_bounds(
        new_rows in 1u16..=50u16,
        new_cols in 1u16..=50u16,
    ) {
        let mut s = Screen::new(24, 80);
        let attrs = SgrAttributes::default();
        // Write a char that will survive the resize (row 0, col 0 always survives)
        s.move_cursor(0, 0);
        s.print('K', attrs, true);

        s.resize(new_rows, new_cols);

        prop_assert_eq!(
            s.get_cell(0, 0).unwrap().char(),
            'K',
            "cell (0,0) must survive resize to ({}, {})",
            new_rows, new_cols
        );
    }
}
