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

/// Resize the PRIMARY screen + scrollback content, reflowing (rewrapping) soft
/// wraps when the column count changes.
///
/// `old_cols` is the column count *before* this resize.  When it differs from
/// `new_cols`, soft-wrapped runs are coalesced into logical lines and re-split
/// at the new width (`Screen::reflow_primary`), preserving content, per-cell
/// attributes, wide chars, and the cursor's logical position.  When the width
/// is unchanged, the cheap per-line truncate/pad path is taken (height-only
/// change needs no rewrap).
#[inline]
fn resize_buffered_screen_content(
    screen: &mut Screen,
    is_primary: bool,
    old_cols: u16,
    new_rows: u16,
    new_cols: u16,
) {
    if is_primary && old_cols != new_cols {
        // Width changed → reflow.  reflow_primary rebuilds lines + scrollback
        // and returns the recovered cursor position (or None → fall back to a
        // simple clamp).  The cursor to track is whichever one currently
        // belongs to the primary buffer: when the alternate screen is active
        // the primary cursor was saved off in `saved_primary_cursor`.
        let (track_row, track_col) = screen
            .saved_primary_cursor
            .map_or((screen.cursor.row, screen.cursor.col), |c| (c.row, c.col));

        let recovered =
            screen.reflow_primary(new_rows as usize, new_cols as usize, track_row, track_col);

        let (row, col) = recovered.unwrap_or_else(|| {
            (
                track_row.min(new_rows.saturating_sub(1) as usize),
                track_col.min(new_cols.saturating_sub(1) as usize),
            )
        });

        // Write the reflowed cursor back to wherever the primary cursor lives.
        if let Some(saved) = screen.saved_primary_cursor.as_mut() {
            saved.row = row;
            saved.col = col;
        } else {
            screen.cursor.row = row;
            screen.cursor.col = col;
        }
        return;
    }

    // Width unchanged (height-only change): keep the existing cheap path.
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
fn resize_active_screen_state(
    screen: &mut Screen,
    is_primary: bool,
    old_cols: u16,
    new_rows: u16,
    new_cols: u16,
) {
    screen.rows = new_rows;
    screen.cols = new_cols;

    resize_buffered_screen_content(screen, is_primary, old_cols, new_rows, new_cols);
    screen.scroll_region = ScrollRegion::full_screen(new_rows as usize);
    screen.cursor.pending_wrap = false;
}

#[inline]
fn resize_primary_while_alternate_active(
    screen: &mut Screen,
    old_cols: u16,
    new_rows: u16,
    new_cols: u16,
) {
    // The cached primary buffer is always reflowed (is_primary = true).
    resize_buffered_screen_content(screen, true, old_cols, new_rows, new_cols);
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
        // Capture the pre-resize width BEFORE overwriting self.cols so reflow
        // can detect a width change (old_cols != new_cols).
        let old_cols = self.cols;

        self.rows = new_rows;
        self.cols = new_cols;

        let was_alternate = self.is_alternate_active;

        // Only the PRIMARY screen is reflowed.  When the alternate screen is
        // active, the active buffer is the alternate one — fullscreen apps
        // redraw themselves, so it is merely resized (is_primary = false).
        let active_is_primary = !was_alternate;

        self.with_active_screen_mut(|screen| {
            // Keep the active screen's geometry in sync with the outer Screen.
            // Without this, the active buffer would keep stale dimensions and
            // later cursor, scroll, and blank-line calculations would diverge.
            resize_active_screen_state(screen, active_is_primary, old_cols, new_rows, new_cols);
        });

        // Keep the inactive screen in sync so switching screens never causes a
        // size mismatch.  Without this, the alternate screen retains its
        // previous dimensions when resized while the primary is active (or
        // vice-versa), causing full-screen apps like htop to render with the
        // wrong terminal size after a resize.
        if was_alternate {
            // Alternate was active → resize the cached primary buffer too,
            // reflowing it (the primary keeps its real scrollback + soft wraps).
            // self.rows/cols were already updated above.
            resize_primary_while_alternate_active(self, old_cols, new_rows, new_cols);
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
