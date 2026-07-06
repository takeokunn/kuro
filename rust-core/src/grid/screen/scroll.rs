//! Scroll region and scroll event methods for Screen

use std::mem;

use super::{Color, Line, Screen, ScrollRegion};

/// Push `line` onto the scrollback buffer of `screen`, evicting the oldest
/// entry when the buffer is at capacity.
#[inline]
fn push_to_scrollback(screen: &mut Screen, line: Line) {
    screen.scrollback_buffer.push_back(line);
    screen.scrollback_line_count = screen.scrollback_buffer.len();
    while screen.scrollback_line_count > screen.scrollback_max_lines {
        if screen.scrollback_buffer.pop_front().is_none() {
            break;
        }
        screen.scrollback_line_count = screen.scrollback_buffer.len();
    }
    screen.scrollback_line_count = screen.scrollback_buffer.len();
}

impl Screen {
    #[inline]
    fn blank_line(cols: usize, bg: Color) -> Line {
        Line::new_with_bg(cols, bg)
    }

    #[inline]
    fn mark_scroll_region_dirty(&mut self) {
        let top = self.scroll_region.top;
        let bottom = self.scroll_region.bottom;
        self.mark_dirty_range(top, bottom);
    }

    #[inline]
    fn clamp_cursor_row_to_rows(&mut self) {
        let rows = usize::from(self.rows);
        if self.cursor.row >= rows {
            self.cursor.row = rows.saturating_sub(1);
        }
    }

    /// Record a full-screen scroll shift for the render drain.
    ///
    /// Same-direction shifts accumulate: Emacs replays `up` scrolls as one
    /// delete-top-N + append-N-blanks edit, which composes additively, so the
    /// aggregate count reproduces the grid state exactly (the rows exposed by
    /// the shift are marked dirty by the caller and rewritten from Rust
    /// state).  Opposite-direction shifts do NOT compose from aggregate
    /// counters — `up(1)` then `down(1)` blanks the top row, while `down(1)`
    /// then `up(1)` blanks the bottom row — so any interleave degrades to a
    /// full repaint.  This is the correctness condition the original
    /// pending-scroll design lacked (it also drained the counters in a
    /// separate FFI call from the dirty rows, so shift and rewrite could
    /// never be applied atomically; the drain now consumes both together).
    fn record_scroll_shift(&mut self, n_actual: usize, opposite_pending: bool, up: bool) {
        if opposite_pending {
            self.pending_scroll_up = 0;
            self.pending_scroll_down = 0;
            self.full_dirty = true;
        } else if !self.full_dirty {
            let n = u32::try_from(n_actual).unwrap_or(u32::MAX);
            if up {
                self.pending_scroll_up = self.pending_scroll_up.saturating_add(n);
            } else {
                self.pending_scroll_down = self.pending_scroll_down.saturating_add(n);
            }
        }
    }

    fn scroll_up_full_screen(&mut self, n: usize, bg: Color) {
        let rows = usize::from(self.rows);
        let cols = usize::from(self.cols);
        let n_actual = n.min(rows);

        // Swap each evicted line with a fresh blank, saving the original
        // to scrollback WITHOUT cloning.  After `rotate_left(n_actual)`
        // these blank lines end up at positions `rows-n_actual..rows`,
        // which is exactly where we would have filled blanks anyway.
        // This eliminates one full `Line` clone per evicted row.
        for i in 0..n_actual {
            if let Some(line) = self.lines.get_mut(i) {
                let evicted = mem::replace(line, Self::blank_line(cols, bg));
                push_to_scrollback(self, evicted);
            }
        }

        // O(n) rotation: shifts indices [0..rows) left by n_actual.
        // The blank lines we just placed at [0..n_actual) rotate to
        // [rows-n_actual..rows), so no post-rotation blank fill needed.
        self.lines.rotate_left(n_actual);

        // Shift dirty bits to match the rotated content.
        self.dirty_set.shift_left(n_actual);

        // Only the blank rows exposed at the bottom need a repaint; the
        // rest of the viewport is reproduced on the Emacs side by the
        // pending-scroll shift (delete top N lines + append N blanks)
        // recorded below.  This keeps per-scroll render cost O(n) instead
        // of the O(rows) full repaint the previous full_dirty design
        // required, which is what kept AI-agent streaming output smooth.
        self.mark_dirty_range(rows - n_actual, rows);

        self.record_scroll_shift(n_actual, self.pending_scroll_down > 0, true);
        self.graphics.scroll_up(n_actual);
    }

