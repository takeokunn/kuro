//! Cursor movement and character printing methods for Screen

use compact_str::CompactString;

use super::{
    Cell, CellWidth, Color, Cursor, DirtySet as _, Screen, SgrAttributes, UnicodeWidthChar,
};

#[inline]
const fn is_printable_ascii(byte: u8) -> bool {
    byte >= 0x20 && byte <= 0x7e
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct NonPrintableAsciiByte {
    pub(crate) byte: u8,
    pub(crate) index: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct PrintableAsciiRun<'a> {
    bytes: &'a [u8],
}

impl<'a> PrintableAsciiRun<'a> {
    pub(crate) fn new(bytes: &'a [u8]) -> Result<Self, NonPrintableAsciiByte> {
        if let Some(index) = bytes.iter().position(|&byte| !is_printable_ascii(byte)) {
            let byte = bytes[index];
            return Err(NonPrintableAsciiByte { byte, index });
        }

        Ok(Self { bytes })
    }

    pub(crate) fn longest_prefix(bytes: &'a [u8]) -> Option<Self> {
        let len = bytes
            .iter()
            .position(|&byte| !is_printable_ascii(byte))
            .unwrap_or(bytes.len());
        if len == 0 {
            None
        } else {
            Some(Self {
                bytes: &bytes[..len],
            })
        }
    }

    pub(crate) const fn as_bytes(self) -> &'a [u8] {
        self.bytes
    }

    pub(crate) const fn len(self) -> usize {
        self.bytes.len()
    }

    pub(crate) const fn is_empty(self) -> bool {
        self.bytes.is_empty()
    }
}

#[derive(Debug, Clone)]
pub(crate) struct PrintableAsciiBuffer {
    bytes: Vec<u8>,
}

impl PrintableAsciiBuffer {
    pub(crate) fn with_capacity(capacity: usize) -> Self {
        Self {
            bytes: Vec::with_capacity(capacity),
        }
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.bytes.is_empty()
    }

    pub(crate) fn len(&self) -> usize {
        self.bytes.len()
    }

    pub(crate) fn clear(&mut self) {
        self.bytes.clear();
    }

    pub(crate) fn try_extend_from_slice(
        &mut self,
        bytes: &[u8],
    ) -> Result<(), NonPrintableAsciiByte> {
        PrintableAsciiRun::new(bytes)?;
        self.bytes.extend_from_slice(bytes);
        Ok(())
    }

    pub(crate) fn push_printable_char(&mut self, c: char) -> bool {
        if !c.is_ascii() {
            return false;
        }

        let byte = c as u8;
        self.try_extend_from_slice(&[byte]).is_ok()
    }

    pub(crate) fn as_run(&self) -> PrintableAsciiRun<'_> {
        PrintableAsciiRun { bytes: &self.bytes }
    }
}

#[inline]
fn last_row_index(screen: &Screen) -> usize {
    usize::from(screen.rows).saturating_sub(1)
}

#[inline]
fn last_col_index(screen: &Screen) -> usize {
    usize::from(screen.cols).saturating_sub(1)
}

impl Screen {
    /// Get reference to the active screen's cursor
    #[inline]
    #[must_use]
    pub fn cursor(&self) -> &Cursor {
        self.with_active_screen(|screen| &screen.cursor)
            .unwrap_or(&self.cursor)
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
        self.with_active_screen_mut(|screen| {
            screen.cursor.row = row.min(last_row_index(screen));
            screen.cursor.col = col.min(last_col_index(screen));
            screen.cursor.pending_wrap = false;
        });
    }

    /// Move cursor relative (clears pending wrap)
    #[inline]
    pub fn move_cursor_by(&mut self, row_offset: i32, col_offset: i32) {
        self.with_active_screen_mut(|screen| {
            screen.cursor.move_by(col_offset, row_offset);
            screen.cursor.row = screen.cursor.row.min(last_row_index(screen));
            screen.cursor.col = screen.cursor.col.min(last_col_index(screen));
            screen.cursor.pending_wrap = false;
        });
    }

    /// Carriage return (CR) — clears pending wrap
    #[inline]
    pub fn carriage_return(&mut self) {
        self.with_active_screen_mut(|screen| {
            screen.cursor.col = 0;
            screen.cursor.pending_wrap = false;
        });
    }

    /// Backspace (BS) — clears pending wrap
    #[inline]
    pub fn backspace(&mut self) {
        self.with_active_screen_mut(|screen| {
            if screen.cursor.col > 0 {
                screen.cursor.col -= 1;
            }
            screen.cursor.pending_wrap = false;
        });
    }

