use super::*;

#[test]
fn erase_chars_clears_n_cells_at_cursor() {
    let mut screen = Screen::new(5, 10);
    fill_cells!(screen, row 0, cols 0..10, 'X');
    screen.move_cursor(0, 3);
    screen.erase_chars(4, SgrAttributes::default());
    let line = screen.get_line(0).unwrap();
    for c in 0..3 {
        assert_eq!(line.cells[c].char(), 'X', "col {c} before cursor unchanged");
    }
    for c in 3..7 {
        assert_eq!(line.cells[c].char(), ' ', "col {c} must be blank after ECH");
    }
    for c in 7..10 {
        assert_eq!(
            line.cells[c].char(),
            'X',
            "col {c} after erased range unchanged"
        );
    }
    assert_eq!(screen.cursor().col, 3, "ECH must not move cursor");
}

#[test]
fn erase_chars_count_exceeds_line_width_clamps() {
    let mut screen = Screen::new(3, 8);
    fill_cells!(screen, row 0, cols 0..8, 'Y');
    screen.move_cursor(0, 5);
    screen.erase_chars(999, SgrAttributes::default());
    let line = screen.get_line(0).unwrap();
    for c in 0..5 {
        assert_eq!(line.cells[c].char(), 'Y', "col {c} before cursor unchanged");
    }
    for c in 5..8 {
        assert_eq!(line.cells[c].char(), ' ', "col {c} erased");
    }
    assert_eq!(line.cells.len(), 8, "line width preserved");
}

#[test]
fn erase_chars_zero_count_is_noop() {
    let mut screen = Screen::new(3, 8);
    fill_cells!(screen, row 0, cols 0..8, 'Z');
    screen.move_cursor(0, 3);
    screen.erase_chars(0, SgrAttributes::default());
    let line = screen.get_line(0).unwrap();
    for c in 0..8 {
        assert_eq!(line.cells[c].char(), 'Z', "col {c}: noop on count=0");
    }
}
