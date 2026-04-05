//! Alternate screen buffer switching methods for Screen

use super::Screen;

impl Screen {
    /// Switch to alternate screen buffer (DEC mode 1049 set)
    pub fn switch_to_alternate(&mut self) {
        if self.is_alternate_active {
            return;
        }

        // Save primary state
        self.saved_primary_cursor = Some(self.cursor);
        self.saved_scroll_region = Some(self.scroll_region);

        // Create or activate alternate screen
        if self.alternate_screen.is_none() {
            self.alternate_screen = Some(Box::new(Self::new(self.rows, self.cols)));
        }
        self.is_alternate_active = true;

        // Clear alternate screen
        if let Some(alt_screen) = self.alternate_screen.as_mut() {
            let rows = alt_screen.rows() as usize;
            alt_screen.clear_lines(0, rows);
            // Mark all lines dirty
            alt_screen.full_dirty = true;
        }
    }

    /// Switch back to primary screen buffer (DEC mode 1049 reset)
    pub const fn switch_to_primary(&mut self) {
        if !self.is_alternate_active {
            return;
        }

        self.is_alternate_active = false;

        // Mark all lines dirty
        self.full_dirty = true;

        // Restore saved cursor if available
        if let Some(cursor) = self.saved_primary_cursor.take() {
            self.cursor = cursor;
        }

        // Restore saved scroll region if available
        if let Some(scroll_region) = self.saved_scroll_region.take() {
            self.scroll_region = scroll_region;
        }
    }

