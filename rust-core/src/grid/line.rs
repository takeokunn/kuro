//! Line type representing a single row in the terminal screen

use crate::types::{cell::CellWidth, Cell, Color, SgrAttributes};
use compact_str::CompactString;
use std::fmt;

/// A single line in the terminal grid
#[derive(Debug, Clone)]
pub struct Line {
    /// Cells in this line
    pub cells: Vec<Cell>,
    /// Whether this line has been modified since last render
    pub is_dirty: bool,
    /// Monotonically increasing mutation counter (wrapping).
    ///
    /// Incremented on every cell write, clear, or resize so that the render
    /// path can skip hash computation for rows that have not changed since the
    /// last frame.  Version `0` is the initial value; any mutation produces `≥ 1`.
    pub(crate) version: u64,
    /// Whether any cell on this line is a wide-character placeholder
    /// (`CellWidth::Wide`).  Set incrementally on writes; cleared on full-line
    /// clear/reset.  Lets `fill_encode_pool` skip the O(cols) pre-scan on the
    /// ~90% of ASCII-only dirty lines.
    pub(crate) has_wide: bool,

    /// Whether this line is *soft-wrapped*: its content overflowed the right
    /// margin under DECAWM and continues on the next line, with no explicit
    /// newline between them.  Set when an auto-wrap fires during printing;
    /// cleared on clear/resize.  This is the boundary information reflow needs
    /// to reconstruct logical lines when the terminal width changes.
    pub(crate) wrapped: bool,
}

impl Line {
    /// Create a new line with the specified number of columns
    #[inline]
    #[must_use]
    pub fn new(cols: usize) -> Self {
        Self {
            cells: vec![Cell::default(); cols],
            is_dirty: false,
            version: 0,
            has_wide: false,
            wrapped: false,
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
            version: 0,
            has_wide: false,
            wrapped: false,
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
                self.mark_dirty_and_bump();
            }
        }
    }

    /// Update cell at column index with a Cell struct (includes width)
    #[inline]
    pub fn update_cell_with(&mut self, col: usize, cell: Cell) {
        if col < self.cells.len() && self.cells[col] != cell {
            // Short-circuit: once has_wide is set it stays set; skip the width
            // enum load on every subsequent cell write to the same line.
            if !self.has_wide && cell.width == CellWidth::Wide {
                self.has_wide = true;
            }
            self.cells[col] = cell;
            self.mark_dirty_and_bump();
        }
    }

    /// Clear all cells in line
    #[inline]
    pub fn clear(&mut self) {
        self.cells.fill(Cell::default());
        self.has_wide = false;
        self.wrapped = false;
        self.mark_dirty_and_bump();
    }

    /// Clear all cells, setting background to specified color.
    /// Implements Background Color Erase (BCE) per VT220: erased cells
    /// receive the given background color rather than the terminal default.
    #[inline]
    pub fn clear_with_bg(&mut self, bg: Color) {
        let mut blank = Cell::default();
        blank.attrs.background = bg;
        self.cells.fill(blank);
        self.has_wide = false;
        self.wrapped = false;
        self.mark_dirty_and_bump();
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

    /// Mark dirty and increment the mutation version counter.
    ///
    /// Every cell write, clear, or resize shares this two-field update.
    /// Inlined at every call site — zero overhead vs. the raw field assignments.
    #[inline]
    pub(crate) fn mark_dirty_and_bump(&mut self) {
        self.is_dirty = true;
        self.version = self.version.wrapping_add(1);
    }

    /// Resize line to new column count
    pub fn resize(&mut self, new_cols: usize) {
        if new_cols > self.cells.len() {
            // Expand with default cells; no wide cells added, has_wide unchanged.
            self.cells.resize(new_cols, Cell::default());
        } else if new_cols < self.cells.len() {
            let old_len = self.cells.len();
            // Only rescan the retained cells if the removed suffix contained a wide
            // cell.  On ASCII-only terminals the suffix has no wide cells, so the full
            // O(new_cols) retained-cell rescan is skipped — O(suffix_len) instead.
            let removed_had_wide = self.cells[new_cols..old_len]
                .iter()
                .any(|c| c.width == CellWidth::Wide);
            // Truncate. Only shrink allocated capacity when it greatly exceeds the new
            // length, to avoid repeated reallocs during interactive window-resize drags.
            self.cells.truncate(new_cols);
            if self.cells.capacity() > new_cols * 2 + 16 {
                // shrink_to retains 16-cell headroom, absorbing the next drag step
                // without an immediate realloc (unlike shrink_to_fit which drops to exact).
                self.cells.shrink_to(new_cols + 16);
            }
            if removed_had_wide {
                self.has_wide = self.cells.iter().any(|c| c.width == CellWidth::Wide);
            }
        }
        // A column-count change invalidates the old soft-wrap boundary.
        self.wrapped = false;
        self.mark_dirty_and_bump();
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
#[path = "line/tests.rs"]
mod tests;
