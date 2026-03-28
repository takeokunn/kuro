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

// ── Eviction: oldest lines dropped when max_lines exceeded ───────────────────

#[test]
fn test_scrollback_evicts_oldest_lines_at_max() {
    // Fill scrollback to exactly max_lines, then add one more.
    // The oldest line must be evicted, keeping buffer at max_lines.
    let mut screen = Screen::new(5, 10);
    screen.set_scrollback_max_lines(3);
    let attrs = crate::types::cell::SgrAttributes::default();

    // Push 4 lines: '1', '2', '3', '4'.
    for ch in ['1', '2', '3', '4'] {
        screen.move_cursor(0, 0);
        screen.print(ch, attrs, false);
        screen.scroll_up(1, Color::Default);
    }
    // Buffer must be capped at 3.
    assert_eq!(
        screen.scrollback_line_count, 3,
        "scrollback must be capped at max_lines=3"
    );
    assert_eq!(screen.scrollback_buffer.len(), 3);

    // The oldest line ('1') must have been evicted; most-recent is '4'.
    let lines = screen.get_scrollback_lines(3);
    assert_eq!(
        lines[0].get_cell(0).map(crate::types::cell::Cell::char),
        Some('4'),
        "most recent line must be '4'"
    );
    // '1' must not appear anywhere in the buffer.
    let has_1 = lines
        .iter()
        .any(|l| l.get_cell(0).map(crate::types::cell::Cell::char) == Some('1'));
    assert!(!has_1, "evicted line '1' must not remain in scrollback");
}

// ── viewport_scroll_{up,down}(0) is a no-op ──────────────────────────────────
//
// Macro: assert that calling the given scroll method with n=0 leaves
// scroll_offset unchanged and does not set scroll_dirty.
//
// Usage:
//   assert_scroll_zero_noop!(test_name, { pre-setup? }, method_call);
macro_rules! assert_scroll_zero_noop {
    ($name:ident, $setup:expr, $call:ident) => {
        #[test]
        fn $name() {
            let mut screen = screen_with_scrollback(10);
            $setup(&mut screen);
            screen.clear_scroll_dirty();
            let offset_before = screen.scroll_offset();
            screen.$call(0);
            assert_eq!(
                screen.scroll_offset(),
                offset_before,
                concat!(stringify!($call), "(0) must not change scroll_offset")
            );
            assert!(
                !screen.is_scroll_dirty(),
                concat!(stringify!($call), "(0) must not set scroll_dirty")
            );
        }
    };
}

assert_scroll_zero_noop!(
    test_viewport_scroll_up_zero_is_noop,
    |_: &mut Screen| {},
    viewport_scroll_up
);
assert_scroll_zero_noop!(
    test_viewport_scroll_down_zero_is_noop,
    |s: &mut Screen| { s.viewport_scroll_up(5); },
    viewport_scroll_down
);

// ── set_scrollback_max_lines(0) evicts everything ────────────────────────────

#[test]
fn test_set_scrollback_max_zero_clears_all() {
    let mut screen = screen_with_scrollback(15);
    assert_eq!(screen.scrollback_line_count, 15);
    screen.set_scrollback_max_lines(0);
    assert_eq!(
        screen.scrollback_line_count, 0,
        "set_scrollback_max_lines(0) must evict all scrollback lines"
    );
    assert!(
        screen.scrollback_buffer.is_empty(),
        "scrollback_buffer must be empty after max set to 0"
    );
}

// ── get_scrollback_lines respects max_lines argument ─────────────────────────

#[test]
fn test_get_scrollback_lines_respects_limit() {
    let screen = screen_with_scrollback(20);
    let lines = screen.get_scrollback_lines(5);
    assert_eq!(
        lines.len(),
        5,
        "get_scrollback_lines(5) must return at most 5 lines even if buffer has 20"
    );
}

#[test]
fn test_get_scrollback_lines_zero_returns_empty() {
    let screen = screen_with_scrollback(10);
    let lines = screen.get_scrollback_lines(0);
    assert!(
        lines.is_empty(),
        "get_scrollback_lines(0) must return an empty Vec"
    );
}

// ── get_scrollback_viewport_line at full offset (anchor == 0) ────────────────

