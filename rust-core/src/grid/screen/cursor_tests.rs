// ── move_cursor (absolute) ────────────────────────────────────────────────

#[test]
fn move_cursor_to_basic() {
    let mut screen = Screen::new(24, 80);
    screen.move_cursor(5, 10);
    assert_cursor!(screen, row 5, col 10);
}

// ── soft-wrap tracking (Line::wrapped) ────────────────────────────────────

#[test]
fn auto_wrap_marks_line_soft_wrapped() {
    let mut screen = Screen::new(3, 5); // 3 rows, 5 cols
    // The 6th char overflows the 5-col row 0 → DECAWM auto-wrap.
    for ch in "abcdef".chars() {
        screen.print(ch, SgrAttributes::default(), true);
    }
    assert!(screen.lines[0].wrapped, "row 0 overflowed → soft-wrapped");
    assert!(
        !screen.lines[1].wrapped,
        "row 1 holds the continuation, not itself wrapped"
    );
}

#[test]
fn print_ascii_run_auto_wrap_marks_line_soft_wrapped() {
    let mut screen = Screen::new(3, 5);
    screen.print_ascii_run(b"abcdef", SgrAttributes::default(), true);
    assert!(
        screen.lines[0].wrapped,
        "the ASCII fast path must also record soft-wrap"
    );
    assert!(!screen.lines[1].wrapped);
}

#[test]
fn explicit_line_feed_is_a_hard_break_not_soft_wrap() {
    let mut screen = Screen::new(3, 5);
    // Fill row 0 exactly (sets pending_wrap but does not wrap yet).
    for ch in "abcde".chars() {
        screen.print(ch, SgrAttributes::default(), true);
    }
    screen.line_feed(Color::Default); // explicit LF = hard break
    assert!(
        !screen.lines[0].wrapped,
        "an explicit line feed must not mark the line soft-wrapped"
    );
}

#[test]
fn no_decawm_does_not_mark_soft_wrap() {
    let mut screen = Screen::new(3, 5);
    for ch in "abcdef".chars() {
        screen.print(ch, SgrAttributes::default(), false); // auto_wrap off
    }
    assert!(
        !screen.lines[0].wrapped,
        "without DECAWM the cursor clamps; no soft-wrap"
    );
}

#[test]
fn clear_line_resets_wrapped_flag() {
    let mut screen = Screen::new(3, 5);
    screen.print_ascii_run(b"abcdef", SgrAttributes::default(), true);
    assert!(screen.lines[0].wrapped);
    screen.lines[0].clear();
    assert!(!screen.lines[0].wrapped, "clear() resets the wrap flag");
}

#[test]
fn move_cursor_to_clamped_at_bounds() {
    let mut screen = Screen::new(10, 20);
    screen.move_cursor(99, 99);
    assert_cursor!(screen, row 9, col 19);
}

#[test]
fn move_cursor_clears_pending_wrap() {
    let mut screen = Screen::new(5, 5);
    screen.move_cursor(0, 4);
    screen.print('X', SgrAttributes::default(), true);
    assert!(
        screen.cursor.pending_wrap,
        "sanity: pending_wrap must be set"
    );
    screen.move_cursor(0, 0);
    assert!(
        !screen.cursor.pending_wrap,
        "move_cursor must clear pending_wrap"
    );
}

// ── move_cursor_by (relative) ─────────────────────────────────────────────

#[test]
fn move_cursor_by_positive_delta() {
    let mut screen = Screen::new(24, 80);
    screen.move_cursor(3, 5);
    // move_cursor_by(row_offset, col_offset): row 3+2=5, col 5+4=9
    screen.move_cursor_by(2, 4);
    assert_cursor!(screen, row 5, col 9);
}

#[test]
fn move_cursor_by_negative_clamps_at_zero() {
    let mut screen = Screen::new(24, 80);
    screen.move_cursor(2, 3);
    screen.move_cursor_by(-100, -100);
    assert_cursor!(screen, row 0, col 0);
}

#[test]
fn move_cursor_by_clears_pending_wrap() {
    let mut screen = Screen::new(5, 5);
    screen.move_cursor(0, 4);
    screen.print('X', SgrAttributes::default(), true);
    assert!(screen.cursor.pending_wrap);
    screen.move_cursor_by(0, -1);
    assert!(
        !screen.cursor.pending_wrap,
        "move_cursor_by must clear pending_wrap"
    );
}
