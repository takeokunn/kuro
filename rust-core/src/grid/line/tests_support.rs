use crate::grid::Line;
use crate::types::cell::{Cell, SgrAttributes};
use crate::types::color::Color;

pub(crate) const DEFAULT_COLS: usize = 8;

pub(crate) fn attrs_with_bg(bg: Color) -> SgrAttributes {
    SgrAttributes {
        background: bg,
        ..Default::default()
    }
}

pub(crate) fn line_with_text(text: &str) -> Line {
    let mut line = Line::new(text.chars().count());
    for (col, c) in text.chars().enumerate() {
        line.update_cell(col, c, SgrAttributes::default());
    }
    line
}

pub(crate) fn assert_cells_are_default(line: &Line) {
    for (col, cell) in line.cells.iter().enumerate() {
        assert_eq!(cell, &Cell::default(), "cell {col} should be default");
    }
}

pub(crate) fn assert_all_cells_have_bg(line: &Line, bg: Color) {
    for (col, cell) in line.cells.iter().enumerate() {
        assert_eq!(
            cell.attrs.background, bg,
            "cell {col} should carry background {bg:?}"
        );
    }
}

macro_rules! line_state_case {
    ($name:ident, $make:expr, len: $len:expr, dirty: $dirty:expr, text: $text:expr) => {
        #[test]
        fn $name() {
            let line = $make;
            assert_eq!(line.cells.len(), $len);
            assert_eq!(line.is_dirty, $dirty);
            assert_eq!(line.to_string(), $text);
        }
    };
}
