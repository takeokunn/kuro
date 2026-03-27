//! Dirty tracking methods for Screen

use super::{DirtySet as _, Screen};

impl Screen {
    /// Attach a combining character to the cell at (row, col).
    /// If the cell exists, appends the combining char to its grapheme cluster
    /// and marks the line dirty.
    pub fn attach_combining(&mut self, row: usize, col: usize, c: char) {
        if let Some(cell) = self.get_cell_mut(row, col) {
            cell.push_combining(c);
        }
        // Mark the line dirty
        if let Some(screen) = self.active_screen_mut() {
            screen.dirty_set.insert(row);
        }
    }

    /// Mark rows in the range `lo..hi` (half-open) as dirty.
    ///
    /// This method is defined on [`Screen`] (the inner active screen), not on the
    /// outer alternate-screen dispatcher.  Callers must obtain the inner screen via
    /// `active_screen_mut()` before calling this method.
    ///
    /// Only `dirty_set` is updated; `line.is_dirty` on each [`Line`] is **not** set.
    /// For single-line dirty marking that also sets `line.is_dirty`, use
    /// [`mark_line_dirty`] instead.
    #[inline]
    pub(super) fn mark_dirty_range(&mut self, lo: usize, hi: usize) {
        self.dirty_set.insert_range(lo, hi);
    }

    /// Mark a line as dirty in both the line flag and the dirty set
    pub fn mark_line_dirty(&mut self, row: usize) {
        if let Some(screen) = self.active_screen_mut() {
            screen.dirty_set.insert(row);
            if let Some(line) = screen.lines.get_mut(row) {
                line.is_dirty = true;
            }
        }
    }

    /// Mark all lines as dirty at once (more efficient than inserting every row)
    pub fn mark_all_dirty(&mut self) {
        if let Some(screen) = self.active_screen_mut() {
            screen.full_dirty = true;
        }
    }

    /// Check whether all lines are marked dirty (full repaint pending)
    #[inline]
    #[must_use]
    pub fn is_full_dirty(&self) -> bool {
        if self.is_alternate_active {
            self.alternate_screen
                .as_ref()
                .is_some_and(|alt| alt.full_dirty)
        } else {
            self.full_dirty
        }
    }

    /// Clear all dirty state without allocating.
    ///
    /// Use this instead of `take_dirty_lines()` when the caller intends to
    /// discard the dirty indices (e.g. suppressed render paths).
    pub fn clear_dirty(&mut self) {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                alt.full_dirty = false;
                alt.dirty_set.clear();
            }
        } else {
            self.full_dirty = false;
            self.dirty_set.clear();
        }
    }

    /// Get dirty lines and clear the dirty set
    pub fn take_dirty_lines(&mut self) -> Vec<usize> {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                if alt.full_dirty {
                    alt.full_dirty = false;
                    alt.dirty_set.clear();
                    return (0..alt.rows as usize).collect();
                }
                let dirty: Vec<usize> = alt.dirty_set.iter_ones_direct().collect();
                alt.dirty_set.clear();
                return dirty;
            }
        }
        // Primary screen (or fallback if is_alternate_active but alternate_screen is None)
        if self.full_dirty {
            self.full_dirty = false;
            self.dirty_set.clear();
            (0..self.rows as usize).collect()
        } else {
            let dirty: Vec<usize> = self.dirty_set.iter_ones_direct().collect();
            self.dirty_set.clear();
            dirty
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mark_dirty_range_marks_correct_rows() {
        let mut screen = Screen::new(24, 80);
        screen.mark_dirty_range(3, 7); // marks rows 3,4,5,6 (half-open)
        for row in 3..7 {
            assert!(screen.dirty_set.contains(row), "row {row} should be dirty");
        }
        // Rows outside the range must not be dirty
        assert!(!screen.dirty_set.contains(2));
        assert!(!screen.dirty_set.contains(7));
    }

    #[test]
    fn mark_dirty_range_empty_range_marks_nothing() {
        let mut screen = Screen::new(24, 80);
        screen.mark_dirty_range(5, 5); // empty range
        assert!(screen.dirty_set.is_empty());
    }

    #[test]
    fn mark_all_dirty_sets_full_dirty_flag() {
        let mut screen = Screen::new(24, 80);
        assert!(!screen.is_full_dirty());
        screen.mark_all_dirty();
        assert!(screen.is_full_dirty());
    }

    #[test]
    fn take_dirty_lines_full_dirty_returns_all_rows_and_clears() {
        let mut screen = Screen::new(6, 80);
        screen.mark_all_dirty();
        let dirty = screen.take_dirty_lines();
        assert_eq!(dirty, vec![0, 1, 2, 3, 4, 5]);
        // After take, full_dirty must be cleared and dirty_set empty.
        assert!(!screen.is_full_dirty());
        assert!(screen.dirty_set.is_empty());
    }

    #[test]
    fn take_dirty_lines_partial_drains_and_clears() {
        let mut screen = Screen::new(24, 80);
        screen.dirty_set.insert(2);
        screen.dirty_set.insert(7);
        let dirty = screen.take_dirty_lines();
        assert_eq!(dirty, vec![2, 7]);
        // Dirty set must be empty after drain.
        assert!(screen.dirty_set.is_empty());
    }

    #[test]
    fn clear_dirty_resets_both_full_dirty_and_set() {
        let mut screen = Screen::new(24, 80);
        screen.mark_all_dirty();
        screen.dirty_set.insert(5);
        screen.clear_dirty();
        assert!(!screen.is_full_dirty());
        assert!(screen.dirty_set.is_empty());
    }

    #[test]
    fn mark_line_dirty_sets_both_set_and_line_flag() {
        let mut screen = Screen::new(24, 80);
        screen.mark_line_dirty(3);
        assert!(screen.dirty_set.contains(3));
        assert!(screen.lines[3].is_dirty);
        // Other rows must not be affected.
        assert!(!screen.dirty_set.contains(4));
        assert!(!screen.lines[4].is_dirty);
    }

    #[test]
    fn is_full_dirty_reflects_alternate_screen_when_active() {
        let mut screen = Screen::new(24, 80);
        // Primary screen starts clean.
        assert!(!screen.is_full_dirty());
        // Switching to alternate clears primary full_dirty flag visibility and sets
        // alt full_dirty (switch_to_alternate always marks alt dirty for repaint).
        screen.switch_to_alternate();
        assert!(screen.is_alternate_screen_active());
        assert!(screen.is_full_dirty()); // alternate was marked full-dirty on entry
                                         // Consume the full-dirty via take_dirty_lines.
        let _ = screen.take_dirty_lines();
        assert!(!screen.is_full_dirty());
        // Re-mark and verify we can set it explicitly.
        screen.mark_all_dirty();
        assert!(screen.is_full_dirty());
        // Switching back to primary sets primary full_dirty (not alternate's).
        screen.switch_to_primary();
        assert!(!screen.is_alternate_screen_active());
        assert!(screen.is_full_dirty()); // primary is now full-dirty on return
    }
}
