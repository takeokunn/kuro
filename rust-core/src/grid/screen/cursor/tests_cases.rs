use super::tests_support::*;
use crate::grid::screen::PrintableAsciiRun;
use crate::types::SgrAttributes;
use crate::{Color, Screen};
use proptest::prelude::*;

fn ascii(bytes: &[u8]) -> PrintableAsciiRun<'_> {
    PrintableAsciiRun::new(bytes).expect("test bytes must be printable ASCII")
}

#[test]
fn move_cursor_cases_clamp_and_clear_pending_wrap() {
    for (row, col, expected_row, expected_col) in [
        (5, 10, 5, 10),
        (99, 99, 23, 79),
        (9999, 0, 23, 0),
        (0, 9999, 0, 79),
    ] {
        let mut screen = make_screen();
        screen.cursor.pending_wrap = true;
        screen.move_cursor(row, col);
        assert_cursor!(screen, row expected_row, col expected_col);
        assert!(!screen.cursor.pending_wrap);
    }
}

#[test]
fn move_cursor_by_cases_clamp_and_clear_pending_wrap() {
    for (start, delta, expected) in [
        ((3, 5), (2, 4), (5, 9)),
        ((2, 3), (-100, -100), (0, 0)),
        ((5, 10), (3, 5), (8, 15)),
        ((20, 70), (100, 100), (23, 79)),
    ] {
        let mut screen = make_screen();
        screen.move_cursor(start.0, start.1);
        screen.cursor.pending_wrap = true;
        screen.move_cursor_by(delta.0, delta.1);
        assert_cursor!(screen, row expected.0, col expected.1);
        assert!(!screen.cursor.pending_wrap);
    }
}

#[test]
fn auto_wrap_marks_line_soft_wrapped() {
    let mut screen = Screen::new(3, 5);
    for ch in "abcdef".chars() {
        screen.print(ch, SgrAttributes::default(), true);
    }
    assert!(screen.lines[0].wrapped, "row 0 overflowed");
    assert!(!screen.lines[1].wrapped);
}

#[test]
fn print_ascii_run_auto_wrap_marks_line_soft_wrapped() {
    let mut screen = Screen::new(3, 5);
    screen.print_ascii_run(ascii(b"abcdef"), SgrAttributes::default(), true);
    assert!(screen.lines[0].wrapped);
    assert!(!screen.lines[1].wrapped);
}

#[test]
fn explicit_line_feed_is_a_hard_break_not_soft_wrap() {
    let mut screen = Screen::new(3, 5);
    for ch in "abcde".chars() {
        screen.print(ch, SgrAttributes::default(), true);
    }
    screen.line_feed(Color::Default);
    assert!(!screen.lines[0].wrapped);
}

#[test]
fn no_decawm_does_not_mark_soft_wrap() {
    let mut screen = Screen::new(3, 5);
    for ch in "abcdef".chars() {
        screen.print(ch, SgrAttributes::default(), false);
    }
    assert!(!screen.lines[0].wrapped);
}

#[test]
fn clear_line_resets_wrapped_flag() {
    let mut screen = Screen::new(3, 5);
    screen.print_ascii_run(ascii(b"abcdef"), SgrAttributes::default(), true);
    assert!(screen.lines[0].wrapped);
    screen.lines[0].clear();
    assert!(!screen.lines[0].wrapped);
}

#[test]
fn carriage_return_resets_col_preserves_row_and_clears_pending_wrap() {
    let mut screen = make_screen();
    screen.move_cursor(7, 50);
    screen.cursor.pending_wrap = true;
    screen.carriage_return();
    assert_cursor!(screen, row 7, col 0);
    assert!(!screen.cursor.pending_wrap);
}

#[test]
fn backspace_cases_are_saturating_and_clear_pending_wrap() {
    for (start_col, expected_col) in [(0, 0), (10, 9)] {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.backspace();
        assert_eq!(screen.cursor().col, expected_col);
        assert!(!screen.cursor.pending_wrap);
    }
}

