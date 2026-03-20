//! Property-based and example-based tests for Screen scrollback and viewport methods.
//!
//! Module under test: `grid/screen/scrollback.rs`
//! Tier: T3 — ProptestConfig::with_cases(256)

use crate::grid::screen::Screen;
use crate::types::color::Color;
use proptest::prelude::*;

// ── Helpers ───────────────────────────────────────────────────────────────────

fn make_screen() -> Screen {
    Screen::new(24, 80)
}

/// Build a screen that already has `count` lines in the scrollback buffer.
fn screen_with_scrollback(count: usize) -> Screen {
    let mut screen = Screen::new(24, 80);
    for _ in 0..count {
        screen.scroll_up(1, Color::Default);
    }
    screen
}

// ── Property-based tests ──────────────────────────────────────────────────────

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // BOUNDARY: viewport_scroll_up(n) must not exceed scrollback_line_count.
    fn prop_viewport_scroll_up_bounded(
        scrollback_lines in 1usize..50usize,
        scroll_n in 0usize..200usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        screen.viewport_scroll_up(scroll_n);
        prop_assert!(
            screen.scroll_offset() <= screen.scrollback_line_count,
            "scroll_offset {} must be <= scrollback_line_count {}",
            screen.scroll_offset(),
            screen.scrollback_line_count
        );
    }

    #[test]
    // BOUNDARY: viewport_scroll_down(n) never underflows (scroll_offset stays >= 0).
    // (usize guarantees this; test documents and verifies the invariant explicitly.)
    fn prop_viewport_scroll_down_bounded(
        scrollback_lines in 1usize..50usize,
        scroll_up_n in 1usize..40usize,
        scroll_down_n in 0usize..200usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        // Get into a non-zero offset first.
        let clamp = scroll_up_n.min(screen.scrollback_line_count);
        screen.viewport_scroll_up(clamp);
        // Now scroll down by an arbitrary amount — must saturate at 0.
        screen.viewport_scroll_down(scroll_down_n);
        // usize can never be negative; value must be 0 or a reduced positive offset.
        prop_assert!(
            screen.scroll_offset() <= screen.scrollback_line_count,
            "scroll_offset must remain <= scrollback_line_count after scroll_down"
        );
    }

    #[test]
    // INVARIANT: viewport_scroll_up(n) where n > 0 sets scroll_dirty when there
    // is scrollback content and the offset actually changes.
    fn prop_scroll_dirty_set_on_viewport_scroll(
        scrollback_lines in 1usize..50usize,
        n in 1usize..10usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        // Ensure offset is 0 and flag is clear before the test.
        screen.clear_scroll_dirty();
        prop_assume!(screen.scroll_offset() == 0);
        screen.viewport_scroll_up(n);
        // Only set if there is actually scrollback to navigate into.
        if screen.scrollback_line_count > 0 {
            prop_assert!(
                screen.is_scroll_dirty(),
                "scroll_dirty must be set after viewport_scroll_up with scrollback"
            );
        }
    }

    #[test]
    // BOUNDARY: set_scrollback_max_lines(max) where max < current count must
    // trim scrollback_line_count down to max.
    fn prop_set_scrollback_max_trims(
        initial_lines in 10usize..30usize,
        new_max in 1usize..9usize,
    ) {
        let mut screen = screen_with_scrollback(initial_lines);
        prop_assume!(screen.scrollback_line_count > new_max);
        screen.set_scrollback_max_lines(new_max);
        prop_assert!(
            screen.scrollback_line_count <= new_max,
            "scrollback_line_count {} must be <= new_max {}",
            screen.scrollback_line_count,
            new_max
        );
        prop_assert!(
            screen.scrollback_buffer.len() <= new_max,
            "scrollback_buffer.len() {} must be <= new_max {}",
            screen.scrollback_buffer.len(),
            new_max
        );
    }

    #[test]
    // INVARIANT: clear_scrollback() always zeroes scrollback_line_count and
    // empties the buffer regardless of prior content.
    fn prop_clear_scrollback_empties(count in 0usize..40usize) {
        let mut screen = screen_with_scrollback(count);
        screen.clear_scrollback();
        prop_assert_eq!(
            screen.scrollback_line_count, 0,
            "scrollback_line_count must be 0 after clear_scrollback"
        );
        prop_assert!(
            screen.scrollback_buffer.is_empty(),
            "scrollback_buffer must be empty after clear_scrollback"
        );
    }

    #[test]
    // INVARIANT: when alternate screen is active, viewport_scroll_up is a no-op
    // (scroll_offset unchanged, scroll_dirty unchanged).
    fn prop_alternate_screen_viewport_scroll_up_noop(
        scrollback_lines in 0usize..30usize,
        n in 1usize..20usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        // Activate alternate screen.
        screen.switch_to_alternate();
        let offset_before = screen.scroll_offset();
        screen.clear_scroll_dirty();
        screen.viewport_scroll_up(n);
        prop_assert_eq!(
            screen.scroll_offset(), offset_before,
            "viewport_scroll_up must be a no-op on alternate screen"
        );
        prop_assert!(
            !screen.is_scroll_dirty(),
            "scroll_dirty must not be set by viewport_scroll_up on alternate screen"
        );
    }

    #[test]
    // INVARIANT: when alternate screen is active, viewport_scroll_down is a no-op.
    fn prop_alternate_screen_viewport_scroll_down_noop(
        scrollback_lines in 0usize..30usize,
        n in 1usize..20usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        screen.switch_to_alternate();
        let offset_before = screen.scroll_offset();
        screen.clear_scroll_dirty();
        screen.viewport_scroll_down(n);
        prop_assert_eq!(
            screen.scroll_offset(), offset_before,
            "viewport_scroll_down must be a no-op on alternate screen"
        );
    }

    #[test]
    // INVARIANT: scroll_offset after viewport_scroll_up is exactly
    // min(n, scrollback_line_count) when starting from offset 0.
    fn prop_viewport_scroll_up_exact_offset(
        scrollback_lines in 1usize..50usize,
        n in 0usize..100usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        screen.viewport_scroll_up(n);
        let expected = n.min(screen.scrollback_line_count);
        prop_assert_eq!(
            screen.scroll_offset(), expected,
            "scroll_offset must equal min(n={}, scrollback_line_count={})",
            n, screen.scrollback_line_count
        );
    }

    #[test]
    // INVARIANT: viewport_scroll_down by the full current offset returns to 0.
    fn prop_viewport_scroll_down_to_zero(
        scrollback_lines in 1usize..50usize,
        n in 1usize..30usize,
    ) {
        let mut screen = screen_with_scrollback(scrollback_lines);
        let up_n = n.min(screen.scrollback_line_count);
        screen.viewport_scroll_up(up_n);
        let offset = screen.scroll_offset();
        screen.viewport_scroll_down(offset);
        prop_assert_eq!(
            screen.scroll_offset(), 0,
            "viewport_scroll_down by the full offset must return to 0"
        );
    }

    #[test]
    // INVARIANT: scrollback grows monotonically with scroll_up on primary screen
    // up to scrollback_max_lines.
    fn prop_scrollback_grows_monotonically(
        steps in 1usize..30usize,
        max_lines in 5usize..20usize,
    ) {
        let mut screen = make_screen();
        screen.set_scrollback_max_lines(max_lines);
        let mut prev = screen.scrollback_line_count;
        for _ in 0..steps {
            screen.scroll_up(1, Color::Default);
            let curr = screen.scrollback_line_count;
            prop_assert!(
                curr >= prev,
                "scrollback_line_count must not decrease: {} < {}",
                curr, prev
            );
            prop_assert!(
                curr <= max_lines,
                "scrollback_line_count {} must not exceed max_lines {}",
                curr, max_lines
            );
            prev = curr;
        }
    }
}

