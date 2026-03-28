// ── FR-001: Property-based tests for Screen::print() cursor bounds ──────

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]
    #[test]
    // INVARIANT: after any print(), cursor.row < rows AND cursor.col < cols
    fn prop_print_cursor_bounds(
        rows in 1u16..=100u16,
        cols in 1u16..=200u16,
        ch in proptest::char::any(),
        auto_wrap in proptest::bool::ANY,
    ) {
        let mut screen = Screen::new(rows, cols);
        screen.print(ch, SgrAttributes::default(), auto_wrap);
        prop_assert!(screen.cursor.row < rows as usize,
            "cursor.row {} >= rows {}", screen.cursor.row, rows);
        prop_assert!(screen.cursor.col < cols as usize,
            "cursor.col {} >= cols {}", screen.cursor.col, cols);
    }

    #[test]
    // INVARIANT: cursor bounds hold regardless of starting position
    fn prop_print_cursor_bounds_from_last_col(
        rows in 1u16..=50u16,
        cols in 2u16..=100u16,
        ch in proptest::char::any(),
        auto_wrap in proptest::bool::ANY,
    ) {
        let mut screen = Screen::new(rows, cols);
        screen.move_cursor(0, cols as usize - 1);
        screen.print(ch, SgrAttributes::default(), auto_wrap);
        prop_assert!(screen.cursor.row < rows as usize);
        prop_assert!(screen.cursor.col < cols as usize);
    }
}

// ── FR-005: Screen resize edge case tests ────────────────────────────────

#[test]
fn test_resize_cursor_clamping() {
    let mut screen = Screen::new(24, 80);
    screen.move_cursor(23, 79);
    assert_cursor!(screen, row 23, col 79);
    screen.resize(10, 40);
    assert!(
        screen.cursor.row < 10,
        "cursor.row {} should be < 10",
        screen.cursor.row
    );
    assert!(
        screen.cursor.col < 40,
        "cursor.col {} should be < 40",
        screen.cursor.col
    );
}

#[test]
fn test_resize_minimum_1x1() {
    let mut screen = Screen::new(24, 80);
    screen.move_cursor(23, 79);
    screen.resize(1, 1);
    assert_cursor!(screen, row 0, col 0);
}

#[test]
fn test_resize_zero_rows_does_not_panic() {
    let mut screen = Screen::new(10, 80);
    screen.resize(0, 80);
    assert_eq!(
        screen.cursor.row, 0,
        "cursor.row should be clamped to 0 when resizing to 0 rows"
    );
}

#[test]
fn test_resize_zero_cols_does_not_panic() {
    let mut screen = Screen::new(10, 80);
    screen.resize(10, 0);
    assert_eq!(
        screen.cursor.col, 0,
        "cursor.col should be clamped to 0 when resizing to 0 cols"
    );
}

#[test]
fn test_resize_larger() {
    let mut screen = Screen::new(10, 40);
    screen.move_cursor(9, 39);
    screen.resize(24, 80);
    assert_cursor!(screen, row 9, col 39);
}

#[test]
fn test_line_feed_at_scroll_region_bottom() {
    let mut screen = Screen::new(24, 80);
    screen.set_scroll_region(5, 10);
    screen.cursor.row = 9;
    screen.cursor.col = 0;

    if let Some(line) = screen.lines.get_mut(5) {
        line.update_cell_with(0, Cell::new('A'));
    }
    if let Some(line) = screen.lines.get_mut(9) {
        line.update_cell_with(0, Cell::new('Z'));
    }

    screen.line_feed(Color::Default);

    assert_eq!(
        screen.cursor.row, 9,
        "Cursor should stay at bottom of scroll region"
    );
    assert_eq!(
        screen.lines[5].cells[0].char(),
        ' ',
        "Row 5 should be cleared after scroll"
    );
    assert_eq!(
        screen.lines[8].cells[0].char(),
        'Z',
        "Row 8 should now have 'Z'"
    );
    assert_eq!(
        screen.lines[9].cells[0].char(),
        ' ',
        "Row 9 should be a fresh blank line"
    );
}

// ── Scrollback-specific unit tests ────────────────────────────────────────────

#[test]
fn test_push_lines_to_scrollback() {
    let mut screen = Screen::new(24, 80);
    assert_eq!(screen.scrollback_line_count, 0);
    assert!(screen.scrollback_buffer.is_empty());

    screen.scroll_up(1, Color::Default);
    assert_eq!(screen.scrollback_line_count, 1);
    screen.scroll_up(1, Color::Default);
    assert_eq!(screen.scrollback_line_count, 2);
    screen.scroll_up(1, Color::Default);
    assert_eq!(screen.scrollback_line_count, 3);
    assert_eq!(screen.scrollback_buffer.len(), 3);
}

