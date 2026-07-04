use super::*;

proptest::proptest! {
    #![proptest_config(ProptestConfig::with_cases(128))]

    #[test]
    fn prop_scrollback_bounded_by_max(n in 1usize..=200usize) {
        let mut screen = Screen::new(4, 8);
        screen.set_scrollback_max_lines(50);
        for _ in 0..n {
            screen.scroll_up(1, Color::Default);
        }
        proptest::prop_assert!(screen.scrollback_line_count <= 50);
    }
}
