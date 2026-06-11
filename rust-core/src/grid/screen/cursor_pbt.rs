// ── PBT tests (merged from tests/unit/grid/screen/cursor.rs) ────────

use proptest::prelude::*;

fn make_screen() -> Screen {
    Screen::new(24, 80)
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    fn prop_move_cursor_clamps_row(row in 0usize..200usize, col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(row, col);
        prop_assert!(screen.cursor().row < screen.rows() as usize);
    }

    #[test]
    fn prop_move_cursor_clamps_col(row in 0usize..24usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        screen.move_cursor(row, col);
        prop_assert!(screen.cursor().col < screen.cols() as usize);
    }

    #[test]
    fn prop_move_cursor_clears_pending_wrap(row in 0usize..200usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        screen.cursor.pending_wrap = true;
        screen.move_cursor(row, col);
        prop_assert!(!screen.cursor().pending_wrap);
    }

    #[test]
    fn prop_move_cursor_by_no_panic(row_offset in i32::MIN..=i32::MAX, col_offset in i32::MIN..=i32::MAX) {
        let mut screen = make_screen();
        screen.move_cursor_by(row_offset, col_offset);
        prop_assert!(screen.cursor().row < screen.rows() as usize);
        prop_assert!(screen.cursor().col < screen.cols() as usize);
    }

    #[test]
    fn prop_move_cursor_by_clears_pending_wrap(
        row_offset in -50i32..50i32,
        col_offset in -50i32..50i32,
    ) {
        let mut screen = make_screen();
        screen.cursor.pending_wrap = true;
        screen.move_cursor_by(row_offset, col_offset);
        prop_assert!(!screen.cursor().pending_wrap);
    }

    #[test]
    fn prop_carriage_return_col_zero(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.carriage_return();
        prop_assert_eq!(screen.cursor().col, 0);
    }

    #[test]
    fn prop_backspace_saturating(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        for _ in 0..100 { screen.backspace(); }
        prop_assert_eq!(screen.cursor().col, 0);
    }

    #[test]
    fn prop_tab_advances_to_stop(start_col in 0usize..79usize) {
        let mut screen = make_screen();
        let cols = screen.cols() as usize;
        screen.move_cursor(0, start_col);
        screen.tab();
        let new_col = screen.cursor().col;
        let expected = ((start_col / 8) + 1) * 8;
        let expected_clamped = expected.min(cols - 1);
        prop_assert_eq!(new_col, expected_clamped);
    }

    #[test]
    fn prop_backspace_clears_pending_wrap(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.backspace();
        prop_assert!(!screen.cursor().pending_wrap);
    }

    #[test]
    fn prop_carriage_return_clears_pending_wrap(start_col in 0usize..80usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.carriage_return();
        prop_assert!(!screen.cursor().pending_wrap);
    }

    #[test]
    fn prop_tab_clears_pending_wrap(start_col in 0usize..79usize) {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.tab();
        prop_assert!(!screen.cursor().pending_wrap);
    }

    #[test]
    fn prop_move_cursor_exact_clamped_value(row in 0usize..200usize, col in 0usize..200usize) {
        let mut screen = make_screen();
        let rows = screen.rows() as usize;
        let cols = screen.cols() as usize;
        screen.move_cursor(row, col);
        prop_assert_eq!(screen.cursor().row, row.min(rows - 1));
        prop_assert_eq!(screen.cursor().col, col.min(cols - 1));
    }
}

