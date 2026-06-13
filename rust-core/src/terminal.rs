//! `TerminalCore` — integrates VTE parser, virtual screen, and PTY state.

use crate::grid::screen::Screen;
use crate::parser;
use crate::parser::apc::ApcScanState;
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
    pub(crate) print_buf: Vec<u8>,
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
            tab_stops: TabStops::new(cols as usize),
            saved_cursor: None,
            saved_attrs: None,
            saved_primary_attrs: None,
            osc_data: types::osc::OscData::default(),
            kitty: types::KittyState::default(),
            meta: types::TerminalMeta::default(),
            parser_in_ground: true,
            vte_callback_count: 0,
            vte_last_ground: true,
            print_buf: Vec::with_capacity(256),
            g0_charset: types::charset::CharsetType::Ascii,
            g1_charset: types::charset::CharsetType::Ascii,
            gl_is_g1: false,
            saved_g0_charset: None,
            saved_g1_charset: None,
            saved_gl_is_g1: None,
            last_printed_char: None,
            sgr_stack: Vec::new(),
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
                &self.print_buf,
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
        let cols = self.screen.cols() as usize;
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
        self.tab_stops.resize(cols as usize);
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

include!("terminal_accessors.rs");

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
