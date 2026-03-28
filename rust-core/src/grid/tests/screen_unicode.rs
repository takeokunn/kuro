// ── Phase 11: Unicode & CJK tests ────────────────────────────────────────

#[test]
fn test_print_cjk_basic() {
    let mut screen = Screen::new(24, 80);
    screen.print('日', SgrAttributes::default(), true);

    assert_cell_char!(screen, row 0, col 0, '日');
    assert_cell_width!(screen, row 0, col 0, CellWidth::Full);
    assert_cell_char!(screen, row 0, col 1, ' ');
    assert_cell_width!(screen, row 0, col 1, CellWidth::Wide);
    assert_eq!(screen.cursor.col, 2);
}

#[test]
fn test_print_cjk_cursor_position() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();
    screen.print('日', attrs, true);
    screen.print('本', attrs, true);
    screen.print('語', attrs, true);

    assert_eq!(screen.cursor.col, 6);
    for (col, expected_width) in [
        (0, CellWidth::Full),
        (1, CellWidth::Wide),
        (2, CellWidth::Full),
        (3, CellWidth::Wide),
        (4, CellWidth::Full),
        (5, CellWidth::Wide),
    ] {
        assert_cell_width!(screen, row 0, col col, expected_width);
    }
}

#[test]
fn test_print_cjk_wrap() {
    let mut screen = Screen::new(24, 80);
    screen.move_cursor(0, 79);
    screen.print('日', SgrAttributes::default(), true);

    assert_cell_char!(screen, row 1, col 0, '日');
    assert_cell_width!(screen, row 1, col 0, CellWidth::Full);
    assert_cell_width!(screen, row 1, col 1, CellWidth::Wide);
}

#[test]
fn test_print_emoji() {
    let mut screen = Screen::new(24, 80);
    screen.print('🎉', SgrAttributes::default(), true);

    assert_cell_char!(screen, row 0, col 0, '🎉');
    assert_cell_width!(screen, row 0, col 0, CellWidth::Full);
    assert_cell_width!(screen, row 0, col 1, CellWidth::Wide);
    assert_eq!(screen.cursor.col, 2);
}

#[test]
fn test_dch_at_wide_placeholder_blanks_full_partner() {
    let mut screen = Screen::new(24, 80);
    screen.print('日', SgrAttributes::default(), true);

    screen.move_cursor(0, 1);
    screen.delete_chars(1);

    assert_cell_width!(screen, row 0, col 0, CellWidth::Half, "Full partner must be blanked when DCH hits Wide placeholder");
    assert_cell_char!(screen, row 0, col 0, ' ');
}

#[test]
fn test_dch_at_full_cell_blanks_wide_partner() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();
    screen.print('A', attrs, true);
    screen.print('日', attrs, true);

    screen.move_cursor(0, 1);
    screen.delete_chars(1);

    assert_cell_width!(screen, row 0, col 1, CellWidth::Half, "Wide partner must be blanked when Full cell is DCH'd");
}

#[test]
fn test_ich_at_wide_placeholder_blanks_full_partner() {
    let mut screen = Screen::new(24, 10);
    screen.print('日', SgrAttributes::default(), true);

    screen.move_cursor(0, 1);
    screen.insert_chars(1, SgrAttributes::default());

    assert_cell_width!(screen, row 0, col 0, CellWidth::Half, "Full partner must be blanked when ICH inserts at Wide placeholder");
    assert_cell_char!(screen, row 0, col 0, ' ');
}

#[test]
fn test_ech_range_ends_at_full_blanks_wide_partner() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();
    screen.print('A', attrs, true);
    screen.print('日', attrs, true);

    screen.move_cursor(0, 0);
    screen.erase_chars(2, attrs);

    assert_cell_width!(screen, row 0, col 2, CellWidth::Half, "Wide partner must be blanked when ECH range ends on Full cell");
    assert_cell_char!(screen, row 0, col 2, ' ');
}

#[test]
fn test_ech_starts_at_wide_blanks_full_partner() {
    let mut screen = Screen::new(24, 80);
    screen.print('日', SgrAttributes::default(), true);

    screen.move_cursor(0, 1);
    screen.erase_chars(1, SgrAttributes::default());

    assert_cell_width!(screen, row 0, col 0, CellWidth::Half, "Full partner must be blanked when ECH starts at Wide placeholder");
    assert_cell_char!(screen, row 0, col 0, ' ');
    assert_cell_width!(screen, row 0, col 1, CellWidth::Half);
}

// ── Phase 12: Scrollback Viewport Navigation tests ─────────────────────

#[test]
fn test_viewport_scroll_up_basic() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    assert_eq!(screen.scroll_offset(), 0);
    screen.viewport_scroll_up(10);
    assert_eq!(screen.scroll_offset(), 10);
    assert!(screen.is_scroll_dirty());
}

