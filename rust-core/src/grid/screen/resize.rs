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

#[inline]
fn clamp_cursor(cursor_row: &mut usize, cursor_col: &mut usize, new_rows: u16, new_cols: u16) {
    *cursor_row = (*cursor_row).min(new_rows.saturating_sub(1) as usize);
    *cursor_col = (*cursor_col).min(new_cols.saturating_sub(1) as usize);
}

#[inline]
fn resize_buffered_screen_content(screen: &mut Screen, new_rows: u16, new_cols: u16) {
    resize_line_buffer(&mut screen.lines, new_rows as usize, new_cols as usize);

    for line in &mut screen.scrollback_buffer {
        line.resize(new_cols as usize);
    }

    clamp_cursor(
        &mut screen.cursor.row,
        &mut screen.cursor.col,
        new_rows,
        new_cols,
    );
}

#[inline]
fn resize_active_screen_state(screen: &mut Screen, new_rows: u16, new_cols: u16) {
    screen.rows = new_rows;
    screen.cols = new_cols;

    resize_buffered_screen_content(screen, new_rows, new_cols);
    screen.scroll_region = ScrollRegion::full_screen(new_rows as usize);
    screen.cursor.pending_wrap = false;
}

#[inline]
fn resize_primary_while_alternate_active(screen: &mut Screen, new_rows: u16, new_cols: u16) {
    resize_buffered_screen_content(screen, new_rows, new_cols);
}

#[inline]
fn resize_cached_alternate_screen(screen: &mut Screen, new_rows: u16, new_cols: u16) {
    resize_line_buffer(&mut screen.lines, new_rows as usize, new_cols as usize);
    screen.rows = new_rows;
    screen.cols = new_cols;
    clamp_cursor(
        &mut screen.cursor.row,
        &mut screen.cursor.col,
        new_rows,
        new_cols,
    );
    screen.scroll_region = ScrollRegion::full_screen(new_rows as usize);
}

impl Screen {
    /// Resize the screen
    pub fn resize(&mut self, new_rows: u16, new_cols: u16) {
        self.rows = new_rows;
        self.cols = new_cols;

        let was_alternate = self.is_alternate_active;

        if let Some(screen) = self.active_screen_mut() {
            // Keep the active screen's geometry in sync with the outer Screen.
            // Without this, the active buffer would keep stale dimensions and
            // later cursor, scroll, and blank-line calculations would diverge.
            resize_active_screen_state(screen, new_rows, new_cols);
        }

        // Keep the inactive screen in sync so switching screens never causes a
        // size mismatch.  Without this, the alternate screen retains its
        // previous dimensions when resized while the primary is active (or
        // vice-versa), causing full-screen apps like htop to render with the
        // wrong terminal size after a resize.
        if was_alternate {
            // Alternate was active → resize the cached primary buffer too.
            // self.rows/cols were already updated above.
            resize_primary_while_alternate_active(self, new_rows, new_cols);
        } else if let Some(ref mut alt) = self.alternate_screen {
            // Primary was active → resize cached alternate screen.
            resize_cached_alternate_screen(alt, new_rows, new_cols);
        }

        // Mark every line dirty so the next render cycle redraws the entire
        // screen with the new geometry.  Without this, resize leaves dirty
        // flags empty and Emacs never receives updated line content.
        self.mark_all_dirty();
    }
}

#[cfg(test)]
#[macro_use]
#[path = "resize/tests_support.rs"]
mod tests_support;

#[cfg(test)]
#[path = "resize/tests_cases.rs"]
mod tests_cases;
