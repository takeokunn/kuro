//! Cursor movement and character printing methods for Screen

use super::*;

impl Screen {
    /// Get reference to the active screen's cursor
    #[inline(always)]
    pub fn cursor(&self) -> &Cursor {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_ref() {
                return &alt.cursor;
            }
        }
        &self.cursor
    }

    /// Get mutable reference to the active screen's cursor
    #[inline(always)]
    pub fn cursor_mut(&mut self) -> &mut Cursor {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                return &mut alt.cursor;
            }
        }
        &mut self.cursor
    }

    /// Move cursor to absolute position
    #[inline]
    pub fn move_cursor(&mut self, row: usize, col: usize) {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                alt.cursor.row = row.min(alt.rows as usize - 1);
                alt.cursor.col = col.min(alt.cols as usize - 1);
            }
        } else {
            self.cursor.row = row.min(self.rows as usize - 1);
            self.cursor.col = col.min(self.cols as usize - 1);
        }
    }

    /// Move cursor relative
    #[inline]
    pub fn move_cursor_by(&mut self, row_offset: i32, col_offset: i32) {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                alt.cursor.move_by(col_offset, row_offset);
                alt.cursor.row = alt.cursor.row.min(alt.rows as usize - 1);
                alt.cursor.col = alt.cursor.col.min(alt.cols as usize - 1);
            }
        } else {
            self.cursor.move_by(col_offset, row_offset);
            self.cursor.row = self.cursor.row.min(self.rows as usize - 1);
            self.cursor.col = self.cursor.col.min(self.cols as usize - 1);
        }
    }

    /// Carriage return (CR)
    #[inline(always)]
    pub fn carriage_return(&mut self) {
        if let Some(screen) = self.active_screen_mut() {
            screen.cursor.col = 0;
        }
    }

    /// Backspace (BS)
    #[inline(always)]
    pub fn backspace(&mut self) {
        if let Some(screen) = self.active_screen_mut() {
            if screen.cursor.col > 0 {
                screen.cursor.col -= 1;
            }
        }
    }

    /// Horizontal tab (HT)
    #[inline(always)]
    pub fn tab(&mut self) {
        if let Some(screen) = self.active_screen_mut() {
            let tab_stop = (screen.cursor.col / 8 + 1) * 8;
            screen.cursor.col = tab_stop.min(screen.cols as usize - 1);
        }
    }

    /// Line feed (LF): advances cursor down one row, scrolling up if at the bottom of the scroll region.
    #[inline]
    pub fn line_feed(&mut self, bg: Color) {
        if let Some(screen) = self.active_screen_mut() {
            let new_row = screen.cursor.row + 1;

            if new_row >= screen.scroll_region.bottom {
                // Scroll up within scroll region, applying BCE to the new blank line.
                screen.scroll_up(1, bg);
            } else {
                screen.cursor.row = new_row;
            }
        }
    }

    /// Print a character at the cursor position
    pub fn print(&mut self, c: char, attrs: SgrAttributes, auto_wrap: bool) {
        let screen = match self.active_screen_mut() {
            Some(s) => s,
            None => return,
        };
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
        } else {
            // Character doesn't fit - wrap to next line
            screen.cursor.col = 0;
            screen.line_feed(attrs.background);

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
            }
        }

        // Handle wrap to next line if cursor reached end
        if screen.cursor.col >= screen.cols as usize {
            if auto_wrap {
                screen.cursor.col = 0;
                screen.line_feed(attrs.background);
            } else {
                // Clamp to last column — do NOT wrap
                screen.cursor.col = (screen.cols as usize).saturating_sub(1);
            }
        }
    }
}
