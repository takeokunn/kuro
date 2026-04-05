//! Scroll region and scroll event methods for Screen

use std::mem;

use super::{Color, Line, Screen, ScrollRegion};

/// Push `line` onto the scrollback buffer of `screen`, evicting the oldest
/// entry when the buffer is at capacity.
#[inline]
fn push_to_scrollback(screen: &mut Screen, line: Line) {
    screen.scrollback_buffer.push_back(line);
    screen.scrollback_line_count += 1;
    while screen.scrollback_line_count > screen.scrollback_max_lines {
        if screen.scrollback_buffer.pop_front().is_none() {
            screen.scrollback_line_count = screen.scrollback_buffer.len();
            break;
        }
        screen.scrollback_line_count -= 1;
    }
}

impl Screen {
    /// Internal scroll-up implementation that operates on `self` directly
    /// (no `active_screen_mut()` dispatch).  `is_primary` controls whether
    /// evicted lines are saved to the scrollback buffer and whether the
    /// full-dirty fast path is used.
    ///
    /// Called by `scroll_up` (public, dispatches) and `line_feed_impl`
    /// (already dispatched).
    pub(super) fn scroll_up_impl(&mut self, n: usize, bg: Color, is_primary: bool) {
        let top = self.scroll_region.top;
        let bottom = self.scroll_region.bottom;
        let rows = self.rows as usize;

        // Full-screen scroll fast path: top==0, bottom==rows, primary screen.
        // VecDeque::rotate_left(n) shifts all logical rows in O(n) pointer ops
        // instead of the O(rows * n) element moves that Vec::remove + Vec::insert
        // requires.  For cmatrix with 40 rows scrolling once per frame at 60fps,
        // this eliminates 40 element clones per frame (~2400 clones/sec).
        if top == 0 && bottom == rows && is_primary {
            let n_actual = n.min(rows);

            // Swap each evicted line with a fresh blank, saving the original
            // to scrollback WITHOUT cloning.  After `rotate_left(n_actual)`
            // these blank lines end up at positions `rows-n_actual..rows`,
            // which is exactly where we would have filled blanks anyway.
            // This eliminates one full `Line` clone per evicted row.
            for i in 0..n_actual {
                if let Some(line) = self.lines.get_mut(i) {
                    let evicted = mem::replace(line, Line::new_with_bg(self.cols as usize, bg));
                    push_to_scrollback(self, evicted);
                }
            }

            // O(n) rotation: shifts indices [0..rows) left by n_actual.
            // The blank lines we just placed at [0..n_actual) rotate to
            // [rows-n_actual..rows), so no post-rotation blank fill needed.
            self.lines.rotate_left(n_actual);

            // Shift dirty bits to match the rotated content.
            self.dirty_set.shift_left(n_actual);

            // Mark ALL lines dirty so Emacs rewrites every row from Rust state.
            //
            // The original design marked only the new blank rows dirty and used
            // pending_scroll_up to let Emacs shift the buffer content via
            // delete-top + append-blank.  This fails when multiple scroll_up
            // calls accumulate between render frames: the Emacs buffer scroll
            // shifts blank rows (inserted by the previous frame's scroll) into
            // the content region, then the dirty-line rewrite only updates the
            // bottom rows — leaving stale blanks in the middle of the display.
            //
            // Setting full_dirty = true and NOT accumulating pending_scroll_up
            // bypasses the Emacs buffer scroll entirely, forcing a full repaint.
            // This is still O(rows) per frame (same as the number of lines to
            // rewrite) and eliminates the scroll-accumulation display corruption.
            self.full_dirty = true;
            self.graphics.scroll_up(n_actual);
        } else {
            // Partial-region scroll: fall back to remove+insert.
            // Each iteration is O(min(top, len-top)) for both remove and
            // insert.  For n > 1 this is O(n * region_size), but n > 1 is
            // extremely rare in practice (most terminal applications scroll
            // one line at a time).  A batch drain+splice approach would be
            // O(region_size) regardless of n, but adds complexity and risk
            // to this correctness-critical path.
            for _ in 0..n {
                if top == 0 && is_primary {
                    // `remove` returns the evicted line — use it directly
                    // instead of cloning before removal.
                    if let Some(evicted) = self.lines.remove(top) {
                        push_to_scrollback(self, evicted);
                    }
                } else {
                    self.lines.remove(top);
                }
                let new_line = Line::new_with_bg(self.cols as usize, bg);
                self.lines.insert(bottom - 1, new_line);

                self.mark_dirty_range(top, bottom);

                if self.cursor.row >= rows {
                    self.cursor.row = rows.saturating_sub(1);
                }
            }
            self.graphics.scroll_up(n);
        }
    }

