//! `TerminalCore` — integrates VTE parser, virtual screen, and PTY state.

use crate::grid::screen::{PrintableAsciiBuffer, Screen};
use crate::parser;
use crate::parser::dec_private::DecModes;
use crate::parser::tabs::TabStops;
use crate::types;

/// Terminal core state, integrating VTE parser, screen, and PTY
pub struct TerminalCore {
    /// Virtual screen buffer
    pub(crate) screen: Screen,
    /// Current SGR attributes
    pub(crate) current_attrs: types::cell::SgrAttributes,
    /// VTE parser (stored to maintain state across advance calls).
    ///
    /// Wrapped in `Option` so that `advance_with_apc` can temporarily `take()`
    /// the parser without allocating a placeholder — `Option::take()` writes
    /// `None` (a single discriminant byte) instead of `vte::Parser::new()`
    /// which would zero ~400 bytes of internal state on every PTY read.
    pub(crate) parser: Option<vte::Parser>,
    /// DEC private mode state
    pub(crate) dec_modes: DecModes,
    /// Tab stop configuration
    pub(crate) tab_stops: TabStops,
    /// Saved cursor position for DECSC/DECRC (ESC 7 / ESC 8)
    pub(crate) saved_cursor: Option<types::Cursor>,
    /// Saved SGR attributes for DECSC/DECRC (ESC 7 / ESC 8)
    pub(crate) saved_attrs: Option<types::cell::SgrAttributes>,
    /// Saved primary screen SGR attributes (for DEC mode 1049 restore)
    pub(crate) saved_primary_attrs: Option<types::cell::SgrAttributes>,
    /// OSC data storage (CWD, hyperlinks, clipboard, prompt marks, etc.)
    pub(crate) osc_data: types::osc::OscData,
    /// Kitty Graphics Protocol state
    pub(crate) kitty: types::KittyState,
    /// Terminal metadata and pending-response state
    pub(crate) meta: types::TerminalMeta,
    /// Whether the VTE parser is known to be in the Ground state.
    /// Used by the ASCII fast-path in `advance_with_apc` to determine
    /// if printable bytes can bypass VTE.
    pub(crate) parser_in_ground: bool,
    /// Number of VTE Perform callbacks fired during current `advance()` call.
    /// Zero means VTE processed transitional bytes with no dispatch.
    pub(crate) vte_callback_count: u32,
    /// Whether the last VTE callback was one that returns to Ground state.
    pub(crate) vte_last_ground: bool,
    /// Buffer for batching ASCII characters from VTE `print()` callbacks.
    /// Flushed via `Screen::print_ascii_run()` when a non-print callback
    /// fires, a non-ASCII char is printed, or VTE `advance()` returns.
    pub(crate) print_buf: PrintableAsciiBuffer,
    /// G0 character set designation (ESC ( 0 / ESC ( B)
    pub(crate) g0_charset: types::charset::CharsetType,
    /// G1 character set designation (ESC ) 0 / ESC ) B)
    pub(crate) g1_charset: types::charset::CharsetType,
    /// Whether GL points to G1 (SO/SI shift state). false = G0, true = G1
    pub(crate) gl_is_g1: bool,
    /// Saved G0 charset for DECSC/DECRC (ESC 7 / ESC 8)
    saved_g0_charset: Option<types::charset::CharsetType>,
    /// Saved G1 charset for DECSC/DECRC (ESC 7 / ESC 8)
    saved_g1_charset: Option<types::charset::CharsetType>,
    /// Saved GL shift state for DECSC/DECRC (ESC 7 / ESC 8)
    saved_gl_is_g1: Option<bool>,
    /// Last printed (non-combining) character, tracked for REP (CSI Ps b).
    pub(crate) last_printed_char: Option<char>,
    /// SGR attributes stack for XTPUSHSGR (CSI # {) / XTPOPSGR (CSI # }).
    pub(crate) sgr_stack: Vec<types::cell::SgrAttributes>,
    /// Grapheme-clustering (DEC mode 2027) state: a ZWJ (U+200D) was just
    /// attached to the previous cell, so the NEXT printable char joins that
    /// cluster instead of advancing the cursor. Only consulted when
    /// `dec_modes.grapheme_clustering` is set; reset on any control/cursor/edit.
    pub(crate) grapheme_join_pending: bool,
    /// Grapheme-clustering (DEC mode 2027) state: a lone regional-indicator
    /// (U+1F1E6..=U+1F1FF) is pending in the previous cell, awaiting a second
    /// RI to form a flag. Only consulted when `dec_modes.grapheme_clustering`
    /// is set; reset on any non-RI print / control / cursor move / edit.
    pub(crate) regional_indicator_pending: bool,
    /// Transient Kitty text-sizing (OSC 66) sizing applied to cells printed
    /// during an OSC 66 payload. Set before feeding the payload chars through
    /// the print path and cleared immediately after, so ordinary prints never
    /// pay any cost. `None` (the overwhelming default) means "normal size".
    pub(crate) active_text_size: Option<types::cell::TextSize>,
}