#[test]
fn test_get_scrollback_viewport_line_at_full_offset_bottom_row() {
    // With n=5, offset=5, rows=5:
    //   anchor = n - offset = 0
    //   row=4 (bottom) → idx = 0 + 4 - (5-1) = 0 → Some(scrollback[0])
    //   row=3           → idx = 0 + 3 - 4 = -1   → None
    let mut screen = Screen::new(5, 10);
    screen.set_scrollback_max_lines(5);
    for _ in 0..5 {
        screen.scroll_up(1, Color::Default);
    }
    assert_eq!(screen.scrollback_line_count, 5);
    screen.viewport_scroll_up(5); // scroll_offset == scrollback_line_count == 5
    assert_eq!(screen.scroll_offset(), 5);

    // Bottom row (4) maps to scrollback[0] — the oldest line.
    assert!(
        screen.get_scrollback_viewport_line(4).is_some(),
        "bottom row must map to Some(scrollback[0]) when offset==n"
    );
    // Row 3 is one step before the oldest line — out of range.
    assert!(
        screen.get_scrollback_viewport_line(3).is_none(),
        "row 3 must map to None when anchor==0 and rows==5"
    );
}

// ── scrollback empty on new screen (explicit) ─────────────────────────────────

#[test]
fn test_scrollback_empty_on_new_screen() {
    let s = make_screen();
    assert_eq!(
        s.scrollback_line_count, 0,
        "scrollback_line_count must be 0 on a fresh screen"
    );
    assert!(
        s.scrollback_buffer.is_empty(),
        "scrollback_buffer must be empty on a fresh screen"
    );
}

// ── push one line: count becomes 1 ───────────────────────────────────────────

#[test]
fn test_push_one_line_count_is_one() {
    let mut s = make_screen();
    s.scroll_up(1, Color::Default);
    assert_eq!(
        s.scrollback_line_count, 1,
        "scrollback_line_count must be 1 after one scroll_up"
    );
    assert_eq!(
        s.scrollback_buffer.len(),
        1,
        "scrollback_buffer.len() must be 1 after one scroll_up"
    );
}

// ── push lines up to max: count equals max ────────────────────────────────────

#[test]
fn test_push_up_to_max_count_equals_max() {
    let mut s = Screen::new(5, 10);
    s.set_scrollback_max_lines(4);
    for _ in 0..4 {
        s.scroll_up(1, Color::Default);
    }
    assert_eq!(
        s.scrollback_line_count, 4,
        "scrollback_line_count must equal max_lines when filled to capacity"
    );
    assert_eq!(s.scrollback_buffer.len(), 4);
}

// ── get_scrollback_lines(0) is the oldest; get_scrollback_lines(n-1) is newest

#[test]
fn test_get_scrollback_lines_oldest_and_newest_order() {
    // get_scrollback_lines returns most-recent first (index 0 = newest).
    // Push '1', '2', '3' — newest is '3' (index 0), oldest is '1' (index 2).
    let mut s = Screen::new(5, 80);
    let attrs = crate::types::cell::SgrAttributes::default();
    for ch in ['1', '2', '3'] {
        s.move_cursor(0, 0);
        s.print(ch, attrs, false);
        s.scroll_up(1, Color::Default);
    }
    let lines = s.get_scrollback_lines(3);
    assert_eq!(lines.len(), 3);
    // Index 0 = newest ('3').
    assert_eq!(
        lines[0].get_cell(0).map(crate::types::cell::Cell::char),
        Some('3'),
        "index 0 of get_scrollback_lines must be the newest line"
    );
    // Index count-1 = oldest ('1').
    assert_eq!(
        lines[2].get_cell(0).map(crate::types::cell::Cell::char),
        Some('1'),
        "index count-1 of get_scrollback_lines must be the oldest line"
    );
}

// ── get_scrollback_lines(count) out-of-bounds returns only count items ────────

#[test]
fn test_get_scrollback_lines_request_more_than_available() {
    // Requesting more lines than are in the buffer must return only what exists.
    let s = screen_with_scrollback(5);
    let lines = s.get_scrollback_lines(999);
    assert_eq!(
        lines.len(),
        5,
        "get_scrollback_lines(999) must return only the 5 available lines"
    );
}

// ── clear scrollback does not reset scroll_offset ────────────────────────────

#[test]
fn test_clear_scrollback_does_not_reset_scroll_offset() {
    // Document (not change) the current behavior: clear_scrollback empties the
    // buffer but does NOT reset scroll_offset. Callers must reset it separately.
    let mut screen = screen_with_scrollback(20);
    screen.viewport_scroll_up(10);
    let offset_before = screen.scroll_offset();
    screen.clear_scrollback();
    assert_eq!(
        screen.scrollback_line_count, 0,
        "scrollback_line_count must be 0 after clear_scrollback"
    );
    // scroll_offset is intentionally NOT reset by clear_scrollback.
    assert_eq!(
        screen.scroll_offset(),
        offset_before,
        "clear_scrollback must not change scroll_offset (caller responsibility)"
    );
}
