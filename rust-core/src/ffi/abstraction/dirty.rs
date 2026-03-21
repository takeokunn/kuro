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
            let _discard = self.core.screen.take_dirty_lines();
            return vec![];
        }

        // Synchronized Output mode (DEC ?2026): hold until batch complete.
        if self.core.dec_modes.synchronized_output {
            let _discard = self.core.screen.take_dirty_lines();
            return vec![];
        }

        let dirty_indices = self.core.screen.take_dirty_lines();
        let mut result = Vec::with_capacity(dirty_indices.len());

        for row in dirty_indices {
            if let Some(line) = self.core.screen.get_line(row) {
                let encoded = Self::encode_line_faces(row, &line.cells);
                result.push(encoded);
            }
        }

        result
    }
}
