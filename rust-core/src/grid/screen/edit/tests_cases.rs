use super::tests_support::*;
use crate::grid::screen::Screen;
use crate::types::Cell;
use crate::types::SgrAttributes;
use proptest::prelude::*;

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

macro_rules! assert_cell_char_pbt {
    ($screen:expr, $row:expr, $col:expr, $expected:expr) => {
        assert_eq!(
            $screen.get_cell($row, $col).unwrap().char(),
            $expected,
            "expected cell ({}, {}) = {:?}",
            $row,
            $col,
            $expected
        )
    };
    ($screen:expr, $row:expr, $col:expr, $expected:expr, $msg:expr) => {
        assert_eq!(
            $screen.get_cell($row, $col).unwrap().char(),
            $expected,
            $msg
        )
    };
}

macro_rules! assert_preserves_row_count_pbt {
    ($name:ident, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen_pbt();
            let rows_before = s.rows() as usize;
            s.move_cursor(0, 0);
            s.$method($($arg),*);
            assert_eq!(s.rows() as usize, rows_before);
        }
    };
}

macro_rules! assert_line_width_unchanged_pbt {
    ($name:ident, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen_pbt();
            s.move_cursor(0, 0);
            s.$method($($arg),*);
            assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
        }
    };
}

macro_rules! assert_outside_scroll_noop_pbt {
    ($name:ident, $row:expr, $ch:expr, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen_pbt();
            s.set_scroll_region(5, 10);
            s.move_cursor($row, 0);
            s.print($ch, SgrAttributes::default(), true);
            s.move_cursor($row, 0);
            s.$method($($arg),*);
            assert_eq!(s.get_cell($row, 0).unwrap().char(), $ch);
        }
    };
}

macro_rules! assert_count_zero_noop_pbt {
    ($name:ident, $ch:expr, $method:ident ( $($arg:expr),* )) => {
        #[test]
        fn $name() {
            let mut s = make_screen_pbt();
            s.move_cursor(0, 0);
            s.print($ch, SgrAttributes::default(), true);
            s.move_cursor(0, 0);
            s.$method($($arg),*);
            assert_eq!(s.get_cell(0, 0).unwrap().char(), $ch);
        }
    };
}

#[path = "tests_cases/erase_chars.rs"]
mod erase_chars;

#[path = "tests_cases/chars.rs"]
mod chars;

#[path = "tests_cases/lines.rs"]
mod lines;

#[path = "tests_cases/pbt.rs"]
mod pbt;