#[test]
fn pbt_line_feed_advances_row() {
    let mut screen = make_screen();
    assert_eq!(screen.cursor().row, 0);
    screen.line_feed(Color::Default);
    assert_eq!(screen.cursor().row, 1);
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn pbt_line_feed_clears_pending_wrap() {
    let mut screen = make_screen();
    screen.move_cursor(5, 10);
    screen.cursor.pending_wrap = true;
    screen.line_feed(Color::Default);
    assert!(!screen.cursor().pending_wrap);
}

#[test]
fn pbt_line_feed_at_bottom_scrolls() {
    let mut screen = make_screen();
    screen.move_cursor(23, 0);
    screen.line_feed(Color::Default);
    assert_eq!(screen.cursor().row, 23);
}

#[test]
fn pbt_move_cursor_clamps_to_last_row() {
    let mut screen = make_screen();
    screen.move_cursor(9999, 0);
    assert_eq!(screen.cursor().row, 23);
}

#[test]
fn pbt_move_cursor_clamps_to_last_col() {
    let mut screen = make_screen();
    screen.move_cursor(0, 9999);
    assert_eq!(screen.cursor().col, 79);
}

#[test]
fn pbt_backspace_from_zero_stays_zero() {
    let mut screen = make_screen();
    screen.backspace();
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn pbt_backspace_decrements_col() {
    let mut screen = make_screen();
    screen.move_cursor(0, 10);
    screen.backspace();
    assert_eq!(screen.cursor().col, 9);
}

#[test]
fn pbt_tab_from_col_zero() {
    let mut screen = make_screen();
    screen.tab();
    assert_eq!(screen.cursor().col, 8);
}

#[test]
fn pbt_tab_from_col_7() {
    let mut screen = make_screen();
    screen.move_cursor(0, 7);
    screen.tab();
    assert_eq!(screen.cursor().col, 8);
}

#[test]
fn pbt_tab_from_col_8() {
    let mut screen = make_screen();
    screen.move_cursor(0, 8);
    screen.tab();
    assert_eq!(screen.cursor().col, 16);
}

#[test]
fn pbt_tab_at_last_tab_stop_clamps() {
    let mut screen = make_screen();
    screen.move_cursor(0, 79);
    screen.tab();
    assert_eq!(screen.cursor().col, 79);
}

#[test]
fn pbt_move_cursor_by_positive_offsets() {
    let mut screen = make_screen();
    screen.move_cursor(5, 10);
    screen.move_cursor_by(3, 5);
    assert_eq!(screen.cursor().row, 8);
    assert_eq!(screen.cursor().col, 15);
}

#[test]
fn pbt_move_cursor_by_negative_clamps_at_zero() {
    let mut screen = make_screen();
    screen.move_cursor(2, 5);
    screen.move_cursor_by(-1000, -1000);
    assert_eq!(screen.cursor().row, 0);
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn pbt_move_cursor_by_large_positive_clamps_at_max() {
    let mut screen = make_screen();
    screen.move_cursor_by(10000, 10000);
    assert_eq!(screen.cursor().row, 23);
    assert_eq!(screen.cursor().col, 79);
}

// ── print_ascii_run tests ───────────────────────────────────────────

#[test]
fn pbt_print_ascii_run_writes_bytes_at_cursor() {
    let mut screen = make_screen();
    screen.move_cursor(0, 0);
    screen.print_ascii_run(b"ABC", SgrAttributes::default(), true);
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'A');
    assert_eq!(screen.get_cell(0, 1).unwrap().char(), 'B');
    assert_eq!(screen.get_cell(0, 2).unwrap().char(), 'C');
}

#[test]
fn pbt_print_ascii_run_advances_cursor() {
    let mut screen = make_screen();
    screen.move_cursor(0, 0);
    screen.print_ascii_run(b"HELLO", SgrAttributes::default(), true);
    assert_eq!(screen.cursor().col, 5);
}

#[test]
fn pbt_print_ascii_run_empty_slice_is_noop() {
    let mut screen = make_screen();
    screen.move_cursor(0, 10);
    screen.print_ascii_run(b"", SgrAttributes::default(), true);
    assert_eq!(screen.cursor().col, 10);
}

#[test]
fn pbt_print_ascii_run_wraps_at_right_margin_with_auto_wrap() {
    let mut screen = make_screen();
    screen.move_cursor(0, 78);
    screen.print_ascii_run(b"XYZ", SgrAttributes::default(), true);
    assert_eq!(screen.get_cell(0, 78).unwrap().char(), 'X');
    assert_eq!(screen.get_cell(0, 79).unwrap().char(), 'Y');
    assert_eq!(screen.get_cell(1, 0).unwrap().char(), 'Z');
}

#[test]
fn pbt_print_ascii_run_no_wrap_without_auto_wrap() {
    let mut screen = make_screen();
    screen.move_cursor(0, 78);
    screen.print_ascii_run(b"XYZ", SgrAttributes::default(), false);
    assert_eq!(screen.get_cell(0, 78).unwrap().char(), 'X');
    assert_eq!(screen.get_cell(0, 79).unwrap().char(), 'Z');
    assert_eq!(screen.get_cell(1, 0).unwrap().char(), ' ');
    assert_eq!(screen.cursor().col, 79);
}

#[test]
fn pbt_print_ascii_run_marks_row_dirty() {
    let mut screen = make_screen();
    let _ = screen.take_dirty_lines();
    screen.move_cursor(3, 0);
    screen.print_ascii_run(b"hello", SgrAttributes::default(), true);
    let dirty = screen.take_dirty_lines();
    assert!(dirty.contains(&3));
}

#[test]
fn pbt_print_ascii_run_preserves_cell_count_at_line_boundary() {
    let mut screen = Screen::new(4, 10);
    screen.move_cursor(0, 0);
    screen.print_ascii_run(b"1234567890", SgrAttributes::default(), true);
    assert_eq!(screen.get_line(0).unwrap().cells.len(), 10);
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(128))]

    #[test]
    fn prop_print_ascii_run_no_panic(
        len in 0usize..200usize,
        start_col in 0usize..80usize,
        auto_wrap in proptest::bool::ANY,
    ) {
        let mut screen = Screen::new(24, 80);
        let bytes: Vec<u8> = (0..len).map(|i| b'A' + (i % 26) as u8).collect();
        screen.move_cursor(0, start_col);
        screen.print_ascii_run(&bytes, SgrAttributes::default(), auto_wrap);
        prop_assert!(screen.cursor().row < 24);
        prop_assert!(screen.cursor().col < 80);
        prop_assert_eq!(screen.get_line(0).unwrap().cells.len(), 80);
    }
}

// ── print() tests ───────────────────────────────────────────────────

