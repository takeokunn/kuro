// --- insert_lines / delete_lines / clear_lines ---

/// Helper: write a distinct character into column 0 of each row.
/// Row 0 → 'A', row 1 → 'B', … (wraps at 26).
fn fill_rows(screen: &mut Screen) {
    let attrs = SgrAttributes::default();
    let rows = screen.rows() as usize;
    for r in 0..rows {
        let ch = char::from(b'A' + (r % 26) as u8);
        if let Some(line) = screen.lines.get_mut(r) {
            line.update_cell_with(0, Cell::new(ch));
        }
        let _ = attrs;
    }
}

/// Return the character at column 0 of the given row.
fn row_char(screen: &Screen, row: usize) -> char {
    screen.get_cell(row, 0).map_or(' ', Cell::char)
}

/// Return true if every cell in a row is the default blank (' ', Half width).
fn row_is_blank(screen: &Screen, row: usize) -> bool {
    if let Some(line) = screen.get_line(row) {
        line.cells.iter().all(|c| c.char() == ' ')
    } else {
        false
    }
}

// ── insert_lines ──────────────────────────────────────────────────────────────

#[test]
fn insert_lines_shifts_content_down() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 1;
    screen.insert_lines(1);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 must be unchanged");
    assert!(row_is_blank(&screen, 1), "row 1 must be blank after insert");
    assert_eq!(
        row_char(&screen, 2),
        'B',
        "row 2 must have old row 1 content"
    );
    assert_eq!(
        row_char(&screen, 3),
        'C',
        "row 3 must have old row 2 content"
    );
    assert_eq!(
        row_char(&screen, 4),
        'D',
        "row 4 must have old row 3 content (E dropped)"
    );
}

