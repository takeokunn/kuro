//! Line type representing a single row in the terminal screen

use crate::types::{Cell, Color, SgrAttributes};
use compact_str::CompactString;
use serde::{Deserialize, Serialize};
use std::fmt;

/// A single line in the terminal grid
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Line {
    /// Cells in this line
    pub cells: Vec<Cell>,
    /// Whether this line has been modified since last render
    pub is_dirty: bool,
}

impl Line {
    /// Create a new line with the specified number of columns
    #[inline]
    #[must_use]
    pub fn new(cols: usize) -> Self {
        Self {
            cells: vec![Cell::default(); cols],
            is_dirty: false,
        }
    }

    /// Create a new line with all cells carrying the given BCE background color.
    /// When `bg` is `Color::Default` this is identical to `Line::new(cols)`.
    #[inline]
    #[must_use]
    pub fn new_with_bg(cols: usize, bg: Color) -> Self {
        if bg == Color::Default {
            return Self::new(cols);
        }
        let mut cell = Cell::default();
        cell.attrs.background = bg;
        Self {
            cells: vec![cell; cols],
            is_dirty: false,
        }
    }

    /// Get cell at column index
    #[inline]
    #[must_use]
    pub fn get_cell(&self, col: usize) -> Option<&Cell> {
        self.cells.get(col)
    }

    /// Get mutable reference to cell at column index
    #[inline]
    pub fn get_cell_mut(&mut self, col: usize) -> Option<&mut Cell> {
        self.cells.get_mut(col)
    }

    /// Update cell at column index
    #[inline]
    pub fn update_cell(&mut self, col: usize, c: char, attrs: SgrAttributes) {
        if let Some(cell) = self.cells.get_mut(col) {
            let mut buf = [0u8; 4];
            let s = c.encode_utf8(&mut buf);
            let grapheme_changed = cell.grapheme.as_str() != s;
            let attrs_changed = cell.attrs != attrs;
            if grapheme_changed || attrs_changed {
                if grapheme_changed {
                    cell.grapheme = CompactString::new(s);
                }
                if attrs_changed {
                    cell.attrs = attrs;
                }
                self.is_dirty = true;
            }
        }
    }

    /// Update cell at column index with a Cell struct (includes width)
    #[inline]
    pub fn update_cell_with(&mut self, col: usize, cell: Cell) {
        if col < self.cells.len() && self.cells[col] != cell {
            self.cells[col] = cell;
            self.is_dirty = true;
        }
    }

    /// Clear all cells in line
    #[inline]
    pub fn clear(&mut self) {
        for cell in &mut self.cells {
            *cell = Cell::default();
        }
        self.is_dirty = true;
    }

    /// Clear all cells, setting background to specified color.
    /// Implements Background Color Erase (BCE) per VT220: erased cells
    /// receive the given background color rather than the terminal default.
    #[inline]
    pub fn clear_with_bg(&mut self, bg: Color) {
        let mut blank = Cell::default();
        blank.attrs.background = bg;
        self.cells.fill(blank);
        self.is_dirty = true;
    }

    /// Mark line as dirty
    #[inline]
    pub const fn mark_dirty(&mut self) {
        self.is_dirty = true;
    }

    /// Mark line as clean (not dirty)
    #[inline]
    pub const fn mark_clean(&mut self) {
        self.is_dirty = false;
    }

    /// Resize line to new column count
    pub fn resize(&mut self, new_cols: usize) {
        if new_cols > self.cells.len() {
            // Expand with default cells
            self.cells.resize(new_cols, Cell::default());
        } else if new_cols < self.cells.len() {
            // Truncate
            self.cells.truncate(new_cols);
            self.cells.shrink_to_fit();
        }
        self.is_dirty = true;
    }
}

impl fmt::Display for Line {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for cell in &self.cells {
            write!(f, "{}", cell.grapheme.as_str())?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_line_creation() {
        let line = Line::new(80);
        assert_eq!(line.cells.len(), 80);
        assert!(!line.is_dirty);
    }

    #[test]
    fn test_line_update_cell() {
        let mut line = Line::new(10);
        let attrs = SgrAttributes::default();

        line.update_cell(5, 'X', attrs);

        assert!(line.is_dirty);
        assert_eq!(line.get_cell(5).unwrap().char(), 'X');
    }

    #[test]
    fn test_line_clear() {
        let mut line = Line::new(10);
        line.update_cell(0, 'A', SgrAttributes::default());

        line.clear();

        assert!(line.is_dirty);
        assert_eq!(line.get_cell(0).unwrap().char(), ' ');
    }

    #[test]
    fn test_line_resize_expand() {
        let mut line = Line::new(10);
        line.resize(20);

        assert_eq!(line.cells.len(), 20);
        assert!(line.is_dirty);
    }

    #[test]
    fn test_line_resize_shrink() {
        let mut line = Line::new(20);
        line.resize(10);

        assert_eq!(line.cells.len(), 10);
        assert!(line.is_dirty);
    }
}