#[test]
fn test_viewport_scroll_up_clamps_at_buffer_size() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    let max = screen.scrollback_line_count;
    screen.viewport_scroll_up(max + 1000);
    assert_eq!(screen.scroll_offset(), max);
}

#[test]
fn test_viewport_scroll_up_noop_at_max() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    let max = screen.scrollback_line_count;
    screen.viewport_scroll_up(max);
    screen.clear_scroll_dirty();
    screen.viewport_scroll_up(1);
    assert!(!screen.is_scroll_dirty());
}

#[test]
fn test_viewport_scroll_down_resets_to_zero() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    screen.viewport_scroll_up(20);
    screen.clear_scroll_dirty();
    screen.viewport_scroll_down(20);
    assert_eq!(screen.scroll_offset(), 0);
    assert!(!screen.is_scroll_dirty());
    let dirty_lines = screen.take_dirty_lines();
    assert_eq!(dirty_lines.len(), 24);
}

#[test]
fn test_viewport_scroll_down_partial_reduction() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 50);
    screen.viewport_scroll_up(20);
    screen.clear_scroll_dirty();

    let _ = screen.take_dirty_lines();

    screen.viewport_scroll_down(10);
    assert_eq!(screen.scroll_offset(), 10);
    assert!(screen.is_scroll_dirty());
    let dirty = screen.take_dirty_lines();
    assert!(
        dirty.len() < 24,
        "full_dirty should not be set for partial scroll down"
    );
}

#[test]
fn test_viewport_scroll_down_saturates_at_zero() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    screen.viewport_scroll_up(5);
    screen.viewport_scroll_down(1000);
    assert_eq!(screen.scroll_offset(), 0);
}

#[test]
fn test_viewport_line_correct_content() {
    let mut screen = Screen::new(24, 80);
    screen.print('A', SgrAttributes::default(), true);
    screen.scroll_up(1, Color::Default);
    assert_eq!(screen.scrollback_line_count, 1);
    screen.viewport_scroll_up(1);
    let line = screen.get_scrollback_viewport_line(23);
    assert!(line.is_some());
    assert_eq!(line.unwrap().cells[0].char(), 'A');
}

#[test]
fn test_viewport_line_none_for_partial_buffer() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 5);
    screen.viewport_scroll_up(5);
    let line = screen.get_scrollback_viewport_line(0);
    assert!(line.is_none());
}

#[test]
fn test_viewport_noop_in_alternate_screen() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    screen.switch_to_alternate();
    let offset_before = screen.scroll_offset();
    screen.viewport_scroll_up(10);
    assert_eq!(screen.scroll_offset(), offset_before);
    assert!(!screen.is_scroll_dirty());
}

#[test]
fn test_resize_while_alternate_screen_active() {
    let mut screen = Screen::new(10, 10);
    screen.switch_to_alternate();
    assert!(screen.is_alternate_screen_active());
    screen.resize(20, 40);
    assert_eq!(screen.rows(), 20);
    assert_eq!(screen.cols(), 40);
    screen.switch_to_primary();
    assert_eq!(screen.rows(), 20);
    assert_eq!(screen.cols(), 40);
}

// ── push_combining boundary tests ─────────────────────────────────────────────

#[test]
fn test_push_combining_at_col0_no_panic() {
    let mut screen = Screen::new(24, 80);
    screen.attach_combining(0, 0, '\u{0301}');
    let cell = screen.get_cell(0, 0).unwrap();
    assert!(
        !cell.grapheme().is_empty(),
        "cell grapheme must remain non-empty"
    );
}

#[test]
fn test_push_combining_after_wide_char_no_corruption() {
    let mut screen = Screen::new(24, 80);
    screen.print('日', SgrAttributes::default(), true);
    screen.attach_combining(0, 1, '\u{0301}');

    let full_cell = screen.get_cell(0, 0).unwrap();
    let wide_cell = screen.get_cell(0, 1).unwrap();
    assert!(!full_cell.grapheme().is_empty());
    assert!(!wide_cell.grapheme().is_empty());
    assert_cell_char!(screen, row 0, col 0, '日');
}

#[test]
fn test_push_combining_cap_at_32_bytes() {
    let mut screen = Screen::new(24, 80);
    screen.print('a', SgrAttributes::default(), true);
    for _ in 0..20 {
        screen.attach_combining(0, 0, '\u{0301}');
    }
    let cell = screen.get_cell(0, 0).unwrap();
    assert!(
        cell.grapheme().len() <= 32,
        "grapheme byte length {} must not exceed 32-byte cap",
        cell.grapheme().len()
    );
    assert_cell_char!(screen, row 0, col 0, 'a');
}

proptest! {
    #[test]
    fn prop_scrollback_bounded_by_max(n in 1usize..=200usize) {
        let mut screen = Screen::new(10, 40);
        screen.set_scrollback_max_lines(50);
        for _ in 0..n {
            screen.scroll_up(1, Color::Default);
        }
        prop_assert!(screen.scrollback_line_count <= 50);
    }
}