#[test]
fn tab_cases_advance_to_next_stop_and_clear_pending_wrap() {
    for (start_col, expected_col) in [(0, 8), (7, 8), (8, 16), (16, 24), (79, 79)] {
        let mut screen = make_screen();
        screen.move_cursor(0, start_col);
        screen.cursor.pending_wrap = true;
        screen.tab();
        assert_eq!(screen.cursor().col, expected_col);
        assert!(!screen.cursor.pending_wrap);
    }
}

#[test]
fn tab_at_near_end_clamps_to_last_col() {
    let mut screen = Screen::new(5, 10);
    screen.move_cursor(0, 5);
    screen.tab();
    assert_eq!(screen.cursor().col, 8);
    screen.tab();
    assert_eq!(screen.cursor().col, 9);
}

#[test]
fn line_feed_cases_update_row_and_preserve_col() {
    for (region, start, expected) in [
        (None, (0, 40), (1, 40)),
        (None, (23, 0), (23, 0)),
        (Some((5, 10)), (2, 0), (3, 0)),
        (Some((0, 10)), (15, 0), (16, 0)),
    ] {
        let mut screen = make_screen();
        if let Some((top, bottom)) = region {
            screen.set_scroll_region(top, bottom);
        }
        screen.move_cursor(start.0, start.1);
        screen.cursor.pending_wrap = true;
        screen.line_feed(Color::Default);
        assert_cursor!(screen, row expected.0, col expected.1);
        assert!(!screen.cursor.pending_wrap);
    }
}

#[test]
fn printing_at_last_col_sets_or_skips_pending_wrap_by_decawm() {
    for (auto_wrap, expected_pending) in [(true, true), (false, false)] {
        let mut screen = Screen::new(5, 10);
        screen.move_cursor(0, 9);
        screen.print('Z', SgrAttributes::default(), auto_wrap);
        assert_cursor!(screen, row 0, col 9);
        assert_eq!(screen.cursor.pending_wrap, expected_pending);
    }
}

#[test]
fn cursor_getters_return_primary_position() {
    let mut screen = make_screen();
    screen.move_cursor(7, 13);
    assert_cursor!(screen, row 7, col 13);
}

#[test]
fn cursor_ref_on_alternate_screen_starts_at_origin() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[5;10H");
    term.advance(b"\x1b[?1049h");
    assert_cursor!(term.screen, row 0, col 0);
}

#[test]
fn cursor_mut_on_primary_modifies_primary() {
    let mut screen = make_screen();
    screen.cursor_mut().row = 7;
    screen.cursor_mut().col = 12;
    assert_cursor!(screen, row 7, col 12);
}

#[test]
fn print_ascii_run_writes_bytes_and_advances_cursor() {
    let mut screen = make_screen();
    screen.print_ascii_run(ascii(b"ABC"), SgrAttributes::default(), true);
    assert_cell(&screen, 0, 0, 'A');
    assert_cell(&screen, 0, 1, 'B');
    assert_cell(&screen, 0, 2, 'C');
    assert_eq!(screen.cursor().col, 3);
}

#[test]
fn print_ascii_run_empty_slice_is_noop() {
    let mut screen = make_screen();
    screen.move_cursor(0, 10);
    screen.print_ascii_run(ascii(b""), SgrAttributes::default(), true);
    assert_eq!(screen.cursor().col, 10);
}

#[test]
fn printable_ascii_run_rejects_control_bytes() {
    let err = PrintableAsciiRun::new(b"A\n").unwrap_err();
    assert_eq!(err.byte, b'\n');
    assert_eq!(err.index, 1);
    assert!(PrintableAsciiRun::longest_prefix(b"\nABC").is_none());
    assert_eq!(
        PrintableAsciiRun::longest_prefix(b"ABC\n")
            .unwrap()
            .as_bytes(),
        b"ABC"
    );
}

#[test]
fn print_ascii_run_wrap_cases() {
    let attrs = SgrAttributes::default();
    let mut wrapped = make_screen();
    wrapped.move_cursor(0, 78);
    wrapped.print_ascii_run(ascii(b"XYZ"), attrs, true);
    assert_cell(&wrapped, 0, 78, 'X');
    assert_cell(&wrapped, 0, 79, 'Y');
    assert_cell(&wrapped, 1, 0, 'Z');

    let mut clamped = make_screen();
    clamped.move_cursor(0, 78);
    clamped.print_ascii_run(ascii(b"XYZ"), attrs, false);
    assert_cell(&clamped, 0, 78, 'X');
    assert_cell(&clamped, 0, 79, 'Z');
    assert_cell(&clamped, 1, 0, ' ');
    assert_eq!(clamped.cursor().col, 79);
}