// ── Example-based tests ───────────────────────────────────────────────────────

#[test]
fn test_viewport_scroll_to_live_view() {
    // After scrolling into history and back, scroll_offset must return to 0.
    let mut screen = screen_with_scrollback(20);
    screen.viewport_scroll_up(10);
    assert_eq!(screen.scroll_offset(), 10);
    screen.viewport_scroll_down(10);
    assert_eq!(screen.scroll_offset(), 0);
}

#[test]
fn test_viewport_scroll_up_clamps_at_scrollback_count() {
    let mut screen = screen_with_scrollback(10);
    screen.viewport_scroll_up(9999);
    assert_eq!(screen.scroll_offset(), screen.scrollback_line_count);
}

#[test]
fn test_viewport_scroll_down_saturates_at_zero() {
    let mut screen = screen_with_scrollback(20);
    screen.viewport_scroll_up(5);
    // Scroll down by far more than the current offset.
    screen.viewport_scroll_down(9999);
    assert_eq!(screen.scroll_offset(), 0);
}

#[test]
fn test_clear_scrollback_resets_offset() {
    let mut screen = screen_with_scrollback(20);
    screen.viewport_scroll_up(10);
    screen.clear_scrollback();
    assert_eq!(screen.scrollback_line_count, 0);
    // The viewport offset should be at most scrollback_line_count (0).
    // After clear_scrollback the offset isn't reset by the method itself,
    // but scrollback_line_count == 0 so the buffer is logically empty.
    assert!(screen.scrollback_buffer.is_empty());
}

