/// Assert that `TabStops::next_stop(from)` returns `expected` for a default
/// 80-column tab-stop set.
///
/// Syntax: `assert_next_stop!(from => expected, "message")`
macro_rules! assert_next_stop {
    ($from:expr => $expected:expr, $msg:expr) => {{
        let tabs = crate::parser::tabs::TabStops::new(80);
        assert_eq!(tabs.next_stop($from), $expected, $msg);
    }};
}

/// Assert that after one `handle_ht` call, the cursor lands at `expected_col`.
///
/// Syntax: `assert_ht_moves!(from_col => expected_col, "message")`
macro_rules! assert_ht_moves {
    ($from:expr => $expected:expr, $msg:expr) => {{
        let mut screen = crate::grid::Screen::new(24, 80);
        let tabs = crate::parser::tabs::TabStops::new(80);
        screen.cursor.col = $from;
        crate::parser::tabs::handle_ht(&mut screen, &tabs);
        assert_eq!(screen.cursor.col, $expected, $msg);
    }};
}

/// Assert that after `resize(new_cols)`, a given stop is either present or absent.
///
/// Syntax:
/// ```text
/// assert_resize_stop!(from_cols, resize_to new_cols, stop N, present)   // must be present
/// assert_resize_stop!(from_cols, resize_to new_cols, stop N, absent)    // must be absent
/// ```
macro_rules! assert_resize_stop {
    ($from_cols:expr, resize_to $new_cols:expr, stop $stop:expr, present) => {{
        let mut tabs = crate::parser::tabs::TabStops::new($from_cols);
        tabs.resize($new_cols);
        assert!(
            tabs.get_stops().contains(&$stop),
            "col {} must be present after resize from {} to {}",
            $stop,
            $from_cols,
            $new_cols
        );
    }};
    ($from_cols:expr, resize_to $new_cols:expr, stop $stop:expr, absent) => {{
        let mut tabs = crate::parser::tabs::TabStops::new($from_cols);
        tabs.resize($new_cols);
        assert!(
            !tabs.get_stops().contains(&$stop),
            "col {} must be absent after resize from {} to {}",
            $stop,
            $from_cols,
            $new_cols
        );
    }};
}
