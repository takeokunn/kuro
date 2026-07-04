use super::Screen;

pub(crate) fn make_screen() -> Screen {
    Screen::new(24, 80)
}

macro_rules! assert_cell_char {
    ($screen:expr, $row:expr, $col:expr, $expected:expr, $msg:expr) => {
        assert_eq!(
            $screen.get_cell($row, $col).unwrap().char(),
            $expected,
            $msg
        )
    };
}
