/// Fill every cell in every row of `term` with either a row-derived character
/// or a fixed character.
macro_rules! fill_rows {
    ($term:expr, rows $n:expr, base $base:expr) => {{
        for r in 0..$n {
            if let Some(line) = $term.screen.get_line_mut(r) {
                let ch = ($base as u8 + r as u8) as char;
                let cols = line.cells.len();
                for c in 0..cols {
                    line.update_cell_with(c, crate::types::Cell::new(ch));
                }
            }
        }
    }};
    ($term:expr, rows $n:expr, char $ch:expr) => {{
        for r in 0..$n {
            if let Some(line) = $term.screen.get_line_mut(r) {
                let cols = line.cells.len();
                for c in 0..cols {
                    line.update_cell_with(c, crate::types::Cell::new($ch));
                }
            }
        }
    }};
}

/// Assert that every cell in every row still holds the character that
/// `fill_rows!(term, rows N, base BASE)` would have written.
macro_rules! assert_rows_unchanged {
    ($term:expr, rows $n:expr, base $base:expr) => {{
        for r in 0..$n {
            let ch = ($base as u8 + r as u8) as char;
            assert_eq!(
                $term
                    .screen
                    .get_cell(r, 0)
                    .map_or(' ', crate::types::cell::Cell::char),
                ch,
                "row {r} should be unchanged"
            );
        }
    }};
}

/// Assert that SU (CSI S) or SD (CSI T) treats a zero parameter as 1.
macro_rules! test_scroll_zero_param_is_one {
    (
        $name:ident,
        seq    = $seq:expr,
        fill   = $fill:expr,
        rows   = $rows:expr,
        row0   = $row0_char:expr, $row0_msg:expr,
        bottom = $bottom_row:expr, $bottom_char:expr, $bottom_msg:expr
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new($rows, 10);
            fill_rows!(term, rows $rows, base $fill);
            term.advance($seq);
            assert_eq!(
                term.screen.get_line(0).unwrap().cells[0].char(),
                $row0_char,
                $row0_msg
            );
            assert_eq!(
                term.screen.get_line($bottom_row).unwrap().cells[0].char(),
                $bottom_char,
                $bottom_msg
            );
        }
    };
}

/// Assert that a full-height SU or SD blanks every visible row.
macro_rules! test_scroll_full_height_blanks_all {
    (
        $name:ident,
        seq  = $seq:expr,
        fill = $fill:expr,
        rows = $rows:expr,
        msg  = $msg:literal
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new($rows, 10);
            fill_rows!(term, rows $rows, char $fill);
            term.advance($seq);
            for r in 0..$rows {
                assert_eq!(
                    term.screen.get_line(r).unwrap().cells[0].char(),
                    ' ',
                    "row {r}: {}",
                    $msg
                );
            }
        }
    };
}

/// Assert that SU or SD with a non-default SGR background propagates BCE to
/// newly inserted blank rows.
macro_rules! test_scroll_bce_propagated {
    (
        $name:ident,
        seq         = $seq:expr,
        fill        = $fill:expr,
        sgr         = $sgr:expr,
        blank_range = $range:expr,
        msg_char    = $msg_char:literal,
        msg_bg      = $msg_bg:literal
        $(,)?
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(5, 10);
            fill_rows!(term, rows 5, char $fill);
            term.advance($sgr);
            term.advance($seq);
            for r in $range {
                let cell = term.screen.get_cell(r, 0).unwrap();
                assert_eq!(cell.char(), ' ', "row {r}: {}", $msg_char);
                assert_ne!(
                    cell.attrs.background,
                    crate::Color::Default,
                    "row {r}: {}",
                    $msg_bg
                );
            }
        }
    };
}
