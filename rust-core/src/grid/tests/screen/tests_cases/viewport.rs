use super::*;

#[test]
fn test_viewport_scroll_up_and_down() {
    let mut screen = screen_with_scrollback!(4 x 8, scrollback 8);

    assert_eq!(screen.scroll_offset(), 0);
    screen.viewport_scroll_up(3);
    assert_eq!(screen.scroll_offset(), 3);
    assert!(screen.is_scroll_dirty());

    screen.viewport_scroll_down(3);
    assert_eq!(screen.scroll_offset(), 0);
}

#[test]
fn test_viewport_line_comes_from_scrollback() {
    let mut screen = Screen::new(4, 8);
    screen.print('A', SgrAttributes::default(), true);
    screen.scroll_up(1, Color::Default);
    screen.viewport_scroll_up(1);

    let line = screen.get_scrollback_viewport_line(3).unwrap();
    assert_eq!(line.cells[0].char(), 'A');
}

#[test]
fn test_viewport_scroll_ignored_in_alternate_screen() {
    let mut screen = screen_with_scrollback!(4 x 8, scrollback 8);

    screen.switch_to_alternate();
    let before = screen.scroll_offset();
    screen.viewport_scroll_up(2);

    assert_eq!(screen.scroll_offset(), before);
}

