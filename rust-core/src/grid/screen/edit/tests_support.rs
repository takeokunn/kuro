use crate::grid::screen::Screen;
use crate::types::Cell;

macro_rules! fill_cells {
    ($screen:expr, row $row:expr, cols $cols:expr, $ch:expr) => {{
        let _row: usize = $row;
        for _c in $cols {
            if let Some(_line) = $screen.lines.get_mut(_row) {
                _line.update_cell_with(_c, Cell::new($ch));
            }
        }
    }};
    ($screen:expr, row $row:expr, cols $cols:expr, $col:ident => $ch:expr) => {{
        let _row: usize = $row;
        for $col in $cols {
            if let Some(_line) = $screen.lines.get_mut(_row) {
                _line.update_cell_with($col, Cell::new($ch));
            }
        }
    }};
}

pub(crate) fn fill_rows(screen: &mut Screen) {
    let rows = screen.rows() as usize;
    for r in 0..rows {
        let ch = char::from(b'A' + (r % 26) as u8);
        fill_cells!(screen, row r, cols 0..1, ch);
    }
}

pub(crate) fn row_char(screen: &Screen, row: usize) -> char {
    screen.get_cell(row, 0).map_or(' ', Cell::char)
}

pub(crate) fn row_is_blank(screen: &Screen, row: usize) -> bool {
    screen
        .get_line(row)
        .is_some_and(|l| l.cells.iter().all(|c| c.char() == ' '))
}

pub(crate) fn make_screen_pbt() -> Screen {
    Screen::new(24, 80)
}
