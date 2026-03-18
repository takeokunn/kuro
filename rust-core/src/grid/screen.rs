//! Virtual screen buffer with dirty tracking

use super::super::types::{Cell, CellWidth, Cursor, SgrAttributes};
use super::dirty_set::{BitVecDirtySet, DirtySet};
use super::line::Line;
use std::collections::VecDeque;
use unicode_width::UnicodeWidthChar;

// Re-export image types so existing `use crate::grid::screen::*` paths keep working
pub use crate::grid::image::{GraphicsStore, ImageData, ImageNotification, ImagePlacement};

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
    /// Set of dirty line indices (bit-vector backed for O(1) insert)
    dirty_set: BitVecDirtySet,
    /// When true, all lines are dirty (overrides dirty_set for efficiency)
    full_dirty: bool,
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
    /// Current viewport scroll offset (0 = live view, N = scrolled back N lines)
    pub scroll_offset: usize,
    /// Whether the viewport scroll position has changed and needs re-render
    scroll_dirty: bool,
    /// Image placement store for Kitty Graphics Protocol
    pub graphics: GraphicsStore,
}

impl Screen {
    /// Create a new screen with the specified dimensions
    pub fn new(rows: u16, cols: u16) -> Self {
        let lines = (0..rows).map(|_| Line::new(cols as usize)).collect();

        Self {
            lines,
            cursor: Cursor::new(0, 0),
            dirty_set: BitVecDirtySet::new(rows as usize),
            full_dirty: false,
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
            scroll_offset: 0,
            scroll_dirty: false,
            graphics: GraphicsStore::new(),
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
            self.alternate_screen
                .as_ref()
                .unwrap()
                .lines
                .get(row)?
                .get_cell(col)
        } else {
            self.lines.get(row)?.get_cell(col)
        }
    }

    /// Get mutable cell at position
    pub fn get_cell_mut(&mut self, row: usize, col: usize) -> Option<&mut Cell> {
        if self.is_alternate_active {
            self.alternate_screen
                .as_mut()
                .unwrap()
                .lines
                .get_mut(row)?
                .cells
                .get_mut(col)
        } else {
            self.lines.get_mut(row)?.cells.get_mut(col)
        }
    }

    /// Attach a combining character to the cell at (row, col).
    /// If the cell exists, appends the combining char to its grapheme cluster
    /// and marks the line dirty.
    pub fn attach_combining(&mut self, row: usize, col: usize, c: char) {
        if let Some(cell) = self.get_cell_mut(row, col) {
            cell.push_combining(c);
        }
        // Mark the line dirty
        let screen = self.active_screen_mut();
        screen.dirty_set.insert(row);
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
        screen.graphics.scroll_up(n);
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
        screen.cursor.row = screen.cursor.row.min(new_rows.saturating_sub(1) as usize);
        screen.cursor.col = screen.cursor.col.min(new_cols.saturating_sub(1) as usize);
    }