impl TerminalCore {
    /// Create a new terminal core with the specified dimensions
    #[must_use]
    pub fn new(rows: u16, cols: u16) -> Self {
        Self {
            screen: Screen::new(rows, cols),
            current_attrs: types::cell::SgrAttributes::default(),
            parser: Some(vte::Parser::new()),
            dec_modes: DecModes::new(),
            tab_stops: TabStops::new(usize::from(cols)),
            saved_cursor: None,
            saved_attrs: None,
            saved_primary_attrs: None,
            osc_data: types::osc::OscData::default(),
            kitty: types::KittyState::default(),
            meta: types::TerminalMeta::default(),
            parser_in_ground: true,
            vte_callback_count: 0,
            vte_last_ground: true,
            print_buf: PrintableAsciiBuffer::with_capacity(256),
            g0_charset: types::charset::CharsetType::Ascii,
            g1_charset: types::charset::CharsetType::Ascii,
            gl_is_g1: false,
            saved_g0_charset: None,
            saved_g1_charset: None,
            saved_gl_is_g1: None,
            last_printed_char: None,
            sgr_stack: Vec::new(),
            grapheme_join_pending: false,
            regional_indicator_pending: false,
            active_text_size: None,
        }
    }

    /// Push an in-band resize report (`CSI 48 ; rows ; cols ; 0 ; 0 t`) to
    /// `meta.pending_responses`.
    ///
    /// Called when DEC mode 2048 (resize-in-band) is enabled or re-enabled
    /// so the receiving application learns the current size immediately.
    /// Pixel dimensions are reported as 0 (cell-based core has no pixel geometry).
    #[inline]
    pub(crate) fn push_in_band_resize_report(&mut self) {
        let rows = self.screen.rows();
        let cols = self.screen.cols();
        let response = format!("\x1b[48;{rows};{cols};0;0t");
        self.meta.pending_responses.push(response.into_bytes());
    }

    /// Flush the VTE print buffer — sends any buffered ASCII bytes to
    /// `Screen::print_ascii_run()` in a single batch.
    ///
    /// Called automatically before any non-print VTE callback, after a
    /// non-ASCII `print()`, and after `advance()` returns.
    #[inline]
    pub(crate) fn flush_print_buf(&mut self) {
        if !self.print_buf.is_empty() {
            let len = self.print_buf.len();
            self.screen.print_ascii_run(
                self.print_buf.as_run(),
                self.current_attrs,
                self.dec_modes.auto_wrap,
            );
            if self.osc_data.hyperlink.uri.is_some() {
                self.stamp_hyperlink_on_last_n_cells(len);
            }
            self.print_buf.clear();
        }
    }

    /// Stamp the active hyperlink URI on the `n` most recently printed cells.
    ///
    /// Walks backward from the current cursor position, handling line wraps.
    /// Called after `print_ascii_run()` when a hyperlink is active.
    /// No-op if `n == 0` or no hyperlink URI is set.
    #[inline]
    pub(crate) fn stamp_hyperlink_on_last_n_cells(&mut self, n: usize) {
        if n == 0 {
            return;
        }
        let uri = match &self.osc_data.hyperlink.uri {
            Some(u) => u.clone(),
            None => return,
        };
        let cursor = *self.screen.cursor();
        let cols = usize::from(self.screen.cols());
        let mut remaining = n;
        let mut row = cursor.row;
        let mut col = cursor.col;

        // If pending_wrap, the last char written is at cursor.col (cursor
        // didn't advance past it — it's "stuck" at the last column).
        if cursor.pending_wrap {
            if let Some(cell) = self.screen.get_cell_mut(row, col) {
                cell.set_hyperlink_id(Some(uri.clone()));
            }
            remaining -= 1;
        }

        // Walk backward from cursor position
        while remaining > 0 {
            if col == 0 {
                if row == 0 {
                    break;
                }
                row -= 1;
                col = cols;
            }
            col -= 1;
            if let Some(cell) = self.screen.get_cell_mut(row, col) {
                cell.set_hyperlink_id(Some(uri.clone()));
            }
            remaining -= 1;
        }
    }

