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
        }
    }

    /// Flush the VTE print buffer — sends any buffered ASCII bytes to
    /// `Screen::print_ascii_run()` in a single batch.
    ///
    /// Called automatically before any non-print VTE callback, after a
    /// non-ASCII `print()`, and after `advance()` returns.
    #[inline]
    pub(crate) fn flush_print_buf(&mut self) {
        if !self.print_buf.is_empty() {
            self.screen.print_ascii_run(
                &self.print_buf,
                self.current_attrs,
                self.dec_modes.auto_wrap,
            );
            self.print_buf.clear();
        }
    }

    /// Advance the VTE parser with input bytes
    ///
    /// Delegates to `parser::apc::advance_with_apc` which runs the hybrid APC
    /// pre-scanner for Kitty Graphics and then the VTE parser for all other sequences.
    pub fn advance(&mut self, bytes: &[u8]) {
        parser::apc::advance_with_apc(self, bytes);
    }

    /// Resize the terminal screen
    pub fn resize(&mut self, rows: u16, cols: u16) {
        self.screen.resize(rows, cols);
        self.tab_stops.resize(cols as usize);
    }

    /// Save cursor position and current SGR attributes (DECSC - ESC 7)
    pub fn save_cursor(&mut self) {
        self.saved_cursor = Some(*self.screen.cursor());
        self.saved_attrs = Some(self.current_attrs);
    }

    /// Restore cursor position and SGR attributes (DECRC - ESC 8)
    pub fn restore_cursor(&mut self) {
        if let Some(cursor) = self.saved_cursor.take() {
            self.screen.move_cursor(cursor.row, cursor.col);
        }
        if let Some(attrs) = self.saved_attrs.take() {
            self.current_attrs = attrs;
        }
    }

    // === Public accessors for integration tests ===
    // Note: current_bold/italic/underline expose internal SGR state for testing.
    // These should not be used in production code paths.

    /// Get the cursor row (0-indexed), using the active screen (primary or alternate)
    #[must_use]
    pub fn cursor_row(&self) -> usize {
        self.screen.cursor().row
    }

    /// Get the cursor column (0-indexed), using the active screen (primary or alternate)
    #[must_use]
    pub fn cursor_col(&self) -> usize {
        self.screen.cursor().col
    }

    /// Get the number of rows in the terminal screen
    #[must_use]
    pub const fn rows(&self) -> u16 {
        self.screen.rows()
    }

    /// Get the number of columns in the terminal screen
    #[must_use]
    pub const fn cols(&self) -> u16 {
        self.screen.cols()
    }

    /// Get whether the cursor is visible (DECTCEM state)
    #[must_use]
    pub const fn cursor_visible(&self) -> bool {
        self.dec_modes.cursor_visible
    }

    /// Get whether application cursor keys mode is active (DECCKM)
    #[must_use]
    pub const fn app_cursor_keys(&self) -> bool {
        self.dec_modes.app_cursor_keys
    }

    /// Get whether bracketed paste mode is active (mode 2004)
    #[must_use]
    pub const fn bracketed_paste(&self) -> bool {
        self.dec_modes.bracketed_paste
    }

    /// Get whether the alternate screen buffer is currently active
    #[must_use]
    pub const fn is_alternate_screen_active(&self) -> bool {
        self.screen.is_alternate_screen_active()
    }

    /// Get whether bold SGR attribute is currently set
    #[must_use]
    pub const fn current_bold(&self) -> bool {
        self.current_attrs
            .flags
            .contains(types::cell::SgrFlags::BOLD)
    }

    /// Get whether italic SGR attribute is currently set
    #[must_use]
    pub const fn current_italic(&self) -> bool {
        self.current_attrs
            .flags
            .contains(types::cell::SgrFlags::ITALIC)
    }

    /// Get whether underline SGR attribute is currently set
    #[must_use]
    pub fn current_underline(&self) -> bool {
        self.current_attrs.underline()
    }

    /// Get a cell from the screen at the given (row, col) position
    #[must_use]
    pub fn get_cell(&self, row: usize, col: usize) -> Option<&types::cell::Cell> {
        self.screen.get_cell(row, col)
    }

    /// Get the number of lines currently in the scrollback buffer
    #[must_use]
    pub const fn scrollback_line_count(&self) -> usize {
        self.screen.scrollback_line_count
    }

    /// Get scrollback lines as cell characters; most recent line first.
    /// Each inner Vec is the characters of one scrolled-off line.
    #[must_use]
    pub fn scrollback_chars(&self, max_lines: usize) -> Vec<Vec<char>> {
        self.screen
            .get_scrollback_lines(max_lines)
            .into_iter()
            .map(|line| {
                line.cells
                    .iter()
                    .map(super::types::cell::Cell::char)
                    .collect()
            })
            .collect()
    }

    /// Get current DEC modes state (read-only reference)
    #[must_use]
    pub const fn dec_modes(&self) -> &parser::dec_private::DecModes {
        &self.dec_modes
    }

    /// Get current SGR attributes (read-only reference)
    #[must_use]
    pub const fn current_attrs(&self) -> &types::cell::SgrAttributes {
        &self.current_attrs
    }

    /// Get current OSC data (read-only reference)
    #[must_use]
    pub const fn osc_data(&self) -> &types::osc::OscData {
        &self.osc_data
    }

    /// Returns whether the 256-color palette has been updated since the last render (OSC 4).
    #[inline]
    #[must_use]
    pub const fn palette_dirty(&self) -> bool {
        self.osc_data.palette_dirty
    }

    /// Returns whether the default fg/bg/cursor colors have changed since the last render (OSC 10/11/12).
    #[inline]
    #[must_use]
    pub const fn default_colors_dirty(&self) -> bool {
        self.osc_data.default_colors_dirty
    }

    /// Get the current window title
    #[must_use]
    pub fn title(&self) -> &str {
        &self.meta.title
    }

    /// Get whether the title has been updated and not yet read
    #[must_use]
    pub const fn title_dirty(&self) -> bool {
        self.meta.title_dirty
    }

    /// Get pending terminal responses (for DA1, DA2, Kitty keyboard, etc.)
    #[must_use]
    pub fn pending_responses(&self) -> &[Vec<u8>] {
        &self.meta.pending_responses
    }

    /// Get current foreground color
    #[must_use]
    pub const fn current_foreground(&self) -> &types::Color {
        &self.current_attrs.foreground
    }

    /// Soft terminal reset (DECSTR - CSI ! p)
    ///
    /// Resets modes but preserves screen content and scrollback.
    pub fn soft_reset(&mut self) {
        // Reset cursor keys to normal mode
        self.dec_modes.app_cursor_keys = false;
        // Reset origin mode
        self.dec_modes.origin_mode = false;
        // Auto-wrap back on
        self.dec_modes.auto_wrap = true;
        // Cursor visible
        self.dec_modes.cursor_visible = true;
        // Reset SGR attributes
        self.current_attrs = types::cell::SgrAttributes::default();
        // Reset scroll region to full screen
        let rows = self.screen.rows() as usize;
        self.screen.set_scroll_region(0, rows);
        // Move cursor to home
        self.screen.move_cursor(0, 0);
        // Reset cursor shape
        self.dec_modes.cursor_shape = types::cursor::CursorShape::BlinkingBlock;
        // Reset Kitty keyboard protocol flags
        self.dec_modes.keyboard_flags = 0;
        self.dec_modes.keyboard_flags_stack.clear();
        // Clear alt-screen SGR snapshot so a subsequent ?1049l cannot restore stale attrs
        self.saved_primary_attrs = None;
        // Note: does NOT clear scrollback, does NOT switch screens, does NOT clear screen
    }

    /// Full terminal reset (RIS - ESC c)
    pub fn reset(&mut self) {
        // Switch back to primary screen if alternate is active
        if self.screen.is_alternate_screen_active() {
            self.screen.switch_to_primary();
        }
        // Reset cursor to home position
        self.screen.move_cursor(0, 0);
        // Reset SGR attributes to defaults
        self.current_attrs = types::cell::SgrAttributes::default();
        // Clear saved cursor state
        self.saved_cursor = None;
        self.saved_attrs = None;
        self.saved_primary_attrs = None;
        // Reset DEC private modes to correct terminal defaults
        self.dec_modes = DecModes::new();
        // Reset tab stops to every 8th column
        self.tab_stops = TabStops::new(self.screen.cols() as usize);
        // Clear title state
        self.meta.title = String::new();
        self.meta.title_dirty = false;
        // Clear pending bell
        self.meta.bell_pending = false;
        // Clear pending responses
        self.meta.pending_responses.clear();
        // Clear Kitty Graphics state
        self.kitty.apc_state = ApcScanState::Idle;
        self.kitty.apc_buf.clear();
        self.kitty.kitty_chunk = None;
        self.meta.dcs_state = parser::dcs::DcsState::Idle;
        self.kitty.pending_image_notifications.clear();
        // Clear OSC data
        self.osc_data = types::osc::OscData::default();
        // Reset VTE parser to fresh Ground state
        self.parser = Some(vte::Parser::new());
        self.parser_in_ground = true;
        // Clear any buffered print characters
        self.print_buf.clear();
    }
}