#[test]
fn insert_lines_at_row_zero_shifts_all_content() {
    let mut screen = Screen::new(4, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 0;
    screen.insert_lines(1);

    assert!(row_is_blank(&screen, 0), "row 0 must be blank");
    assert_eq!(
        row_char(&screen, 1),
        'A',
        "row 1 must have old row 0 content"
    );
    assert_eq!(
        row_char(&screen, 2),
        'B',
        "row 2 must have old row 1 content"
    );
    assert_eq!(
        row_char(&screen, 3),
        'C',
        "row 3 must have old row 2 content (D dropped)"
    );
}

#[test]
fn insert_lines_count_exceeding_remaining_rows_clears_to_bottom() {
    let mut screen = Screen::new(4, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 2;
    screen.insert_lines(10);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 unchanged");
    assert_eq!(row_char(&screen, 1), 'B', "row 1 unchanged");
    assert!(row_is_blank(&screen, 2), "row 2 must be blank");
    assert!(row_is_blank(&screen, 3), "row 3 must be blank");
}

#[test]
fn insert_lines_respects_scroll_region() {
    let mut screen = Screen::new(6, 10);
    fill_rows(&mut screen);
    screen.set_scroll_region(2, 5);
    screen.cursor.row = 2;
    screen.insert_lines(1);

    assert_eq!(
        row_char(&screen, 0),
        'A',
        "row 0 outside region — unchanged"
    );
    assert_eq!(
        row_char(&screen, 1),
        'B',
        "row 1 outside region — unchanged"
    );
    assert!(
        row_is_blank(&screen, 2),
        "row 2 must be blank (inserted line)"
    );
    assert_eq!(
        row_char(&screen, 3),
        'C',
        "row 3 must have old row 2 content"
    );
    assert_eq!(
        row_char(&screen, 4),
        'D',
        "row 4 must have old row 3 content (E dropped)"
    );
    assert_eq!(
        row_char(&screen, 5),
        'F',
        "row 5 outside region — unchanged"
    );
}

#[test]
fn insert_lines_noop_when_cursor_outside_scroll_region() {
    let mut screen = Screen::new(6, 10);
    fill_rows(&mut screen);
    screen.set_scroll_region(1, 4);
    screen.cursor.row = 4;
    screen.insert_lines(1);

    for r in 0..6usize {
        let expected = char::from(b'A' + r as u8);
        assert_eq!(row_char(&screen, r), expected, "row {r} must be unchanged");
    }
}

// ── delete_lines ──────────────────────────────────────────────────────────────

#[test]
fn delete_lines_shifts_content_up() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 1;
    screen.delete_lines(1);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 unchanged");
    assert_eq!(
        row_char(&screen, 1),
        'C',
        "row 1 must have old row 2 content"
    );
    assert_eq!(
        row_char(&screen, 2),
        'D',
        "row 2 must have old row 3 content"
    );
    assert_eq!(
        row_char(&screen, 3),
        'E',
        "row 3 must have old row 4 content"
    );
    assert!(row_is_blank(&screen, 4), "row 4 must be blank");
}

#[test]
fn delete_lines_at_last_row_clears_that_row() {
    let mut screen = Screen::new(4, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 3;
    screen.delete_lines(1);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 unchanged");
    assert_eq!(row_char(&screen, 1), 'B', "row 1 unchanged");
    assert_eq!(row_char(&screen, 2), 'C', "row 2 unchanged");
    assert!(row_is_blank(&screen, 3), "row 3 must be blank after delete");
}

#[test]
fn delete_lines_respects_scroll_region() {
    let mut screen = Screen::new(6, 10);
    fill_rows(&mut screen);
    screen.set_scroll_region(1, 5);
    screen.cursor.row = 1;
    screen.delete_lines(1);

    assert_eq!(
        row_char(&screen, 0),
        'A',
        "row 0 outside region — unchanged"
    );
    assert_eq!(
        row_char(&screen, 1),
        'C',
        "row 1 must have old row 2 content"
    );
    assert_eq!(
        row_char(&screen, 2),
        'D',
        "row 2 must have old row 3 content"
    );
    assert_eq!(
        row_char(&screen, 3),
        'E',
        "row 3 must have old row 4 content"
    );
    assert!(row_is_blank(&screen, 4), "row 4 must be blank");
    assert_eq!(
        row_char(&screen, 5),
        'F',
        "row 5 outside region — unchanged"
    );
}

#[test]
fn delete_lines_noop_when_cursor_outside_scroll_region() {
    let mut screen = Screen::new(6, 10);
    fill_rows(&mut screen);
    screen.set_scroll_region(2, 5);
    screen.cursor.row = 1;
    screen.delete_lines(1);

    for r in 0..6usize {
        let expected = char::from(b'A' + r as u8);
        assert_eq!(row_char(&screen, r), expected, "row {r} must be unchanged");
    }
}

// ── clear_lines ───────────────────────────────────────────────────────────────

#[test]
fn clear_lines_blanks_range() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.clear_lines(1, 4);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 must be unchanged");
    assert!(row_is_blank(&screen, 1), "row 1 must be blank");
    assert!(row_is_blank(&screen, 2), "row 2 must be blank");
    assert!(row_is_blank(&screen, 3), "row 3 must be blank");
    assert_eq!(row_char(&screen, 4), 'E', "row 4 must be unchanged");
}

#[test]
fn clear_lines_single_row() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.clear_lines(2, 3);

    assert_eq!(row_char(&screen, 1), 'B', "row 1 unchanged");
    assert!(row_is_blank(&screen, 2), "row 2 must be blank");
    assert_eq!(row_char(&screen, 3), 'D', "row 3 unchanged");
}

#[test]
fn clear_lines_empty_range_is_noop() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.clear_lines(2, 2);

    for r in 0..5usize {
        let expected = char::from(b'A' + r as u8);
        assert_eq!(row_char(&screen, r), expected, "row {r} must be unchanged");
    }
}

#[test]
fn clear_lines_clamps_end_past_screen_height() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.clear_lines(3, 999);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 unchanged");
    assert_eq!(row_char(&screen, 1), 'B', "row 1 unchanged");
    assert_eq!(row_char(&screen, 2), 'C', "row 2 unchanged");
    assert!(row_is_blank(&screen, 3), "row 3 must be blank");
    assert!(row_is_blank(&screen, 4), "row 4 must be blank");
}

// ── New edge-case tests (made feasible by macros) ─────────────────────────────

