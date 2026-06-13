use super::*;

fn fill_rows(screen: &mut Screen) {
    let rows = screen.rows() as usize;
    for r in 0..rows {
        let ch = char::from(b'A' + (r % 26) as u8);
        if let Some(line) = screen.lines.get_mut(r) {
            line.update_cell_with(0, Cell::new(ch));
        }
    }
}

fn row_char(screen: &Screen, row: usize) -> char {
    screen.get_cell(row, 0).map_or(' ', Cell::char)
}

fn row_is_blank(screen: &Screen, row: usize) -> bool {
    screen
        .get_line(row)
        .is_some_and(|l| l.cells.iter().all(|c| c.char() == ' '))
}

macro_rules! assert_row_char {
    ($screen:expr, $row:expr, $ch:expr) => {
        assert_eq!(row_char($screen, $row), $ch, "row {} char mismatch", $row);
    };
}

macro_rules! assert_row_blank {
    ($screen:expr, $row:expr) => {
        assert!(row_is_blank($screen, $row), "row {} must be blank", $row);
    };
}

// ── erase_chars ───────────────────────────────────────────────────────────

#[test]
fn erase_chars_clears_n_cells_at_cursor() {
    let mut screen = Screen::new(5, 10);
    for c in 0..10 {
        if let Some(line) = screen.lines.get_mut(0) {
            line.update_cell_with(c, Cell::new('X'));
        }
    }
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
    for c in 0..8 {
        if let Some(line) = screen.lines.get_mut(0) {
            line.update_cell_with(c, Cell::new('Y'));
        }
    }
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
    for c in 0..8 {
        if let Some(line) = screen.lines.get_mut(0) {
            line.update_cell_with(c, Cell::new('Z'));
        }
    }
    screen.move_cursor(0, 3);
    screen.erase_chars(0, SgrAttributes::default());
    let line = screen.get_line(0).unwrap();
    for c in 0..8 {
        assert_eq!(line.cells[c].char(), 'Z', "col {c}: noop on count=0");
    }
}

// ── insert_chars ──────────────────────────────────────────────────────────

#[test]
fn insert_chars_shifts_existing_right() {
    let mut screen = Screen::new(3, 8);
    for c in 0..8 {
        if let Some(line) = screen.lines.get_mut(0) {
            line.update_cell_with(c, Cell::new(char::from(b'A' + c as u8)));
        }
    }
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
    for c in 0..5 {
        if let Some(line) = screen.lines.get_mut(0) {
            line.update_cell_with(c, Cell::new(char::from(b'A' + c as u8)));
        }
    }
    screen.move_cursor(0, 0);
    screen.insert_chars(1, SgrAttributes::default());
    let line = screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), ' ', "blank at col 0");
    assert_eq!(line.cells[1].char(), 'A', "old col 0 shifted to col 1");
    assert_eq!(line.cells[2].char(), 'B');
}

// ── delete_chars ──────────────────────────────────────────────────────────

#[test]
fn delete_chars_shifts_remaining_left() {
    let mut screen = Screen::new(3, 8);
    for c in 0..8 {
        if let Some(line) = screen.lines.get_mut(0) {
            line.update_cell_with(c, Cell::new(char::from(b'A' + c as u8)));
        }
    }
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
    for c in 0..5 {
        if let Some(line) = screen.lines.get_mut(0) {
            line.update_cell_with(c, Cell::new(char::from(b'0' + c as u8)));
        }
    }
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

// ── insert_lines ──────────────────────────────────────────────────────────

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

// ── delete_lines ──────────────────────────────────────────────────────────

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

// ── scroll_up / scroll_down ───────────────────────────────────────────────

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
