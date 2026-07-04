use crate::types::cell::SgrAttributes;
use crate::Screen;

pub(crate) const ROWS: u16 = 24;
pub(crate) const COLS: u16 = 80;
pub(crate) const LAST_ROW: usize = (ROWS - 1) as usize;

pub(crate) fn screen() -> Screen {
    Screen::new(ROWS, COLS)
}

pub(crate) fn attrs() -> SgrAttributes {
    SgrAttributes::default()
}

pub(crate) fn put_char(screen: &mut Screen, row: usize, col: usize, ch: char) {
    screen.move_cursor(row, col);
    screen.print(ch, attrs(), false);
}

pub(crate) fn assert_size_is_stable(screen: &Screen) {
    assert_eq!(screen.rows(), ROWS);
    assert_eq!(screen.cols(), COLS);
}

pub(crate) fn dirty_count_after(mut screen: Screen) -> usize {
    screen.take_dirty_lines().len()
}

pub(crate) fn consume_twice(screen: &mut Screen) -> ((u32, u32), (u32, u32)) {
    let first = screen.consume_scroll_events();
    let second = screen.consume_scroll_events();
    (first, second)
}

pub(crate) fn set_middle_region(screen: &mut Screen) {
    screen.set_scroll_region(10, 20);
}