    /// Print an OSC 66 text-sizing payload, stamping each printed cell with the
    /// given [`types::cell::TextSize`].
    ///
    /// The payload chars are fed through the normal `Screen::print` path so that
    /// cursor advance, auto-wrap, and wide-character handling all behave exactly
    /// as for ordinary text.  After each char is printed the resulting cell (and
    /// the wide placeholder, if any) is tagged with `ts` — mirroring the
    /// hyperlink stamping strategy.  A default (`is_default`) sizing is a no-op
    /// beyond ordinary printing, so it never allocates `CellExtras`.
    ///
    /// `payload` is the already-decoded, UTF-8 text (capped to 4096 bytes by the
    /// caller).
    pub(crate) fn print_text_sized_payload(&mut self, payload: &str, ts: types::cell::TextSize) {
        // Flush any pending ASCII run so buffered chars are not retroactively
        // attributed to this text-sizing region.
        self.flush_print_buf();

        let stamp = !ts.is_default();
        self.active_text_size = Some(ts);

        for c in payload.chars() {
            if c.is_control() {
                // Control chars inside the payload are ignored for sizing; they
                // would not produce a printable cell anyway.
                continue;
            }
            let pre_cursor = *self.screen.cursor();
            let width = unicode_width::UnicodeWidthChar::width(c).unwrap_or(1);
            self.screen
                .print(c, self.current_attrs, self.dec_modes.auto_wrap);

            if stamp {
                let cursor_after = *self.screen.cursor();
                let (write_row, write_col) = text_size_write_position(pre_cursor, cursor_after);
                if let Some(cell) = self.screen.get_cell_mut(write_row, write_col) {
                    cell.set_text_size(Some(ts));
                }
                if width > 1 {
                    if let Some(cell) = self.screen.get_cell_mut(write_row, write_col + 1) {
                        cell.set_text_size(Some(ts));
                    }
                }
                // `get_cell_mut` mutates the cell in place without bumping the
                // line version (and an identical re-print would have short-
                // circuited `update_cell_with`).  Force the row dirty + version
                // bump so a text-size-only change is never dropped by the dirty
                // pipeline's `line.version` skip.
                self.screen.mark_line_dirty_and_bump(write_row);
            }
        }

        self.active_text_size = None;
    }

    /// Get the currently active charset for GL (the "left" graphic set).
    #[inline]
    pub(crate) fn active_charset(&self) -> types::charset::CharsetType {
        if self.gl_is_g1 {
            self.g1_charset
        } else {
            self.g0_charset
        }
    }

    /// Advance the VTE parser with input bytes
    ///
    /// Delegates to `parser::apc::advance_with_apc` which runs the hybrid APC
    /// pre-scanner for Kitty Graphics and then the VTE parser for all other sequences.
    pub fn advance(&mut self, bytes: &[u8]) {
        parser::apc::advance_with_apc(self, bytes);
    }

    /// Resize the terminal screen.
    ///
    /// When DEC mode 2048 (in-band resize notifications) is active, emits a
    /// `CSI 48 ; rows ; cols ; 0 ; 0 t` report so the running application
    /// learns the new size without relying on SIGWINCH.
    pub fn resize(&mut self, rows: u16, cols: u16) {
        self.screen.resize(rows, cols);
        self.tab_stops.resize(usize::from(cols));
        if self.dec_modes.resize_in_band {
            self.push_in_band_resize_report();
        }
    }

    /// Save cursor position, SGR attributes, and charset state (DECSC - ESC 7)
    pub fn save_cursor(&mut self) {
        self.saved_cursor = Some(*self.screen.cursor());
        self.saved_attrs = Some(self.current_attrs);
        self.saved_g0_charset = Some(self.g0_charset);
        self.saved_g1_charset = Some(self.g1_charset);
        self.saved_gl_is_g1 = Some(self.gl_is_g1);
    }

    /// Restore cursor position, SGR attributes, and charset state (DECRC - ESC 8)
    pub fn restore_cursor(&mut self) {
        if let Some(cursor) = self.saved_cursor.take() {
            self.screen.move_cursor(cursor.row, cursor.col);
        }
        if let Some(attrs) = self.saved_attrs.take() {
            self.current_attrs = attrs;
        }
        if let Some(g0) = self.saved_g0_charset.take() {
            self.g0_charset = g0;
        }
        if let Some(g1) = self.saved_g1_charset.take() {
            self.g1_charset = g1;
        }
        if let Some(gl) = self.saved_gl_is_g1.take() {
            self.gl_is_g1 = gl;
        }
    }
}

/// Compute the (row, col) where the just-printed char landed, given the cursor
/// before and after the print and the screen width.
///
/// Mirrors `hyperlink_write_position` in `vte_handler.rs`: if the cursor wrapped
/// to a new row (or jumped backward on the same row via pending-wrap reset), the
/// char was written at column 0 of the new row; otherwise it sits at the
/// pre-print position.
#[inline]
fn text_size_write_position(
    pre_cursor: types::cursor::Cursor,
    cursor_after: types::cursor::Cursor,
) -> (usize, usize) {
    if cursor_after.row != pre_cursor.row || cursor_after.col < pre_cursor.col {
        // Wrapped: the char landed at column 0 of the new row. This holds for
        // BOTH a deferred wrap (`pending_wrap` was set by a prior char filling
        // the last column) AND an immediate wide-char wrap — in either case the
        // glyph is placed at (cursor_after.row, 0). The earlier `pending_wrap`
        // special case was wrong: it stamped the *previous* row's last cell,
        // corrupting that cell's sizing and dropping the wrapped char's stamp.
        (cursor_after.row, 0)
    } else {
        (pre_cursor.row, pre_cursor.col)
    }
}

#[path = "terminal_accessors.rs"]
mod accessors;

#[cfg(test)]
mod tests {
    /// Create a standard 24x80 `TerminalCore` for testing.
    fn make_term() -> super::TerminalCore {
        super::TerminalCore::new(24, 80)
    }

    mod apc;
    mod osc;
    mod regression;
    mod sgr;
    mod terminal;
}
