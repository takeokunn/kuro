#[test]
fn pbt_erase_chars_clamped_at_right_margin() {
    let mut s = make_screen_pbt();
    s.move_cursor(0, 78);
    s.erase_chars(9999, SgrAttributes::default());
    assert_eq!(s.get_cell(0, 78).unwrap().char(), ' ');
    assert_eq!(s.get_cell(0, 79).unwrap().char(), ' ');
}

#[test]
fn pbt_insert_lines_count_greater_than_one() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('A', attrs, true);
    s.move_cursor(1, 0);
    s.print('B', attrs, true);
    s.move_cursor(2, 0);
    s.print('C', attrs, true);
    s.move_cursor(0, 0);
    s.insert_lines(2);
    assert_cell_char_pbt!(s, 0, 0, ' ');
    assert_cell_char_pbt!(s, 1, 0, ' ');
    assert_cell_char_pbt!(s, 2, 0, 'A');
    assert_cell_char_pbt!(s, 3, 0, 'B');
    assert_cell_char_pbt!(s, 4, 0, 'C');
}

#[test]
fn pbt_insert_lines_count_clamped_to_remaining() {
    let mut s = make_screen_pbt();
    let rows_before = s.rows() as usize;
    s.move_cursor(20, 0);
    s.insert_lines(100);
    assert_eq!(s.rows() as usize, rows_before);
    for row in 20..24 {
        assert_eq!(s.get_cell(row, 0).unwrap().char(), ' ');
    }
}

#[test]
fn pbt_insert_lines_at_bottom_minus_one() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    let last_row = s.rows() as usize - 1;
    s.move_cursor(last_row, 0);
    s.print('X', attrs, true);
    s.move_cursor(last_row, 0);
    s.insert_lines(1);
    assert_eq!(s.get_cell(last_row, 0).unwrap().char(), ' ');
}

#[test]
fn pbt_delete_lines_count_greater_than_one() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    for (row, ch) in [(0, 'A'), (1, 'B'), (2, 'C'), (3, 'D')] {
        s.move_cursor(row, 0);
        s.print(ch, attrs, true);
    }
    s.move_cursor(0, 0);
    s.delete_lines(2);
    assert_cell_char_pbt!(s, 0, 0, 'C');
    assert_cell_char_pbt!(s, 1, 0, 'D');
    assert_cell_char_pbt!(s, 22, 0, ' ');
    assert_cell_char_pbt!(s, 23, 0, ' ');
}

#[test]
fn pbt_delete_lines_count_clamped_to_remaining() {
    let mut s = make_screen_pbt();
    let rows_before = s.rows() as usize;
    s.move_cursor(20, 0);
    s.delete_lines(100);
    assert_eq!(s.rows() as usize, rows_before);
    for row in 20..24 {
        assert_eq!(s.get_cell(row, 0).unwrap().char(), ' ');
    }
}

#[test]
fn pbt_delete_lines_within_partial_scroll_region() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('T', attrs, true);
    s.move_cursor(15, 0);
    s.print('B', attrs, true);
    s.set_scroll_region(5, 10);
    s.move_cursor(5, 0);
    s.print('X', attrs, true);
    s.move_cursor(5, 0);
    s.delete_lines(1);
    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'T');
    assert_eq!(s.get_cell(15, 0).unwrap().char(), 'B');
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    fn prop_insert_lines_no_panic(n in 0usize..50usize, row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        let rows_before = s.rows() as usize;
        s.move_cursor(row, 0);
        s.insert_lines(n);
        prop_assert_eq!(s.rows() as usize, rows_before);
    }

    #[test]
    fn prop_delete_lines_no_panic(n in 0usize..50usize, row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        let rows_before = s.rows() as usize;
        s.move_cursor(row, 0);
        s.delete_lines(n);
        prop_assert_eq!(s.rows() as usize, rows_before);
    }
}

#[test]
fn pbt_erase_chars_with_count_zero_preserves_width() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('X', attrs, true);
    s.move_cursor(0, 0);
    s.erase_chars(0, attrs);
    assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
}

#[test]
fn pbt_insert_chars_at_last_col_does_not_grow_line() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    let last_col = s.cols() as usize - 1;
    s.move_cursor(0, last_col);
    s.print('Z', attrs, true);
    s.move_cursor(0, last_col);
    s.insert_chars(1, attrs);
    assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
}

#[test]
fn pbt_delete_chars_at_col_zero_shifts_entire_row_left() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    for ch in ['A', 'B', 'C', 'D', 'E'] {
        s.print(ch, attrs, true);
    }
    s.move_cursor(0, 0);
    s.delete_chars(1);
    assert_cell_char_pbt!(s, 0, 0, 'B');
    assert_cell_char_pbt!(s, 0, 1, 'C');
    assert_cell_char_pbt!(s, 0, 2, 'D');
    assert_cell_char_pbt!(s, 0, 3, 'E');
    assert_cell_char_pbt!(s, 0, 79, ' ');
}

#[test]
fn pbt_insert_lines_within_scroll_region_does_not_affect_rows_outside() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('T', attrs, true);
    s.move_cursor(15, 0);
    s.print('B', attrs, true);
    s.set_scroll_region(5, 10);
    s.move_cursor(5, 0);
    s.print('X', attrs, true);
    s.move_cursor(5, 0);
    s.insert_lines(1);
    assert_cell_char_pbt!(s, 5, 0, ' ');
    assert_cell_char_pbt!(s, 6, 0, 'X');
    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'T');
    assert_eq!(s.get_cell(15, 0).unwrap().char(), 'B');
}

#[test]
fn pbt_clear_lines_does_not_affect_rows_outside_range() {
    let mut s = make_screen_pbt();
    let attrs = SgrAttributes::default();
    s.move_cursor(1, 0);
    s.print('X', attrs, true);
    s.move_cursor(5, 0);
    s.print('Y', attrs, true);
    s.move_cursor(2, 0);
    s.print('A', attrs, true);
    s.move_cursor(3, 0);
    s.print('B', attrs, true);
    s.clear_lines(2, 4);
    assert_eq!(s.get_cell(2, 0).unwrap().char(), ' ');
    assert_eq!(s.get_cell(3, 0).unwrap().char(), ' ');
    assert_eq!(s.get_cell(1, 0).unwrap().char(), 'X');
    assert_eq!(s.get_cell(5, 0).unwrap().char(), 'Y');
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    fn prop_erase_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        s.move_cursor(0, col);
        s.erase_chars(n, SgrAttributes::default());
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }

    #[test]
    fn prop_delete_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        s.move_cursor(0, col);
        s.delete_chars(n);
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }

    #[test]
    fn prop_insert_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        s.move_cursor(0, col);
        s.insert_chars(n, SgrAttributes::default());
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }
}
