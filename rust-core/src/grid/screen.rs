//! Virtual screen buffer with dirty tracking

use super::super::types::{Cell, CellWidth, Cursor, SgrAttributes};
use super::line::Line;
use std::collections::{HashSet, VecDeque};
use unicode_width::UnicodeWidthChar;

/// Scroll region for DECSTBM
#[derive(Debug, Clone, Copy)]
pub struct ScrollRegion {
    /// Top margin (inclusive)
    pub top: usize,
    /// Bottom margin (exclusive)
    pub bottom: usize,
}

impl ScrollRegion {
    /// Create a new scroll region
    pub fn new(top: usize, bottom: usize) -> Self {
        Self { top, bottom }
    }

    /// Create default scroll region (entire screen)
    pub fn full_screen(rows: usize) -> Self {
        Self {
            top: 0,
            bottom: rows,
        }
    }
}

/// Virtual screen representing the terminal display
#[derive(Debug)]
pub struct Screen {
    /// Lines in the screen
    lines: Vec<Line>,
    /// Cursor state
    pub cursor: Cursor,
    /// Set of dirty line indices
    dirty_set: HashSet<usize>,
    /// Scroll region
    scroll_region: ScrollRegion,
    /// Number of rows
    rows: u16,
    /// Number of columns
    cols: u16,
    /// Alternate screen buffer (for DEC mode 1049)
    alternate_screen: Option<Box<Screen>>,
    /// Whether alternate screen is currently active
    is_alternate_active: bool,
    /// Saved primary cursor position when switching to alternate
    saved_primary_cursor: Option<Cursor>,
    /// Saved scroll region when switching to alternate
    saved_scroll_region: Option<ScrollRegion>,
    /// Scrollback buffer for preserving scrolled content
    pub scrollback_buffer: VecDeque<Line>,
    /// Number of lines currently in scrollback buffer
    pub scrollback_line_count: usize,
    /// Maximum scrollback buffer size (configured from Emacs)
    pub scrollback_max_lines: usize,
}

impl Screen {
    /// Create a new screen with the specified dimensions
    pub fn new(rows: u16, cols: u16) -> Self {
        let lines = (0..rows).map(|_| Line::new(cols as usize)).collect();

        Self {
            lines,
            cursor: Cursor::new(0, 0),
            dirty_set: HashSet::new(),
            scroll_region: ScrollRegion::full_screen(rows as usize),
            rows,
            cols,
            alternate_screen: None,
            is_alternate_active: false,
            saved_primary_cursor: None,
            saved_scroll_region: None,
            scrollback_buffer: VecDeque::new(),
            scrollback_line_count: 0,
            scrollback_max_lines: 10000, // Default scrollback size
        }
    }

    /// Get number of rows
    pub fn rows(&self) -> u16 {
        self.rows
    }

    /// Get number of columns
    pub fn cols(&self) -> u16 {
        self.cols
    }

    /// Get cell at position
    pub fn get_cell(&self, row: usize, col: usize) -> Option<&Cell> {
        if self.is_alternate_active {
            self.alternate_screen.as_ref().unwrap().lines.get(row)?.get_cell(col)
        } else {
            self.lines.get(row)?.get_cell(col)
        }
    }

