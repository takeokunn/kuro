//! Cursor movement and character printing methods for Screen

use compact_str::CompactString;

use super::{
    Cell, CellWidth, Color, Cursor, DirtySet as _, Screen, SgrAttributes, UnicodeWidthChar,
};

impl Screen {
    /// Get reference to the active screen's cursor
    #[inline]
    #[must_use]
    pub fn cursor(&self) -> &Cursor {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_ref() {
                return &alt.cursor;
            }
        }
        &self.cursor
    }

    /// Get mutable reference to the active screen's cursor
    #[inline]
    pub fn cursor_mut(&mut self) -> &mut Cursor {
        // active_screen_mut() returns Some(self) in normal mode and
        // Some(alt) in alternate mode, so the unwrap_or_else fallback
        // is only reached if the invariant is violated (None in alt mode).
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                return &mut alt.cursor;
            }
        }
        &mut self.cursor
    }

    /// Move cursor to absolute position (clears pending wrap)
    #[inline]
    pub fn move_cursor(&mut self, row: usize, col: usize) {
        if let Some(screen) = self.active_screen_mut() {
            screen.cursor.row = row.min(screen.rows as usize - 1);
            screen.cursor.col = col.min(screen.cols as usize - 1);
            screen.cursor.pending_wrap = false;
        }
    }

    /// Move cursor relative (clears pending wrap)
    #[inline]
    pub fn move_cursor_by(&mut self, row_offset: i32, col_offset: i32) {
        if let Some(screen) = self.active_screen_mut() {
            screen.cursor.move_by(col_offset, row_offset);
            screen.cursor.row = screen.cursor.row.min(screen.rows as usize - 1);
            screen.cursor.col = screen.cursor.col.min(screen.cols as usize - 1);
            screen.cursor.pending_wrap = false;
        }
    }

    /// Carriage return (CR) — clears pending wrap
    #[inline]
    pub fn carriage_return(&mut self) {
        if let Some(screen) = self.active_screen_mut() {
            screen.cursor.col = 0;
            screen.cursor.pending_wrap = false;
        }
    }

    /// Backspace (BS) — clears pending wrap
    #[inline]
    pub fn backspace(&mut self) {
        if let Some(screen) = self.active_screen_mut() {
            if screen.cursor.col > 0 {
                screen.cursor.col -= 1;
            }
            screen.cursor.pending_wrap = false;
        }
    }

    /// Horizontal tab (HT) — clears pending wrap
    #[inline]
    pub fn tab(&mut self) {
        if let Some(screen) = self.active_screen_mut() {
            let tab_stop = (screen.cursor.col / 8 + 1) * 8;
            screen.cursor.col = tab_stop.min(screen.cols as usize - 1);
            screen.cursor.pending_wrap = false;
        }
    }

    /// Internal line-feed that operates on an already-dispatched screen.
    /// `is_primary` is forwarded to `scroll_up_impl` so alternate-screen
    /// scrolls never save to scrollback.
    ///
    /// Per VT220: scrolling the scroll region is only triggered when the cursor
    /// is **within** [top, bottom) **and** at the bottom margin (cursor.row ==
    /// bottom - 1).  If the cursor is outside the scroll region (above top or
    /// below bottom), the cursor simply moves down one row, clamped at rows - 1.
    #[inline]
    pub(super) fn line_feed_impl(&mut self, bg: Color, is_primary: bool) {
        self.cursor.pending_wrap = false;
        let new_row = self.cursor.row + 1;
        let rows = self.rows as usize;

        // Cursor must be inside [top, bottom) to trigger a region scroll.
        let in_region = self.cursor.row >= self.scroll_region.top
            && self.cursor.row < self.scroll_region.bottom;

        if in_region && new_row >= self.scroll_region.bottom {
            self.scroll_up_impl(1, bg, is_primary);
        } else {
            self.cursor.row = new_row.min(rows - 1);
        }
    }

    /// Line feed (LF): advances cursor down one row, scrolling up if at the bottom of the scroll region.
    /// Clears pending wrap.  Dispatches to the active screen.
    #[inline]
    pub fn line_feed(&mut self, bg: Color) {
        let is_primary = !self.is_alternate_active;
        if let Some(screen) = self.active_screen_mut() {
            screen.line_feed_impl(bg, is_primary);
        }
    }

    /// Print a character at the cursor position.
    ///
    /// Implements DEC pending-wrap (DECAWM last-column flag):
    /// - When a character fills the last column the cursor stays there and
    ///   `pending_wrap` is set.
    /// - On the *next* printable character the deferred wrap fires (col → 0,
    ///   `line_feed`).
    /// - Any explicit cursor movement clears `pending_wrap` without wrapping.
    #[inline]
    pub fn print(&mut self, c: char, attrs: SgrAttributes, auto_wrap: bool) {
        // Compute is_primary BEFORE dispatching so that scroll_up_impl
        // (called from line_feed_impl) sees the correct value even when
        // operating on the alternate screen.
        let is_primary = !self.is_alternate_active;
        let Some(screen) = self.active_screen_mut() else {
            return;
        };

        // --- Deferred wrap: execute the pending wrap from a previous print ---
        if screen.cursor.pending_wrap {
            screen.cursor.pending_wrap = false;
            if auto_wrap {
                screen.cursor.col = 0;
                screen.line_feed_impl(attrs.background, is_primary);
            }
        }

        let row = screen.cursor.row;
        let col = screen.cursor.col;

        // Determine character width using Unicode width
        // ASCII fast-path: single comparison avoids the full Unicode lookup
        let width = if c.is_ascii() {
            1
        } else {
            UnicodeWidthChar::width(c).unwrap_or(1)
        };
        let cell_width = if width > 1 {
            CellWidth::Full
        } else {
            CellWidth::Half
        };

        // Check if character fits on current line
        if col + width <= screen.cols as usize {
            // Create and update the main cell
            let cell = Cell::with_char_and_width(c, attrs, cell_width);

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

            // If cursor reached beyond the last column, set pending wrap
            if screen.cursor.col >= screen.cols as usize {
                // Clamp to last column; set pending wrap flag only if auto-wrap is on
                screen.cursor.col = (screen.cols as usize).saturating_sub(1);
                if auto_wrap {
                    screen.cursor.pending_wrap = true;
                }
            }
        } else {
            // Character doesn't fit (wide char at last column) — wrap to next line
            if auto_wrap {
                screen.cursor.col = 0;
                screen.line_feed_impl(attrs.background, is_primary);
            }

            // Print on next line if it fits
            if width <= screen.cols as usize {
                let new_row = screen.cursor.row;
                let cell = Cell::with_char_and_width(c, attrs, cell_width);

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

                // If the wide char exactly fills the line, set pending wrap
                if screen.cursor.col >= screen.cols as usize {
                    // Clamp to last column; set pending wrap flag only if auto-wrap is on
                    screen.cursor.col = (screen.cols as usize).saturating_sub(1);
                    if auto_wrap {
                        screen.cursor.pending_wrap = true;
                    }
                }
            }
        }
    }

    /// Print a contiguous run of printable ASCII bytes (0x20..=0x7E) directly,
    /// bypassing VTE per-character dispatch.
    ///
    /// This is a performance-critical fast path: for ASCII-dominated terminal
    /// output, this avoids the overhead of VTE state machine dispatch,
    /// `UnicodeWidthChar` lookups, and per-character `Cell` construction.
    ///
    /// Caller must ensure all bytes are in the range 0x20..=0x7E.
    /// This method must only be called when the VTE parser is in Ground state.
    #[inline]
    pub fn print_ascii_run(&mut self, bytes: &[u8], attrs: SgrAttributes, auto_wrap: bool) {
        if bytes.is_empty() {
            return;
        }

        // Pre-compute before borrowing self through active_screen_mut()
        let is_primary = !self.is_alternate_active;
        let cols = self.cols as usize;

        // Hoist active_screen_mut() outside the per-byte loop.
        // Previously called per byte, adding a branch + Option unwrap per iteration.
        let Some(screen) = self.active_screen_mut() else {
            return;
        };

        // Track the last row we marked dirty to avoid redundant dirty_set.insert +
        // version.wrapping_add inside the per-byte loop.  On an 80-col ASCII run,
        // these would otherwise fire 80 times for the same row; after the first cell
        // changes the row, subsequent writes to the same row are already captured
        // by the next re-encode cycle.  Saves ~80× dirty_set.insert per run.
        let mut last_marked_dirty_row = usize::MAX;

        for &byte in bytes {
            // Handle pending wrap from previous print
            if screen.cursor.pending_wrap {
                screen.cursor.pending_wrap = false;
                if auto_wrap {
                    screen.cursor.col = 0;
                    screen.line_feed_impl(attrs.background, is_primary);
                    // Row changed by line_feed — allow dirty-mark on the new row.
                    last_marked_dirty_row = usize::MAX;
                }
            }

            let row = screen.cursor.row;
            let col = screen.cursor.col;

            // ASCII is always width 1, always fits (col + 1 <= cols)
            if col < cols {
                if let Some(line) = screen.lines.get_mut(row) {
                    // Direct cell write: avoid Cell construction + PartialEq comparison
                    let cell = &mut line.cells[col];
                    // Direct byte comparison: avoid encode_utf8 + str compare overhead.
                    // For ASCII bytes, checking the raw byte is faster than encoding
                    // to UTF-8 and comparing &str slices.
                    // Bind the byte slice once to share the fat-pointer load
                    // across both .len() and [0] accesses.
                    let gb = cell.grapheme.as_bytes();
                    let grapheme_matches = gb.len() == 1 && gb[0] == byte;
                    if !grapheme_matches
                        || cell.width != CellWidth::Half
                        || cell.attrs != attrs
                        || cell.extras.is_some()
                    {
                        if !grapheme_matches {
                            // SAFETY: byte is guaranteed 0x20..=0x7E (printable ASCII),
                            // which is always valid UTF-8.
                            let buf = [byte];
                            let s = unsafe { std::str::from_utf8_unchecked(&buf) };
                            cell.grapheme = CompactString::new(s);
                        }
                        cell.attrs = attrs;
                        cell.width = CellWidth::Half;
                        cell.extras = None;
                        // Guard: mark dirty only on the first changed cell per row.
                        // All subsequent cells on the same row are captured by the
                        // next re-encode; dirty_set.insert is idempotent but not free.
                        if row != last_marked_dirty_row {
                            line.is_dirty = true;
                            line.version = line.version.wrapping_add(1);
                            screen.dirty_set.insert(row);
                            last_marked_dirty_row = row;
                        }
                    }
                }

                // Advance cursor
                screen.cursor.col += 1;

                // Check for pending wrap at end of line
                if screen.cursor.col >= cols {
                    screen.cursor.col = cols.saturating_sub(1);
                    if auto_wrap {
                        screen.cursor.pending_wrap = true;
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::cursor::CursorShape;

    macro_rules! assert_cursor {
        ($screen:expr, row $r:expr, col $c:expr) => {
            assert_eq!($screen.cursor().row, $r, "cursor.row mismatch");
            assert_eq!($screen.cursor().col, $c, "cursor.col mismatch");
        };
    }

    // ── move_cursor (absolute) ────────────────────────────────────────────────

    #[test]
    fn move_cursor_to_basic() {
        let mut screen = Screen::new(24, 80);
        screen.move_cursor(5, 10);
        assert_cursor!(screen, row 5, col 10);
    }

    #[test]
    fn move_cursor_to_clamped_at_bounds() {
        let mut screen = Screen::new(10, 20);
        screen.move_cursor(99, 99);
        assert_cursor!(screen, row 9, col 19);
    }

    #[test]
    fn move_cursor_clears_pending_wrap() {
        let mut screen = Screen::new(5, 5);
        screen.move_cursor(0, 4);
        screen.print('X', SgrAttributes::default(), true);
        assert!(
            screen.cursor.pending_wrap,
            "sanity: pending_wrap must be set"
        );
        screen.move_cursor(0, 0);
        assert!(
            !screen.cursor.pending_wrap,
            "move_cursor must clear pending_wrap"
        );
    }

    // ── move_cursor_by (relative) ─────────────────────────────────────────────

    #[test]
    fn move_cursor_by_positive_delta() {
        let mut screen = Screen::new(24, 80);
        screen.move_cursor(3, 5);
        // move_cursor_by(row_offset, col_offset): row 3+2=5, col 5+4=9
        screen.move_cursor_by(2, 4);
        assert_cursor!(screen, row 5, col 9);
    }

    #[test]
    fn move_cursor_by_negative_clamps_at_zero() {
        let mut screen = Screen::new(24, 80);
        screen.move_cursor(2, 3);
        screen.move_cursor_by(-100, -100);
        assert_cursor!(screen, row 0, col 0);
    }

    #[test]
    fn move_cursor_by_clears_pending_wrap() {
        let mut screen = Screen::new(5, 5);
        screen.move_cursor(0, 4);
        screen.print('X', SgrAttributes::default(), true);
        assert!(screen.cursor.pending_wrap);
        screen.move_cursor_by(0, -1);
        assert!(
            !screen.cursor.pending_wrap,
            "move_cursor_by must clear pending_wrap"
        );
    }

    // ── carriage_return ───────────────────────────────────────────────────────

    #[test]
    fn carriage_return_resets_col_to_zero() {
        let mut screen = Screen::new(10, 40);
        screen.move_cursor(3, 20);
        screen.carriage_return();
        assert_cursor!(screen, row 3, col 0);
    }

    #[test]
    fn carriage_return_clears_pending_wrap() {
        let mut screen = Screen::new(5, 5);
        screen.move_cursor(0, 4);
        screen.print('X', SgrAttributes::default(), true);
        assert!(screen.cursor.pending_wrap);
        screen.carriage_return();
        assert!(
            !screen.cursor.pending_wrap,
            "carriage_return must clear pending_wrap"
        );
    }

    // ── tab ───────────────────────────────────────────────────────────────────

    #[test]
    fn tab_advances_to_next_tab_stop() {
        let mut screen = Screen::new(5, 80);
        screen.tab();
        assert_eq!(screen.cursor().col, 8, "tab from col 0 must reach col 8");
    }

    #[test]
    fn tab_at_near_end_clamps_to_last_col() {
        let mut screen = Screen::new(5, 10);
        screen.move_cursor(0, 5);
        screen.tab(); // 5 → 8
        assert_eq!(screen.cursor().col, 8);
        screen.tab(); // 8 → 16 clamped to 9 (cols-1)
        assert_eq!(
            screen.cursor().col,
            9,
            "tab past last col must clamp to cols-1"
        );
    }

    // ── line_feed ─────────────────────────────────────────────────────────────

    #[test]
    fn line_feed_col_preserved_after_advance() {
        let mut screen = Screen::new(24, 80);
        screen.move_cursor(0, 40);
        screen.line_feed(Color::Default);
        assert_cursor!(screen, row 1, col 40);
    }

    #[test]
    fn line_feed_without_auto_wrap_stays_in_col() {
        let mut screen = Screen::new(5, 10);
        screen.move_cursor(0, 9);
        screen.print('Z', SgrAttributes::default(), false);
        assert_cursor!(screen, row 0, col 9);
        assert!(
            !screen.cursor.pending_wrap,
            "auto_wrap=false: no pending_wrap after last col"
        );
    }

    #[test]
    fn line_feed_with_auto_wrap_sets_pending_wrap() {
        let mut screen = Screen::new(5, 10);
        screen.move_cursor(0, 9);
        screen.print('Z', SgrAttributes::default(), true);
        assert!(
            screen.cursor.pending_wrap,
            "auto_wrap=true: pending_wrap must be set after printing at last col"
        );
    }

    // ── cursor getters ────────────────────────────────────────────────────────

    #[test]
    fn cursor_row_and_col_return_correct_values() {
        let mut screen = Screen::new(24, 80);
        screen.move_cursor(7, 13);
        assert_eq!(screen.cursor().row, 7, "cursor().row mismatch");
        assert_eq!(screen.cursor().col, 13, "cursor().col mismatch");
    }

    #[test]
    fn cursor_default_shape_is_blinking_block() {
        let screen = Screen::new(24, 80);
        assert_eq!(
            screen.cursor().shape,
            CursorShape::BlinkingBlock,
            "default cursor shape must be BlinkingBlock"
        );
    }

    // ── backspace ─────────────────────────────────────────────────────────────

    #[test]
    fn backspace_clears_pending_wrap() {
        let mut screen = Screen::new(5, 5);
        screen.move_cursor(0, 4);
        screen.print('X', SgrAttributes::default(), true);
        assert!(screen.cursor.pending_wrap);
        screen.backspace();
        assert!(
            !screen.cursor.pending_wrap,
            "backspace must clear pending_wrap"
        );
    }
}
