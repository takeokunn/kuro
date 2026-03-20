//! Property-based and example-based tests for Screen cursor movement methods.
//!
//! Module under test: `grid/screen/cursor.rs`
//! Tier: T2 — `ProptestConfig::with_cases(500)`

use crate::grid::screen::Screen;
use crate::types::color::Color;
use proptest::prelude::*;

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Standard 24×80 screen for most tests.
fn make_screen() -> Screen {
    Screen::new(24, 80)
}

// ── Property-based tests ──────────────────────────────────────────────────────

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    // INVARIANT: move_cursor clamps row to [0, rows-1]; cursor.row is always in-bounds.
    fn prop_move_cursor_clamps_row(row in 0usize..200usize, col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(row, col);
        prop_assert!(
            screen.cursor().row < screen.rows() as usize,
            "cursor.row {} must be < rows {}",
            screen.cursor().row,
            screen.rows()
        );
    }

    #[test]
    // INVARIANT: move_cursor clamps col to [0, cols-1]; cursor.col is always in-bounds.
    fn prop_move_cursor_clamps_col(row in 0usize..24usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        screen.move_cursor(row, col);
        prop_assert!(
            screen.cursor().col < screen.cols() as usize,
            "cursor.col {} must be < cols {}",
            screen.cursor().col,
            screen.cols()
        );
    }

    #[test]
    // INVARIANT: move_cursor always clears pending_wrap regardless of position.
    fn prop_move_cursor_clears_pending_wrap(row in 0usize..200usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        // Artificially set pending_wrap to simulate a prior last-column print.
        screen.cursor.pending_wrap = true;
        screen.move_cursor(row, col);
        prop_assert!(
            !screen.cursor().pending_wrap,
            "move_cursor must clear pending_wrap"
        );
    }

    #[test]
    // INVARIANT: move_cursor_by never panics for any i32 row/col offsets.
    fn prop_move_cursor_by_no_panic(row_offset in i32::MIN..=i32::MAX, col_offset in i32::MIN..=i32::MAX) {
        let mut screen = make_screen();
        // Should not panic under any offset combination.
        screen.move_cursor_by(row_offset, col_offset);
        // Cursor must remain in-bounds after clamping.
        prop_assert!(screen.cursor().row < screen.rows() as usize);
        prop_assert!(screen.cursor().col < screen.cols() as usize);
    }

    #[test]
    // INVARIANT: move_cursor_by clears pending_wrap for any offset.
    fn prop_move_cursor_by_clears_pending_wrap(
        row_offset in -50i32..50i32,
        col_offset in -50i32..50i32,
    ) {
        let mut screen = make_screen();
        screen.cursor.pending_wrap = true;
        screen.move_cursor_by(row_offset, col_offset);
        prop_assert!(
            !screen.cursor().pending_wrap,
            "move_cursor_by must clear pending_wrap"
        );
    }

    #[test]
    // INVARIANT: carriage_return always sets cursor.col to 0.
    fn prop_carriage_return_col_zero(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.carriage_return();
        prop_assert_eq!(
            screen.cursor().col, 0,
            "carriage_return must set col to 0"
        );
    }

    #[test]
    // INVARIANT: backspace never underflows (col stays >= 0 as a usize).
    fn prop_backspace_saturating(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        // Backspace many more times than there are columns — must not panic or underflow.
        for _ in 0..100 {
            screen.backspace();
        }
        // usize can't go negative; verify the invariant explicitly.
        prop_assert_eq!(
            screen.cursor().col, 0,
            "backspace must saturate at col 0"
        );
    }

    #[test]
    // INVARIANT: tab advances cursor.col to the next tab stop (multiple of 8),
    // clamped to cols-1.
    fn prop_tab_advances_to_stop(start_col in 0usize..79usize) {
        let mut screen = make_screen();
        let cols = screen.cols() as usize;
        screen.move_cursor(0, start_col);
        screen.tab();
        let new_col = screen.cursor().col;
        let expected = ((start_col / 8) + 1) * 8;
        let expected_clamped = expected.min(cols - 1);
        prop_assert_eq!(
            new_col, expected_clamped,
            "tab from col {} should advance to {} (clamped from {})",
            start_col, expected_clamped, expected
        );
    }

    #[test]
    // INVARIANT: backspace clears pending_wrap.
    fn prop_backspace_clears_pending_wrap(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.backspace();
        prop_assert!(
            !screen.cursor().pending_wrap,
            "backspace must clear pending_wrap"
        );
    }

    #[test]
    // INVARIANT: carriage_return clears pending_wrap.
    fn prop_carriage_return_clears_pending_wrap(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.carriage_return();
        prop_assert!(
            !screen.cursor().pending_wrap,
            "carriage_return must clear pending_wrap"
        );
    }

    #[test]
    // INVARIANT: tab clears pending_wrap.
    fn prop_tab_clears_pending_wrap(start_col in 0usize..79usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.tab();
        prop_assert!(
            !screen.cursor().pending_wrap,
            "tab must clear pending_wrap"
        );
    }

    #[test]
    // INVARIANT: after move_cursor, the exact clamped values are stored.
    fn prop_move_cursor_exact_clamped_value(row in 0usize..200usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        let rows = screen.rows() as usize;
        let cols = screen.cols() as usize;
        screen.move_cursor(row, col);
        let expected_row = row.min(rows - 1);
        let expected_col = col.min(cols - 1);
        prop_assert_eq!(screen.cursor().row, expected_row);
        prop_assert_eq!(screen.cursor().col, expected_col);
    }
}

