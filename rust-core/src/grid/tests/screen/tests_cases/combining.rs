use super::*;

#[test]
fn test_attach_combining_to_base_cell() {
    let mut screen = Screen::new(4, 8);

    screen.print('a', SgrAttributes::default(), true);
    screen.attach_combining(0, 0, '\u{0301}');

    assert!(!screen.get_cell(0, 0).unwrap().grapheme().is_empty());
}

#[test]
fn test_attach_combining_after_wide_char() {
    let mut screen = Screen::new(4, 8);

    screen.print('日', SgrAttributes::default(), true);
    screen.attach_combining(0, 1, '\u{0301}');

    assert!(!screen.get_cell(0, 1).unwrap().grapheme().is_empty());
}

#[test]
fn test_attach_combining_caps_grapheme_bytes() {
    let mut screen = Screen::new(4, 8);

    for _ in 0..64 {
        screen.attach_combining(0, 0, '\u{0301}');
    }

    assert!(screen.get_cell(0, 0).unwrap().grapheme().len() <= 32);
}
