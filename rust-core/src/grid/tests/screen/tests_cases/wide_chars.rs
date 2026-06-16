use super::*;

#[test]
fn test_print_cjk_uses_full_and_wide_cells() {
    let mut screen = Screen::new(4, 8);

    screen.print('日', SgrAttributes::default(), true);

    assert_cell_char!(screen, row 0, col 0, '日');
    assert_cell_width!(screen, row 0, col 0, CellWidth::Full);
    assert_cell_width!(screen, row 0, col 1, CellWidth::Wide);
}

#[test]
fn test_print_emoji_advances_by_two_cells() {
    let mut screen = Screen::new(4, 8);

    screen.print('🎉', SgrAttributes::default(), true);

    assert_eq!(screen.cursor.col, 2);
    assert_cell_width!(screen, row 0, col 0, CellWidth::Full);
    assert_cell_width!(screen, row 0, col 1, CellWidth::Wide);
}

#[test]
fn test_delete_chars_blanks_wide_partner() {
    let mut screen = Screen::new(4, 8);
    let attrs = SgrAttributes::default();

    screen.print('日', attrs, true);
    screen.move_cursor(0, 1);
    screen.delete_chars(1);

    assert_cell_char!(screen, row 0, col 0, ' ');
    assert_cell_width!(screen, row 0, col 0, CellWidth::Half);
}

#[test]
fn test_insert_chars_blanks_wide_partner() {
    let mut screen = Screen::new(4, 8);

    screen.print('日', SgrAttributes::default(), true);
    screen.move_cursor(0, 1);
    screen.insert_chars(1, SgrAttributes::default());

    assert_cell_char!(screen, row 0, col 0, ' ');
    assert_cell_width!(screen, row 0, col 0, CellWidth::Half);
}

#[test]
fn test_erase_chars_blanks_wide_partner() {
    let mut screen = Screen::new(4, 8);

    screen.print('日', SgrAttributes::default(), true);
    screen.move_cursor(0, 1);
    screen.erase_chars(1, SgrAttributes::default());

    assert_cell_char!(screen, row 0, col 0, ' ');
    assert_cell_width!(screen, row 0, col 0, CellWidth::Half);
}

