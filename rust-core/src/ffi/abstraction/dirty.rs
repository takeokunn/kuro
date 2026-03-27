//! Dirty-line rendering and scroll-event methods for `TerminalSession`
//!
//! This module contains the `consume_scroll_events` and `get_dirty_lines_with_faces`
//! methods, which handle the scrollback viewport and synchronized-output logic.

use super::session::TerminalSession;

impl TerminalSession {
    /// Consume pending full-screen scroll event counts and reset them to zero.
    ///
    /// Returns `(scroll_up, scroll_down)`.  Called by the Emacs render cycle
    /// BEFORE `get_dirty_lines_with_faces` so that buffer-level line
    /// deletion/insertion can precede per-row text updates, preventing the
    /// bottom row from being rendered twice per scroll step.
    ///
    /// Returns `(0, 0)` when the viewport is scrolled into the scrollback
    /// buffer (`scroll_offset > 0`).  Scroll events that accumulated while
    /// the user was viewing scrollback are discarded in
    /// `viewport_scroll_down` when `scroll_offset` returns to 0.
    pub fn consume_scroll_events(&mut self) -> (u32, u32) {
        if self.core.screen.scroll_offset() > 0 {
            return (0, 0);
        }
        self.core.screen.consume_scroll_events()
    }

    /// Get dirty lines with face ranges from screen, with scrollback viewport support.
    ///
    /// When the viewport is scrolled back (`scroll_offset > 0`) and `scroll_dirty` is
    /// set, returns all rows as scrollback content. Otherwise falls through to the
    /// standard live dirty-line path.
    ///
    /// Returns a list where each element is `(line_no, text, face_ranges, col_to_buf)`:
    /// - `face_ranges`: `(start_buf, end_buf, fg_color, bg_color, flags)` in buffer offsets
    /// - `col_to_buf`: mapping from grid column index to buffer char offset
    pub fn get_dirty_lines_with_faces(&mut self) -> Vec<crate::ffi::codec::EncodedLine> {
        // Scrollback viewport path: when scroll_dirty, return scrollback lines instead of live lines
        if self.core.screen.is_scroll_dirty() && self.core.screen.scroll_offset() > 0 {
            self.core.screen.clear_scroll_dirty();
            let rows = self.core.screen.rows() as usize;
            let mut result = Vec::with_capacity(rows);
            for row in 0..rows {
                match self.core.screen.get_scrollback_viewport_line(row) {
                    Some(line) => {
                        let encoded = Self::encode_line_faces(row, &line.cells);
                        result.push(encoded);
                    }
                    None => {
                        result.push((row, String::new(), vec![], vec![]));
                    }
                }
            }
            return result;
        }

        // If viewport is scrolled but not dirty (scroll_dirty == false),
        // suppress live dirty lines to preserve the scrollback view.
        if self.core.screen.scroll_offset() > 0 {
            self.core.screen.clear_dirty();
            return vec![];
        }

        // Synchronized Output mode (DEC ?2026): hold until batch complete.
        if self.core.dec_modes.synchronized_output {
            self.core.screen.clear_dirty();
            return vec![];
        }

        // Check if the 256-color palette changed since the last render and bump
        // palette_epoch so every cached row hash is implicitly invalidated.
        if self.core.osc_data.palette_dirty {
            self.core.osc_data.palette_dirty = false;
            self.palette_epoch = self.palette_epoch.wrapping_add(1);
        }

        // Check if alternate screen was toggled since the last render and clear
        // row_hashes to force a full re-render of all rows.
        let now_alt = self.core.screen.is_alternate_screen_active();
        if now_alt != self.was_alt_screen {
            self.was_alt_screen = now_alt;
            self.row_hashes.clear();
        }

        // Fast path: full_dirty → iterate 0..rows directly without allocating a Vec.
        // Also update row_hashes for each encoded row so subsequent partial-dirty
        // frames can skip rows that haven't changed.
        // NOTE: The hash-skip optimisation (below) only applies in the partial-dirty
        // path.  Full-dirty frames — triggered by scrolling, resize, alt-screen switch,
        // or programs that dirty more rows than the dirty threshold — always return all
        // rows.  This is intentional: `full_dirty` is a conservative "repaint everything"
        // signal where correctness requires sending every row to the Elisp renderer.
        if self.core.screen.is_full_dirty() {
            let rows = self.core.screen.rows() as usize;
            self.core.screen.clear_dirty();
            let mut result = Vec::with_capacity(rows);
            for row in 0..rows {
                if let Some(line) = self.core.screen.get_line(row) {
                    let (text, face_ranges, col_to_buf) =
                        crate::ffi::codec::encode_line(&line.cells);
                    let hash = crate::ffi::codec::compute_row_hash(line, &col_to_buf);
                    self.row_hashes.insert(row, (hash, self.palette_epoch));
                    result.push((row, text, face_ranges, col_to_buf));
                }
            }
            return result;
        }

        let dirty_indices = self.core.screen.take_dirty_lines();
        let mut result = Vec::with_capacity(dirty_indices.len());
        let epoch = self.palette_epoch;

        for row in dirty_indices {
            if let Some(line) = self.core.screen.get_line(row) {
                let (text, face_ranges, col_to_buf) = crate::ffi::codec::encode_line(&line.cells);
                let new_hash = crate::ffi::codec::compute_row_hash(line, &col_to_buf);

                // Skip this row if both content hash and palette epoch match.
                if let Some(&(stored_hash, stored_epoch)) = self.row_hashes.get(&row) {
                    if stored_hash == new_hash && stored_epoch == epoch {
                        // Unchanged row — do not include in output.
                        continue;
                    }
                }

                self.row_hashes.insert(row, (new_hash, epoch));
                result.push((row, text, face_ranges, col_to_buf));
            }
        }

        result
    }
}