    /// Check if alternate screen is currently active
    #[must_use]
    pub const fn is_alternate_screen_active(&self) -> bool {
        self.is_alternate_active
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

    #[test]
    fn alternate_initially_inactive() {
        let s = make_screen();
        assert!(!s.is_alternate_screen_active());
    }

    #[test]
    fn switch_to_alternate_activates_flag() {
        let mut s = make_screen();
        s.switch_to_alternate();
        assert!(s.is_alternate_screen_active());
    }

    #[test]
    fn switch_to_alternate_is_idempotent() {
        let mut s = make_screen();
        s.switch_to_alternate();
        s.switch_to_alternate();
        assert!(s.is_alternate_screen_active());
    }

    #[test]
    fn switch_to_alternate_cursor_starts_at_origin() {
        let mut s = make_screen();
        s.move_cursor(10, 20);
        s.switch_to_alternate();
        assert_eq!(s.cursor().row, 0);
        assert_eq!(s.cursor().col, 0);
    }

    #[test]
    fn switch_to_alternate_clears_content() {
        let mut s = make_screen();
        let attrs = SgrAttributes::default();
        s.move_cursor(0, 0);
        s.print('X', attrs, true);
        s.switch_to_alternate();
        assert_eq!(s.get_cell(0, 0).unwrap().char(), ' ');
    }

    #[test]
    fn switch_to_alternate_saves_primary_cursor() {
        let mut s = make_screen();
        s.move_cursor(7, 15);
        s.switch_to_alternate();
        s.switch_to_primary();
        assert_eq!(s.cursor().row, 7);
        assert_eq!(s.cursor().col, 15);
    }

    #[test]
    fn switch_to_primary_deactivates_flag() {
        let mut s = make_screen();
        s.switch_to_alternate();
        s.switch_to_primary();
        assert!(!s.is_alternate_screen_active());
    }

    #[test]
    fn switch_to_primary_is_idempotent_when_not_alternate() {
        let mut s = make_screen();
        s.switch_to_primary();
        assert!(!s.is_alternate_screen_active());
    }

    #[test]
    fn switch_to_primary_restores_cursor() {
        let mut s = make_screen();
        s.move_cursor(3, 12);
        s.switch_to_alternate();
        s.move_cursor(1, 1);
        s.switch_to_primary();
        assert_eq!(s.cursor().row, 3);
        assert_eq!(s.cursor().col, 12);
    }

    #[test]
    fn primary_content_unaffected_by_alternate_writes() {
        let mut s = make_screen();
        let attrs = SgrAttributes::default();
        s.move_cursor(0, 0);
        s.print('P', attrs, true);
        s.switch_to_alternate();
        s.move_cursor(0, 0);
        s.print('A', attrs, true);
        s.switch_to_primary();
        assert_eq!(s.get_cell(0, 0).unwrap().char(), 'P');
    }

    #[test]
    fn alternate_content_unaffected_by_primary_writes_after_switch() {
        let mut s = make_screen();
        let attrs = SgrAttributes::default();
        s.switch_to_alternate();
        s.move_cursor(0, 0);
        s.print('A', attrs, true);
        s.switch_to_primary();
        s.move_cursor(0, 0);
        s.print('P', attrs, true);
        s.switch_to_alternate();
        assert_eq!(s.get_cell(0, 0).unwrap().char(), ' ');
    }

    #[test]
    fn alternate_screen_dimensions_match_primary() {
        let mut s = make_screen();
        s.switch_to_alternate();
        assert_eq!(s.rows(), 24);
        assert_eq!(s.cols(), 80);
    }

    #[test]
    fn switch_to_alternate_marks_alternate_full_dirty() {
        let mut s = make_screen();
        s.switch_to_alternate();
        assert!(s.is_full_dirty());
    }

    #[test]
    fn switch_to_primary_marks_primary_full_dirty() {
        let mut s = make_screen();
        s.switch_to_alternate();
        let _ = s.take_dirty_lines();
        s.switch_to_primary();
        assert!(s.is_full_dirty());
    }

    #[test]
    fn take_dirty_lines_on_alternate_drains_alt_dirty() {
        let mut s = make_screen();
        s.switch_to_alternate();
        let dirty = s.take_dirty_lines();
        assert_eq!(dirty.len(), 24);
        assert!(!s.is_full_dirty());
    }

    #[test]
    fn switch_to_alternate_saves_scroll_region_then_restores() {
        let mut s = make_screen();
        s.set_scroll_region(3, 18);
        let saved_top = s.get_scroll_region().top;
        let saved_bottom = s.get_scroll_region().bottom;
        s.switch_to_alternate();
        s.switch_to_primary();
        assert_eq!(s.get_scroll_region().top, saved_top);
        assert_eq!(s.get_scroll_region().bottom, saved_bottom);
    }

    #[test]
    fn cursor_position_isolated_between_primary_and_alternate() {
        let mut s = make_screen();
        s.move_cursor(10, 30);
        s.switch_to_alternate();
        s.move_cursor(5, 7);
        assert_eq!(s.cursor().row, 5);
        assert_eq!(s.cursor().col, 7);
        s.switch_to_primary();
        assert_eq!(s.cursor().row, 10);
        assert_eq!(s.cursor().col, 30);
    }

    #[test]
    fn multiple_alt_cycles_restore_cursor_each_time() {
        let mut s = Screen::new(24, 80);
        let attrs = SgrAttributes::default();
        s.move_cursor(3, 7);
        s.switch_to_alternate();
        s.switch_to_primary();
        assert_eq!(s.cursor().row, 3);
        assert_eq!(s.cursor().col, 7);
        s.move_cursor(15, 60);
        s.switch_to_alternate();
        s.print('Q', attrs, true);
        s.switch_to_primary();
        assert_eq!(s.cursor().row, 15);
        assert_eq!(s.cursor().col, 60);
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(64))]

        #[test]
        fn prop_primary_content_survives_alt_cycle(ch in proptest::char::range('A', 'Z')) {
            let mut s = Screen::new(24, 80);
            let attrs = SgrAttributes::default();
            s.move_cursor(0, 0);
            s.print(ch, attrs, true);
            s.switch_to_alternate();
            s.switch_to_primary();
            prop_assert_eq!(s.get_cell(0, 0).unwrap().char(), ch);
        }

        #[test]
        fn prop_not_alternate_after_full_cycle(rows in 4u16..=30u16, cols in 10u16..=100u16) {
            let mut s = Screen::new(rows, cols);
            s.switch_to_alternate();
            s.switch_to_primary();
            prop_assert!(!s.is_alternate_screen_active());
        }

        #[test]
        fn prop_cursor_restored_after_alt_cycle(
            row in 0usize..24usize,
            col in 0usize..80usize,
        ) {
            let mut s = Screen::new(24, 80);
            s.move_cursor(row, col);
            s.switch_to_alternate();
            s.switch_to_primary();
            prop_assert_eq!(s.cursor().row, row);
            prop_assert_eq!(s.cursor().col, col);
        }
    }
}
