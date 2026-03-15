//! Kuro Terminal Emulator Core
//!
//! This library provides the core functionality for the Kuro terminal emulator,
//! including VTE parsing, virtual screen management, PTY handling, and Emacs
//! dynamic module FFI bindings.

#![warn(missing_docs)]
#![warn(clippy::all)]

pub mod error;
pub mod ffi;
pub mod grid;
pub mod parser;
pub mod pty;
pub mod types;

#[cfg(test)]
mod vttest;

use emacs::Env;
use parser::dec_private::DecModes;
use parser::tabs::TabStops;

emacs::plugin_is_GPL_compatible!();

#[emacs::module(
    name = "kuro-core",
    defun_prefix = "",
    separator = "",
    mod_in_name = false
)]
fn init(env: &Env) -> emacs::Result<()> {
    ffi::bridge::module_init(env)
}

// Re-exports for convenience
pub use error::KuroError;
pub use grid::screen::Screen;
pub use types::{cell::Cell, cell::UnderlineStyle, color::Color, cursor::CursorShape};

// Re-export FFI abstraction layer
pub use ffi::{EmacsModuleFFI, KuroFFI, RawFFI, TerminalSession, TERMINAL_SESSION};

/// Result type for Kuro operations
pub type Result<T> = std::result::Result<T, KuroError>;

// Re-export ApcScanState from the dedicated parser module
pub use parser::apc::ApcScanState;

/// Terminal core state, integrating VTE parser, screen, and PTY
pub struct TerminalCore {
    /// Virtual screen buffer
    pub(crate) screen: Screen,
    /// Current SGR attributes
    pub(crate) current_attrs: types::cell::SgrAttributes,
    /// VTE parser (stored to maintain state across advance calls)
    pub(crate) parser: vte::Parser,
    /// DEC private mode state
    pub(crate) dec_modes: DecModes,
    /// Tab stop configuration
    pub(crate) tab_stops: TabStops,
    /// Window title set via OSC 0 or OSC 2
    pub(crate) title: String,
    /// Whether the title has been updated and not yet read
    pub(crate) title_dirty: bool,
    /// Whether a BEL character has been received and not yet cleared
    pub(crate) bell_pending: bool,
    /// Queued responses to write back to the PTY (e.g. DA1/DA2 replies)
    pub(crate) pending_responses: Vec<Vec<u8>>,
    /// Saved cursor position for DECSC/DECRC (ESC 7 / ESC 8)
    pub(crate) saved_cursor: Option<types::Cursor>,
    /// Saved SGR attributes for DECSC/DECRC (ESC 7 / ESC 8)
    pub(crate) saved_attrs: Option<types::cell::SgrAttributes>,
    /// APC byte-stream state machine for Kitty Graphics pre-scanning
    pub(crate) apc_state: ApcScanState,
    /// Accumulation buffer for the current APC payload (cleared on each new APC)
    pub(crate) apc_buf: Vec<u8>,
    /// Accumulated chunk state for multi-chunk Kitty image transfers (m=1)
    pub(crate) kitty_chunk: Option<parser::kitty::KittyChunkState>,
    /// DCS (Device Control String) sequence state
    pub(crate) dcs_state: parser::dcs::DcsState,
    /// Image placement notifications waiting to be sent to Elisp
    pub(crate) pending_image_notifications: Vec<grid::screen::ImageNotification>,
    /// OSC data storage (CWD, hyperlinks, clipboard, prompt marks, etc.)
    pub(crate) osc_data: types::osc::OscData,
}

impl TerminalCore {
    /// Create a new terminal core with the specified dimensions
    pub fn new(rows: u16, cols: u16) -> Self {
        Self {
            screen: Screen::new(rows, cols),
            current_attrs: Default::default(),
            parser: vte::Parser::new(),
            dec_modes: DecModes::new(),
            tab_stops: TabStops::new(cols as usize),
            title: String::new(),
            title_dirty: false,
            bell_pending: false,
            pending_responses: Vec::new(),
            saved_cursor: None,
            saved_attrs: None,
            apc_state: ApcScanState::Idle,
            apc_buf: Vec::new(),
            kitty_chunk: None,
            dcs_state: Default::default(),
            pending_image_notifications: Vec::new(),
            osc_data: Default::default(),
        }
    }

