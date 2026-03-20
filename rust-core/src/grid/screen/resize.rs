//! Screen resize methods for Screen

use super::{VecDeque, Line, Screen, ScrollRegion};

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
    }
}
