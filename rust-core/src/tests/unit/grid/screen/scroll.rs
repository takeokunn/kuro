//! Property-based and example-based tests for Screen scroll methods.
//!
//! Module under test: `grid/screen/scroll.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::make_screen;
use crate::types::color::Color;
use proptest::prelude::*;

// ── Property-based tests ──────────────────────────────────────────────────────

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // INVARIANT: scroll_up(n) never panics for any n in a valid range.
    fn prop_scroll_up_no_panic(n in 0usize..50usize) {
        let mut screen = make_screen();
        screen.scroll_up(n, Color::Default);
        // Post-condition: screen dimensions are unchanged.
        prop_assert_eq!(screen.rows(), 24);
        prop_assert_eq!(screen.cols(), 80);
    }

    #[test]
    // INVARIANT: scroll_down(n) never panics for any n in a valid range.
    fn prop_scroll_down_no_panic(n in 0usize..50usize) {
        let mut screen = make_screen();
        screen.scroll_down(n, Color::Default);
        prop_assert_eq!(screen.rows(), 24);
        prop_assert_eq!(screen.cols(), 80);
    }

    #[test]
    // INVARIANT: scroll_up(n) always preserves screen dimensions
    // (no lines are created or destroyed, only rotated).
    fn prop_scroll_up_preserves_line_count(n in 0usize..50usize) {
        let mut screen = make_screen();
        let rows_before = screen.rows() as usize;
        screen.scroll_up(n, Color::Default);
        prop_assert_eq!(screen.rows() as usize, rows_before);
    }

    #[test]
    // INVARIANT: scroll_down(n) always preserves screen dimensions.
    fn prop_scroll_down_preserves_line_count(n in 0usize..50usize) {
        let mut screen = make_screen();
        let rows_before = screen.rows() as usize;
        screen.scroll_down(n, Color::Default);
        prop_assert_eq!(screen.rows() as usize, rows_before);
    }

    #[test]
    // INVARIANT: full-screen scroll_up(n) triggers full dirty state (fast path).
    // Verified by observing that take_dirty_lines() returns all rows.
    fn prop_full_screen_scroll_up_sets_full_dirty(n in 1usize..10usize) {
        let mut screen = make_screen();
        // Confirm the scroll region is full-screen (invariant of new()).
        prop_assert_eq!(screen.get_scroll_region().top, 0);
        prop_assert_eq!(screen.get_scroll_region().bottom, 24);
        screen.scroll_up(n, Color::Default);
        // Full-screen primary scroll must mark all rows dirty.
        let dirty = screen.take_dirty_lines();
        prop_assert_eq!(
            dirty.len(), 24,
            "full-screen scroll_up must dirty all rows"
        );
    }

    #[test]
    // INVARIANT: full-screen scroll_down(n) triggers full dirty state (fast path).
    fn prop_full_screen_scroll_down_sets_full_dirty(n in 1usize..10usize) {
        let mut screen = make_screen();
        screen.scroll_down(n, Color::Default);
        let dirty = screen.take_dirty_lines();
        prop_assert_eq!(
            dirty.len(), 24,
            "full-screen scroll_down must dirty all rows"
        );
    }

    #[test]
    // INVARIANT: consume_scroll_events() resets pending counters to zero.
    // (Both pending_scroll_up and pending_scroll_down accumulate to 0 in
    // current implementation; consume must reset and return 0,0.)
    fn prop_consume_scroll_events_resets(n in 0usize..20usize) {
        let mut screen = make_screen();
        screen.scroll_up(n, Color::Default);
        // First call drains whatever was accumulated.
        let _first = screen.consume_scroll_events();
        // Second call must always return (0, 0).
        let (up2, down2) = screen.consume_scroll_events();
        prop_assert_eq!(up2, 0, "second consume must return up=0");
        prop_assert_eq!(down2, 0, "second consume must return down=0");
    }

    #[test]
    // INVARIANT: consume_scroll_events is idempotent — after first drain, counters stay 0.
    fn prop_consume_scroll_events_idempotent(
        n_up in 0usize..15usize,
        n_down in 0usize..15usize,
    ) {
        let mut screen = make_screen();
        screen.scroll_up(n_up, Color::Default);
        screen.scroll_down(n_down, Color::Default);
        // Drain once.
        screen.consume_scroll_events();
        // Any number of additional drains must return (0, 0).
        for _ in 0..3 {
            let (up, down) = screen.consume_scroll_events();
            prop_assert_eq!(up, 0);
            prop_assert_eq!(down, 0);
        }
    }

    #[test]
    // INVARIANT: set_scroll_region stores the given top/bottom unconditionally.
    // (No validation is performed by the method itself — it accepts any values.)
    fn prop_set_scroll_region_stores_values(
        top in 0usize..12usize,
        bottom in 13usize..24usize,
    ) {
        let mut screen = make_screen();
        screen.set_scroll_region(top, bottom);
        let region = screen.get_scroll_region();
        prop_assert_eq!(region.top, top);
        prop_assert_eq!(region.bottom, bottom);
    }

    #[test]
    // INVARIANT: scroll_up(n) with n >= rows replaces every line (n_actual clamped to rows).
    // The screen must still have `rows` rows after an over-large scroll.
    fn prop_scroll_up_over_rows_no_panic(n in 24usize..100usize) {
        let mut screen = make_screen();
        screen.scroll_up(n, Color::Default);
        prop_assert_eq!(screen.rows() as usize, 24);
    }

    #[test]
    // INVARIANT: cursor.row stays in-bounds after any scroll_up.
    fn prop_scroll_up_cursor_row_in_bounds(n in 0usize..50usize) {
        let mut screen = make_screen();
        screen.move_cursor(23, 0);
        screen.scroll_up(n, Color::Default);
        prop_assert!(
            screen.cursor().row < screen.rows() as usize,
            "cursor.row must remain < rows after scroll_up"
        );
    }

    #[test]
    // INVARIANT: scrollback_line_count grows by min(n, rows) per scroll_up call
    // on primary screen with full-screen region.
    // Relies on default scrollback_max_lines (10_000) >> 24 rows; no eviction occurs here.
    fn prop_scroll_up_grows_scrollback(n in 1usize..25usize) {
        let mut screen = make_screen();
        let before = screen.scrollback_line_count;
        screen.scroll_up(n, Color::Default);
        let added = n.min(screen.rows() as usize);
        prop_assert_eq!(
            screen.scrollback_line_count,
            before + added,
            "scrollback_line_count must grow by min(n, rows)"
        );
    }
}