    /// Scrolls the scroll region up by `n` lines, filling new blank lines with `bg`.
    /// Dispatches to the active screen and computes `is_primary` from the outer screen.
    pub fn scroll_up(&mut self, n: usize, bg: Color) {
        let is_primary = !self.is_alternate_active;
        if let Some(screen) = self.active_screen_mut() {
            screen.scroll_up_impl(n, bg, is_primary);
        }
    }

    /// Internal scroll-down implementation that operates on `self` directly.
    pub(super) fn scroll_down_impl(&mut self, n: usize, bg: Color, is_primary: bool) {
        let top = self.scroll_region.top;
        let bottom = self.scroll_region.bottom;
        let rows = self.rows as usize;

        // Full-screen scroll-down fast path (mirrors scroll_up rotation, but
        // does not save evicted lines to scrollback — lines scrolled off the
        // bottom are discarded).
        // Guard `is_primary`: alternate screen has no scrollback and its
        // content is always full-dirty redrawn.
        if top == 0 && bottom == rows && is_primary {
            let n_actual = n.min(rows);
            self.lines.rotate_right(n_actual);

            // Shift dirty bits to match the rotated content.
            self.dirty_set.shift_right(n_actual);

            // Replace the now-stale head lines with fresh blank lines.
            // Use clear_with_bg instead of new_with_bg to reuse the existing
            // Vec<Cell> allocation — avoids one heap alloc+dealloc per rotated line.
            for i in 0..n_actual {
                if let Some(line) = self.lines.get_mut(i) {
                    line.clear_with_bg(bg);
                }
            }

            // Mark ALL lines dirty (same rationale as scroll_up: avoids
            // stale-blank corruption when scroll events accumulate between
            // render frames).
            self.full_dirty = true;
            self.graphics.scroll_down(n_actual, rows);
        } else {
            // Partial-region scroll: fall back to remove+insert.
            for _ in 0..n {
                self.lines.remove(bottom - 1);
                let new_line = Line::new_with_bg(self.cols as usize, bg);
                self.lines.insert(top, new_line);

                self.mark_dirty_range(top, bottom);
            }
            self.graphics.scroll_down(n, rows);
        }
    }

    /// Scrolls the scroll region down by `n` lines, filling new blank lines at the top with `bg`.
    /// Dispatches to the active screen and computes `is_primary` from the outer screen.
    pub fn scroll_down(&mut self, n: usize, bg: Color) {
        let is_primary = !self.is_alternate_active;
        if let Some(screen) = self.active_screen_mut() {
            screen.scroll_down_impl(n, bg, is_primary);
        }
    }

