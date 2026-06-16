use crate::Screen;
use crate::types::cell::Cell;

macro_rules! assert_cursor {
    ($screen:expr, row $r:expr, col $c:expr) => {
        assert_eq!($screen.cursor().row, $r, "cursor.row mismatch");
        assert_eq!($screen.cursor().col, $c, "cursor.col mismatch");
    };
}

macro_rules! assert_cell_char {
    ($screen:expr, row $r:expr, col $c:expr, $ch:expr) => {
        assert_eq!(
            $screen.get_cell($r, $c).unwrap().char(),
            $ch,
            "cell ({},{}) char mismatch",
            $r,
            $c
        );
    };
    ($screen:expr, row $r:expr, col $c:expr, $ch:expr, $msg:literal) => {
        assert_eq!($screen.get_cell($r, $c).unwrap().char(), $ch, $msg);
    };
}

macro_rules! assert_cell_width {
    ($screen:expr, row $r:expr, col $c:expr, $w:expr) => {
        assert_eq!(
            $screen.get_cell($r, $c).unwrap().width,
            $w,
            "cell ({},{}) width mismatch",
            $r,
            $c
        );
    };
    ($screen:expr, row $r:expr, col $c:expr, $w:expr, $msg:literal) => {
        assert_eq!($screen.get_cell($r, $c).unwrap().width, $w, $msg);
    };
}



macro_rules! screen_with_scrollback {
    ($rows:literal x $cols:literal, scrollback $n:expr) => {{
        let mut _s = Screen::new($rows, $cols);
        for _ in 0..$n {
            _s.scroll_up(1, crate::Color::Default);
        }
        _s
    }};
}



pub(super) fn fill_rows(screen: &mut Screen) {
    let rows = screen.rows() as usize;
    for r in 0..rows {
        let ch = char::from(b'A' + (r % 26) as u8);
        fill_cell(screen, r, 0, ch);
    }
}

pub(super) fn fill_cell(screen: &mut Screen, row: usize, col: usize, ch: char) {
    if let Some(line) = screen.lines.get_mut(row) {
        line.update_cell_with(col, Cell::new(ch));
    }
}

pub(super) fn row_char(screen: &Screen, row: usize) -> char {
    screen.get_cell(row, 0).map_or(' ', Cell::char)
}

pub(super) fn row_is_blank(screen: &Screen, row: usize) -> bool {
    if let Some(line) = screen.get_line(row) {
        line.cells.iter().all(|c| c.char() == ' ')
    } else {
        false
    }
}