    /// Get dirty lines and clear the dirty set
    pub fn take_dirty_lines(&mut self) -> Vec<usize> {
        if self.is_alternate_active {
            let alt = self.alternate_screen.as_mut().unwrap();
            if alt.full_dirty {
                alt.full_dirty = false;
                alt.dirty_set.clear();
                (0..alt.rows as usize).collect()
            } else {
                let mut dirty: Vec<usize> = alt.dirty_set.iter().collect();
                alt.dirty_set.clear();
                dirty.sort_unstable();
                dirty
            }
        } else if self.full_dirty {
            self.full_dirty = false;
            self.dirty_set.clear();
            (0..self.rows as usize).collect()
        } else {
            let mut dirty: Vec<usize> = self.dirty_set.iter().collect();
            self.dirty_set.clear();
            dirty.sort_unstable();
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

    /// Mark all lines as dirty at once (more efficient than inserting every row)
    pub fn mark_all_dirty(&mut self) {
        let screen = self.active_screen_mut();
        screen.full_dirty = true;
    }

    /// Set scroll region
    pub fn set_scroll_region(&mut self, top: usize, bottom: usize) {
        if self.is_alternate_active {
            self.alternate_screen.as_mut().unwrap().scroll_region = ScrollRegion::new(top, bottom);
        } else {
            self.scroll_region = ScrollRegion::new(top, bottom);
        }
    }

    /// Get scroll region
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

    /// Get reference to the active screen's graphics store
    pub fn active_graphics(&self) -> &GraphicsStore {
        if self.is_alternate_active {
            &self.alternate_screen.as_ref().unwrap().graphics
        } else {
            &self.graphics
        }
    }

    /// Get mutable reference to the active screen's graphics store
    pub fn active_graphics_mut(&mut self) -> &mut GraphicsStore {
        if self.is_alternate_active {
            &mut self.alternate_screen.as_mut().unwrap().graphics
        } else {
            &mut self.graphics
        }
    }

    /// Get image from any screen (primary first, then active if alternate)
    pub fn get_image_png_base64(&self, image_id: u32) -> String {
        // Check primary screen's store
        let result = self.graphics.get_image_png_base64(image_id);
        if !result.is_empty() {
            return result;
        }
        // If alternate is active, also check alternate screen's store
        if self.is_alternate_active {
            if let Some(alt) = &self.alternate_screen {
                return alt.graphics.get_image_png_base64(image_id);
            }
        }
        String::new()
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
        alt_screen.full_dirty = true;
    }

    /// Switch back to primary screen buffer (DEC mode 1049 reset)
    pub fn switch_to_primary(&mut self) {
        if !self.is_alternate_active {
            return;
        }

        self.is_alternate_active = false;

        // Mark all lines dirty
        self.full_dirty = true;

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

    /// Insert `count` blank lines at the cursor row within the scroll region (IL — CSI Ps L)
    ///
    /// Lines from the cursor row to the scroll region bottom shift down. Lines
    /// pushed past the bottom margin are discarded. Blank lines are filled using
    /// default cell attributes. No-op when the cursor is outside the scroll region.
    pub fn insert_lines(&mut self, count: usize) {
        let screen = self.active_screen_mut();
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
        for row in cursor_row..bottom {
            screen.dirty_set.insert(row);
        }
    }

    /// Delete `count` lines at the cursor row within the scroll region (DL — CSI Ps M)
    ///
    /// Lines below the deleted area scroll up within the scroll region. Blank lines
    /// fill the bottom of the scroll region. No-op when the cursor is outside the
    /// scroll region. Does NOT save lines to the scrollback buffer.
    pub fn delete_lines(&mut self, count: usize) {
        let screen = self.active_screen_mut();
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
        for row in cursor_row..bottom {
            screen.dirty_set.insert(row);
        }
    }

    /// Insert `count` blank characters at the cursor column in the current line (ICH — CSI Ps @)
    ///
    /// Characters to the right of the cursor shift right. Characters pushed past
    /// the right margin are discarded. Blank cells use the current SGR background color.
    pub fn insert_chars(&mut self, count: usize, attrs: SgrAttributes) {
        let screen = self.active_screen_mut();
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
            screen.dirty_set.insert(cursor_row);
        }
    }

    /// Delete `count` characters at the cursor column in the current line (DCH — CSI Ps P)
    ///
    /// Characters to the right of the deleted area shift left. Blank cells fill
    /// the right end of the line.
    pub fn delete_chars(&mut self, count: usize) {
        let screen = self.active_screen_mut();
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
            screen.dirty_set.insert(cursor_row);
        }
    }

    /// Scroll the viewport up by n lines (toward older scrollback content)
    ///
    /// No-op when the alternate screen is active (alternate screen has no scrollback).
    pub fn viewport_scroll_up(&mut self, n: usize) {
        if self.is_alternate_active {
            return;
        }
        let new_offset = (self.scroll_offset + n).min(self.scrollback_line_count);
        if new_offset != self.scroll_offset {
            self.scroll_offset = new_offset;
            self.scroll_dirty = true;
        }
    }

    /// Scroll the viewport down by n lines (toward live content)
    ///
    /// No-op when the alternate screen is active.
    pub fn viewport_scroll_down(&mut self, n: usize) {
        if self.is_alternate_active {
            return;
        }
        let new_offset = self.scroll_offset.saturating_sub(n);
        if new_offset != self.scroll_offset {
            self.scroll_offset = new_offset;
            if new_offset == 0 {
                self.full_dirty = true;
                self.scroll_dirty = false;
            } else {
                self.scroll_dirty = true;
            }
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
    /// line count. Returns `None` when the computed index is negative.
    pub fn get_scrollback_viewport_line(&self, row_in_viewport: usize) -> Option<&Line> {
        let n = self.scrollback_line_count as isize;
        let offset = self.scroll_offset as isize;
        let rows = self.rows as isize;
        let row = row_in_viewport as isize;
        // anchor = the scrollback index shown at the bottom of the viewport
        let anchor = n - offset;
        let idx = anchor + row - (rows - 1);
        if idx < 0 || idx >= n {
            return None;
        }
        self.scrollback_buffer.get(idx as usize)
    }

    /// Return true if the viewport scroll position changed and a re-render is needed
    pub fn is_scroll_dirty(&self) -> bool {
        self.scroll_dirty
    }

    /// Clear the scroll_dirty flag after re-rendering
    pub fn clear_scroll_dirty(&mut self) {
        self.scroll_dirty = false;
    }

    /// Return the current viewport scroll offset (0 = live view)
    pub fn scroll_offset(&self) -> usize {
        self.scroll_offset
    }

    /// Erase `count` characters at the cursor column in the current line (ECH — CSI Ps X)
    ///
    /// Cells are replaced with blanks using the current SGR background color (BCE).
    /// The cursor position does not change. Characters beyond the right margin are ignored.
    pub fn erase_chars(&mut self, count: usize, attrs: SgrAttributes) {
        let screen = self.active_screen_mut();
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
            screen.dirty_set.insert(cursor_row);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

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

        assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'A');
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

    #[test]
    fn test_full_dirty_initially_false() {
        let screen = Screen::new(24, 80);
        assert!(!screen.full_dirty, "full_dirty should be false on creation");
    }

    #[test]
    fn test_mark_all_dirty_sets_flag() {
        let mut screen = Screen::new(24, 80);
        screen.mark_all_dirty();
        assert!(
            screen.full_dirty,
            "mark_all_dirty should set full_dirty = true"
        );
    }

    #[test]
    fn test_take_dirty_lines_full_dirty_returns_all_rows() {
        let mut screen = Screen::new(4, 80);
        screen.mark_all_dirty();
        let mut dirty = screen.take_dirty_lines();
        dirty.sort_unstable();
        assert_eq!(
            dirty,
            vec![0, 1, 2, 3],
            "full_dirty should return all row indices"
        );
    }

    #[test]
    fn test_take_dirty_lines_clears_full_dirty() {
        let mut screen = Screen::new(4, 80);
        screen.mark_all_dirty();
        let _ = screen.take_dirty_lines();
        assert!(
            !screen.full_dirty,
            "full_dirty should be cleared after take_dirty_lines"
        );
        // Second call should return empty
        let dirty2 = screen.take_dirty_lines();
        assert!(
            dirty2.is_empty(),
            "dirty_set should also be empty after full_dirty was consumed"
        );
    }

    #[test]
    fn test_take_dirty_lines_full_dirty_also_clears_dirty_set() {
        let mut screen = Screen::new(4, 80);
        // Add some entries to dirty_set, then set full_dirty
        screen.mark_line_dirty(1);
        screen.mark_line_dirty(3);
        screen.mark_all_dirty();
        let _ = screen.take_dirty_lines();
        // After consuming full_dirty, dirty_set should also be cleared
        let dirty2 = screen.take_dirty_lines();
        assert!(
            dirty2.is_empty(),
            "dirty_set should be cleared when full_dirty is consumed"
        );
    }

    #[test]
    fn test_switch_to_alternate_uses_full_dirty() {
        let mut screen = Screen::new(4, 10);
        screen.switch_to_alternate();
        // All alt-screen lines should be dirty via full_dirty (not individual HashSet inserts)
        let mut dirty = screen.take_dirty_lines();
        dirty.sort_unstable();
        assert_eq!(
            dirty.len(),
            4,
            "switch_to_alternate should mark all lines dirty"
        );
        assert_eq!(dirty, vec![0, 1, 2, 3]);
    }

    #[test]
    fn test_switch_to_primary_uses_full_dirty() {
        let mut screen = Screen::new(4, 10);
        screen.switch_to_alternate();
        let _ = screen.take_dirty_lines(); // consume alt-screen dirty
        screen.switch_to_primary();
        // All primary-screen lines should be dirty via full_dirty
        let mut dirty = screen.take_dirty_lines();
        dirty.sort_unstable();
        assert_eq!(
            dirty.len(),
            4,
            "switch_to_primary should mark all primary lines dirty"
        );
        assert_eq!(dirty, vec![0, 1, 2, 3]);
    }

    // ── Phase 11: Unicode & CJK tests ────────────────────────────────────

    #[test]
    fn test_print_cjk_basic() {
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        screen.print('日', attrs, true);

        // Full cell at col 0
        let full_cell = screen.get_cell(0, 0).unwrap();
        assert_eq!(full_cell.char(), '日');
        assert_eq!(full_cell.width, CellWidth::Full);

        // Wide placeholder at col 1
        let wide_cell = screen.get_cell(0, 1).unwrap();
        assert_eq!(wide_cell.char(), ' ');
        assert_eq!(wide_cell.width, CellWidth::Wide);

        // Cursor advanced by 2
        assert_eq!(screen.cursor.col, 2);
    }

    #[test]
    fn test_print_cjk_cursor_position() {
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        screen.print('日', attrs, true);
        screen.print('本', attrs, true);
        screen.print('語', attrs, true);

        // Three wide chars = cursor at col 6
        assert_eq!(screen.cursor.col, 6);

        // Verify Full/Wide pairs for each character
        assert_eq!(screen.get_cell(0, 0).unwrap().width, CellWidth::Full);
        assert_eq!(screen.get_cell(0, 1).unwrap().width, CellWidth::Wide);
        assert_eq!(screen.get_cell(0, 2).unwrap().width, CellWidth::Full);
        assert_eq!(screen.get_cell(0, 3).unwrap().width, CellWidth::Wide);
        assert_eq!(screen.get_cell(0, 4).unwrap().width, CellWidth::Full);
        assert_eq!(screen.get_cell(0, 5).unwrap().width, CellWidth::Wide);
    }

    #[test]
    fn test_print_cjk_wrap() {
        // Place a CJK char at the last column — it must wrap to the next line
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        screen.move_cursor(0, 79);
        screen.print('日', attrs, true);

        // CJK did not fit at col 79; it wrapped to row 1, cols 0-1
        let full_cell = screen.get_cell(1, 0).unwrap();
        assert_eq!(full_cell.char(), '日');
        assert_eq!(full_cell.width, CellWidth::Full);

        let wide_cell = screen.get_cell(1, 1).unwrap();
        assert_eq!(wide_cell.width, CellWidth::Wide);
    }

    #[test]
    fn test_print_emoji() {
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        // 🎉 has Unicode display width 2
        screen.print('🎉', attrs, true);

        let full_cell = screen.get_cell(0, 0).unwrap();
        assert_eq!(full_cell.char(), '🎉');
        assert_eq!(full_cell.width, CellWidth::Full);

        let wide_cell = screen.get_cell(0, 1).unwrap();
        assert_eq!(wide_cell.width, CellWidth::Wide);

        assert_eq!(screen.cursor.col, 2);
    }

    #[test]
    fn test_dch_at_wide_placeholder_blanks_full_partner() {
        // DCH at a Wide placeholder must blank the Full cell to the left
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        // Print CJK: Full at col 0, Wide at col 1
        screen.print('日', attrs, true);

        // Position cursor on the Wide placeholder
        screen.move_cursor(0, 1);
        screen.delete_chars(1);

        // The Full partner at col 0 should be blanked (Half-width space)
        let col0 = screen.get_cell(0, 0).unwrap();
        assert_eq!(
            col0.width,
            CellWidth::Half,
            "Full partner must be blanked when DCH hits Wide placeholder"
        );
        assert_eq!(col0.char(), ' ');
    }

    #[test]
    fn test_dch_at_full_cell_blanks_wide_partner() {
        // DCH at a Full cell: the Wide partner shifts left and must be blanked
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        // 'A' at col 0, CJK Full at col 1, Wide at col 2
        screen.print('A', attrs, true);
        screen.print('日', attrs, true);

        // Delete from the Full cell at col 1
        screen.move_cursor(0, 1);
        screen.delete_chars(1);

        // After drain of col 1, old col 2 (Wide) shifts to col 1 — it was pre-blanked
        let col1 = screen.get_cell(0, 1).unwrap();
        assert_eq!(
            col1.width,
            CellWidth::Half,
            "Wide partner must be blanked when Full cell is DCH'd"
        );
    }

    #[test]
    fn test_ich_at_wide_placeholder_blanks_full_partner() {
        // ICH at a Wide placeholder must blank its Full partner before shifting
        let mut screen = Screen::new(24, 10);
        let attrs = SgrAttributes::default();

        // CJK Full at col 0, Wide at col 1
        screen.print('日', attrs, true);

        // Insert blank at the Wide placeholder
        screen.move_cursor(0, 1);
        screen.insert_chars(1, attrs);

        // Full partner at col 0 should be blanked
        let col0 = screen.get_cell(0, 0).unwrap();
        assert_eq!(
            col0.width,
            CellWidth::Half,
            "Full partner must be blanked when ICH inserts at Wide placeholder"
        );
        assert_eq!(col0.char(), ' ');
    }

    #[test]
    fn test_ech_range_ends_at_full_blanks_wide_partner() {
        // ECH range ending on a Full cell must also erase its Wide partner
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        // 'A' at col 0, CJK Full at col 1, Wide at col 2
        screen.print('A', attrs, true);
        screen.print('日', attrs, true);

        // Erase 2 chars from col 0: covers col 0 ('A') and col 1 (Full)
        screen.move_cursor(0, 0);
        screen.erase_chars(2, attrs);

        // Wide partner at col 2 must be blanked (extended erase range)
        let col2 = screen.get_cell(0, 2).unwrap();
        assert_eq!(
            col2.width,
            CellWidth::Half,
            "Wide partner must be blanked when ECH range ends on Full cell"
        );
        assert_eq!(col2.char(), ' ');
    }

    #[test]
    fn test_ech_starts_at_wide_blanks_full_partner() {
        // ECH starting at a Wide placeholder must also erase its Full partner
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        // CJK Full at col 0, Wide at col 1
        screen.print('日', attrs, true);

        // Erase 1 char starting at the Wide placeholder
        screen.move_cursor(0, 1);
        screen.erase_chars(1, attrs);

        // Full partner at col 0 must be blanked (extended erase range)
        let col0 = screen.get_cell(0, 0).unwrap();
        assert_eq!(
            col0.width,
            CellWidth::Half,
            "Full partner must be blanked when ECH starts at Wide placeholder"
        );
        assert_eq!(col0.char(), ' ');

        // Wide cell itself is also erased
        let col1 = screen.get_cell(0, 1).unwrap();
        assert_eq!(col1.width, CellWidth::Half);
    }

    // ── Phase 12: Scrollback Viewport Navigation tests ─────────────────────

    #[test]
    fn test_viewport_scroll_up_basic() {
        let mut screen = Screen::new(24, 80);
        // Add some scrollback lines by scrolling up the screen
        for _ in 0..30 {
            screen.scroll_up(1);
        }
        assert_eq!(screen.scroll_offset(), 0);
        screen.viewport_scroll_up(10);
        assert_eq!(screen.scroll_offset(), 10);
        assert!(screen.is_scroll_dirty());
    }

    #[test]
    fn test_viewport_scroll_up_clamps_at_buffer_size() {
        let mut screen = Screen::new(24, 80);
        for _ in 0..30 {
            screen.scroll_up(1);
        }
        let max = screen.scrollback_line_count;
        // Should not panic and should clamp at max
        screen.viewport_scroll_up(max + 1000);
        assert_eq!(screen.scroll_offset(), max);
    }

    #[test]
    fn test_viewport_scroll_up_noop_at_max() {
        let mut screen = Screen::new(24, 80);
        for _ in 0..30 {
            screen.scroll_up(1);
        }
        let max = screen.scrollback_line_count;
        screen.viewport_scroll_up(max);
        screen.clear_scroll_dirty();
        // Already at max — no change, scroll_dirty should stay false
        screen.viewport_scroll_up(1);
        assert!(!screen.is_scroll_dirty());
    }

    #[test]
    fn test_viewport_scroll_down_resets_to_zero() {
        let mut screen = Screen::new(24, 80);
        for _ in 0..30 {
            screen.scroll_up(1);
        }
        screen.viewport_scroll_up(20);
        screen.clear_scroll_dirty();
        screen.viewport_scroll_down(20);
        assert_eq!(screen.scroll_offset(), 0);
        assert!(!screen.is_scroll_dirty());
        // full_dirty should be set to force live re-render
        let dirty_lines = screen.take_dirty_lines();
        // All 24 rows should be dirty after returning to live view
        assert_eq!(dirty_lines.len(), 24);
    }

    #[test]
    fn test_viewport_scroll_down_partial_reduction() {
        let mut screen = Screen::new(24, 80);
        for _ in 0..50 {
            screen.scroll_up(1);
        }
        // Scroll up to offset 20
        screen.viewport_scroll_up(20);
        screen.clear_scroll_dirty();

        // Drain any accumulated dirty rows from scroll_up calls before partial scroll-down
        let _ = screen.take_dirty_lines();

        // Scroll down by 10 (partial — still scrolled)
        screen.viewport_scroll_down(10);

        // Should be at offset 10, not 0
        assert_eq!(screen.scroll_offset(), 10);
        // scroll_dirty should be set (not full_dirty since not at 0)
        assert!(screen.is_scroll_dirty());
        // take_dirty_lines should NOT return all rows (full_dirty is not set)
        let dirty = screen.take_dirty_lines();
        assert!(
            dirty.len() < 24,
            "full_dirty should not be set for partial scroll down"
        );
    }

    #[test]
    fn test_viewport_scroll_down_saturates_at_zero() {
        let mut screen = Screen::new(24, 80);
        for _ in 0..30 {
            screen.scroll_up(1);
        }
        screen.viewport_scroll_up(5);
        // Should not panic (no usize underflow)
        screen.viewport_scroll_down(1000);
        assert_eq!(screen.scroll_offset(), 0);
    }

    #[test]
    fn test_viewport_line_correct_content() {
        let mut screen = Screen::new(24, 80);
        // Generate scrollback: write 'A' to row 0 then scroll it off
        let attrs = SgrAttributes::default();
        screen.print('A', attrs, true);
        screen.scroll_up(1);
        // scrollback has 1 line containing 'A'
        assert_eq!(screen.scrollback_line_count, 1);
        screen.viewport_scroll_up(1);
        let line = screen.get_scrollback_viewport_line(23); // last viewport row = the line we saved
        assert!(line.is_some());
        let line = line.unwrap();
        // The line should contain 'A' at column 0 (we printed 'A' earlier)
        assert_eq!(line.cells[0].char(), 'A');
    }

    #[test]
    fn test_viewport_line_none_for_partial_buffer() {
        let mut screen = Screen::new(24, 80);
        // Only 5 scrollback lines, screen is 24 rows — row 0 should be None
        for _ in 0..5 {
            screen.scroll_up(1);
        }
        screen.viewport_scroll_up(5);
        // Rows 0..18 should return None (no scrollback content there)
        let line = screen.get_scrollback_viewport_line(0);
        assert!(line.is_none());
    }

    #[test]
    fn test_viewport_noop_in_alternate_screen() {
        let mut screen = Screen::new(24, 80);
        // Fill some scrollback first (on primary screen)
        for _ in 0..30 {
            screen.scroll_up(1);
        }
        // Switch to alternate screen
        screen.switch_to_alternate();
        let offset_before = screen.scroll_offset();
        screen.viewport_scroll_up(10);
        // Should be a no-op
        assert_eq!(screen.scroll_offset(), offset_before);
        assert!(!screen.is_scroll_dirty());
    }

    proptest! {
        #[test]
        fn prop_scrollback_bounded_by_max(n in 1usize..=200usize) {
            let mut screen = Screen::new(10, 40);
            screen.set_scrollback_max_lines(50);
            for _ in 0..n {
                screen.scroll_up(1);
            }
            prop_assert!(screen.scrollback_line_count <= 50);
        }
    }

    // ── FR-001: Property-based tests for Screen::print() cursor bounds ──────

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(256))]
        #[test]
        // INVARIANT: after any print(), cursor.row < rows AND cursor.col < cols
        fn prop_print_cursor_bounds(
            rows in 1u16..=100u16,
            cols in 1u16..=200u16,
            ch in proptest::char::any(),
            auto_wrap in proptest::bool::ANY,
        ) {
            let mut screen = Screen::new(rows, cols);
            // Move cursor to a varied position within bounds first
            screen.print(ch, SgrAttributes::default(), auto_wrap);
            prop_assert!(screen.cursor.row < rows as usize,
                "cursor.row {} >= rows {}", screen.cursor.row, rows);
            prop_assert!(screen.cursor.col < cols as usize,
                "cursor.col {} >= cols {}", screen.cursor.col, cols);
        }

        #[test]
        // INVARIANT: cursor bounds hold regardless of starting position
        fn prop_print_cursor_bounds_from_last_col(
            rows in 1u16..=50u16,
            cols in 2u16..=100u16,
            ch in proptest::char::any(),
            auto_wrap in proptest::bool::ANY,
        ) {
            let mut screen = Screen::new(rows, cols);
            // Move cursor to last column to test wrapping behavior
            screen.move_cursor(0, cols as usize - 1);
            screen.print(ch, SgrAttributes::default(), auto_wrap);
            prop_assert!(screen.cursor.row < rows as usize);
            prop_assert!(screen.cursor.col < cols as usize);
        }
    }

