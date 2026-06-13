// Init/construction and property-based tests for Screen.
// Included by screen.rs via `include!()`.

fn make_screen_init() -> Screen {
    Screen::new(24, 80)
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    fn prop_new_screen_has_correct_dimensions(
        rows in 1u16..=200u16,
        cols in 1u16..=200u16,
    ) {
        let s = Screen::new(rows, cols);
        prop_assert_eq!(s.rows(), rows);
        prop_assert_eq!(s.cols(), cols);
    }

    #[test]
    fn prop_get_cell_in_bounds_some(
        rows in 1u16..=50u16,
        cols in 1u16..=50u16,
        row in 0usize..50usize,
        col in 0usize..50usize,
    ) {
        let s = Screen::new(rows, cols);
        let r = row % rows as usize;
        let c = col % cols as usize;
        prop_assert!(s.get_cell(r, c).is_some());
    }

    #[test]
    fn prop_get_cell_out_of_bounds_none(
        rows in 1u16..=50u16,
        cols in 1u16..=50u16,
    ) {
        let s = Screen::new(rows, cols);
        prop_assert!(s.get_cell(rows as usize, 0).is_none());
        prop_assert!(s.get_cell(0, cols as usize).is_none());
    }

    #[test]
    fn prop_move_cursor_clamped_init(rows in 1u16..=50u16, cols in 1u16..=50u16) {
        let mut s = Screen::new(rows, cols);
        s.move_cursor(usize::MAX, usize::MAX);
        prop_assert!(s.cursor().row < rows as usize);
        prop_assert!(s.cursor().col < cols as usize);
    }

    #[test]
    fn prop_print_char_stored_in_cell(
        ch in proptest::char::range('A', 'Z'),
        row in 0usize..24usize,
        col in 0usize..79usize,
    ) {
        let mut s = Screen::new(24, 80);
        let attrs = SgrAttributes::default();
        s.move_cursor(row, col);
        s.print(ch, attrs, true);
        prop_assert_eq!(s.get_cell(row, col).unwrap().char(), ch);
    }
}

#[test]
fn init_screen_new_default_cursor_at_origin() {
    let s = make_screen_init();
    assert_eq!(s.cursor().row, 0);
    assert_eq!(s.cursor().col, 0);
}

#[test]
fn init_print_advances_cursor() {
    let mut s = make_screen_init();
    s.move_cursor(0, 0);
    s.print('A', SgrAttributes::default(), true);
    assert_eq!(s.cursor().col, 1);
    assert_eq!(s.cursor().row, 0);
}

#[test]
fn init_move_cursor_stores_position() {
    let mut s = make_screen_init();
    s.move_cursor(5, 12);
    assert_eq!(s.cursor().row, 5);
    assert_eq!(s.cursor().col, 12);
}

#[test]
fn init_get_line_in_bounds() {
    let s = make_screen_init();
    assert!(s.get_line(0).is_some());
    assert!(s.get_line(23).is_some());
}

#[test]
fn init_get_line_out_of_bounds() {
    let s = make_screen_init();
    assert!(s.get_line(24).is_none());
}

#[test]
fn init_get_cell_mut_modifies_in_place() {
    let mut s = make_screen_init();
    let attrs = SgrAttributes::default();
    s.move_cursor(2, 5);
    s.print('Q', attrs, true);
    s.move_cursor(2, 5);
    s.print('Z', attrs, true);
    assert_eq!(s.get_cell(2, 5).unwrap().char(), 'Z');
}

#[test]
fn init_rows_cols_return_u16() {
    let s = Screen::new(12, 40);
    let r: u16 = s.rows();
    let c: u16 = s.cols();
    assert_eq!(r, 12u16);
    assert_eq!(c, 40u16);
}

#[test]
fn init_new_screen_cells_default_to_space() {
    let s = Screen::new(4, 8);
    for row in 0..4 {
        for col in 0..8 {
            assert_eq!(s.get_cell(row, col).unwrap().char(), ' ');
        }
    }
}

#[test]
fn init_get_cell_returns_none_for_large_indices() {
    let s = make_screen_init();
    assert!(s.get_cell(usize::MAX, 0).is_none());
    assert!(s.get_cell(0, usize::MAX).is_none());
    assert!(s.get_cell(usize::MAX, usize::MAX).is_none());
}

#[test]
fn init_get_line_mut_allows_writing() {
    let mut s = make_screen_init();
    assert!(s.get_line_mut(0).is_some());
    assert!(s.get_line_mut(23).is_some());
    assert!(s.get_line_mut(24).is_none());
}

#[test]
fn init_new_screen_line_count_equals_rows() {
    let s = Screen::new(10, 40);
    for row in 0..10 {
        assert!(s.get_line(row).is_some());
    }
    assert!(s.get_line(10).is_none());
}

#[test]
fn init_new_screen_each_line_has_cols_cells() {
    let s = Screen::new(5, 20);
    for row in 0..5 {
        assert!(s.get_cell(row, 19).is_some());
        assert!(s.get_cell(row, 20).is_none());
    }
}