    fn scroll_up_partial_region(&mut self, n: usize, bg: Color, is_primary: bool) {
        let top = self.scroll_region.top;
        let bottom = self.scroll_region.bottom;
        let cols = usize::from(self.cols);

        // Clamp to the region height, mirroring the full-screen path's
        // `n.min(rows)`. Scrolling by >= the region height blanks the whole
        // region, so extra iterations are pure churn — and `n` comes from a vte
        // param (up to 65535), so an unclamped loop is an amplification DoS
        // (each iteration heap-allocates a blank `Line` and does VecDeque
        // remove+insert), freezing the synchronous module call.
        let n = n.min(bottom.saturating_sub(top));

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
            self.lines.insert(bottom - 1, Self::blank_line(cols, bg));
        }

        self.mark_scroll_region_dirty();
        self.clamp_cursor_row_to_rows();
        self.graphics.scroll_up(n);
    }

    fn scroll_down_full_screen(&mut self, n: usize, bg: Color) {
        let rows = usize::from(self.rows);
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

        // Only the blank rows exposed at the top need a repaint; the rest
        // of the viewport is reproduced by the pending-scroll shift (see
        // `record_scroll_shift` and `scroll_up_full_screen`).
        self.mark_dirty_range(0, n_actual);

        self.record_scroll_shift(n_actual, self.pending_scroll_up > 0, false);
        self.graphics.scroll_down(n_actual, rows);
    }

    fn scroll_down_partial_region(&mut self, n: usize, bg: Color, rows: usize) {
        let top = self.scroll_region.top;
        let bottom = self.scroll_region.bottom;
        let cols = usize::from(self.cols);

        // Clamp to the region height (see `scroll_up_partial_region`): an
        // unclamped vte param would drive an amplification DoS via per-iteration
        // blank-line allocation and VecDeque remove+insert.
        let n = n.min(bottom.saturating_sub(top));

        // Partial-region scroll: fall back to remove+insert.
        for _ in 0..n {
            self.lines.remove(bottom - 1);
            self.lines.insert(top, Self::blank_line(cols, bg));
        }

        self.mark_scroll_region_dirty();
        self.graphics.scroll_down(n, rows);
    }

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
        let rows = usize::from(self.rows);

        // Full-screen scroll fast path: top==0, bottom==rows, primary screen.
        // VecDeque::rotate_left(n) shifts all logical rows in O(n) pointer ops
        // instead of the O(rows * n) element moves that Vec::remove + Vec::insert
        // requires.  For cmatrix with 40 rows scrolling once per frame at 60fps,
        // this eliminates 40 element clones per frame (~2400 clones/sec).
        if top == 0 && bottom == rows && is_primary {
            self.scroll_up_full_screen(n, bg);
        } else {
            self.scroll_up_partial_region(n, bg, is_primary);
        }
    }

    /// Scrolls the scroll region up by `n` lines, filling new blank lines with `bg`.
    /// Dispatches to the active screen and computes `is_primary` from the outer screen.
    pub fn scroll_up(&mut self, n: usize, bg: Color) {
        let is_primary = !self.is_alternate_active;
        self.with_active_screen_mut(|screen| {
            screen.scroll_up_impl(n, bg, is_primary);
        });
    }

    /// Internal scroll-down implementation that operates on `self` directly.
    pub(super) fn scroll_down_impl(&mut self, n: usize, bg: Color, is_primary: bool) {
        let top = self.scroll_region.top;
        let bottom = self.scroll_region.bottom;
        let rows = usize::from(self.rows);

        // Full-screen scroll-down fast path (mirrors scroll_up rotation, but
        // does not save evicted lines to scrollback — lines scrolled off the
        // bottom are discarded).
        // Guard `is_primary`: alternate screen has no scrollback and its
        // content is always full-dirty redrawn.
        if top == 0 && bottom == rows && is_primary {
            self.scroll_down_full_screen(n, bg);
        } else {
            self.scroll_down_partial_region(n, bg, rows);
        }
    }

    /// Scrolls the scroll region down by `n` lines, filling new blank lines at the top with `bg`.
    /// Dispatches to the active screen and computes `is_primary` from the outer screen.
    pub fn scroll_down(&mut self, n: usize, bg: Color) {
        let is_primary = !self.is_alternate_active;
        self.with_active_screen_mut(|screen| {
            screen.scroll_down_impl(n, bg, is_primary);
        });
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
        self.with_active_screen(|screen| &screen.scroll_region)
            .unwrap_or(&self.scroll_region)
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
#[path = "scroll/tests.rs"]
mod tests;