    /// Print a character at the cursor position
    pub fn print(&mut self, c: char, attrs: SgrAttributes, auto_wrap: bool) {
        let screen = self.active_screen_mut();
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
            screen.line_feed();

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
                screen.line_feed();
            } else {
                // Clamp to last column — do NOT wrap
                screen.cursor.col = (screen.cols as usize).saturating_sub(1);
            }
        }
    }

    /// Line feed (LF, VT, FF)
    pub fn line_feed(&mut self) {
        let screen = self.active_screen_mut();
        let new_row = screen.cursor.row + 1;

        if new_row >= screen.scroll_region.bottom {
            // Scroll up within scroll region
            screen.scroll_up(1);
        } else {
            screen.cursor.row = new_row;
        }
    }

    /// Carriage return (CR)
    pub fn carriage_return(&mut self) {
        self.active_screen_mut().cursor.col = 0;
    }

    /// Backspace (BS)
    pub fn backspace(&mut self) {
        let screen = self.active_screen_mut();
        if screen.cursor.col > 0 {
            screen.cursor.col -= 1;
        }
    }

    /// Horizontal tab (HT)
    pub fn tab(&mut self) {
        let screen = self.active_screen_mut();
        let tab_stop = (screen.cursor.col / 8 + 1) * 8;
        screen.cursor.col = tab_stop.min(screen.cols as usize - 1);
    }

    /// Scroll up by n lines with scrollback preservation
    pub fn scroll_up(&mut self, n: usize) {
        let screen = self.active_screen_mut();
        let top = screen.scroll_region.top;
        let bottom = screen.scroll_region.bottom;

        for _ in 0..n {
            // Only save to scrollback if scrolling from top of primary screen (not in scroll region or alternate)
            if top == 0 && !screen.is_alternate_active {
                if let Some(line) = screen.lines.get(top).cloned() {
                    screen.scrollback_buffer.push_back(line);
                    screen.scrollback_line_count += 1;

                    // Trim scrollback if exceeding max size
                    while screen.scrollback_line_count > screen.scrollback_max_lines {
                        if screen.scrollback_buffer.pop_front().is_some() {
                            screen.scrollback_line_count -= 1;
                        }
                    }
                }
            }

            // Remove top line in scroll region
            screen.lines.remove(top);

            // Add new blank line at bottom
            let new_line = Line::new(screen.cols as usize);
            screen.lines.insert(bottom - 1, new_line);

            // Mark affected lines as dirty
            for row in top..bottom {
                screen.dirty_set.insert(row);
            }

            // Adjust cursor position if it was on the scrolled line
            if screen.cursor.row >= screen.rows as usize {
                screen.cursor.row = (screen.rows as usize).saturating_sub(1);
            }
        }
    }

    /// Scroll down by n lines
    pub fn scroll_down(&mut self, n: usize) {
        let screen = self.active_screen_mut();
        let top = screen.scroll_region.top;
        let bottom = screen.scroll_region.bottom;

        for _ in 0..n {
            // Remove bottom line in scroll region
            screen.lines.remove(bottom - 1);

            // Add new blank line at top
            let new_line = Line::new(screen.cols as usize);
            screen.lines.insert(top, new_line);

            // Mark affected lines as dirty
            for row in top..bottom {
                screen.dirty_set.insert(row);
            }
        }
    }

    /// Resize the screen
    pub fn resize(&mut self, new_rows: u16, new_cols: u16) {
        self.rows = new_rows;
        self.cols = new_cols;

        let screen = self.active_screen_mut();

        // Resize or add/remove lines
        if new_rows as usize > screen.lines.len() {
            // Add lines
            while screen.lines.len() < new_rows as usize {
                screen.lines.push(Line::new(new_cols as usize));
            }
        } else {
            // Remove lines
            screen.lines.truncate(new_rows as usize);
        }

        // Resize all lines
        for line in &mut screen.lines {
            line.resize(new_cols as usize);
        }

        // Resize scrollback buffer lines to new column count
        for line in &mut screen.scrollback_buffer {
            line.resize(new_cols as usize);
        }

        // Reset scroll region
        screen.scroll_region = ScrollRegion::full_screen(new_rows as usize);

        // Clamp cursor
        screen.cursor.row = screen.cursor.row.min(new_rows as usize - 1);
        screen.cursor.col = screen.cursor.col.min(new_cols as usize - 1);
    }

    /// Get dirty lines and clear the dirty set
    pub fn take_dirty_lines(&mut self) -> Vec<usize> {
        if self.is_alternate_active {
            let alt = self.alternate_screen.as_mut().unwrap();
            let dirty: Vec<usize> = alt.dirty_set.iter().copied().collect();
            alt.dirty_set.clear();
            dirty
        } else {
            let dirty: Vec<usize> = self.dirty_set.iter().copied().collect();
            self.dirty_set.clear();
            dirty
        }
    }

    /// Get line data at row
    pub fn get_line(&self, row: usize) -> Option<&Line> {
        if self.is_alternate_active {
            self.alternate_screen.as_ref().unwrap().lines.get(row)
        } else {
            self.lines.get(row)
        }
    }

    /// Get mutable line data at row
    pub fn get_line_mut(&mut self, row: usize) -> Option<&mut Line> {
        if self.is_alternate_active {
            self.alternate_screen.as_mut().unwrap().lines.get_mut(row)
        } else {
            self.lines.get_mut(row)
        }
    }

    /// Clear all lines in range
    pub fn clear_lines(&mut self, start: usize, end: usize) {
        if self.is_alternate_active {
            let alt = self.alternate_screen.as_mut().unwrap();
            let end = end.min(alt.lines.len());
            if start < end {
                for line in &mut alt.lines[start..end] {
                    line.clear();
                }
            }
        } else {
            let end = end.min(self.lines.len());
            if start < end {
                for line in &mut self.lines[start..end] {
                    line.clear();
                }
            }
        }
    }

    /// Move cursor to absolute position
    pub fn move_cursor(&mut self, row: usize, col: usize) {
        if self.is_alternate_active {
            let alt = self.alternate_screen.as_mut().unwrap();
            alt.cursor.row = row.min(alt.rows as usize - 1);
            alt.cursor.col = col.min(alt.cols as usize - 1);
        } else {
            self.cursor.row = row.min(self.rows as usize - 1);
            self.cursor.col = col.min(self.cols as usize - 1);
        }
    }

    /// Move cursor relative
    pub fn move_cursor_by(&mut self, row_offset: i32, col_offset: i32) {
        if self.is_alternate_active {
            let alt = self.alternate_screen.as_mut().unwrap();
            alt.cursor.move_by(col_offset, row_offset);
            alt.cursor.row = alt.cursor.row.min(alt.rows as usize - 1);
            alt.cursor.col = alt.cursor.col.min(alt.cols as usize - 1);
        } else {
            self.cursor.move_by(col_offset, row_offset);
            self.cursor.row = self.cursor.row.min(self.rows as usize - 1);
            self.cursor.col = self.cursor.col.min(self.cols as usize - 1);
        }
    }

    /// Mark a line as dirty in both the line flag and the dirty set
    pub fn mark_line_dirty(&mut self, row: usize) {
        if self.is_alternate_active {
            let alt = self.alternate_screen.as_mut().unwrap();
            alt.dirty_set.insert(row);
            if let Some(line) = alt.lines.get_mut(row) {
                line.is_dirty = true;
            }
        } else {
            self.dirty_set.insert(row);
            if let Some(line) = self.lines.get_mut(row) {
                line.is_dirty = true;
            }
        }
    }

    /// Set scroll region
    pub fn set_scroll_region(&mut self, top: usize, bottom: usize) {
        if self.is_alternate_active {
            self.alternate_screen.as_mut().unwrap().scroll_region = ScrollRegion::new(top, bottom);
        } else {
            self.scroll_region = ScrollRegion::new(top, bottom);
        }
    }

    /// Get scroll region (for testing)
    #[cfg(test)]
    pub fn get_scroll_region(&self) -> &ScrollRegion {
        if self.is_alternate_active {
            &self.alternate_screen.as_ref().unwrap().scroll_region
        } else {
            &self.scroll_region
        }
    }

    /// Set maximum scrollback buffer size
    pub fn set_scrollback_max_lines(&mut self, max_lines: usize) {
        let screen = self.active_screen_mut();
        screen.scrollback_max_lines = max_lines;

        // Trim scrollback if new max is smaller than current count
        while screen.scrollback_line_count > screen.scrollback_max_lines {
            if screen.scrollback_buffer.pop_front().is_some() {
                screen.scrollback_line_count -= 1;
            }
        }
    }

    /// Get scrollback lines (most recent first)
    pub fn get_scrollback_lines(&self, max_lines: usize) -> Vec<Line> {
        let screen = self.active_screen();
        screen
            .scrollback_buffer
            .iter()
            .rev()
            .take(max_lines)
            .cloned()
            .collect()
    }

    /// Clear the scrollback buffer
    pub fn clear_scrollback(&mut self) {
        let screen = self.active_screen_mut();
        screen.scrollback_buffer.clear();
        screen.scrollback_line_count = 0;
    }

    /// Get reference to the active screen's cursor
    pub fn cursor(&self) -> &Cursor {
        if self.is_alternate_active {
            &self.alternate_screen.as_ref().unwrap().cursor
        } else {
            &self.cursor
        }
    }

    /// Get mutable reference to the active screen's cursor
    pub fn cursor_mut(&mut self) -> &mut Cursor {
        if self.is_alternate_active {
            &mut self.alternate_screen.as_mut().unwrap().cursor
        } else {
            &mut self.cursor
        }
    }

    /// Get mutable reference to the currently active screen
    fn active_screen_mut(&mut self) -> &mut Self {
        if self.is_alternate_active {
            self.alternate_screen.as_mut().unwrap()
        } else {
            self
        }
    }

    /// Get reference to the currently active screen
    fn active_screen(&self) -> &Self {
        if self.is_alternate_active {
            self.alternate_screen.as_ref().unwrap()
        } else {
            self
        }
    }

    /// Switch to alternate screen buffer (DEC mode 1049 set)
    pub fn switch_to_alternate(&mut self) {
        if self.is_alternate_active {
            return;
        }

        // Save primary state
        self.saved_primary_cursor = Some(self.cursor);
        self.saved_scroll_region = Some(self.scroll_region);

        // Create or activate alternate screen
        if self.alternate_screen.is_none() {
            self.alternate_screen = Some(Box::new(Self::new(self.rows, self.cols)));
        }
        self.is_alternate_active = true;

        // Clear alternate screen
        let alt_screen = self.alternate_screen.as_mut().unwrap();
        alt_screen.clear_lines(0, alt_screen.rows() as usize);

        // Mark all lines dirty
        for i in 0..self.rows as usize {
            alt_screen.dirty_set.insert(i);
        }
    }

    /// Switch back to primary screen buffer (DEC mode 1049 reset)
    pub fn switch_to_primary(&mut self) {
        if !self.is_alternate_active {
            return;
        }

        self.is_alternate_active = false;

        // Mark all lines dirty
        for i in 0..self.rows as usize {
            self.dirty_set.insert(i);
        }

        // Restore saved cursor if available
        if let Some(cursor) = self.saved_primary_cursor.take() {
            self.cursor = cursor;
        }

        // Restore saved scroll region if available
        if let Some(scroll_region) = self.saved_scroll_region.take() {
            self.scroll_region = scroll_region;
        }
    }

    /// Check if alternate screen is currently active
    pub fn is_alternate_screen_active(&self) -> bool {
        self.is_alternate_active
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_screen_creation() {
        let screen = Screen::new(24, 80);
        assert_eq!(screen.rows(), 24);
        assert_eq!(screen.cols(), 80);
        assert_eq!(screen.cursor.row, 0);
        assert_eq!(screen.cursor.col, 0);
    }

    #[test]
    fn test_print_character() {
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        screen.print('A', attrs, true);

        assert_eq!(screen.get_cell(0, 0).unwrap().c, 'A');
        assert_eq!(screen.cursor.col, 1);
    }

    #[test]
    fn test_line_feed() {
        let mut screen = Screen::new(24, 80);
        screen.line_feed();

        assert_eq!(screen.cursor.row, 1);
        assert_eq!(screen.cursor.col, 0);
    }

    #[test]
    fn test_carriage_return() {
        let mut screen = Screen::new(24, 80);
        screen.cursor.col = 10;
        screen.carriage_return();

        assert_eq!(screen.cursor.col, 0);
    }

    #[test]
    fn test_backspace() {
        let mut screen = Screen::new(24, 80);
        screen.cursor.col = 5;
        screen.backspace();

        assert_eq!(screen.cursor.col, 4);
    }

    #[test]
    fn test_tab() {
        let mut screen = Screen::new(24, 80);
        screen.tab();

        assert_eq!(screen.cursor.col, 8);
    }

    #[test]
    fn test_scroll_up() {
        let mut screen = Screen::new(24, 80);

        // Mark line 0
        screen.lines[0].mark_dirty();
        assert!(screen.lines[0].is_dirty);

        screen.scroll_up(1);

        // Line 0 should have been replaced
        assert!(!screen.lines[0].is_dirty);
    }

    #[test]
    fn test_dirty_lines() {
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        screen.print('A', attrs, true);
        let dirty = screen.take_dirty_lines();

        assert_eq!(dirty.len(), 1);
        assert_eq!(dirty[0], 0);

        // Dirty set should be cleared
        let dirty2 = screen.take_dirty_lines();
        assert_eq!(dirty2.len(), 0);
    }

    #[test]
    fn test_resize() {
        let mut screen = Screen::new(24, 80);
        screen.resize(10, 40);

        assert_eq!(screen.rows(), 10);
        assert_eq!(screen.cols(), 40);
        assert_eq!(screen.lines.len(), 10);
        assert_eq!(screen.lines[0].cells.len(), 40);
    }

    #[test]
    fn test_screen_creation_with_scrollback() {
        let screen = Screen::new(24, 80);
        assert_eq!(screen.rows(), 24);
        assert_eq!(screen.cols(), 80);
        assert_eq!(screen.cursor.row, 0);
        assert_eq!(screen.cursor.col, 0);
        assert_eq!(screen.scrollback_line_count, 0);
        assert_eq!(screen.scrollback_max_lines, 10000);
    }

    #[test]
    fn test_scroll_up_saves_to_scrollback() {
        let mut screen = Screen::new(5, 80);

        // Fill screen with content
        for _ in 0..3 {
            screen.scroll_up(1);
        }

        // Scrollback should have the scrolled lines
        assert_eq!(screen.scrollback_line_count, 3);
        assert_eq!(screen.scrollback_buffer.len(), 3);
    }

    #[test]
    fn test_scrollback_trimming() {
        let mut screen = Screen::new(5, 80);
        screen.set_scrollback_max_lines(3);

        // Fill screen with content
        for _ in 0..10 {
            screen.scroll_up(1);
        }

        // Scrollback should be trimmed to max size
        assert_eq!(screen.scrollback_line_count, 3);
        assert_eq!(screen.scrollback_buffer.len(), 3);
    }

    #[test]
    fn test_get_scrollback_lines() {
        let mut screen = Screen::new(24, 80);

        // Add some lines to scrollback
        for _ in 0..5 {
            screen.scroll_up(1);
        }

        let lines = screen.get_scrollback_lines(3);
        assert_eq!(lines.len(), 3);

        // Get all scrollback
        let all_lines = screen.get_scrollback_lines(100);
        assert_eq!(all_lines.len(), 5);
    }

    #[test]
    fn test_clear_scrollback() {
        let mut screen = Screen::new(24, 80);

        // Add some lines to scrollback
        for _ in 0..5 {
            screen.scroll_up(1);
        }

        assert_eq!(screen.scrollback_line_count, 5);

        screen.clear_scrollback();

        assert_eq!(screen.scrollback_line_count, 0);
        assert!(screen.scrollback_buffer.is_empty());
    }

    #[test]
    fn test_scrollback_not_saved_in_alternate_screen() {
        let mut screen = Screen::new(5, 80);

        // Switch to alternate screen
        screen.switch_to_alternate();
        assert!(screen.is_alternate_screen_active());

        // Scroll in alternate screen
        for _ in 0..3 {
            screen.scroll_up(1);
        }

        // Scrollback should still be empty (scrolling in alternate doesn't save to primary scrollback)
        assert_eq!(screen.scrollback_line_count, 0);

        // Switch back to primary
        screen.switch_to_primary();
        assert!(!screen.is_alternate_screen_active());

        // Scroll in primary screen
        screen.scroll_up(1);

        // Now scrollback should have one line
        assert_eq!(screen.scrollback_line_count, 1);
    }

    #[test]
    fn test_resize_updates_scrollback_lines() {
        let mut screen = Screen::new(5, 80);

        // Add some lines to scrollback
        for _ in 0..3 {
            screen.scroll_up(1);
        }

        // Resize screen
        screen.resize(10, 40);

        // Scrollback lines should be resized to new column count
        assert_eq!(screen.scrollback_buffer.len(), 3);
        assert_eq!(screen.scrollback_buffer[0].cells.len(), 40);
    }

    #[test]
    fn test_alt_screen_cursor_routing() {
        let mut screen = Screen::new(24, 80);

        // Move cursor on primary screen
        screen.move_cursor(5, 10);
        assert_eq!(screen.cursor().row, 5);
        assert_eq!(screen.cursor().col, 10);

        // Activate alternate screen
        screen.switch_to_alternate();

        // Alt screen cursor starts at (0, 0)
        assert_eq!(screen.cursor().row, 0);
        assert_eq!(screen.cursor().col, 0);

        // Move cursor on alt screen — should NOT affect primary
        screen.move_cursor(3, 7);
        assert_eq!(screen.cursor().row, 3);
        assert_eq!(screen.cursor().col, 7);

        // Switch back to primary — primary cursor still at (5, 10)
        screen.switch_to_primary();
        assert_eq!(screen.cursor().row, 5);
        assert_eq!(screen.cursor().col, 10);
    }

    #[test]
    fn test_alt_screen_dirty_lines_routing() {
        let mut screen = Screen::new(24, 80);

        // Mark line dirty on primary
        screen.mark_line_dirty(2);

        // Switch to alternate — take_dirty_lines drains the alt screen's set
        screen.switch_to_alternate();

        // switch_to_alternate marks all lines dirty; drain them so we start clean
        let _ = screen.take_dirty_lines();

        // Mark a specific line dirty on alt screen
        screen.mark_line_dirty(5);

        // take_dirty_lines should return alt screen's dirty lines (just [5])
        let alt_dirty = screen.take_dirty_lines();
        assert_eq!(alt_dirty, vec![5]);

        // Switch back to primary — switch_to_primary marks all lines dirty; drain them
        screen.switch_to_primary();
        let _ = screen.take_dirty_lines();

        // The primary dirty set had line 2 marked before the switch;
        // switch_to_primary re-marks all lines dirty so line 2 is included.
        // Verify line 2 is still present in the primary dirty set.
        // Re-mark just line 2 to test isolation independently of switch overhead.
        screen.mark_line_dirty(2);
        let primary_dirty = screen.take_dirty_lines();
        assert!(primary_dirty.contains(&2));
    }
}