#[test]
fn print_ascii_run_marks_row_dirty() {
    let mut screen = make_screen();
    let _ = screen.take_dirty_lines();
    screen.move_cursor(3, 0);
    screen.print_ascii_run(ascii(b"hello"), SgrAttributes::default(), true);
    assert!(screen.take_dirty_lines().contains(&3));
}

#[test]
fn print_ascii_run_preserves_cell_count_at_line_boundary() {
    let mut screen = Screen::new(4, 10);
    screen.print_ascii_run(ascii(b"1234567890"), SgrAttributes::default(), true);
    assert_eq!(screen.get_line(0).unwrap().cells.len(), 10);
}

#[test]
fn print_ascii_char_writes_cell() {
    let mut screen = make_screen();
    screen.print('A', SgrAttributes::default(), true);
    assert_cell(&screen, 0, 0, 'A');
    assert_eq!(screen.cursor().col, 1);
}

#[test]
fn print_deferred_wrap_fires_on_next_print() {
    let mut screen = make_screen();
    let attrs = SgrAttributes::default();
    screen.move_cursor(0, 79);
    screen.print('A', attrs, true);
    assert!(screen.cursor().pending_wrap);
    screen.print('B', attrs, true);
    assert_cursor!(screen, row 1, col 1);
    assert_cell(&screen, 1, 0, 'B');
}

#[test]
fn print_marks_row_dirty() {
    let mut screen = make_screen();
    let _ = screen.take_dirty_lines();
    screen.move_cursor(5, 0);
    screen.print('Z', SgrAttributes::default(), true);
    assert!(screen.take_dirty_lines().contains(&5));
}

#[test]
fn print_wide_char_cases() {
    let mut start = make_screen();
    start.print('\u{4E2D}', SgrAttributes::default(), true);
    assert_cell(&start, 0, 0, '\u{4E2D}');
    assert_eq!(start.cursor().col, 2);

    let mut last_col = make_screen();
    last_col.move_cursor(0, 79);
    last_col.print('\u{5B57}', SgrAttributes::default(), true);
    assert_cell(&last_col, 1, 0, '\u{5B57}');
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
        for _ in 0..100 {
            screen.backspace();
        }
        prop_assert_eq!(screen.cursor().col, 0);
    }

    #[test]
    fn prop_tab_advances_to_stop(start_col in 0usize..79usize) {
        let mut screen = make_screen();
        let cols = screen.cols() as usize;
        screen.move_cursor(0, start_col);
        screen.tab();
        let expected = ((start_col / 8) + 1) * 8;
        prop_assert_eq!(screen.cursor().col, expected.min(cols - 1));
    }

    #[test]
    fn prop_control_ops_clear_pending_wrap(start_col in 0usize..79usize) {
        let ops: &[fn(&mut Screen)] = &[
            Screen::backspace,
            Screen::carriage_return,
            Screen::tab,
        ];

        for op in ops {
            let mut screen = make_screen();
            screen.move_cursor(0, start_col);
            screen.cursor.pending_wrap = true;
            op(&mut screen);
            prop_assert!(!screen.cursor().pending_wrap);
        }
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

proptest! {
    #![proptest_config(ProptestConfig::with_cases(128))]

    #[test]
    fn prop_print_ascii_run_no_panic(
        len in 0usize..200usize,
        start_col in 0usize..80usize,
        auto_wrap in proptest::bool::ANY,
    ) {
        let mut screen = make_screen();
        let bytes: Vec<u8> = (0..len).map(|i| b'A' + (i % 26) as u8).collect();
        screen.move_cursor(0, start_col);
        screen.print_ascii_run(ascii(&bytes), SgrAttributes::default(), auto_wrap);
        prop_assert!(screen.cursor().row < 24);
        prop_assert!(screen.cursor().col < 80);
        prop_assert_eq!(screen.get_line(0).unwrap().cells.len(), 80);
    }
}