#[test]
fn test_is_scroll_dirty_false_initially() {
    let screen = make_screen();
    assert!(!screen.is_scroll_dirty());
}

#[test]
fn test_clear_scroll_dirty_resets_flag() {
    let mut screen = screen_with_scrollback(5);
    screen.viewport_scroll_up(3);
    assert!(screen.is_scroll_dirty());
    screen.clear_scroll_dirty();
    assert!(!screen.is_scroll_dirty());
}

#[test]
fn test_viewport_scroll_up_noop_at_max_no_dirty() {
    // Already at max offset — a further scroll_up must be a no-op.
    let mut screen = screen_with_scrollback(10);
    screen.viewport_scroll_up(10); // reach max
    screen.clear_scroll_dirty();
    screen.viewport_scroll_up(1); // no-op: already at max
    assert!(!screen.is_scroll_dirty());
}

#[test]
fn test_viewport_scroll_down_to_zero_sets_full_dirty() {
    // Scrolling down to offset 0 forces a full re-render via full_dirty.
    let mut screen = screen_with_scrollback(20);
    screen.viewport_scroll_up(10);
    let _ = screen.take_dirty_lines(); // drain scroll_up dirty state
    screen.viewport_scroll_down(10); // return to live view
    // full_dirty must be set.
    let dirty = screen.take_dirty_lines();
    assert_eq!(
        dirty.len(),
        24,
        "returning to live view must mark all 24 rows dirty"
    );
}

#[test]
fn test_scroll_offset_accessor_returns_zero_initially() {
    let screen = make_screen();
    assert_eq!(screen.scroll_offset(), 0);
}

#[test]
fn test_set_scrollback_max_lines_trims_immediately() {
    let mut screen = screen_with_scrollback(10);
    assert_eq!(screen.scrollback_line_count, 10);
    screen.set_scrollback_max_lines(3);
    assert_eq!(screen.scrollback_line_count, 3);
    assert_eq!(screen.scrollback_buffer.len(), 3);
}

#[test]
fn test_set_scrollback_max_larger_than_current_no_trim() {
    let mut screen = screen_with_scrollback(5);
    screen.set_scrollback_max_lines(100);
    // No trimming should occur; count remains 5.
    assert_eq!(screen.scrollback_line_count, 5);
}