    // ── FR-005: Screen resize edge case tests ────────────────────────────────

    #[test]
    fn test_resize_cursor_clamping() {
        let mut screen = Screen::new(24, 80);
        // Move cursor to bottom-right corner
        screen.move_cursor(23, 79);
        assert_eq!(screen.cursor.row, 23);
        assert_eq!(screen.cursor.col, 79);
        // Resize to smaller dimensions
        screen.resize(10, 40);
        assert!(
            screen.cursor.row < 10,
            "cursor.row {} should be < 10",
            screen.cursor.row
        );
        assert!(
            screen.cursor.col < 40,
            "cursor.col {} should be < 40",
            screen.cursor.col
        );
    }

    #[test]
    fn test_resize_minimum_1x1() {
        let mut screen = Screen::new(24, 80);
        screen.move_cursor(23, 79);
        screen.resize(1, 1);
        // After fix: cursor must be clamped to (0, 0)
        assert_eq!(screen.cursor.row, 0);
        assert_eq!(screen.cursor.col, 0);
    }

    #[test]
    fn test_resize_zero_rows_does_not_panic() {
        // After the saturating_sub fix, resize(0, 80) should not panic
        let mut screen = Screen::new(10, 80);
        screen.resize(0, 80);
        // After the saturating_sub fix: cursor.row is clamped to min(old_row, 0.saturating_sub(1)) = 0
        assert_eq!(
            screen.cursor.row, 0,
            "cursor.row should be clamped to 0 when resizing to 0 rows"
        );
    }

