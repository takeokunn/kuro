use crate::grid::Line;
use crate::types::cell::{Cell, SgrAttributes};
use crate::types::color::Color;
use crate::Screen;

pub(crate) const DEFAULT_ROWS: usize = 24;
pub(crate) const DEFAULT_COLS: usize = 80;

pub(crate) fn make_screen() -> Screen {
    new_screen(DEFAULT_ROWS, DEFAULT_COLS)
}

pub(crate) fn new_screen(rows: usize, cols: usize) -> Screen {
    Screen::new(rows as u16, cols as u16)
}

pub(crate) fn screen_with_scrollback(count: usize) -> Screen {
    let mut screen = make_screen();
    for _ in 0..count {
        screen.scroll_up(1, Color::Default);
    }
    screen
}

pub(crate) fn screen_with_labeled_scrollback(rows: usize, cols: usize, labels: &[char]) -> Screen {
    let mut screen = new_screen(rows, cols);
    let attrs = SgrAttributes::default();

    for &ch in labels {
        screen.move_cursor(0, 0);
        screen.print(ch, attrs, false);
        screen.scroll_up(1, Color::Default);
    }

    screen
}

pub(crate) fn first_char(line: &Line) -> Option<char> {
    line.get_cell(0).map(Cell::char)
}

pub(crate) fn scrollback_chars(screen: &Screen, limit: usize) -> Vec<Option<char>> {
    screen
        .get_scrollback_lines(limit)
        .into_iter()
        .map(|line| first_char(&line))
        .collect()
}

macro_rules! assert_scroll_zero_noop {
    ($name:ident, $setup:expr, $call:ident) => {
        #[test]
        fn $name() {
            let mut screen = screen_with_scrollback(10);
            $setup(&mut screen);
            screen.clear_scroll_dirty();
            let offset_before = screen.scroll_offset();

            screen.$call(0);

            assert_eq!(screen.scroll_offset(), offset_before);
            assert!(!screen.is_scroll_dirty());
        }
    };
}
