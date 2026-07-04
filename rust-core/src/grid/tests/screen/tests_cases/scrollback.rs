use super::*;

#[test]
fn test_scrollback_grows_with_scroll_up() {
    let mut screen = Screen::new(4, 8);

    assert_eq!(screen.scrollback_line_count, 0);
    screen.scroll_up(1, Color::Default);
    screen.scroll_up(1, Color::Default);

    assert_eq!(screen.scrollback_line_count, 2);
    assert_eq!(screen.scrollback_buffer.len(), 2);
}

#[test]
fn test_scrollback_clear_resets_buffer() {
    let mut screen = screen_with_scrollback!(4 x 8, scrollback 4);

    assert!(screen.scrollback_line_count > 0);
    screen.clear_scrollback();

    assert_eq!(screen.scrollback_line_count, 0);
    assert!(screen.scrollback_buffer.is_empty());
}

#[test]
fn test_scrollback_max_is_enforced() {
    let mut screen = Screen::new(4, 8);
    screen.set_scrollback_max_lines(2);

    for _ in 0..5 {
        screen.scroll_up(1, Color::Default);
    }

    assert_eq!(screen.scrollback_line_count, 2);
    assert_eq!(screen.scrollback_buffer.len(), 2);
}

#[test]
fn test_get_scrollback_lines_zero_is_empty() {
    let screen = screen_with_scrollback!(4 x 8, scrollback 3);
    let lines = screen.get_scrollback_lines(0);

    assert!(lines.is_empty());
}
