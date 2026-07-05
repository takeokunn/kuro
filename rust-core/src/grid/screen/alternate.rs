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
            let rows = usize::from(alt_screen.rows());
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

        // Mark all lines dirty.  Also discard any scroll shift the primary
        // screen accumulated before the alternate screen was entered: the
        // full repaint rewrites every row, so replaying a stale shift on
        // the Emacs side would corrupt the display (full_dirty invariant,
        // see `mark_all_dirty`).
        self.full_dirty = true;
        self.pending_scroll_up = 0;
        self.pending_scroll_down = 0;

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
#[path = "alternate/tests_support.rs"]
mod tests_support;

#[cfg(test)]
#[path = "alternate/tests_cases.rs"]
mod tests_cases;
