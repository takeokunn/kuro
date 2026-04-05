//! Scrollback buffer and viewport scroll methods for Screen

use super::{Line, Screen};

impl Screen {
    /// Set maximum scrollback buffer size
    pub fn set_scrollback_max_lines(&mut self, max_lines: usize) {
        if let Some(screen) = self.active_screen_mut() {
            screen.scrollback_max_lines = max_lines;

            // Trim scrollback if new max is smaller than current count
            while screen.scrollback_line_count > screen.scrollback_max_lines {
                if screen.scrollback_buffer.pop_front().is_some() {
                    screen.scrollback_line_count -= 1;
                }
            }
        }
    }

    /// Get scrollback lines (most recent first)
    #[must_use]
    pub fn get_scrollback_lines(&self, max_lines: usize) -> Vec<Line> {
        self.active_screen().map_or_else(Vec::new, |screen| {
            screen
                .scrollback_buffer
                .iter()
                .rev()
                .take(max_lines)
                .cloned()
                .collect()
        })
    }

    /// Clear the scrollback buffer
    pub fn clear_scrollback(&mut self) {
        if let Some(screen) = self.active_screen_mut() {
            screen.scrollback_buffer.clear();
            screen.scrollback_line_count = 0;
        }
    }

    /// Scroll the viewport up by n lines (toward older scrollback content)
    ///
    /// No-op when the alternate screen is active (alternate screen has no scrollback).
    pub fn viewport_scroll_up(&mut self, n: usize) {
        if self.is_alternate_active {
            return;
        }
        let new_offset = (self.scroll_offset + n).min(self.scrollback_line_count);
        if new_offset != self.scroll_offset {
            self.scroll_offset = new_offset;
            self.scroll_dirty = true;
        }
    }

    /// Scroll the viewport down by n lines (toward live content)
    ///
    /// No-op when the alternate screen is active.
    pub const fn viewport_scroll_down(&mut self, n: usize) {
        if self.is_alternate_active {
            return;
        }
        let new_offset = self.scroll_offset.saturating_sub(n);
        if new_offset != self.scroll_offset {
            self.scroll_offset = new_offset;
            if new_offset == 0 {
                self.full_dirty = true;
                self.scroll_dirty = false;
                // Reset pending scroll counters that accumulated while the user
                // was viewing scrollback.  Without this, stale counts would
                // burst-apply in `consume_scroll_events` on the first render
                // frame after returning to the live view, causing the Emacs
                // buffer to shift by the wrong number of lines.
                self.pending_scroll_up = 0;
                self.pending_scroll_down = 0;
            } else {
                self.scroll_dirty = true;
            }
        }
    }