    /// Advance the VTE parser with input bytes
    ///
    /// Delegates to [`parser::apc::advance_with_apc`] which runs the hybrid APC
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
    pub fn cursor_row(&self) -> usize {
        self.screen.cursor().row
    }

    /// Get the cursor column (0-indexed), using the active screen (primary or alternate)
    pub fn cursor_col(&self) -> usize {
        self.screen.cursor().col
    }

    /// Get the number of rows in the terminal screen
    pub fn rows(&self) -> u16 {
        self.screen.rows()
    }

    /// Get the number of columns in the terminal screen
    pub fn cols(&self) -> u16 {
        self.screen.cols()
    }

    /// Get whether the cursor is visible (DECTCEM state)
    pub fn cursor_visible(&self) -> bool {
        self.dec_modes.cursor_visible
    }

    /// Get whether application cursor keys mode is active (DECCKM)
    pub fn app_cursor_keys(&self) -> bool {
        self.dec_modes.app_cursor_keys
    }

    /// Get whether bracketed paste mode is active (mode 2004)
    pub fn bracketed_paste(&self) -> bool {
        self.dec_modes.bracketed_paste
    }

    /// Get whether the alternate screen buffer is currently active
    pub fn is_alternate_screen_active(&self) -> bool {
        self.screen.is_alternate_screen_active()
    }

    /// Get whether bold SGR attribute is currently set
    pub fn current_bold(&self) -> bool {
        self.current_attrs.bold
    }

    /// Get whether italic SGR attribute is currently set
    pub fn current_italic(&self) -> bool {
        self.current_attrs.italic
    }

    /// Get whether underline SGR attribute is currently set
    pub fn current_underline(&self) -> bool {
        self.current_attrs.underline()
    }

    /// Get a cell from the screen at the given (row, col) position
    pub fn get_cell(&self, row: usize, col: usize) -> Option<&types::cell::Cell> {
        self.screen.get_cell(row, col)
    }

    /// Get the number of lines currently in the scrollback buffer
    pub fn scrollback_line_count(&self) -> usize {
        self.screen.scrollback_line_count
    }

    /// Get scrollback lines as cell characters; most recent line first.
    /// Each inner Vec is the characters of one scrolled-off line.
    pub fn scrollback_chars(&self, max_lines: usize) -> Vec<Vec<char>> {
        self.screen
            .get_scrollback_lines(max_lines)
            .into_iter()
            .map(|line| line.cells.iter().map(|c| c.char()).collect())
            .collect()
    }

    /// Get current DEC modes state (read-only reference)
    pub fn dec_modes(&self) -> &parser::dec_private::DecModes {
        &self.dec_modes
    }

    /// Get current SGR attributes (read-only reference)
    pub fn current_attrs(&self) -> &types::cell::SgrAttributes {
        &self.current_attrs
    }

    /// Get current OSC data (read-only reference)
    pub fn osc_data(&self) -> &types::osc::OscData {
        &self.osc_data
    }

    /// Get the current window title
    pub fn title(&self) -> &str {
        &self.title
    }

    /// Get whether the title has been updated and not yet read
    pub fn title_dirty(&self) -> bool {
        self.title_dirty
    }

    /// Get pending terminal responses (for DA1, DA2, Kitty keyboard, etc.)
    pub fn pending_responses(&self) -> &[Vec<u8>] {
        &self.pending_responses
    }

    /// Get current foreground color
    pub fn current_foreground(&self) -> &types::Color {
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
        // Reset DEC private modes to correct terminal defaults
        self.dec_modes = DecModes::new();
        // Reset tab stops to every 8th column
        self.tab_stops = TabStops::new(self.screen.cols() as usize);
        // Clear title state
        self.title = String::new();
        self.title_dirty = false;
        // Clear pending bell
        self.bell_pending = false;
        // Clear pending responses
        self.pending_responses.clear();
        // Clear Kitty Graphics state
        self.apc_state = ApcScanState::Idle;
        self.apc_buf.clear();
        self.kitty_chunk = None;
        self.dcs_state = parser::dcs::DcsState::Idle;
        self.pending_image_notifications.clear();
        // Clear OSC data
        self.osc_data = Default::default();
    }
}

#[cfg(test)]
mod tests;
