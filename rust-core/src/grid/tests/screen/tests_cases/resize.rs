use super::*;

#[test]
fn test_resize_clamps_cursor() {
    let mut screen = Screen::new(10, 20);

    screen.move_cursor(9, 19);
    screen.resize(5, 7);

    assert!(screen.cursor().row < 5);
    assert!(screen.cursor().col < 7);
}

#[test]
fn test_resize_same_dimensions_is_noop() {
    let mut screen = Screen::new(10, 20);

    screen.move_cursor(3, 7);
    screen.resize(10, 20);

    assert_cursor!(screen, row 3, col 7);
}

#[test]
fn test_resize_zero_rows_does_not_panic() {
    let mut screen = Screen::new(10, 20);

    screen.resize(0, 20);
    assert_eq!(screen.rows(), 0);
}

#[test]
fn test_resize_zero_cols_does_not_panic() {
    let mut screen = Screen::new(10, 20);

    screen.resize(10, 0);
    assert_eq!(screen.cols(), 0);
}

#[test]
fn test_line_feed_scrolls_at_region_bottom() {
    let mut screen = Screen::new(6, 8);
    screen.set_scroll_region(2, 5);
    screen.cursor.row = 4;
    screen.cursor.col = 0;
    fill_cell(&mut screen, 2, 0, 'A');
    fill_cell(&mut screen, 4, 0, 'Z');

    screen.line_feed(Color::Default);

    assert_eq!(screen.cursor.row, 4);
    assert_eq!(screen.lines[2].cells[0].char(), ' ');
    assert_eq!(screen.lines[3].cells[0].char(), 'Z');
    assert_eq!(screen.lines[4].cells[0].char(), ' ');
}
