//! Scrollback buffer and viewport scroll methods for Screen

use super::{Line, Screen};

#[inline]
fn trim_scrollback_to_max(screen: &mut Screen) {
    while screen.scrollback_line_count > screen.scrollback_max_lines {
        if screen.scrollback_buffer.pop_front().is_some() {
            screen.scrollback_line_count -= 1;
        }
    }
}

#[inline]
const fn reset_live_view_scroll_state(screen: &mut Screen) {
    screen.full_dirty = true;
    screen.scroll_dirty = false;

    // Reset pending scroll counters that accumulated while the user was
    // viewing scrollback. Without this, stale counts would burst-apply in
    // `consume_scroll_events` on the first render frame after returning to the
    // live view, causing the Emacs buffer to shift by the wrong number of
    // lines.
    screen.pending_scroll_up = 0;
    screen.pending_scroll_down = 0;
}

#[inline]
const fn set_scroll_offset(screen: &mut Screen, new_offset: usize) {
    screen.scroll_offset = new_offset;
    if new_offset == 0 {
        reset_live_view_scroll_state(screen);
    } else {
        screen.scroll_dirty = true;
    }
}

impl Screen {
    /// Set maximum scrollback buffer size
    pub fn set_scrollback_max_lines(&mut self, max_lines: usize) {
        self.with_active_screen_mut(|screen| {
            screen.scrollback_max_lines = max_lines;
            trim_scrollback_to_max(screen);
        });
    }

    /// Get scrollback lines (most recent first)
    #[must_use]
    pub fn get_scrollback_lines(&self, max_lines: usize) -> Vec<Line> {
        self.with_active_screen(|screen| {
            screen
                .scrollback_buffer
                .iter()
                .rev()
                .take(max_lines)
                .cloned()
                .collect()
        })
        .unwrap_or_default()
    }

    /// Clear the scrollback buffer
    pub fn clear_scrollback(&mut self) {
        self.with_active_screen_mut(|screen| {
            screen.scrollback_buffer.clear();
            screen.scrollback_line_count = 0;
        });
    }

    /// Scroll the viewport up by n lines (toward older scrollback content)
    ///
    /// No-op when the alternate screen is active (alternate screen has no scrollback).
    pub fn viewport_scroll_up(&mut self, n: usize) {
        if self.is_alternate_active {
            return;
        }
        let new_offset = self
            .scroll_offset
            .saturating_add(n)
            .min(self.scrollback_line_count);
        if new_offset != self.scroll_offset {
            set_scroll_offset(self, new_offset);
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
            set_scroll_offset(self, new_offset);
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
    /// line count. Returns `None` when the computed index is outside the
    /// scrollback buffer.
    #[must_use]
    pub fn get_scrollback_viewport_line(&self, row_in_viewport: usize) -> Option<&Line> {
        let rows = usize::from(self.rows);
        if rows == 0 || row_in_viewport >= rows {
            return None;
        }

        // `scroll_offset` points to the scrollback line shown at the bottom of
        // the viewport. Rows above it move further back from the scrollback end.
        let rows_above_bottom = rows - 1 - row_in_viewport;
        let distance_from_end = self.scroll_offset.checked_add(rows_above_bottom)?;
        let idx = self.scrollback_line_count.checked_sub(distance_from_end)?;
        self.scrollback_buffer.get(idx)
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
#[path = "scrollback/tests.rs"]
mod tests;