// ── Example-based tests ───────────────────────────────────────────────────────

#[test]
fn test_scroll_up_one_blank_line_at_bottom() {
    // After scroll_up(1), the last row must be a fresh blank line.
    let mut screen = make_screen();
    // Fill every cell of row 23 with 'Z'.
    let attrs = crate::types::cell::SgrAttributes::default();
    screen.move_cursor(23, 0);
    for _ in 0..80 {
        screen.print('Z', attrs, false);
    }
    // Verify row 23 has 'Z' at col 0.
    assert_eq!(screen.get_cell(23, 0).unwrap().char(), 'Z');

    screen.scroll_up(1, Color::Default);

    // Row 23 must now be blank (the new line introduced by the scroll).
    assert_eq!(
        screen.get_cell(23, 0).unwrap().char(),
        ' ',
        "row 23 must be blank after scroll_up(1)"
    );
}

#[test]
fn test_scroll_down_one_blank_line_at_top() {
    // After scroll_down(1), row 0 must be a fresh blank line.
    let mut screen = make_screen();
    let attrs = crate::types::cell::SgrAttributes::default();
    screen.move_cursor(0, 0);
    screen.print('A', attrs, false);
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'A');

    screen.scroll_down(1, Color::Default);

    assert_eq!(
        screen.get_cell(0, 0).unwrap().char(),
        ' ',
        "row 0 must be blank after scroll_down(1)"
    );
}

#[test]
fn test_consume_scroll_events_returns_zero_zero_after_scroll_up() {
    // In the current implementation full-screen scroll_up does NOT increment
    // pending_scroll_up (full_dirty path only); consume must return (0, 0).
    let mut screen = make_screen();
    screen.scroll_up(5, Color::Default);
    let (up, down) = screen.consume_scroll_events();
    assert_eq!(up, 0);
    assert_eq!(down, 0);
}

#[test]
fn test_consume_scroll_events_second_call_always_zero() {
    let mut screen = make_screen();
    screen.scroll_up(3, Color::Default);
    screen.consume_scroll_events(); // drain
    let (up, down) = screen.consume_scroll_events(); // second drain
    assert_eq!(up, 0);
    assert_eq!(down, 0);
}

#[test]
fn test_set_scroll_region_and_get_roundtrip() {
    let mut screen = make_screen();
    screen.set_scroll_region(5, 18);
    let region = screen.get_scroll_region();
    assert_eq!(region.top, 5);
    assert_eq!(region.bottom, 18);
}

#[test]
fn test_scroll_up_zero_is_noop() {
    let mut screen = make_screen();
    let attrs = crate::types::cell::SgrAttributes::default();
    screen.move_cursor(0, 0);
    screen.print('Q', attrs, false);
    screen.scroll_up(0, Color::Default);
    // Row 0 should still have 'Q' — scroll_up(0) rotates by 0 and is a no-op.
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'Q');
}

#[test]
fn test_scroll_region_scroll_up_does_not_affect_outside_rows() {
    // Partial-region scroll: only rows 10..20 scroll.
    let mut screen = make_screen();
    let attrs = crate::types::cell::SgrAttributes::default();
    // Write sentinel to row 0 (outside region).
    screen.move_cursor(0, 0);
    screen.print('S', attrs, false);
    // Write sentinel to row 23 (outside region).
    screen.move_cursor(23, 0);
    screen.print('E', attrs, false);

    screen.set_scroll_region(10, 20);
    screen.scroll_up(1, Color::Default);

    // Rows outside the region must be untouched.
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'S');
    assert_eq!(screen.get_cell(23, 0).unwrap().char(), 'E');
}

#[test]
fn test_full_dirty_is_set_after_full_screen_scroll_up() {
    // A fresh screen with no scrolls has no dirty rows.
    let mut screen = make_screen();
    assert_eq!(screen.take_dirty_lines().len(), 0);
    // After scroll_up, all rows must be dirty (full_dirty fast path).
    screen.scroll_up(1, Color::Default);
    let dirty = screen.take_dirty_lines();
    assert_eq!(dirty.len(), 24, "scroll_up must dirty all rows");
}

#[test]
fn test_full_dirty_cleared_by_take_dirty_lines() {
    let mut screen = make_screen();
    screen.scroll_up(1, Color::Default);
    // First drain returns all 24 rows.
    let dirty = screen.take_dirty_lines();
    assert_eq!(dirty.len(), 24);
    // Second drain must be empty (full_dirty flag was cleared).
    let dirty2 = screen.take_dirty_lines();
    assert!(
        dirty2.is_empty(),
        "full_dirty must be cleared after take_dirty_lines"
    );
}