// ── Example-based tests ───────────────────────────────────────────────────────

#[test]
fn test_line_feed_advances_row() {
    let mut screen = make_screen();
    assert_eq!(screen.cursor().row, 0);
    screen.line_feed(Color::Default);
    assert_eq!(screen.cursor().row, 1);
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn test_line_feed_clears_pending_wrap() {
    // line_feed_impl sets pending_wrap = false before advancing.
    let mut screen = make_screen();
    // Place cursor at a mid-screen row so LF advances without scrolling.
    screen.move_cursor(5, 10);
    screen.cursor.pending_wrap = true;
    screen.line_feed(Color::Default);
    assert!(!screen.cursor().pending_wrap);
}

#[test]
fn test_line_feed_at_bottom_scrolls() {
    // When cursor is at row 23 (last row of a 24-row screen), LF triggers scroll_up.
    let mut screen = make_screen();
    screen.move_cursor(23, 0);
    screen.line_feed(Color::Default);
    // Cursor stays at row 23 (scroll region bottom - 1).
    assert_eq!(screen.cursor().row, 23);
}

#[test]
fn test_carriage_return_clears_pending_wrap_example() {
    let mut screen = make_screen();
    screen.move_cursor(3, 50);
    screen.cursor.pending_wrap = true;
    screen.carriage_return();
    assert_eq!(screen.cursor().col, 0);
    assert!(!screen.cursor().pending_wrap);
}

#[test]
fn test_move_cursor_clamps_to_last_row() {
    let mut screen = make_screen();
    screen.move_cursor(9999, 0);
    assert_eq!(screen.cursor().row, 23); // rows=24, last index=23
}

#[test]
fn test_move_cursor_clamps_to_last_col() {
    let mut screen = make_screen();
    screen.move_cursor(0, 9999);
    assert_eq!(screen.cursor().col, 79); // cols=80, last index=79
}

#[test]
fn test_backspace_from_zero_stays_zero() {
    let mut screen = make_screen();
    assert_eq!(screen.cursor().col, 0);
    screen.backspace();
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn test_backspace_decrements_col() {
    let mut screen = make_screen();
    screen.move_cursor(0, 10);
    screen.backspace();
    assert_eq!(screen.cursor().col, 9);
}

#[test]
fn test_tab_from_col_zero() {
    let mut screen = make_screen();
    screen.tab();
    assert_eq!(screen.cursor().col, 8);
}

#[test]
fn test_tab_from_col_7() {
    // col=7: next stop is (7/8+1)*8 = 8.
    let mut screen = make_screen();
    screen.move_cursor(0, 7);
    screen.tab();
    assert_eq!(screen.cursor().col, 8);
}

#[test]
fn test_tab_from_col_8() {
    // col=8: next stop is (8/8+1)*8 = 16.
    let mut screen = make_screen();
    screen.move_cursor(0, 8);
    screen.tab();
    assert_eq!(screen.cursor().col, 16);
}

#[test]
fn test_tab_at_last_tab_stop_clamps() {
    // col=79 (last col of 80-col screen): (79/8+1)*8 = 80, clamped to 79.
    let mut screen = make_screen();
    screen.move_cursor(0, 79);
    screen.tab();
    assert_eq!(screen.cursor().col, 79);
}

#[test]
fn test_move_cursor_by_positive_offsets() {
    let mut screen = make_screen();
    screen.move_cursor(5, 10);
    screen.move_cursor_by(3, 5); // row_offset=3, col_offset=5
    // move_by(col_offset=5, row_offset=3): col += 5 → 15, row += 3 → 8
    assert_eq!(screen.cursor().row, 8);
    assert_eq!(screen.cursor().col, 15);
}

#[test]
fn test_move_cursor_by_negative_clamps_at_zero() {
    let mut screen = make_screen();
    screen.move_cursor(2, 5);
    // Large negative offsets must not underflow.
    screen.move_cursor_by(-1000, -1000);
    assert_eq!(screen.cursor().row, 0);
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn test_move_cursor_by_large_positive_clamps_at_max() {
    let mut screen = make_screen();
    screen.move_cursor_by(10000, 10000);
    assert_eq!(screen.cursor().row, 23);
    assert_eq!(screen.cursor().col, 79);
}