    /// Horizontal tab (HT) — clears pending wrap
    #[inline]
    pub fn tab(&mut self) {
        self.with_active_screen_mut(|screen| {
            let tab_stop = screen
                .cursor
                .col
                .saturating_div(8)
                .saturating_add(1)
                .saturating_mul(8);
            screen.cursor.col = tab_stop.min(last_col_index(screen));
            screen.cursor.pending_wrap = false;
        });
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
        let new_row = self.cursor.row.saturating_add(1);
        let rows = usize::from(self.rows);

        // Cursor must be inside [top, bottom) to trigger a region scroll.
        let in_region = self.cursor.row >= self.scroll_region.top
            && self.cursor.row < self.scroll_region.bottom;

        if in_region && new_row >= self.scroll_region.bottom {
            self.scroll_up_impl(1, bg, is_primary);
        } else {
            self.cursor.row = new_row.min(rows.saturating_sub(1));
        }
    }

    /// Mark the current cursor row as soft-wrapped.
    /// Called when DECAWM causes overflow: the line's content continues on the next row.
    #[inline]
    fn mark_cursor_line_wrapped(&mut self) {
        let row = self.cursor.row;
        if let Some(line) = self.lines.get_mut(row) {
            line.wrapped = true;
        }
    }

    /// Clamp `cursor.col` to the last column and set `pending_wrap` if DECAWM is active.
    /// Called after placing a cell that may have pushed the cursor to or past the right margin.
    #[inline]
    fn clamp_cursor_col_with_pending_wrap(&mut self, auto_wrap: bool) {
        let cols = usize::from(self.cols);
        if self.cursor.col >= cols {
            self.cursor.col = cols.saturating_sub(1);
            if auto_wrap {
                self.cursor.pending_wrap = true;
            }
        }
    }

    /// Wrap the cursor to the next line and mark the current row as soft-wrapped.
    #[inline]
    fn wrap_to_next_line(&mut self, bg: Color, is_primary: bool) {
        self.mark_cursor_line_wrapped();
        self.cursor.col = 0;
        self.line_feed_impl(bg, is_primary);
    }

    /// Consume a deferred wrap from the previous printable cell.
    ///
    /// Returns `true` when the deferred wrap actually advanced to the next line.
    #[inline]
    fn consume_pending_wrap(&mut self, bg: Color, is_primary: bool, auto_wrap: bool) -> bool {
        if !self.cursor.pending_wrap {
            return false;
        }

        self.cursor.pending_wrap = false;
        if auto_wrap {
            self.wrap_to_next_line(bg, is_primary);
            return true;
        }

        false
    }

    /// Write a printable cell and keep the row dirty state in sync.
    #[inline]
    fn place_printed_cell(&mut self, row: usize, col: usize, cell: Cell, width: usize) {
        if let Some(line) = self.lines.get_mut(row) {
            line.update_cell_with(col, cell);
            self.dirty_set.insert(row);
            if width > 1 {
                if let Some(next_col) = col.checked_add(1) {
                    if next_col < usize::from(self.cols) {
                        line.update_cell_with(
                            next_col,
                            Cell {
                                width: CellWidth::Wide,
                                ..Cell::default()
                            },
                        );
                    }
                }
            }
        }
    }

    /// Advance the cursor after printing and apply DECAWM clamping.
    #[inline]
    fn advance_print_cursor(&mut self, width: usize, auto_wrap: bool) {
        self.cursor.col = self.cursor.col.saturating_add(width);
        self.clamp_cursor_col_with_pending_wrap(auto_wrap);
    }

