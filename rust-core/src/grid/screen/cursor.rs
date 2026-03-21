//! Cursor movement and character printing methods for Screen

use super::{
    Cell, CellWidth, Color, Cursor, DirtySet as _, Screen, SgrAttributes, UnicodeWidthChar,
};

impl Screen {
    /// Get reference to the active screen's cursor
    #[inline]
    #[must_use]
    pub fn cursor(&self) -> &Cursor {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_ref() {
                return &alt.cursor;
            }
        }
        &self.cursor
    }

    /// Get mutable reference to the active screen's cursor
    #[inline]
    pub fn cursor_mut(&mut self) -> &mut Cursor {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                return &mut alt.cursor;
            }
        }
        &mut self.cursor
    }

    /// Move cursor to absolute position (clears pending wrap)
    #[inline]
    pub fn move_cursor(&mut self, row: usize, col: usize) {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                alt.cursor.row = row.min(alt.rows as usize - 1);
                alt.cursor.col = col.min(alt.cols as usize - 1);
                alt.cursor.pending_wrap = false;
            }
        } else {
            self.cursor.row = row.min(self.rows as usize - 1);
            self.cursor.col = col.min(self.cols as usize - 1);
            self.cursor.pending_wrap = false;
        }
    }

    /// Move cursor relative (clears pending wrap)
    #[inline]
    pub fn move_cursor_by(&mut self, row_offset: i32, col_offset: i32) {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                alt.cursor.move_by(col_offset, row_offset);
                alt.cursor.row = alt.cursor.row.min(alt.rows as usize - 1);
                alt.cursor.col = alt.cursor.col.min(alt.cols as usize - 1);
                alt.cursor.pending_wrap = false;
            }
        } else {
            self.cursor.move_by(col_offset, row_offset);
            self.cursor.row = self.cursor.row.min(self.rows as usize - 1);
            self.cursor.col = self.cursor.col.min(self.cols as usize - 1);
            self.cursor.pending_wrap = false;
        }
    }

    /// Carriage return (CR) — clears pending wrap
    #[inline]
    pub fn carriage_return(&mut self) {
        if let Some(screen) = self.active_screen_mut() {
            screen.cursor.col = 0;
            screen.cursor.pending_wrap = false;
        }
    }

    /// Backspace (BS) — clears pending wrap
    #[inline]
    pub fn backspace(&mut self) {
        if let Some(screen) = self.active_screen_mut() {
            if screen.cursor.col > 0 {
                screen.cursor.col -= 1;
            }
            screen.cursor.pending_wrap = false;
        }
    }

    /// Horizontal tab (HT) — clears pending wrap
    #[inline]
    pub fn tab(&mut self) {
        if let Some(screen) = self.active_screen_mut() {
            let tab_stop = (screen.cursor.col / 8 + 1) * 8;
            screen.cursor.col = tab_stop.min(screen.cols as usize - 1);
            screen.cursor.pending_wrap = false;
        }
    }

    /// Internal line-feed that operates on an already-dispatched screen.
    /// `is_primary` is forwarded to `scroll_up_impl` so alternate-screen
    /// scrolls never save to scrollback.
    ///
    /// Per VT220: scrolling the scroll region is only triggered when the cursor
    /// is **within** [top, bottom) **and** at the bottom margin (cursor.row ==
    /// bottom - 1).  If the cursor is outside the scroll region (above top or
    /// below bottom), the cursor simply moves down one row, clamped at rows - 1.
    #[inline]
    pub(super) fn line_feed_impl(&mut self, bg: Color, is_primary: bool) {
        self.cursor.pending_wrap = false;
        let new_row = self.cursor.row + 1;
        let rows = self.rows as usize;

        // Cursor must be inside [top, bottom) to trigger a region scroll.
        let in_region = self.cursor.row >= self.scroll_region.top
            && self.cursor.row < self.scroll_region.bottom;

        if in_region && new_row >= self.scroll_region.bottom {
            self.scroll_up_impl(1, bg, is_primary);
        } else {
            self.cursor.row = new_row.min(rows - 1);
        }
    }

    /// Line feed (LF): advances cursor down one row, scrolling up if at the bottom of the scroll region.
    /// Clears pending wrap.  Dispatches to the active screen.
    #[inline]
    pub fn line_feed(&mut self, bg: Color) {
        let is_primary = !self.is_alternate_active;
        if let Some(screen) = self.active_screen_mut() {
            screen.line_feed_impl(bg, is_primary);
        }
    }

    /// Print a character at the cursor position.
    ///
    /// Implements DEC pending-wrap (DECAWM last-column flag):
    /// - When a character fills the last column the cursor stays there and
    ///   `pending_wrap` is set.
    /// - On the *next* printable character the deferred wrap fires (col → 0,
    ///   `line_feed`).
    /// - Any explicit cursor movement clears `pending_wrap` without wrapping.
    #[inline]
    pub fn print(&mut self, c: char, attrs: SgrAttributes, auto_wrap: bool) {
        // Compute is_primary BEFORE dispatching so that scroll_up_impl
        // (called from line_feed_impl) sees the correct value even when
        // operating on the alternate screen.
        let is_primary = !self.is_alternate_active;
        let Some(screen) = self.active_screen_mut() else {
            return;
        };

        // --- Deferred wrap: execute the pending wrap from a previous print ---
        if screen.cursor.pending_wrap {
            screen.cursor.pending_wrap = false;
            if auto_wrap {
                screen.cursor.col = 0;
                screen.line_feed_impl(attrs.background, is_primary);
            }
        }

        let row = screen.cursor.row;
        let col = screen.cursor.col;

        // Determine character width using Unicode width
        let width = UnicodeWidthChar::width(c).unwrap_or(1);
        let cell_width = if width > 1 {
            CellWidth::Full
        } else {
            CellWidth::Half
        };

        // Check if character fits on current line
        if col + width <= screen.cols as usize {
            // Create and update the main cell
            let mut cell = Cell::new(c);
            cell.attrs = attrs;
            cell.width = cell_width;

            if let Some(line) = screen.lines.get_mut(row) {
                line.update_cell_with(col, cell);
                screen.dirty_set.insert(row);

                // Add placeholder cell for wide characters
                if width > 1 && col + 1 < screen.cols as usize {
                    let placeholder = Cell {
                        width: CellWidth::Wide,
                        ..Cell::default()
                    };
                    line.update_cell_with(col + 1, placeholder);
                }
            }

            // Advance cursor by character width
            screen.cursor.col += width;

            // If cursor reached beyond the last column, set pending wrap
            if screen.cursor.col >= screen.cols as usize {
                // Clamp to last column; set pending wrap flag only if auto-wrap is on
                screen.cursor.col = (screen.cols as usize).saturating_sub(1);
                if auto_wrap {
                    screen.cursor.pending_wrap = true;
                }
            }
        } else {
            // Character doesn't fit (wide char at last column) — wrap to next line
            if auto_wrap {
                screen.cursor.col = 0;
                screen.line_feed_impl(attrs.background, is_primary);
            }

            // Print on next line if it fits
            if width <= screen.cols as usize {
                let new_row = screen.cursor.row;
                let mut cell = Cell::new(c);
                cell.attrs = attrs;
                cell.width = cell_width;

                if let Some(line) = screen.lines.get_mut(new_row) {
                    line.update_cell_with(0, cell);
                    screen.dirty_set.insert(new_row);

                    // Add placeholder cell for wide characters
                    if width > 1 && 1 < screen.cols as usize {
                        let placeholder = Cell {
                            width: CellWidth::Wide,
                            ..Cell::default()
                        };
                        line.update_cell_with(1, placeholder);
                    }
                }

                screen.cursor.col = width;

                // If the wide char exactly fills the line, set pending wrap
                if screen.cursor.col >= screen.cols as usize {
                    // Clamp to last column; set pending wrap flag only if auto-wrap is on
                    screen.cursor.col = (screen.cols as usize).saturating_sub(1);
                    if auto_wrap {
                        screen.cursor.pending_wrap = true;
                    }
                }
            }
        }
    }
}