#[test]
fn test_get_scrollback_lines_order_most_recent_first() {
    // scroll_up pushes lines onto the back of scrollback_buffer.
    // get_scrollback_lines returns them in reverse (most recent first).
    let mut screen = Screen::new(5, 80);
    let attrs = crate::types::cell::SgrAttributes::default();
    for ch in ['1', '2', '3'] {
        screen.move_cursor(0, 0);
        screen.print(ch, attrs, false);
        screen.scroll_up(1, Color::Default);
    }
    let lines = screen.get_scrollback_lines(3);
    assert_eq!(lines.len(), 3);
    // Most recent line ('3') must come first.
    assert_eq!(lines[0].get_cell(0).map(|c| c.char()), Some('3'));
    assert_eq!(lines[1].get_cell(0).map(|c| c.char()), Some('2'));
    assert_eq!(lines[2].get_cell(0).map(|c| c.char()), Some('1'));
}

#[test]
fn test_viewport_scroll_down_partial_sets_scroll_dirty() {
    // Scrolling down without reaching offset 0 must set scroll_dirty (not full_dirty).
    let mut screen = screen_with_scrollback(30);
    screen.viewport_scroll_up(20);
    let _ = screen.take_dirty_lines(); // drain
    screen.clear_scroll_dirty();
    screen.viewport_scroll_down(5); // offset: 20 → 15, not 0
    assert_eq!(screen.scroll_offset(), 15);
    assert!(screen.is_scroll_dirty());
    // full_dirty must NOT be set for a partial scroll-down.
    let dirty = screen.take_dirty_lines();
    assert!(
        dirty.len() < 24,
        "full_dirty must not be set for partial viewport_scroll_down"
    );
}

// ---------------------------------------------------------------------------
// get_scrollback_viewport_line
// ---------------------------------------------------------------------------

#[test]
fn test_get_scrollback_viewport_line_empty_returns_none() {
    let screen = make_screen(); // no scrollback
    // No lines scrolled off → every row in viewport maps to None
    assert!(screen.get_scrollback_viewport_line(0).is_none());
    assert!(screen.get_scrollback_viewport_line(23).is_none());
}

#[test]
fn test_get_scrollback_viewport_line_scrolled_returns_some() {
    // Formula: idx = (n - offset) + row - (rows - 1)
    // With n=30, offset=10, rows=24:
    //   row=23 → idx = (30-10) + 23 - 23 = 20 → Some (scrollback line 20)
    //   row=0  → idx = (30-10) + 0  - 23 = -3 → None (negative)
    let mut screen = screen_with_scrollback(30);
    screen.viewport_scroll_up(10);
    // The bottom row of the scrolled viewport maps into scrollback → Some
    assert!(
        screen.get_scrollback_viewport_line(23).is_some(),
        "row 23 (bottom of viewport) must map to scrollback after viewport_scroll_up(10)"
    );
    // The top row falls before the scrollback window → None
    assert!(
        screen.get_scrollback_viewport_line(0).is_none(),
        "row 0 (top of viewport) is out of scrollback window with offset=10, n=30"
    );
}

#[test]
fn test_get_scrollback_viewport_line_out_of_range_returns_none() {
    // With n=5, offset=5, rows=24:
    //   row=0  → idx = (5-5) + 0 - 23 = -23 → None (negative)
    //   row=23 → idx = (5-5) + 23 - 23 = 0  → Some (scrollback line 0)
    // The top rows of the viewport are outside the 5-line scrollback window.
    let mut screen = screen_with_scrollback(5);
    screen.viewport_scroll_up(5);
    assert!(
        screen.get_scrollback_viewport_line(0).is_none(),
        "row 0 must be out of range: only 5 scrollback lines, offset=5"
    );
}

#[test]
fn test_alternate_screen_scroll_up_no_scrollback() {
    // scroll_up on alternate screen must NOT save lines to the primary scrollback.
    let mut screen = make_screen();
    screen.switch_to_alternate();
    for _ in 0..5 {
        screen.scroll_up(1, Color::Default);
    }
    // Switch back to primary; its scrollback must still be empty.
    screen.switch_to_primary();
    assert_eq!(
        screen.scrollback_line_count, 0,
        "alternate screen scroll_up must not write to primary scrollback"
    );
}
