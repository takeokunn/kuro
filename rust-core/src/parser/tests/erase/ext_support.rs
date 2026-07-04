/// Test helper macro for EL cases with BCE.
macro_rules! test_el_bce {
    (
        $name:ident,
        color $color:expr,
        row $row:expr, fill $fill_ch:expr,
        cursor_col $cursor_col:expr,
        seq $seq:expr,
        $assertions:expr
    ) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(5, 10);
            let attrs = SgrAttributes {
                background: Color::Named($color),
                ..Default::default()
            };
            term.current_attrs = attrs;
            let row = $row;
            for c in 0..10 {
                if let Some(line) = term.screen.get_line_mut(row) {
                    line.update_cell_with(c, Cell::new($fill_ch));
                }
            }
            term.screen.move_cursor(row, $cursor_col);
            term.advance($seq);
            $assertions(&term, row);
        }
    };
}

/// Test helper macro for ED cases with BCE.
macro_rules! test_ed_bce {
    (
        $name:ident,
        grid $rows:literal x $cols:literal, fill $fill_ch:expr,
        color $color:expr,
        cursor ($cursor_row:expr, $cursor_col:expr),
        seq $seq:expr,
        $assertions:expr
    ) => {
        #[test]
        fn $name() {
            let mut term = term_filled!($rows x $cols, $fill_ch);
            term.current_attrs.background = Color::Named($color);
            term.screen.move_cursor($cursor_row, $cursor_col);
            term.advance($seq);
            $assertions(&term);
        }
    };
}
