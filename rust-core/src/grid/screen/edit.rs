//! Line and character editing methods for Screen

use super::{Cell, CellWidth, Line, Screen, SgrAttributes};

impl Screen {
    /// Clear all lines in range
    pub fn clear_lines(&mut self, start: usize, end: usize) {
        if let Some(lines) = self.active_lines_mut() {
            let end = end.min(lines.len());
            if start < end {
                // VecDeque does not support range-slice indexing; use iter_mut.
                for line in lines.iter_mut().skip(start).take(end - start) {
                    line.clear();
                }
            }
        }
    }

    /// Insert `count` blank lines at the cursor row within the scroll region (IL — CSI Ps L)
    ///
    /// Lines from the cursor row to the scroll region bottom shift down. Lines
    /// pushed past the bottom margin are discarded. Blank lines are filled using
    /// default cell attributes. No-op when the cursor is outside the scroll region.
    #[inline]
    pub fn insert_lines(&mut self, count: usize) {
        let Some(screen) = self.active_screen_mut() else {
            return;
        };
        let cursor_row = screen.cursor.row;
        let top = screen.scroll_region.top;
        let bottom = screen.scroll_region.bottom;

        // Strict guard: no-op when cursor is outside [top, bottom)
        if cursor_row < top || cursor_row >= bottom {
            return;
        }

        // Clamp to lines available between cursor and scroll region bottom
        let count = count.min(bottom - cursor_row);

        for _ in 0..count {
            // Discard the bottom-most line in the scroll region
            screen.lines.remove(bottom - 1);
            // Insert a blank line at the cursor row (shifts existing lines down)
            screen
                .lines
                .insert(cursor_row, Line::new(screen.cols as usize));
        }

        // All rows from cursor to bottom of scroll region are now dirty
        screen.mark_dirty_range(cursor_row, bottom);
    }

    /// Delete `count` lines at the cursor row within the scroll region (DL — CSI Ps M)
    ///
    /// Lines below the deleted area scroll up within the scroll region. Blank lines
    /// fill the bottom of the scroll region. No-op when the cursor is outside the
    /// scroll region. Does NOT save lines to the scrollback buffer.
    #[inline]
    pub fn delete_lines(&mut self, count: usize) {
        let Some(screen) = self.active_screen_mut() else {
            return;
        };
        let cursor_row = screen.cursor.row;
        let top = screen.scroll_region.top;
        let bottom = screen.scroll_region.bottom;

        // Strict guard: no-op when cursor is outside [top, bottom)
        if cursor_row < top || cursor_row >= bottom {
            return;
        }

        // Clamp to lines available between cursor and scroll region bottom
        let count = count.min(bottom - cursor_row);

        for _ in 0..count {
            // Remove the line at the cursor row (shifts lines below it up)
            screen.lines.remove(cursor_row);
            // Insert a blank line at the bottom of the scroll region
            screen
                .lines
                .insert(bottom - 1, Line::new(screen.cols as usize));
        }

        // All rows from cursor to bottom of scroll region are now dirty
        screen.mark_dirty_range(cursor_row, bottom);
    }

    /// Insert `count` blank characters at the cursor column in the current line (ICH — CSI Ps @)
    ///
    /// Characters to the right of the cursor shift right. Characters pushed past
    /// the right margin are discarded. Blank cells use the current SGR background color.
    #[inline]
    pub fn insert_chars(&mut self, count: usize, attrs: SgrAttributes) {
        let Some(screen) = self.active_screen_mut() else {
            return;
        };
        let cursor_row = screen.cursor.row;
        let cursor_col = screen.cursor.col;
        let cols = screen.cols as usize;

        // Clamp to columns available from cursor to right margin
        let count = count.min(cols.saturating_sub(cursor_col));
        if count == 0 {
            return;
        }

        if let Some(line) = screen.lines.get_mut(cursor_row) {
            let mut blank = Cell::default();
            blank.attrs.background = attrs.background;

            // Wide pair safety: if cursor is on a Wide placeholder, blank its Full partner.
            // Inserting blanks at this position destroys the pair relationship.
            if cursor_col > 0 && line.cells[cursor_col].width == CellWidth::Wide {
                line.cells[cursor_col - 1] = Cell::default();
            }

            // Drain everything from cursor_col onward, keep only the non-overflowing tail
            let tail: Vec<Cell> = line.cells.drain(cursor_col..).collect();
            for _ in 0..count {
                line.cells.push(blank.clone());
            }
            let keep = tail.len().saturating_sub(count);
            line.cells.extend_from_slice(&tail[..keep]);

            line.is_dirty = true;
            screen.mark_dirty_range(cursor_row, cursor_row + 1);
        }
    }

    /// Delete `count` characters at the cursor column in the current line (DCH — CSI Ps P)
    ///
    /// Characters to the right of the deleted area shift left. Blank cells fill
    /// the right end of the line.
    #[inline]
    pub fn delete_chars(&mut self, count: usize) {
        let Some(screen) = self.active_screen_mut() else {
            return;
        };
        let cursor_row = screen.cursor.row;
        let cursor_col = screen.cursor.col;
        let cols = screen.cols as usize;

        // Clamp to columns available from cursor to right margin
        let count = count.min(cols.saturating_sub(cursor_col));
        if count == 0 {
            return;
        }

        if let Some(line) = screen.lines.get_mut(cursor_row) {
            // Wide pair safety (must be done before drain):
            // 1. If start of range is a Wide placeholder, blank its Full partner.
            if cursor_col > 0 && line.cells[cursor_col].width == CellWidth::Wide {
                line.cells[cursor_col - 1] = Cell::default();
            }
            // 2. If end of range ends on a Full cell, blank its Wide partner
            //    (the Wide placeholder would shift left and become orphaned).
            let drain_end = (cursor_col + count).min(cols);
            if drain_end < cols && line.cells[drain_end - 1].width == CellWidth::Full {
                line.cells[drain_end] = Cell::default();
            }

            line.cells.drain(cursor_col..drain_end);
            line.cells.resize(cols, Cell::default());
            line.is_dirty = true;
            screen.mark_dirty_range(cursor_row, cursor_row + 1);
        }
    }

    /// Erase `count` characters at the cursor column in the current line (ECH — CSI Ps X)
    ///
    /// Cells are replaced with blanks using the current SGR background color (BCE).
    /// The cursor position does not change. Characters beyond the right margin are ignored.
    #[inline]
    pub fn erase_chars(&mut self, count: usize, attrs: SgrAttributes) {
        let Some(screen) = self.active_screen_mut() else {
            return;
        };
        let cursor_row = screen.cursor.row;
        let cursor_col = screen.cursor.col;
        let cols = screen.cols as usize;

        let end = (cursor_col + count).min(cols);
        if cursor_col >= end {
            return;
        }

        if let Some(line) = screen.lines.get_mut(cursor_row) {
            // Wide pair safety: extend erase range to include orphaned pair halves.
            // 1. If start of range is a Wide placeholder, also erase its Full partner.
            let erase_start = if cursor_col > 0 && line.cells[cursor_col].width == CellWidth::Wide {
                cursor_col - 1
            } else {
                cursor_col
            };
            // 2. If end of range ends on a Full cell, also erase its Wide partner.
            let erase_end = if end < cols && line.cells[end - 1].width == CellWidth::Full {
                end + 1
            } else {
                end
            };

            for col in erase_start..erase_end {
                let mut blank = Cell::default();
                blank.attrs.background = attrs.background;
                line.cells[col] = blank;
            }
            line.is_dirty = true;
            screen.mark_dirty_range(cursor_row, cursor_row + 1);
        }
    }
}
