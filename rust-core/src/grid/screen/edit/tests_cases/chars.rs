use super::*;

#[test]
fn insert_chars_shifts_existing_right() {
    let mut screen = Screen::new(3, 8);
    fill_cells!(screen, row 0, cols 0..8, c => char::from(b'A' + c as u8));
    screen.move_cursor(0, 2);
    screen.insert_chars(2, SgrAttributes::default());
    let line = screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), 'A');
    assert_eq!(line.cells[1].char(), 'B');
    assert_eq!(line.cells[2].char(), ' ', "inserted blank at col 2");
    assert_eq!(line.cells[3].char(), ' ', "inserted blank at col 3");
    assert_eq!(line.cells[4].char(), 'C', "old col 2 shifted to col 4");
    assert_eq!(line.cells[5].char(), 'D');
}

#[test]
fn insert_chars_at_col_zero_shifts_all() {
    let mut screen = Screen::new(3, 5);
    fill_cells!(screen, row 0, cols 0..5, c => char::from(b'A' + c as u8));
    screen.move_cursor(0, 0);
    screen.insert_chars(1, SgrAttributes::default());
    let line = screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), ' ', "blank at col 0");
    assert_eq!(line.cells[1].char(), 'A', "old col 0 shifted to col 1");
    assert_eq!(line.cells[2].char(), 'B');
}

#[test]
fn delete_chars_shifts_remaining_left() {
    let mut screen = Screen::new(3, 8);
    fill_cells!(screen, row 0, cols 0..8, c => char::from(b'A' + c as u8));
    screen.move_cursor(0, 2);
    screen.delete_chars(2);
    let line = screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), 'A');
    assert_eq!(line.cells[1].char(), 'B');
    assert_eq!(line.cells[2].char(), 'E', "old col 4 shifted to col 2");
    assert_eq!(line.cells[3].char(), 'F');
    assert_eq!(line.cells[6].char(), ' ', "tail filled with blank");
    assert_eq!(line.cells[7].char(), ' ');
    assert_eq!(line.cells.len(), 8, "line width preserved");
}

#[test]
fn delete_chars_count_exceeds_remaining_clamps() {
    let mut screen = Screen::new(3, 5);
    fill_cells!(screen, row 0, cols 0..5, c => char::from(b'0' + c as u8));
    screen.move_cursor(0, 3);
    screen.delete_chars(999);
    let line = screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), '0');
    assert_eq!(line.cells[1].char(), '1');
    assert_eq!(line.cells[2].char(), '2');
    assert_eq!(line.cells[3].char(), ' ', "erased by DCH");
    assert_eq!(line.cells[4].char(), ' ', "erased by DCH");
    assert_eq!(line.cells.len(), 5);
}
