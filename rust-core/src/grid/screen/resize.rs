//! Screen resize methods for Screen

use super::{Line, Screen, ScrollRegion, VecDeque};

/// Grow or shrink `lines` to exactly `new_rows` rows, then resize every
/// existing row to `new_cols` columns.
///
/// Existing cells beyond `new_cols` are truncated (data loss on shrink).
/// Newly added rows are blank.
///
/// # Note
/// This is a free function rather than a `Screen` method because the
/// borrow checker requires operating on a sub-field (`VecDeque<Line>`)
/// independently of the rest of `&mut Screen`.
#[inline]
fn resize_line_buffer(lines: &mut VecDeque<Line>, new_rows: usize, new_cols: usize) {
    // Grow
    while lines.len() < new_rows {
        lines.push_back(Line::new(new_cols));
    }
    // Shrink
    while lines.len() > new_rows {
        lines.pop_back();
    }
    // Resize existing cells
    for line in lines.iter_mut() {
        line.resize(new_cols);
    }
}

impl Screen {
    /// Resize the screen
    pub fn resize(&mut self, new_rows: u16, new_cols: u16) {
        self.rows = new_rows;
        self.cols = new_cols;

        let was_alternate = self.is_alternate_active;

        if let Some(screen) = self.active_screen_mut() {
            // Keep the active screen's rows/cols in sync with the outer Screen.
            // Without this, the alternate screen retains stale dimensions after
            // resize, causing incorrect cursor clamping, wrong blank-line widths
            // during scroll, and the scroll fast-path check to fail.
            screen.rows = new_rows;
            screen.cols = new_cols;

            // Resize or add/remove lines
            resize_line_buffer(&mut screen.lines, new_rows as usize, new_cols as usize);

            // Resize scrollback buffer lines to new column count
            for line in &mut screen.scrollback_buffer {
                line.resize(new_cols as usize);
            }

            // Reset scroll region
            screen.scroll_region = ScrollRegion::full_screen(new_rows as usize);

            // Clamp cursor and clear pending wrap
            screen.cursor.row = screen.cursor.row.min(new_rows.saturating_sub(1) as usize);
            screen.cursor.col = screen.cursor.col.min(new_cols.saturating_sub(1) as usize);
            screen.cursor.pending_wrap = false;
        }

        // Keep the inactive screen in sync so switching screens never causes a
        // size mismatch.  Without this, the alternate screen retains its
        // previous dimensions when resized while the primary is active (or
        // vice-versa), causing full-screen apps like htop to render with the
        // wrong terminal size after a resize.
        if was_alternate {
            // Alternate was active → resize primary lines/cursor too.
            // self.rows/cols already updated above.
            resize_line_buffer(&mut self.lines, new_rows as usize, new_cols as usize);
            for line in &mut self.scrollback_buffer {
                line.resize(new_cols as usize);
            }
            self.cursor.row = self.cursor.row.min(new_rows.saturating_sub(1) as usize);
            self.cursor.col = self.cursor.col.min(new_cols.saturating_sub(1) as usize);
        } else if let Some(ref mut alt) = self.alternate_screen {
            // Primary was active → resize cached alternate screen.
            resize_line_buffer(&mut alt.lines, new_rows as usize, new_cols as usize);
            alt.rows = new_rows;
            alt.cols = new_cols;
            alt.cursor.row = alt.cursor.row.min(new_rows.saturating_sub(1) as usize);
            alt.cursor.col = alt.cursor.col.min(new_cols.saturating_sub(1) as usize);
            alt.scroll_region = ScrollRegion::full_screen(new_rows as usize);
        }

        // Mark every line dirty so the next render cycle redraws the entire
        // screen with the new geometry.  Without this, resize leaves dirty
        // flags empty and Emacs never receives updated line content.
        self.mark_all_dirty();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::cell::SgrAttributes;
    use proptest::prelude::*;

    fn make_screen() -> Screen {
        Screen::new(24, 80)
    }

    macro_rules! assert_cell_char {
        ($screen:expr, $row:expr, $col:expr, $expected:expr, $msg:expr) => {
            assert_eq!(
                $screen.get_cell($row, $col).unwrap().char(),
                $expected,
                $msg
            )
        };
    }

    #[test]
    fn resize_updates_rows_and_cols() {
        let mut s = make_screen();
        s.resize(10, 40);
        assert_eq!(s.rows(), 10);
        assert_eq!(s.cols(), 40);
    }

    #[test]
    fn resize_larger_grows_line_count() {
        let mut s = Screen::new(5, 20);
        s.resize(10, 20);
        assert_eq!(s.rows() as usize, 10);
        assert!(s.get_line(9).is_some());
    }

    #[test]
    fn resize_smaller_shrinks_line_count() {
        let mut s = make_screen();
        s.resize(5, 40);
        assert_eq!(s.rows(), 5);
        assert!(s.get_line(5).is_none());
    }

    #[test]
    fn resize_clamps_cursor_row_when_shrinking() {
        let mut s = make_screen();
        s.move_cursor(23, 0);
        s.resize(10, 80);
        assert!(s.cursor().row < 10);
    }

    #[test]
    fn resize_clamps_cursor_col_when_shrinking() {
        let mut s = make_screen();
        s.move_cursor(0, 79);
        s.resize(24, 30);
        assert!(s.cursor().col < 30);
    }

    #[test]
    fn resize_clears_pending_wrap() {
        let mut s = make_screen();
        s.move_cursor(0, 79);
        s.print('X', SgrAttributes::default(), false);
        s.resize(24, 80);
        assert!(!s.cursor().pending_wrap);
    }

    #[test]
    fn resize_to_1x1_does_not_panic() {
        let mut s = make_screen();
        s.move_cursor(23, 79);
        s.resize(1, 1);
        assert_eq!(s.rows(), 1);
        assert_eq!(s.cols(), 1);
        assert_eq!(s.cursor().row, 0);
        assert_eq!(s.cursor().col, 0);
    }

    #[test]
    fn resize_preserves_content_within_new_bounds() {
        let mut s = make_screen();
        let attrs = SgrAttributes::default();
        s.move_cursor(0, 0);
        s.print('A', attrs, true);
        s.move_cursor(1, 1);
        s.print('B', attrs, true);
        s.resize(20, 60);
        assert_cell_char!(s, 0, 0, 'A', "cell (0,0) must survive resize");
        assert_cell_char!(s, 1, 1, 'B', "cell (1,1) must survive resize");
    }

    #[test]
    fn resize_while_alternate_active_updates_both_screens() {
        let mut s = Screen::new(10, 10);
        s.switch_to_alternate();
        s.resize(20, 40);
        assert_eq!(s.rows(), 20);
        assert_eq!(s.cols(), 40);
        s.switch_to_primary();
        assert_eq!(s.rows(), 20);
        assert_eq!(s.cols(), 40);
    }

    #[test]
    fn resize_marks_all_dirty() {
        let mut s = make_screen();
        let _ = s.take_dirty_lines();
        s.resize(30, 100);
        assert!(s.is_full_dirty());
        let dirty = s.take_dirty_lines();
        assert_eq!(dirty.len(), 30);
    }

    #[test]
    fn resize_same_dimensions_marks_dirty() {
        let mut s = make_screen();
        let _ = s.take_dirty_lines();
        s.resize(24, 80);
        assert!(s.is_full_dirty());
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(500))]