    /// Get a scrollback line for the current viewport position
    ///
    /// Returns the line at `row_in_viewport` (0 = top of viewport) given the
    /// current `scroll_offset`. Returns `None` when there is no scrollback
    /// content for that viewport row (i.e. the scrollback buffer is smaller
    /// than the screen height).
    ///
    /// Mapping: viewport row `r` maps to scrollback index
    /// `(n - scroll_offset) + r - (rows - 1)`, where `n` is the scrollback
    /// line count. Returns `None` when the computed index is negative.
    #[must_use]
    #[expect(
        clippy::cast_possible_wrap,
        reason = "terminal dimensions are bounded by u16::MAX; usize/u32→isize for signed arithmetic index bounds checking"
    )]
    pub fn get_scrollback_viewport_line(&self, row_in_viewport: usize) -> Option<&Line> {
        let n = self.scrollback_line_count as isize;
        let offset = self.scroll_offset as isize;
        let rows = self.rows as isize;
        let row = row_in_viewport as isize;
        // anchor = the scrollback index shown at the bottom of the viewport
        let anchor = n - offset;
        let idx = anchor + row - (rows - 1);
        if idx < 0 || idx >= n {
            return None;
        }
        self.scrollback_buffer.get(idx.cast_unsigned())
    }

    /// Return true if the viewport scroll position changed and a re-render is needed
    #[inline]
    #[must_use]
    pub const fn is_scroll_dirty(&self) -> bool {
        self.scroll_dirty
    }

    /// Clear the `scroll_dirty` flag after re-rendering
    #[inline]
    pub const fn clear_scroll_dirty(&mut self) {
        self.scroll_dirty = false;
    }

    /// Return the current viewport scroll offset (0 = live view)
    #[inline]
    #[must_use]
    pub const fn scroll_offset(&self) -> usize {
        self.scroll_offset
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::cell::SgrAttributes;
    use crate::types::color::Color;
    use proptest::prelude::*;

    fn make_screen() -> Screen {
        Screen::new(24, 80)
    }

    fn screen_with_scrollback(count: usize) -> Screen {
        let mut screen = Screen::new(24, 80);
        for _ in 0..count {
            screen.scroll_up(1, Color::Default);
        }
        screen
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(256))]

        #[test]
        fn prop_viewport_scroll_up_bounded(
            scrollback_lines in 1usize..50usize,
            scroll_n in 0usize..200usize,
        ) {
            let mut screen = screen_with_scrollback(scrollback_lines);
            screen.viewport_scroll_up(scroll_n);
            prop_assert!(screen.scroll_offset() <= screen.scrollback_line_count);
        }

        #[test]
        fn prop_viewport_scroll_down_bounded(
            scrollback_lines in 1usize..50usize,
            scroll_up_n in 1usize..40usize,
            scroll_down_n in 0usize..200usize,
        ) {
            let mut screen = screen_with_scrollback(scrollback_lines);
            let clamp = scroll_up_n.min(screen.scrollback_line_count);
            screen.viewport_scroll_up(clamp);
            screen.viewport_scroll_down(scroll_down_n);
            prop_assert!(screen.scroll_offset() <= screen.scrollback_line_count);
        }

        #[test]
        fn prop_scroll_dirty_set_on_viewport_scroll(
            scrollback_lines in 1usize..50usize,
            n in 1usize..10usize,
        ) {
            let mut screen = screen_with_scrollback(scrollback_lines);
            screen.clear_scroll_dirty();
            prop_assume!(screen.scroll_offset() == 0);
            screen.viewport_scroll_up(n);
            if screen.scrollback_line_count > 0 {
                prop_assert!(screen.is_scroll_dirty());
            }
        }

        #[test]
        fn prop_set_scrollback_max_trims(
            initial_lines in 10usize..30usize,
            new_max in 1usize..9usize,
        ) {
            let mut screen = screen_with_scrollback(initial_lines);
            prop_assume!(screen.scrollback_line_count > new_max);
            screen.set_scrollback_max_lines(new_max);
            prop_assert!(screen.scrollback_line_count <= new_max);
            prop_assert!(screen.scrollback_buffer.len() <= new_max);
        }

        #[test]
        fn prop_clear_scrollback_empties(count in 0usize..40usize) {
            let mut screen = screen_with_scrollback(count);
            screen.clear_scrollback();
            prop_assert_eq!(screen.scrollback_line_count, 0);
            prop_assert!(screen.scrollback_buffer.is_empty());
        }

        #[test]
        fn prop_alternate_screen_viewport_scroll_up_noop(
            scrollback_lines in 0usize..30usize,
            n in 1usize..20usize,
        ) {
            let mut screen = screen_with_scrollback(scrollback_lines);
            screen.switch_to_alternate();
            let offset_before = screen.scroll_offset();
            screen.clear_scroll_dirty();
            screen.viewport_scroll_up(n);
            prop_assert_eq!(screen.scroll_offset(), offset_before);
            prop_assert!(!screen.is_scroll_dirty());
        }

        #[test]
        fn prop_alternate_screen_viewport_scroll_down_noop(
            scrollback_lines in 0usize..30usize,
            n in 1usize..20usize,
        ) {
            let mut screen = screen_with_scrollback(scrollback_lines);
            screen.switch_to_alternate();
            let offset_before = screen.scroll_offset();
            screen.clear_scroll_dirty();
            screen.viewport_scroll_down(n);
            prop_assert_eq!(screen.scroll_offset(), offset_before);
        }

        #[test]
        fn prop_viewport_scroll_up_exact_offset(
            scrollback_lines in 1usize..50usize,
            n in 0usize..100usize,
        ) {
            let mut screen = screen_with_scrollback(scrollback_lines);
            screen.viewport_scroll_up(n);
            let expected = n.min(screen.scrollback_line_count);
            prop_assert_eq!(screen.scroll_offset(), expected);
        }

        #[test]
        fn prop_viewport_scroll_down_to_zero(
            scrollback_lines in 1usize..50usize,
            n in 1usize..30usize,
        ) {
            let mut screen = screen_with_scrollback(scrollback_lines);
            let up_n = n.min(screen.scrollback_line_count);
            screen.viewport_scroll_up(up_n);
            let offset = screen.scroll_offset();
            screen.viewport_scroll_down(offset);
            prop_assert_eq!(screen.scroll_offset(), 0);
        }

        #[test]
        fn prop_scrollback_grows_monotonically(
            steps in 1usize..30usize,
            max_lines in 5usize..20usize,
        ) {
            let mut screen = make_screen();
            screen.set_scrollback_max_lines(max_lines);
            let mut prev = screen.scrollback_line_count;
            for _ in 0..steps {
                screen.scroll_up(1, Color::Default);
                let curr = screen.scrollback_line_count;
                prop_assert!(curr >= prev);
                prop_assert!(curr <= max_lines);
                prev = curr;
            }
        }
    }

    #[test]
    fn test_viewport_scroll_to_live_view() {
        let mut screen = screen_with_scrollback(20);
        screen.viewport_scroll_up(10);
        assert_eq!(screen.scroll_offset(), 10);
        screen.viewport_scroll_down(10);
        assert_eq!(screen.scroll_offset(), 0);
    }

    #[test]
    fn test_viewport_scroll_up_clamps_at_scrollback_count() {
        let mut screen = screen_with_scrollback(10);
        screen.viewport_scroll_up(9999);
        assert_eq!(screen.scroll_offset(), screen.scrollback_line_count);
    }

    #[test]
    fn test_viewport_scroll_down_saturates_at_zero() {
        let mut screen = screen_with_scrollback(20);
        screen.viewport_scroll_up(5);
        screen.viewport_scroll_down(9999);
        assert_eq!(screen.scroll_offset(), 0);
    }

    #[test]
    fn test_clear_scrollback_resets_offset() {
        let mut screen = screen_with_scrollback(20);
        screen.viewport_scroll_up(10);
        screen.clear_scrollback();
        assert_eq!(screen.scrollback_line_count, 0);
        assert!(screen.scrollback_buffer.is_empty());
    }

    #[test]
    fn test_is_scroll_dirty_false_initially() {
        let screen = make_screen();
        assert!(!screen.is_scroll_dirty());
    }

    #[test]
    fn test_clear_scroll_dirty_resets_flag() {
        let mut screen = screen_with_scrollback(5);
        screen.viewport_scroll_up(3);
        assert!(screen.is_scroll_dirty());
        screen.clear_scroll_dirty();
        assert!(!screen.is_scroll_dirty());
    }

    #[test]
    fn test_viewport_scroll_up_noop_at_max_no_dirty() {
        let mut screen = screen_with_scrollback(10);
        screen.viewport_scroll_up(10);
        screen.clear_scroll_dirty();
        screen.viewport_scroll_up(1);
        assert!(!screen.is_scroll_dirty());
    }

    #[test]
    fn test_viewport_scroll_down_to_zero_sets_full_dirty() {
        let mut screen = screen_with_scrollback(20);
        screen.viewport_scroll_up(10);
        let _ = screen.take_dirty_lines();
        screen.viewport_scroll_down(10);
        let dirty = screen.take_dirty_lines();
        assert_eq!(dirty.len(), 24);
    }

    #[test]
    fn test_scroll_offset_accessor_returns_zero_initially() {
        let screen = make_screen();
        assert_eq!(screen.scroll_offset(), 0);
    }

    #[test]
    fn test_set_scrollback_max_lines_trims_immediately() {
        let mut screen = screen_with_scrollback(10);
        assert_eq!(screen.scrollback_line_count, 10);
        screen.set_scrollback_max_lines(3);
        assert_eq!(screen.scrollback_line_count, 3);
        assert_eq!(screen.scrollback_buffer.len(), 3);
    }

    #[test]
    fn test_set_scrollback_max_larger_than_current_no_trim() {
        let mut screen = screen_with_scrollback(5);
        screen.set_scrollback_max_lines(100);
        assert_eq!(screen.scrollback_line_count, 5);
    }

    #[test]
    fn test_get_scrollback_lines_order_most_recent_first() {
        let mut screen = Screen::new(5, 80);
        let attrs = SgrAttributes::default();
        for ch in ['1', '2', '3'] {
            screen.move_cursor(0, 0);
            screen.print(ch, attrs, false);
            screen.scroll_up(1, Color::Default);
        }
        let lines = screen.get_scrollback_lines(3);
        assert_eq!(lines.len(), 3);
        assert_eq!(lines[0].get_cell(0).map(crate::types::cell::Cell::char), Some('3'));
        assert_eq!(lines[1].get_cell(0).map(crate::types::cell::Cell::char), Some('2'));
        assert_eq!(lines[2].get_cell(0).map(crate::types::cell::Cell::char), Some('1'));
    }

    #[test]
    fn test_viewport_scroll_down_partial_sets_scroll_dirty() {
        let mut screen = screen_with_scrollback(30);
        screen.viewport_scroll_up(20);
        let _ = screen.take_dirty_lines();
        screen.clear_scroll_dirty();
        screen.viewport_scroll_down(5);
        assert_eq!(screen.scroll_offset(), 15);
        assert!(screen.is_scroll_dirty());
        let dirty = screen.take_dirty_lines();
        assert!(dirty.len() < 24);
    }

    // ── get_scrollback_viewport_line ────────────────────────────────────

    #[test]
    fn test_get_scrollback_viewport_line_empty_returns_none() {
        let screen = make_screen();
        assert!(screen.get_scrollback_viewport_line(0).is_none());
        assert!(screen.get_scrollback_viewport_line(23).is_none());
    }

    #[test]
    fn test_get_scrollback_viewport_line_scrolled_returns_some() {
        let mut screen = screen_with_scrollback(30);
        screen.viewport_scroll_up(10);
        assert!(screen.get_scrollback_viewport_line(23).is_some());
        assert!(screen.get_scrollback_viewport_line(0).is_none());
    }

    #[test]
    fn test_get_scrollback_viewport_line_out_of_range_returns_none() {
        let mut screen = screen_with_scrollback(5);
        screen.viewport_scroll_up(5);
        assert!(screen.get_scrollback_viewport_line(0).is_none());
    }

    #[test]
    fn test_alternate_screen_scroll_up_no_scrollback() {
        let mut screen = make_screen();
        screen.switch_to_alternate();
        for _ in 0..5 { screen.scroll_up(1, Color::Default); }
        screen.switch_to_primary();
        assert_eq!(screen.scrollback_line_count, 0);
    }

    #[test]
    fn test_scrollback_evicts_oldest_lines_at_max() {
        let mut screen = Screen::new(5, 10);
        screen.set_scrollback_max_lines(3);
        let attrs = SgrAttributes::default();
        for ch in ['1', '2', '3', '4'] {
            screen.move_cursor(0, 0);
            screen.print(ch, attrs, false);
            screen.scroll_up(1, Color::Default);
        }
        assert_eq!(screen.scrollback_line_count, 3);
        let lines = screen.get_scrollback_lines(3);
        assert_eq!(lines[0].get_cell(0).map(crate::types::cell::Cell::char), Some('4'));
        let has_1 = lines.iter().any(|l| l.get_cell(0).map(crate::types::cell::Cell::char) == Some('1'));
        assert!(!has_1);
    }

    macro_rules! assert_scroll_zero_noop {
        ($name:ident, $setup:expr, $call:ident) => {
            #[test]
            fn $name() {
                let mut screen = screen_with_scrollback(10);
                $setup(&mut screen);
                screen.clear_scroll_dirty();
                let offset_before = screen.scroll_offset();
                screen.$call(0);
                assert_eq!(screen.scroll_offset(), offset_before);
                assert!(!screen.is_scroll_dirty());
            }
        };
    }

    assert_scroll_zero_noop!(test_viewport_scroll_up_zero_is_noop, |_: &mut Screen| {}, viewport_scroll_up);
    assert_scroll_zero_noop!(test_viewport_scroll_down_zero_is_noop, |s: &mut Screen| { s.viewport_scroll_up(5); }, viewport_scroll_down);

    #[test]
    fn test_set_scrollback_max_zero_clears_all() {
        let mut screen = screen_with_scrollback(15);
        screen.set_scrollback_max_lines(0);
        assert_eq!(screen.scrollback_line_count, 0);
        assert!(screen.scrollback_buffer.is_empty());
    }

    #[test]
    fn test_get_scrollback_lines_respects_limit() {
        let screen = screen_with_scrollback(20);
        let lines = screen.get_scrollback_lines(5);
        assert_eq!(lines.len(), 5);
    }

    #[test]
    fn test_get_scrollback_lines_zero_returns_empty() {
        let screen = screen_with_scrollback(10);
        let lines = screen.get_scrollback_lines(0);
        assert!(lines.is_empty());
    }

    #[test]
    fn test_get_scrollback_viewport_line_at_full_offset_bottom_row() {
        let mut screen = Screen::new(5, 10);
        screen.set_scrollback_max_lines(5);
        for _ in 0..5 { screen.scroll_up(1, Color::Default); }
        screen.viewport_scroll_up(5);
        assert!(screen.get_scrollback_viewport_line(4).is_some());
        assert!(screen.get_scrollback_viewport_line(3).is_none());
    }

    #[test]
    fn test_scrollback_empty_on_new_screen() {
        let s = make_screen();
        assert_eq!(s.scrollback_line_count, 0);
        assert!(s.scrollback_buffer.is_empty());
    }

    #[test]
    fn test_push_one_line_count_is_one() {
        let mut s = make_screen();
        s.scroll_up(1, Color::Default);
        assert_eq!(s.scrollback_line_count, 1);
        assert_eq!(s.scrollback_buffer.len(), 1);
    }

    #[test]
    fn test_push_up_to_max_count_equals_max() {
        let mut s = Screen::new(5, 10);
        s.set_scrollback_max_lines(4);
        for _ in 0..4 { s.scroll_up(1, Color::Default); }
        assert_eq!(s.scrollback_line_count, 4);
        assert_eq!(s.scrollback_buffer.len(), 4);
    }

    #[test]
    fn test_get_scrollback_lines_oldest_and_newest_order() {
        let mut s = Screen::new(5, 80);
        let attrs = SgrAttributes::default();
        for ch in ['1', '2', '3'] {
            s.move_cursor(0, 0);
            s.print(ch, attrs, false);
            s.scroll_up(1, Color::Default);
        }
        let lines = s.get_scrollback_lines(3);
        assert_eq!(lines[0].get_cell(0).map(crate::types::cell::Cell::char), Some('3'));
        assert_eq!(lines[2].get_cell(0).map(crate::types::cell::Cell::char), Some('1'));
    }

    #[test]
    fn test_get_scrollback_lines_request_more_than_available() {
        let s = screen_with_scrollback(5);
        let lines = s.get_scrollback_lines(999);
        assert_eq!(lines.len(), 5);
    }

    #[test]
    fn test_clear_scrollback_does_not_reset_scroll_offset() {
        let mut screen = screen_with_scrollback(20);
        screen.viewport_scroll_up(10);
        let offset_before = screen.scroll_offset();
        screen.clear_scrollback();
        assert_eq!(screen.scrollback_line_count, 0);
        assert_eq!(screen.scroll_offset(), offset_before);
    }
}
