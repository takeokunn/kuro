//! Scrollback buffer and viewport scroll methods for Screen

use super::{Screen, Line};

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
    #[expect(clippy::cast_possible_wrap, reason = "terminal dimensions are bounded by u16::MAX; usize/u32→isize for signed arithmetic index bounds checking")]
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