#[test]
fn pbt_print_ascii_char_writes_cell() {
    let mut screen = make_screen();
    screen.move_cursor(0, 0);
    screen.print('A', SgrAttributes::default(), true);
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'A');
    assert_eq!(screen.cursor().col, 1);
}

#[test]
fn pbt_print_sets_pending_wrap_at_last_column() {
    let mut screen = make_screen();
    screen.move_cursor(0, 79);
    screen.print('X', SgrAttributes::default(), true);
    assert!(screen.cursor().pending_wrap);
    assert_eq!(screen.cursor().col, 79);
}

#[test]
fn pbt_print_no_pending_wrap_without_auto_wrap() {
    let mut screen = make_screen();
    screen.move_cursor(0, 79);
    screen.print('X', SgrAttributes::default(), false);
    assert!(!screen.cursor().pending_wrap);
}

#[test]
fn pbt_print_deferred_wrap_fires_on_next_print() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 79);
    screen.print('A', attrs, true);
    assert!(screen.cursor().pending_wrap);
    screen.print('B', attrs, true);
    assert_eq!(screen.cursor().row, 1);
    assert_eq!(screen.cursor().col, 1);
    assert_eq!(screen.get_cell(1, 0).unwrap().char(), 'B');
}

#[test]
fn pbt_print_marks_row_dirty() {
    let mut screen = make_screen();
    let _ = screen.take_dirty_lines();
    screen.move_cursor(5, 0);
    screen.print('Z', SgrAttributes::default(), true);
    let dirty = screen.take_dirty_lines();
    assert!(dirty.contains(&5));
}

#[test]
fn pbt_print_wide_char_places_placeholder() {
    let mut screen = make_screen();
    screen.move_cursor(0, 0);
    screen.print('\u{4E2D}', SgrAttributes::default(), true);
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), '\u{4E2D}');
    assert_eq!(screen.cursor().col, 2);
}

#[test]
fn pbt_print_wide_char_at_last_col_wraps() {
    let mut screen = make_screen();
    screen.move_cursor(0, 79);
    screen.print('\u{5B57}', SgrAttributes::default(), true);
    assert_eq!(screen.get_cell(1, 0).unwrap().char(), '\u{5B57}');
}

#[test]
fn pbt_cursor_ref_on_primary_screen() {
    let screen = make_screen();
    assert_eq!(screen.cursor().row, 0);
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn pbt_cursor_ref_on_alternate_screen() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[5;10H");
    term.advance(b"\x1b[?1049h");
    assert_eq!(term.screen.cursor().row, 0);
    assert_eq!(term.screen.cursor().col, 0);
}

#[test]
fn pbt_cursor_mut_on_primary_modifies_primary() {
    let mut screen = make_screen();
    screen.cursor_mut().row = 7;
    screen.cursor_mut().col = 12;
    assert_eq!(screen.cursor().row, 7);
    assert_eq!(screen.cursor().col, 12);
}

#[test]
fn pbt_line_feed_outside_scroll_region_moves_down() {
    let mut screen = make_screen();
    screen.set_scroll_region(5, 10);
    screen.move_cursor(2, 0);
    screen.line_feed(Color::Default);
    assert_eq!(screen.cursor().row, 3);
}

#[test]
fn pbt_line_feed_below_scroll_region_does_not_scroll() {
    let mut screen = make_screen();
    screen.set_scroll_region(0, 10);
    screen.move_cursor(15, 0);
    screen.line_feed(Color::Default);
    assert_eq!(screen.cursor().row, 16);
}

#[test]
fn pbt_line_feed_at_screen_bottom_clamps() {
    let mut screen = make_screen();
    screen.move_cursor(23, 0);
    screen.line_feed(Color::Default);
    assert_eq!(screen.cursor().row, 23);
}

#[test]
fn pbt_move_cursor_rel_positive_overflow_clamps() {
    let mut screen = make_screen();
    screen.move_cursor(20, 70);
    screen.move_cursor_by(100, 100);
    assert_eq!(screen.cursor().row, 23);
    assert_eq!(screen.cursor().col, 79);
}

#[test]
fn pbt_move_cursor_rel_negative_overflow_clamps_at_origin() {
    let mut screen = make_screen();
    screen.move_cursor(3, 5);
    screen.move_cursor_by(-100, -100);
    assert_eq!(screen.cursor().row, 0);
    assert_eq!(screen.cursor().col, 0);
}

#[test]
fn pbt_tab_from_col_exactly_at_tab_stop_jumps_to_next_stop() {
    let mut screen = make_screen();
    screen.move_cursor(0, 16);
    screen.tab();
    assert_eq!(screen.cursor().col, 24);
}

#[test]
fn pbt_line_feed_col_preserved_after_advance() {
    let mut screen = make_screen();
    screen.move_cursor(0, 40);
    screen.line_feed(Color::Default);
    assert_eq!(screen.cursor().row, 1);
    assert_eq!(screen.cursor().col, 40);
}

#[test]
fn pbt_carriage_return_row_unchanged() {
    let mut screen = make_screen();
    screen.move_cursor(7, 50);
    screen.carriage_return();
    assert_eq!(screen.cursor().row, 7);
    assert_eq!(screen.cursor().col, 0);
}
