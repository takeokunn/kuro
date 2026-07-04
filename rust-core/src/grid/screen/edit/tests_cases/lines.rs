use super::*;

#[test]
fn insert_lines_shifts_content_down() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 1;
    screen.insert_lines(1);
    assert_row_char!(&screen, 0, 'A');
    assert_row_blank!(&screen, 1);
    assert_row_char!(&screen, 2, 'B');
    assert_row_char!(&screen, 3, 'C');
    assert_row_char!(&screen, 4, 'D');
}

#[test]
fn insert_lines_noop_outside_scroll_region() {
    let mut screen = Screen::new(6, 10);
    fill_rows(&mut screen);
    screen.set_scroll_region(1, 4);
    screen.cursor.row = 5;
    screen.insert_lines(1);
    for r in 0..6usize {
        assert_row_char!(&screen, r, char::from(b'A' + r as u8));
    }
}

#[test]
fn delete_lines_shifts_content_up() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 1;
    screen.delete_lines(1);
    assert_row_char!(&screen, 0, 'A');
    assert_row_char!(&screen, 1, 'C');
    assert_row_char!(&screen, 2, 'D');
    assert_row_char!(&screen, 3, 'E');
    assert_row_blank!(&screen, 4);
}

#[test]
fn delete_lines_noop_outside_scroll_region() {
    let mut screen = Screen::new(6, 10);
    fill_rows(&mut screen);
    screen.set_scroll_region(2, 5);
    screen.cursor.row = 0;
    screen.delete_lines(1);
    for r in 0..6usize {
        assert_row_char!(&screen, r, char::from(b'A' + r as u8));
    }
}

#[test]
fn scroll_up_moves_content_up_one_row() {
    let mut screen = Screen::new(5, 10);
    if let Some(line) = screen.lines.get_mut(1) {
        line.update_cell_with(0, Cell::new('A'));
    }
    screen.scroll_up(1, crate::types::Color::Default);
    assert_eq!(
        screen.get_cell(0, 0).map_or(' ', Cell::char),
        'A',
        "row 1 content should move to row 0 after scroll_up(1)"
    );
    assert!(row_is_blank(&screen, 4));
}

#[test]
fn scroll_down_moves_content_down_one_row() {
    let mut screen = Screen::new(5, 10);
    if let Some(line) = screen.lines.get_mut(0) {
        line.update_cell_with(0, Cell::new('B'));
    }
    screen.scroll_down(1, crate::types::Color::Default);
    assert_eq!(
        screen.get_cell(1, 0).map_or(' ', Cell::char),
        'B',
        "row 0 content should move to row 1 after scroll_down(1)"
    );
    assert!(row_is_blank(&screen, 0));
}