/// Scrollback line count never goes negative after clear_scrollback on an empty buffer.
#[test]
fn test_clear_scrollback_on_empty_is_noop() {
    let mut screen = Screen::new(5, 10);
    assert_eq!(screen.scrollback_line_count, 0);
    screen.clear_scrollback();
    assert_eq!(screen.scrollback_line_count, 0);
    assert!(screen.scrollback_buffer.is_empty());
}

/// Resizing to the same dimensions must not change cursor or buffer.
#[test]
fn test_resize_same_dimensions_is_noop() {
    let mut screen = Screen::new(10, 20);
    screen.move_cursor(3, 7);
    screen.resize(10, 20);
    assert_cursor!(screen, row 3, col 7);
    assert_eq!(screen.rows(), 10);
    assert_eq!(screen.cols(), 20);
}

/// Printing to the last cell of a row and then a newline must advance to
/// the next row without wrapping the cursor column past the screen edge.
#[test]
fn test_print_at_last_col_then_newline_stays_in_bounds() {
    let mut screen = Screen::new(5, 5);
    screen.move_cursor(0, 4);
    screen.print('Z', SgrAttributes::default(), true);
    screen.line_feed(Color::Default);
    assert!(
        screen.cursor.row < 5,
        "cursor.row must be in bounds after LF"
    );
    assert!(
        screen.cursor.col < 5,
        "cursor.col must be in bounds after LF"
    );
}

/// `take_dirty_lines` returns indices in a range that only contains lines that
/// were explicitly marked dirty (no false positives from unrelated lines).
#[test]
fn test_take_dirty_lines_precision() {
    let mut screen = Screen::new(8, 10);
    // Mark only rows 2 and 5
    screen.mark_line_dirty(2);
    screen.mark_line_dirty(5);
    let mut dirty = screen.take_dirty_lines();
    dirty.sort_unstable();
    assert_eq!(dirty, vec![2, 5], "only rows 2 and 5 should be dirty");
}

/// Multiple consecutive tab stops accumulate correctly.
#[test]
fn test_multiple_tabs_accumulate() {
    let mut screen = Screen::new(5, 80);
    screen.tab();
    screen.tab();
    // After two tabs: 0→8→16
    assert_eq!(
        screen.cursor.col, 16,
        "two tabs should advance cursor to col 16"
    );
}

/// Backspace at column 0 must not underflow (cursor must stay at 0).
#[test]
fn test_backspace_at_col_zero_no_underflow() {
    let mut screen = Screen::new(5, 10);
    assert_eq!(screen.cursor.col, 0);
    screen.backspace();
    assert_eq!(
        screen.cursor.col, 0,
        "backspace at col 0 must not underflow"
    );
}

/// Scroll_up by more than the screen height must not panic and the buffer
/// grows monotonically (capped at max).
#[test]
fn test_scroll_up_large_count_no_panic() {
    let mut screen = Screen::new(3, 10);
    screen.set_scrollback_max_lines(10);
    for _ in 0..20 {
        screen.scroll_up(1, Color::Default);
    }
    assert!(
        screen.scrollback_line_count <= 10,
        "scrollback must not exceed max"
    );
}

/// `get_scrollback_lines(0)` must return an empty slice without panicking.
#[test]
fn test_get_scrollback_lines_zero_count() {
    let screen = screen_with_scrollback!(5 x 10, scrollback 5);
    let lines = screen.get_scrollback_lines(0);
    assert_eq!(
        lines.len(),
        0,
        "requesting 0 scrollback lines must return empty slice"
    );
}

/// Alternate screen is initially clean (full_dirty = false) after the switch
/// is followed by consuming dirty lines.
#[test]
fn test_alt_screen_clean_after_dirty_consumed() {
    let mut screen = Screen::new(4, 10);
    screen.switch_to_alternate();
    let _ = screen.take_dirty_lines(); // consume the initial full_dirty
    assert!(
        !screen.full_dirty,
        "alt screen must be clean after dirty lines consumed"
    );
    let dirty = screen.take_dirty_lines();
    assert!(
        dirty.is_empty(),
        "no spurious dirty lines after consumption"
    );
}
