/// Create a `TerminalCore` and flood every cell with `$ch`.
macro_rules! term_filled {
    ($rows:literal x $cols:literal, $ch:expr) => {{
        let mut _t = crate::TerminalCore::new($rows, $cols);
        for _r in 0..$rows {
            for _c in 0..$cols {
                if let Some(_line) = _t.screen.get_line_mut(_r) {
                    _line.update_cell_with(_c, Cell::new($ch));
                }
            }
        }
        _t
    }};
}

/// Fill selected cells in one row of a `TerminalCore`.
macro_rules! fill_cells {
    ($term:expr, row $row:expr, cols $cols:expr, $ch:expr) => {{
        let _row: usize = $row;
        for _c in $cols {
            if let Some(_line) = $term.screen.get_line_mut(_row) {
                _line.update_cell_with(_c, Cell::new($ch));
            }
        }
    }};
}

/// Assert that every cell in `$row_range × $col_range` has char `$ch`.
macro_rules! assert_row_range_char {
    ($term:expr, rows $rr:expr, cols $cr:expr, $ch:expr, $msg:literal) => {
        for _r in $rr {
            let _line = $term.screen.get_line(_r).unwrap();
            for _c in $cr {
                assert_eq!(
                    _line.cells[_c].char(),
                    $ch,
                    concat!($msg, " (row={}, col={})"),
                    _r,
                    _c
                );
            }
        }
    };
}

/// Assert every cell in a single `$row` across `$col_range` has char `$ch`.
macro_rules! assert_line_char {
    ($term:expr, row $r:expr, cols $cr:expr, $ch:expr, $msg:literal) => {
        let _line = $term.screen.get_line($r).unwrap();
        for _c in $cr {
            assert_eq!(_line.cells[_c].char(), $ch, concat!($msg, " (col={})"), _c);
        }
    };
}

/// Assert every cell in a single `$row` across `$col_range` has background color `$bg`.
macro_rules! assert_line_bg {
    ($term:expr, row $r:expr, cols $cr:expr, $bg:expr, $msg:literal) => {
        let _line = $term.screen.get_line($r).unwrap();
        for _c in $cr {
            assert_eq!(
                _line.cells[_c].attrs.background,
                $bg,
                concat!($msg, " (col={})"),
                _c
            );
        }
    };
}

/// Assert every cell in `$row_range × $col_range` has background `$bg`.
macro_rules! assert_row_range_bg {
    ($term:expr, rows $rr:expr, cols $cr:expr, $bg:expr, $msg:literal) => {
        for _r in $rr {
            let _line = $term.screen.get_line(_r).unwrap();
            for _c in $cr {
                assert_eq!(
                    _line.cells[_c].attrs.background,
                    $bg,
                    concat!($msg, " (row={}, col={})"),
                    _r,
                    _c
                );
            }
        }
    };
}

/// Assert every cell in `$row_range × $col_range` contains `$flags`.
macro_rules! assert_row_range_flags {
    ($term:expr, rows $rr:expr, cols $cr:expr, $flags:expr, $msg:literal) => {
        for _r in $rr {
            let _line = $term.screen.get_line(_r).unwrap();
            for _c in $cr {
                assert!(
                    _line.cells[_c].attrs.flags.contains($flags),
                    concat!($msg, " (row={}, col={})"),
                    _r,
                    _c
                );
            }
        }
    };
}

/// Assert every cell in `$row_range × $col_range` has foreground `$fg`.
macro_rules! assert_row_range_foreground {
    ($term:expr, rows $rr:expr, cols $cr:expr, $fg:expr, $msg:literal) => {
        for _r in $rr {
            let _line = $term.screen.get_line(_r).unwrap();
            for _c in $cr {
                assert_eq!(
                    _line.cells[_c].attrs.foreground,
                    $fg,
                    concat!($msg, " (row={}, col={})"),
                    _r,
                    _c
                );
            }
        }
    };
}

/// Assert a single cell's char and width.
macro_rules! assert_cell {
    ($term:expr, row $r:expr, col $c:expr, char $ch:expr, width $w:expr) => {{
        let _line = $term.screen.get_line($r).unwrap();
        assert_eq!(_line.cells[$c].char(), $ch);
        assert_eq!(_line.cells[$c].width, $w);
    }};
    ($term:expr, row $r:expr, col $c:expr, char $ch:expr) => {{
        let _line = $term.screen.get_line($r).unwrap();
        assert_eq!(_line.cells[$c].char(), $ch);
    }};
}