        #[test]
        fn prop_resize_updates_dimensions(r in 1u16..=200u16, c in 1u16..=200u16) {
            let mut s = Screen::new(24, 80);
            s.resize(r, c);
            prop_assert_eq!(s.rows(), r);
            prop_assert_eq!(s.cols(), c);
        }

        #[test]
        fn prop_resize_no_panic(r in 1u16..=200u16, c in 1u16..=200u16) {
            let mut s = Screen::new(24, 80);
            s.resize(r, c);
            prop_assert!(s.rows() == r && s.cols() == c);
        }

        #[test]
        fn prop_resize_clamps_cursor_row(new_rows in 1u16..=200u16) {
            let mut s = Screen::new(24, 80);
            s.move_cursor(23, 0);
            s.resize(new_rows, 80);
            prop_assert!(s.cursor().row <= (new_rows - 1) as usize);
        }

        #[test]
        fn prop_resize_clamps_cursor_col(new_cols in 1u16..=200u16) {
            let mut s = Screen::new(24, 80);
            s.move_cursor(0, 79);
            s.resize(24, new_cols);
            prop_assert!(s.cursor().col <= (new_cols - 1) as usize);
        }

        #[test]
        fn prop_resize_clears_pending_wrap(r in 1u16..=200u16, c in 1u16..=200u16) {
            let mut s = Screen::new(24, 80);
            s.cursor_mut().pending_wrap = true;
            s.resize(r, c);
            prop_assert!(!s.cursor().pending_wrap);
        }

        #[test]
        fn prop_resize_line_count_correct(r in 1u16..=100u16, c in 1u16..=100u16) {
            let mut s = Screen::new(24, 80);
            s.resize(r, c);
            prop_assert!(s.get_line((r - 1) as usize).is_some());
            prop_assert!(s.get_line(r as usize).is_none());
        }

        #[test]
        fn prop_resize_preserves_content_within_bounds(
            new_rows in 1u16..=50u16,
            new_cols in 1u16..=50u16,
        ) {
            let mut s = Screen::new(24, 80);
            s.move_cursor(0, 0);
            s.print('K', SgrAttributes::default(), true);
            s.resize(new_rows, new_cols);
            prop_assert_eq!(s.get_cell(0, 0).unwrap().char(), 'K');
        }

        #[test]
        fn prop_resize_marks_all_dirty(r in 1u16..=200u16, c in 1u16..=200u16) {
            let mut s = Screen::new(24, 80);
            let _ = s.take_dirty_lines();
            s.resize(r, c);
            prop_assert!(s.is_full_dirty());
            let dirty = s.take_dirty_lines();
            prop_assert_eq!(dirty.len(), r as usize);
        }
    }
}