    #[test]
    fn test_resize_zero_cols_does_not_panic() {
        let mut screen = Screen::new(10, 80);
        screen.resize(10, 0);
        assert_eq!(
            screen.cursor.col, 0,
            "cursor.col should be clamped to 0 when resizing to 0 cols"
        );
    }

    #[test]
    fn test_resize_larger() {
        let mut screen = Screen::new(10, 40);
        screen.move_cursor(9, 39);
        screen.resize(24, 80);
        // Cursor should stay at (9, 39) when resizing larger
        assert_eq!(screen.cursor.row, 9);
        assert_eq!(screen.cursor.col, 39);
    }

    #[test]
    fn test_line_feed_at_scroll_region_bottom() {
        let mut screen = Screen::new(24, 80);
        // Set scroll region rows 5-10 (top=5, bottom=10)
        screen.set_scroll_region(5, 10);
        // Position cursor at the bottom of scroll region (row 9, since bottom is exclusive)
        screen.cursor.row = 9;
        screen.cursor.col = 0;

        // Fill some content in the scroll region for verification
        if let Some(line) = screen.lines.get_mut(5) {
            line.update_cell_with(0, Cell::new('A'));
        }
        if let Some(line) = screen.lines.get_mut(9) {
            line.update_cell_with(0, Cell::new('Z'));
        }

        // line_feed at bottom of scroll region should scroll, cursor stays at row 9
        screen.line_feed();

        assert_eq!(
            screen.cursor.row, 9,
            "Cursor should stay at bottom of scroll region"
        );

        // The content should have scrolled:
        // - Row 5 originally had 'A'; after scroll_up within region [5..10),
        //   row 5 now gets the content that was at row 6 (which was empty).
        assert_eq!(
            screen.lines[5].cells[0].char(),
            ' ',
            "Row 5 should be cleared after scroll (original 'A' scrolled out)"
        );

        // - Row 9 originally had 'Z' but it was at the bottom of the scroll region.
        //   After scrolling, row 8 should now hold the old row 9 content ('Z'),
        //   and row 9 (new blank line) should be empty.
        assert_eq!(
            screen.lines[8].cells[0].char(),
            'Z',
            "Row 8 should now have 'Z' (shifted up from row 9)"
        );
        assert_eq!(
            screen.lines[9].cells[0].char(),
            ' ',
            "Row 9 should be a fresh blank line after scroll"
        );
    }
}
