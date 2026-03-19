//! Scroll region and scroll event methods for Screen

use super::*;

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
    /// Scrolls the scroll region up by `n` lines, filling new blank lines with `bg`.
    /// Uses an O(n) fast path for full-screen scrolls and saves evicted lines to the scrollback buffer.
    pub fn scroll_up(&mut self, n: usize, bg: Color) {
        let is_primary = !self.is_alternate_active;
        let screen = match self.active_screen_mut() {
            Some(s) => s,
            None => return,
        };
        let top = screen.scroll_region.top;
        let bottom = screen.scroll_region.bottom;
        let rows = screen.rows as usize;

        // Full-screen scroll fast path: top==0, bottom==rows, no alternate active.
        // VecDeque::rotate_left(n) shifts all logical rows in O(n) pointer ops
        // instead of the O(rows * n) element moves that Vec::remove + Vec::insert
        // requires.  For cmatrix with 40 rows scrolling once per frame at 60fps,
        // this eliminates 40 element clones per frame (~2400 clones/sec).
        if top == 0 && bottom == rows && is_primary {
            let n_actual = n.min(rows);

            // Save the lines that will be rotated out to the scrollback buffer.
            for i in 0..n_actual {
                if let Some(line) = screen.lines.get(i).cloned() {
                    push_to_scrollback(screen, line);
                }
            }

            // O(n) rotation: shifts indices [0..rows) left by n_actual.
            screen.lines.rotate_left(n_actual);

            // Replace the now-stale tail lines with fresh blank lines.
            for i in (rows - n_actual)..rows {
                if let Some(line) = screen.lines.get_mut(i) {
                    *line = Line::new_with_bg(screen.cols as usize, bg);
                }
            }

            // Mark only the new blank lines dirty; Emacs handles the shift via
            // the pending_scroll_up count in consume_scroll_events.
            screen.mark_dirty_range(rows - n_actual, rows);
            screen.pending_scroll_up += n_actual as u32;
            screen.graphics.scroll_up(n_actual);
        } else {
            // Partial-region scroll: fall back to remove+insert.
            for _ in 0..n {
                if top == 0 && is_primary {
                    if let Some(line) = screen.lines.get(top).cloned() {
                        push_to_scrollback(screen, line);
                    }
                }

                screen.lines.remove(top);
                let new_line = Line::new_with_bg(screen.cols as usize, bg);
                screen.lines.insert(bottom - 1, new_line);

                screen.mark_dirty_range(top, bottom);

                if screen.cursor.row >= rows {
                    screen.cursor.row = rows.saturating_sub(1);
                }
            }
            screen.graphics.scroll_up(n);
        }
    }

    /// Scrolls the scroll region down by `n` lines, filling new blank lines at the top with `bg`.
    pub fn scroll_down(&mut self, n: usize, bg: Color) {
        let screen = match self.active_screen_mut() {
            Some(s) => s,
            None => return,
        };
        let top = screen.scroll_region.top;
        let bottom = screen.scroll_region.bottom;
        let rows = screen.rows as usize;

        // Full-screen scroll-down fast path (symmetric to scroll_up).
        if top == 0 && bottom == rows {
            let n_actual = n.min(rows);
            screen.lines.rotate_right(n_actual);

            // Replace the now-stale head lines with fresh blank lines.
            for i in 0..n_actual {
                if let Some(line) = screen.lines.get_mut(i) {
                    *line = Line::new_with_bg(screen.cols as usize, bg);
                }
            }

            // Mark only the new blank lines dirty.
            screen.mark_dirty_range(0, n_actual);
            screen.pending_scroll_down += n_actual as u32;
            screen.graphics.scroll_down(n_actual, rows);
        } else {
            // Partial-region scroll: fall back to remove+insert.
            for _ in 0..n {
                screen.lines.remove(bottom - 1);
                let new_line = Line::new_with_bg(screen.cols as usize, bg);
                screen.lines.insert(top, new_line);

                screen.mark_dirty_range(top, bottom);
            }
            screen.graphics.scroll_down(n, rows);
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
        let screen = match self.active_screen_mut() {
            Some(s) => s,
            None => return (0, 0),
        };
        let up = screen.pending_scroll_up;
        let down = screen.pending_scroll_down;
        screen.pending_scroll_up = 0;
        screen.pending_scroll_down = 0;
        (up, down)
    }
}