    /// Line feed (LF): advances cursor down one row, scrolling up if at the bottom of the scroll region.
    /// Clears pending wrap.  Dispatches to the active screen.
    #[inline]
    pub fn line_feed(&mut self, bg: Color) {
        let is_primary = !self.is_alternate_active;
        self.with_active_screen_mut(|screen| {
            screen.line_feed_impl(bg, is_primary);
        });
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
        screen.consume_pending_wrap(attrs.background, is_primary, auto_wrap);

        let row = screen.cursor.row;
        let col = screen.cursor.col;

        // Determine character width — ASCII fast-path avoids the Unicode lookup.
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

        if col
            .checked_add(width)
            .is_some_and(|end_col| end_col <= usize::from(screen.cols))
        {
            // Character fits on the current line.
            screen.place_printed_cell(
                row,
                col,
                Cell::with_char_and_width(c, attrs, cell_width),
                width,
            );
            screen.advance_print_cursor(width, auto_wrap);
        } else {
            // Character doesn't fit (wide char at last column) — wrap to next line.
            if auto_wrap {
                screen.wrap_to_next_line(attrs.background, is_primary);
            }
            if width <= usize::from(screen.cols) {
                let new_row = screen.cursor.row;
                screen.place_printed_cell(
                    new_row,
                    0,
                    Cell::with_char_and_width(c, attrs, cell_width),
                    width,
                );
                screen.advance_print_cursor(width, auto_wrap);
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
    /// The run is processed in **row-sized chunks**: for each chunk the
    /// pending-wrap check, `lines.get_mut(row)` lookup, cursor advance, and
    /// DECAWM clamp run once instead of once per byte, and the cell writes
    /// iterate a checked sub-slice (`cells[col..col + chunk_len]`) so the
    /// per-byte indexing bounds check disappears.  An 80-column line of
    /// streamed output thus pays 1 wrap check + 1 cursor advance instead
    /// of 80 of each.
    ///
    /// The `PrintableAsciiRun` type ensures all bytes are in the range
    /// 0x20..=0x7E before this fast path can be called.
    /// This method must only be called when the VTE parser is in Ground state.
    #[inline]
    pub(crate) fn print_ascii_run(
        &mut self,
        run: PrintableAsciiRun<'_>,
        attrs: SgrAttributes,
        auto_wrap: bool,
    ) {
        if run.is_empty() {
            return;
        }
        let mut bytes = run.as_bytes();

        // Pre-compute before borrowing self through active_screen_mut()
        let is_primary = !self.is_alternate_active;
        let cols = usize::from(self.cols);

        // Hoist active_screen_mut() outside the loop.
        let Some(screen) = self.active_screen_mut() else {
            return;
        };

        // Track the last row we marked dirty so a row is marked at most once
        // per run: dirty_set.insert + version bump are idempotent per encode
        // cycle, so the first changed cell on a row suffices.
        let mut last_marked_dirty_row = usize::MAX;

        while !bytes.is_empty() {
            // Handle the deferred wrap from the previous chunk (or a previous
            // print).  Fires at most once per row chunk instead of per byte.
            if screen.consume_pending_wrap(attrs.background, is_primary, auto_wrap) {
                // Row changed by line_feed — or scrolled, reusing the same
                // bottom-row index — so allow dirty-mark on the new row.
                last_marked_dirty_row = usize::MAX;
            }

            let row = screen.cursor.row;
            let col = screen.cursor.col;
            if col >= cols {
                // Unreachable: clamp keeps col < cols.  Defensive bail-out
                // rather than a panic in the streaming hot path.
                return;
            }

            // Largest prefix that fits on the current row.  With DECAWM off
            // the cursor re-clamps to the last column, so the tail degrades
            // to 1-byte chunks overwriting the last cell — matching the
            // former per-byte loop's behaviour.
            let chunk_len = bytes.len().min(cols - col);
            let (chunk, rest) = bytes.split_at(chunk_len);
            bytes = rest;

            if let Some(line) = screen.lines.get_mut(row) {
                let mut changed = false;
                for (cell, &byte) in line.cells[col..col + chunk_len].iter_mut().zip(chunk) {
                    // Direct byte comparison: avoid encode_utf8 + str compare
                    // overhead.  Bind the byte slice once to share the
                    // fat-pointer load across both .len() and [0] accesses.
                    let gb = cell.grapheme.as_bytes();
                    let grapheme_matches = gb.len() == 1 && gb[0] == byte;
                    if !grapheme_matches
                        || cell.width != CellWidth::Half
                        || cell.attrs != attrs
                        || cell.extras.is_some()
                    {
                        if !grapheme_matches {
                            let mut buf = [0; 4];
                            let s = char::from(byte).encode_utf8(&mut buf);
                            cell.grapheme = CompactString::new(s);
                        }
                        cell.attrs = attrs;
                        cell.width = CellWidth::Half;
                        cell.extras = None;
                        changed = true;
                    }
                }
                if changed && row != last_marked_dirty_row {
                    line.mark_dirty_and_bump();
                    screen.dirty_set.insert(row);
                    last_marked_dirty_row = row;
                }
            }

            // One cursor advance + DECAWM clamp per chunk (was per byte).
            screen.advance_print_cursor(chunk_len, auto_wrap);
        }
    }
}

#[cfg(test)]
#[path = "cursor/tests.rs"]
mod tests;