    /// Set scroll region
    pub fn set_scroll_region(&mut self, top: usize, bottom: usize) {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                alt.scroll_region = ScrollRegion::new(top, bottom);
            }
        } else {
            self.scroll_region = ScrollRegion::new(top, bottom);
        }
    }

    /// Get scroll region
    #[must_use]
    pub fn get_scroll_region(&self) -> &ScrollRegion {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_ref() {
                return &alt.scroll_region;
            }
        }
        &self.scroll_region
    }

    /// Atomically consume pending full-screen scroll event counts.
    ///
    /// Returns `(scroll_up, scroll_down)` and resets both counters to 0.
    /// Called by the Emacs render cycle BEFORE `take_dirty_lines` so that
    /// buffer-level scroll operations (delete first line + append blank) can
    /// be performed first, avoiding double-render of the bottom row.
    pub fn consume_scroll_events(&mut self) -> (u32, u32) {
        let Some(screen) = self.active_screen_mut() else {
            return (0, 0);
        };
        let up = screen.pending_scroll_up;
        let down = screen.pending_scroll_down;
        screen.pending_scroll_up = 0;
        screen.pending_scroll_down = 0;
        (up, down)
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

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(256))]

        #[test]
        fn prop_scroll_up_no_panic(n in 0usize..50usize) {
            let mut screen = make_screen();
            screen.scroll_up(n, Color::Default);
            prop_assert_eq!(screen.rows(), 24);
            prop_assert_eq!(screen.cols(), 80);
        }

        #[test]
        fn prop_scroll_down_no_panic(n in 0usize..50usize) {
            let mut screen = make_screen();
            screen.scroll_down(n, Color::Default);
            prop_assert_eq!(screen.rows(), 24);
            prop_assert_eq!(screen.cols(), 80);
        }

        #[test]
        fn prop_scroll_up_preserves_line_count(n in 0usize..50usize) {
            let mut screen = make_screen();
            let rows_before = screen.rows() as usize;
            screen.scroll_up(n, Color::Default);
            prop_assert_eq!(screen.rows() as usize, rows_before);
        }

        #[test]
        fn prop_scroll_down_preserves_line_count(n in 0usize..50usize) {
            let mut screen = make_screen();
            let rows_before = screen.rows() as usize;
            screen.scroll_down(n, Color::Default);
            prop_assert_eq!(screen.rows() as usize, rows_before);
        }

        #[test]
        fn prop_full_screen_scroll_up_sets_full_dirty(n in 1usize..10usize) {
            let mut screen = make_screen();
            prop_assert_eq!(screen.get_scroll_region().top, 0);
            prop_assert_eq!(screen.get_scroll_region().bottom, 24);
            screen.scroll_up(n, Color::Default);
            let dirty = screen.take_dirty_lines();
            prop_assert_eq!(dirty.len(), 24);
        }

        #[test]
        fn prop_full_screen_scroll_down_sets_full_dirty(n in 1usize..10usize) {
            let mut screen = make_screen();
            screen.scroll_down(n, Color::Default);
            let dirty = screen.take_dirty_lines();
            prop_assert_eq!(dirty.len(), 24);
        }

        #[test]
        fn prop_consume_scroll_events_resets(n in 0usize..20usize) {
            let mut screen = make_screen();
            screen.scroll_up(n, Color::Default);
            let _ = screen.consume_scroll_events();
            let (up2, down2) = screen.consume_scroll_events();
            prop_assert_eq!(up2, 0);
            prop_assert_eq!(down2, 0);
        }

        #[test]
        fn prop_consume_scroll_events_idempotent(
            n_up in 0usize..15usize,
            n_down in 0usize..15usize,
        ) {
            let mut screen = make_screen();
            screen.scroll_up(n_up, Color::Default);
            screen.scroll_down(n_down, Color::Default);
            screen.consume_scroll_events();
            for _ in 0..3 {
                let (up, down) = screen.consume_scroll_events();
                prop_assert_eq!(up, 0);
                prop_assert_eq!(down, 0);
            }
        }

        #[test]
        fn prop_set_scroll_region_stores_values(
            top in 0usize..12usize,
            bottom in 13usize..24usize,
        ) {
            let mut screen = make_screen();
            screen.set_scroll_region(top, bottom);
            let region = screen.get_scroll_region();
            prop_assert_eq!(region.top, top);
            prop_assert_eq!(region.bottom, bottom);
        }

        #[test]
        fn prop_scroll_up_over_rows_no_panic(n in 24usize..100usize) {
            let mut screen = make_screen();
            screen.scroll_up(n, Color::Default);
            prop_assert_eq!(screen.rows() as usize, 24);
        }

        #[test]
        fn prop_scroll_up_cursor_row_in_bounds(n in 0usize..50usize) {
            let mut screen = make_screen();
            screen.move_cursor(23, 0);
            screen.scroll_up(n, Color::Default);
            prop_assert!(screen.cursor().row < screen.rows() as usize);
        }

        #[test]
        fn prop_scroll_up_grows_scrollback(n in 1usize..25usize) {
            let mut screen = make_screen();
            let before = screen.scrollback_line_count;
            screen.scroll_up(n, Color::Default);
            let added = n.min(screen.rows() as usize);
            prop_assert_eq!(screen.scrollback_line_count, before + added);
        }
    }

    #[test]
    fn test_scroll_up_one_blank_line_at_bottom() {
        let mut screen = make_screen();
        let attrs = SgrAttributes::default();
        screen.move_cursor(23, 0);
        for _ in 0..80 {
            screen.print('Z', attrs, false);
        }
        assert_eq!(screen.get_cell(23, 0).unwrap().char(), 'Z');
        screen.scroll_up(1, Color::Default);
        assert_eq!(screen.get_cell(23, 0).unwrap().char(), ' ');
    }

    #[test]
    fn test_scroll_down_one_blank_line_at_top() {
        let mut screen = make_screen();
        let attrs = SgrAttributes::default();
        screen.move_cursor(0, 0);
        screen.print('A', attrs, false);
        screen.scroll_down(1, Color::Default);
        assert_eq!(screen.get_cell(0, 0).unwrap().char(), ' ');
    }

    #[test]
    fn test_consume_scroll_events_returns_zero_zero() {
        let mut screen = make_screen();
        screen.scroll_up(5, Color::Default);
        let (up, down) = screen.consume_scroll_events();
        assert_eq!(up, 0);
        assert_eq!(down, 0);
    }

    #[test]
    fn test_consume_scroll_events_second_call_always_zero() {
        let mut screen = make_screen();
        screen.scroll_up(3, Color::Default);
        screen.consume_scroll_events();
        let (up, down) = screen.consume_scroll_events();
        assert_eq!(up, 0);
        assert_eq!(down, 0);
    }

    #[test]
    fn test_set_scroll_region_and_get_roundtrip() {
        let mut screen = make_screen();
        screen.set_scroll_region(5, 18);
        let region = screen.get_scroll_region();
        assert_eq!(region.top, 5);
        assert_eq!(region.bottom, 18);
    }

    #[test]
    fn test_scroll_up_zero_is_noop() {
        let mut screen = make_screen();
        let attrs = SgrAttributes::default();
        screen.move_cursor(0, 0);
        screen.print('Q', attrs, false);
        screen.scroll_up(0, Color::Default);
        assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'Q');
    }

    #[test]
    fn test_scroll_region_scroll_up_does_not_affect_outside_rows() {
        let mut screen = make_screen();
        let attrs = SgrAttributes::default();
        screen.move_cursor(0, 0);
        screen.print('S', attrs, false);
        screen.move_cursor(23, 0);
        screen.print('E', attrs, false);
        screen.set_scroll_region(10, 20);
        screen.scroll_up(1, Color::Default);
        assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'S');
        assert_eq!(screen.get_cell(23, 0).unwrap().char(), 'E');
    }

    #[test]
    fn test_full_dirty_is_set_after_full_screen_scroll_up() {
        let mut screen = make_screen();
        assert_eq!(screen.take_dirty_lines().len(), 0);
        screen.scroll_up(1, Color::Default);
        let dirty = screen.take_dirty_lines();
        assert_eq!(dirty.len(), 24);
    }

    #[test]
    fn test_full_dirty_cleared_by_take_dirty_lines() {
        let mut screen = make_screen();
        screen.scroll_up(1, Color::Default);
        let dirty = screen.take_dirty_lines();
        assert_eq!(dirty.len(), 24);
        let dirty2 = screen.take_dirty_lines();
        assert!(dirty2.is_empty());
    }
}