#[test]
fn test_scrollback_max_size_eviction() {
    let mut screen = Screen::new(24, 80);
    screen.set_scrollback_max_lines(5);
    assert_eq!(screen.scrollback_max_lines, 5);

    for _ in 0..10 {
        screen.scroll_up(1, Color::Default);
    }

    assert_eq!(
        screen.scrollback_line_count, 5,
        "scrollback_line_count must be clamped"
    );
    assert_eq!(
        screen.scrollback_buffer.len(),
        5,
        "scrollback_buffer.len() must equal max after eviction"
    );
}

#[test]
fn test_scrollback_eviction_retains_newest_lines() {
    let mut screen = Screen::new(24, 80);
    screen.set_scrollback_max_lines(3);
    let attrs = SgrAttributes::default();

    let labels = ['1', '2', '3', '4', '5', '6'];
    for &ch in &labels {
        screen.cursor.row = 0;
        screen.cursor.col = 0;
        screen.print(ch, attrs, true);
        screen.scroll_up(1, Color::Default);
    }

    assert_eq!(screen.scrollback_buffer.len(), 3);

    let surviving: Vec<char> = screen
        .scrollback_buffer
        .iter()
        .map(|line| line.get_cell(0).map_or(' ', crate::types::cell::Cell::char))
        .collect();

    assert_eq!(
        surviving,
        vec!['4', '5', '6'],
        "oldest lines must be evicted; only newest 3 survive"
    );
}

#[test]
fn test_scroll_offset_clamping() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 10);
    screen.viewport_scroll_up(9999);

    assert_eq!(
        screen.scroll_offset(),
        screen.scrollback_line_count,
        "scroll_offset must not exceed scrollback_line_count"
    );
}

#[test]
fn test_scroll_to_live_view() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 20);
    screen.viewport_scroll_up(15);
    assert_eq!(screen.scroll_offset(), 15);
    assert!(screen.is_scroll_dirty());

    screen.clear_scroll_dirty();
    screen.viewport_scroll_down(15);

    assert_eq!(
        screen.scroll_offset(),
        0,
        "scroll_offset must be 0 when returned to live view"
    );
    let dirty = screen.take_dirty_lines();
    assert_eq!(
        dirty.len(),
        24,
        "all rows must be dirty after returning to live view"
    );
}

// ── FR-007: Alternate screen isolation and default scrollback eviction ────────

#[test]
fn test_alt_screen_cell_content_is_isolated() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    screen.print('X', attrs, true);
    assert_cell_char!(screen, row 0, col 0, 'X');

    screen.switch_to_alternate();
    screen.print('Y', attrs, true);
    assert_cell_char!(screen, row 0, col 0, 'Y');

    screen.switch_to_primary();
    assert_cell_char!(screen, row 0, col 0, 'X', "Primary screen cell must not be polluted by alternate screen writes");
}

#[test]
fn test_default_scrollback_max_exact_eviction() {
    let mut screen = Screen::new(24, 80);
    screen.set_scrollback_max_lines(DEFAULT_SCROLLBACK_MAX);

    for _ in 0..=DEFAULT_SCROLLBACK_MAX {
        screen.scroll_up(1, Color::Default);
    }

    assert_eq!(screen.scrollback_line_count, DEFAULT_SCROLLBACK_MAX);
    assert_eq!(screen.scrollback_buffer.len(), DEFAULT_SCROLLBACK_MAX);
}

#[test]
fn test_scroll_down_no_pending_in_alternate_screen() {
    let mut screen = Screen::new(24, 80);
    screen.switch_to_alternate();
    screen.scroll_down(3, Color::Default);
    let (up, down) = screen.consume_scroll_events();
    assert_eq!(
        up, 0,
        "alternate screen scroll_down must not set pending_scroll_up"
    );
    assert_eq!(
        down, 0,
        "alternate screen scroll_down must not set pending_scroll_down"
    );
}

#[test]
fn test_viewport_scroll_down_resets_pending_scroll_counters() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    let _ = screen.consume_scroll_events();

    screen.viewport_scroll_up(10);
    screen.scroll_up(5, Color::Default);

    screen.viewport_scroll_down(10);
    assert_eq!(screen.scroll_offset(), 0);

    let (up, down) = screen.consume_scroll_events();
    assert_eq!(
        up, 0,
        "pending_scroll_up must be reset when returning to live view"
    );
    assert_eq!(
        down, 0,
        "pending_scroll_down must be reset when returning to live view"
    );
}
