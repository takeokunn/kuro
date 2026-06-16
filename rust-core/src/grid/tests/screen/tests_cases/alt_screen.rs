use super::*;

#[test]
fn test_alternate_screen_keeps_primary_content_isolated() {
    let mut screen = Screen::new(4, 8);
    let attrs = SgrAttributes::default();

    screen.print('X', attrs, true);
    screen.switch_to_alternate();
    screen.print('Y', attrs, true);

    assert_cell_char!(screen, row 0, col 0, 'Y');
    screen.switch_to_primary();
    assert_cell_char!(screen, row 0, col 0, 'X');
}

#[test]
fn test_alt_screen_consumes_dirty_state_cleanly() {
    let mut screen = Screen::new(4, 8);

    screen.switch_to_alternate();
    let _ = screen.take_dirty_lines();

    assert!(!screen.full_dirty);
    assert!(screen.take_dirty_lines().is_empty());
}

#[test]
fn test_alt_screen_scroll_down_does_not_queue_events() {
    let mut screen = Screen::new(4, 8);

    screen.switch_to_alternate();
    screen.scroll_down(3, Color::Default);
    let (up, down) = screen.consume_scroll_events();

    assert_eq!(up, 0);
    assert_eq!(down, 0);
}

