//! Dirty tracking methods for Screen

use super::{BitVecDirtySet, DirtySet as _, Screen};

impl Screen {
    /// Attach a combining character to the cell at (row, col).
    /// If the cell exists, appends the combining char to its grapheme cluster
    /// and marks the line dirty.
    pub fn attach_combining(&mut self, row: usize, col: usize, c: char) {
        if let Some(cell) = self.get_cell_mut(row, col) {
            cell.push_combining(c);
        }
        // Mark the line dirty
        self.with_active_screen_mut(|screen| {
            screen.dirty_set.insert(row);
        });
    }

    /// Merge a second regional indicator into the cell at (row, col), forming a
    /// single width-2 flag cluster (DEC mode 2027 grapheme clustering).
    ///
    /// `(row, col)` holds the first regional indicator (printed as a normal
    /// width-1 cell, so the cursor is currently one column to its right). This:
    /// 1. appends `c` to that cell's grapheme cluster,
    /// 2. promotes the cell to [`CellWidth::Full`],
    /// 3. installs a [`CellWidth::Wide`] continuation in the trailing cell, and
    /// 4. advances the cursor one column so the flag occupies two cells total.
    ///
    /// Marks the affected line dirty.
    pub fn merge_flag_pair(&mut self, row: usize, col: usize, c: char) {
        use crate::types::cell::{Cell, CellWidth};

        if let Some(cell) = self.get_cell_mut(row, col) {
            cell.push_combining(c);
            cell.width = CellWidth::Full;
        }
        let cols = self.cols() as usize;
        if col + 1 < cols {
            if let Some(trailing) = self.get_cell_mut(row, col + 1) {
                *trailing = Cell {
                    width: CellWidth::Wide,
                    ..Cell::default()
                };
            }
        }
        self.with_active_screen_mut(|screen| {
            screen.dirty_set.insert(row);
            // Advance past the trailing continuation cell so the next print
            // lands beyond the two-cell flag. Clamp to the last column.
            screen.cursor.col = (screen.cursor.col + 1).min(cols.saturating_sub(1));
        });
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
        self.with_active_screen_mut(|screen| {
            screen.dirty_set.insert(row);
            if let Some(line) = screen.lines.get_mut(row) {
                line.is_dirty = true;
            }
        });
    }

    /// Mark a line dirty AND bump its mutation version.
    ///
    /// Needed when a row changes via a side channel that does not flow through
    /// `update_cell_with` (which only bumps the version when the cell's
    /// `PartialEq` value differs).  The Kitty text-sizing (OSC 66) path stamps
    /// `text_size` onto already-printed cells via `get_cell_mut`; when the
    /// underlying grapheme/attrs are identical to the previous content the cell
    /// write short-circuits without bumping the version, so the dirty pipeline's
    /// `line.version` skip would incorrectly drop the row.  Calling this after
    /// stamping forces the row to be re-encoded (and its hash — which now folds
    /// in `text_size` — to be recomputed).
    pub(crate) fn mark_line_dirty_and_bump(&mut self, row: usize) {
        self.with_active_screen_mut(|screen| {
            screen.dirty_set.insert(row);
            if let Some(line) = screen.lines.get_mut(row) {
                line.mark_dirty_and_bump();
            }
        });
    }

    /// Mark all lines as dirty at once (more efficient than inserting every row)
    pub fn mark_all_dirty(&mut self) {
        self.with_active_screen_mut(|screen| {
            screen.full_dirty = true;
        });
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
                Self::clear_dirty_state(&mut alt.full_dirty, &mut alt.dirty_set);
            }
        } else {
            Self::clear_dirty_state(&mut self.full_dirty, &mut self.dirty_set);
        }
    }

    /// Fill `out` with dirty row indices and clear the dirty set.
    ///
    /// Clears `out` first, then drains dirty indices into it.  Prefer this
    /// over [`take_dirty_lines`] in hot paths (120fps render loop) to reuse
    /// an existing allocation rather than allocating a fresh `Vec` each frame.
    pub fn take_dirty_lines_into(&mut self, out: &mut Vec<usize>) {
        out.clear();
        self.drain_dirty_rows(|dirty_rows| out.extend(dirty_rows));
    }

    /// Get dirty lines and clear the dirty set
    pub fn take_dirty_lines(&mut self) -> Vec<usize> {
        let mut dirty = Vec::new();
        self.drain_dirty_rows(|dirty_rows| dirty.extend(dirty_rows));
        dirty
    }

    #[inline]
    fn drain_dirty_rows<F>(&mut self, mut emit: F)
    where
        F: FnMut(&mut dyn Iterator<Item = usize>),
    {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                Self::drain_dirty_state(
                    &mut alt.full_dirty,
                    &mut alt.dirty_set,
                    alt.rows as usize,
                    &mut emit,
                );
                return;
            }
        }

        // Primary screen (or fallback if is_alternate_active but alternate_screen is None)
        Self::drain_dirty_state(
            &mut self.full_dirty,
            &mut self.dirty_set,
            self.rows as usize,
            &mut emit,
        );
    }

    #[inline]
    fn clear_dirty_state(full_dirty: &mut bool, dirty_set: &mut BitVecDirtySet) {
        *full_dirty = false;
        dirty_set.clear();
    }

    #[inline]
    fn drain_dirty_state<F>(
        full_dirty: &mut bool,
        dirty_set: &mut BitVecDirtySet,
        rows: usize,
        emit: &mut F,
    ) where
        F: FnMut(&mut dyn Iterator<Item = usize>),
    {
        if *full_dirty {
            *full_dirty = false;
            dirty_set.clear();
            let mut dirty_rows = 0..rows;
            emit(&mut dirty_rows);
            return;
        }

        {
            let mut dirty_rows = dirty_set.iter_ones_direct();
            emit(&mut dirty_rows);
        }
        dirty_set.clear();
    }
}

#[cfg(test)]
#[path = "dirty/tests.rs"]
mod tests;
