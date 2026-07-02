use crate::grid::screen::Screen;

pub(crate) const ROWS: u16 = 24;
pub(crate) const COLS: u16 = 80;

pub(crate) fn screen() -> Screen {
    Screen::new(ROWS, COLS)
}

pub(crate) fn clean_screen() -> Screen {
    let mut screen = screen();
    let _ = screen.take_dirty_lines();
    screen
}

pub(crate) fn all_rows(rows: u16) -> Vec<usize> {
    (0..usize::from(rows)).collect()
}

pub(crate) fn take_after(screen: &mut Screen) -> Vec<usize> {
    screen.take_dirty_lines()
}

pub(crate) fn assert_dirty_rows(screen: &mut Screen, expected: &[usize]) {
    assert_eq!(take_after(screen), expected);
}

pub(crate) fn assert_dirty_rows_unordered(screen: &mut Screen, expected: &[usize]) {
    let mut dirty = screen.take_dirty_lines();
    dirty.sort_unstable();
    assert_eq!(dirty, expected);
}

pub(crate) fn assert_drained(screen: &mut Screen) {
    let _ = screen.take_dirty_lines();
    assert!(screen.take_dirty_lines().is_empty());
}
