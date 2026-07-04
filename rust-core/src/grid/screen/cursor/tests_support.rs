use crate::Screen;

const ROWS: u16 = 24;
const COLS: u16 = 80;

macro_rules! assert_cursor {
    ($screen:expr, row $r:expr, col $c:expr) => {
        assert_eq!($screen.cursor().row, $r, "cursor.row mismatch");
        assert_eq!($screen.cursor().col, $c, "cursor.col mismatch");
    };
}

pub(crate) fn make_screen() -> Screen {
    Screen::new(ROWS, COLS)
}

pub(crate) fn assert_cell(screen: &Screen, row: usize, col: usize, expected: char) {
    assert_eq!(screen.get_cell(row, col).unwrap().char(), expected);
}
