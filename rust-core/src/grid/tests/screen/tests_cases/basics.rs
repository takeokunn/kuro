use super::*;

#[test]
fn test_screen_creation_starts_blank() {
    let screen = Screen::new(3, 4);

    assert_eq!(screen.rows(), 3);
    assert_eq!(screen.cols(), 4);
    assert_cursor!(screen, row 0, col 0);
    for row in 0..3 {
        for col in 0..4 {
            assert_eq!(screen.get_cell(row, col).unwrap().char(), ' ');
        }
    }
}

#[test]
fn test_print_advances_cursor_and_marks_dirty() {
    let mut screen = Screen::new(2, 4);

    screen.print('A', SgrAttributes::default(), true);

    assert_cell_char!(screen, row 0, col 0, 'A');
    assert_cursor!(screen, row 0, col 1);
    assert!(screen.take_dirty_lines().contains(&0));
}

#[test]
fn test_line_feed_wraps_to_next_row() {
    let mut screen = Screen::new(3, 4);

    screen.move_cursor(0, 0);
    screen.print('A', SgrAttributes::default(), true);
    screen.line_feed(Color::Default);

    assert_cursor!(screen, row 1, col 1);
}

#[test]
fn test_backspace_and_tab_stay_in_bounds() {
    let mut screen = Screen::new(2, 16);

    screen.backspace();
    assert_cursor!(screen, row 0, col 0);

    screen.tab();
    assert_cursor!(screen, row 0, col 8);
    screen.tab();
    assert_cursor!(screen, row 0, col 16.min(screen.cols() as usize - 1));
}
