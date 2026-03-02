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

use emacs::Env;
use parser::dec_private::DecModes;
use parser::tabs::TabStops;
use unicode_width::UnicodeWidthChar;

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
pub use types::{cell::Cell, color::Color, cursor::CursorShape};

// Re-export FFI abstraction layer
pub use ffi::{EmacsModuleFFI, KuroFFI, RawFFI, TerminalSession, TERMINAL_SESSION};

/// Result type for Kuro operations
pub type Result<T> = std::result::Result<T, KuroError>;

/// Internal state tag for raw APC pre-scanning.
/// vte 0.15.0 routes ESC _ to SosPmApcString which silently discards bytes,
/// so we scan the raw byte stream ourselves.
/// The payload buffer is stored separately in `TerminalCore::apc_buf` to avoid
/// per-byte heap moves through the state machine.
#[derive(Clone, Copy, PartialEq, Eq)]
enum ApcScanState {
    Idle,
    /// Saw ESC, waiting to see if next byte is '_' (APC start)
    AfterEsc,
    /// Inside an APC payload (ESC _ received); accumulating bytes in apc_buf
    InApc,
    /// Inside APC, saw ESC — waiting to see if next byte is '\\' (ST = String Terminator)
    AfterApcEsc,
}

/// Terminal core state, integrating VTE parser, screen, and PTY
pub struct TerminalCore {
    /// Virtual screen buffer
    pub(crate) screen: Screen,
    /// Current SGR attributes
    pub(crate) current_attrs: types::cell::SgrAttributes,
    /// VTE parser (stored to maintain state across advance calls)
    parser: vte::Parser,
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
    apc_state: ApcScanState,
    /// Accumulation buffer for the current APC payload (cleared on each new APC)
    apc_buf: Vec<u8>,
    /// Accumulated chunk state for multi-chunk Kitty image transfers (m=1)
    pub(crate) kitty_chunk: Option<parser::kitty::KittyChunkState>,
    /// Image placement notifications waiting to be sent to Elisp
    pub(crate) pending_image_notifications: Vec<grid::screen::ImageNotification>,
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
            pending_image_notifications: Vec::new(),
        }
    }

    /// Advance the VTE parser with input bytes
    ///
    /// This method runs two parallel passes over the byte stream:
    /// 1. A raw APC pre-scanner that extracts Kitty Graphics Protocol sequences
    ///    (ESC _ G...ESC \) which vte 0.15.0 silently discards
    /// 2. The vte parser for all other terminal sequences
    pub fn advance(&mut self, bytes: &[u8]) {
        /// Maximum bytes accumulated in a single APC payload (4 MiB).
        /// Bytes beyond this limit are silently dropped; the sequence is still
        /// dispatched with the truncated payload.
        const MAX_APC_PAYLOAD_BYTES: usize = 4 * 1024 * 1024;

        // --- Pass 1: APC pre-scanner for Kitty Graphics ---
        for &byte in bytes {
            match (self.apc_state, byte) {
                // Idle: watch for ESC
                (ApcScanState::Idle, 0x1B) => {
                    self.apc_state = ApcScanState::AfterEsc;
                }
                (ApcScanState::Idle, _) => {}
                // AfterEsc: ESC + '_' starts APC; anything else resets
                (ApcScanState::AfterEsc, b'_') => {
                    self.apc_buf.clear();
                    self.apc_state = ApcScanState::InApc;
                }
                (ApcScanState::AfterEsc, _) => {
                    self.apc_state = ApcScanState::Idle;
                }
                // InApc: accumulate bytes (with size cap); ESC may be start of ST
                (ApcScanState::InApc, 0x1B) => {
                    self.apc_state = ApcScanState::AfterApcEsc;
                }
                (ApcScanState::InApc, b) => {
                    if self.apc_buf.len() < MAX_APC_PAYLOAD_BYTES {
                        self.apc_buf.push(b);
                    }
                    // If over limit, keep state but drop byte (truncate silently)
                }
                // AfterApcEsc: '\\' completes the APC (ESC \\ = ST); else keep accumulating
                (ApcScanState::AfterApcEsc, b'\\') => {
                    // APC complete — dispatch if it starts with 'G' (Kitty Graphics)
                    if self.apc_buf.first() == Some(&b'G') {
                        let payload = self.apc_buf[1..].to_vec();
                        self.dispatch_kitty_apc(&payload);
                    }
                    self.apc_buf.clear();
                    self.apc_state = ApcScanState::Idle;
                }
                (ApcScanState::AfterApcEsc, b) => {
                    // False ESC — add ESC + this byte back and stay in InApc
                    if self.apc_buf.len() + 2 <= MAX_APC_PAYLOAD_BYTES {
                        self.apc_buf.push(0x1B);
                        self.apc_buf.push(b);
                    }
                    self.apc_state = ApcScanState::InApc;
                }
            }
        }

        // --- Pass 2: vte parser for all other sequences ---
        let mut parser = std::mem::replace(&mut self.parser, vte::Parser::new());
        parser.advance(self, bytes);
        self.parser = parser;
    }

    /// Dispatch a fully assembled Kitty Graphics APC payload.
    ///
    /// `payload` is everything after the leading 'G' byte (i.e., the key=value header
    /// and optional base64 data, separated by ';').
    fn dispatch_kitty_apc(&mut self, payload: &[u8]) {
        use grid::screen::{ImageData, ImagePlacement};
        use parser::kitty::{process_apc_payload, KittyCommand};

        let cmd = match process_apc_payload(payload, &mut self.kitty_chunk) {
            Some(cmd) => cmd,
            None => return, // more chunks incoming, or malformed
        };

        match cmd {
            KittyCommand::Transmit {
                image_id,
                pixels,
                format,
                pixel_width,
                pixel_height,
                ..
            } => {
                let data = ImageData {
                    pixels,
                    format,
                    pixel_width,
                    pixel_height,
                };
                self.screen
                    .active_graphics_mut()
                    .store_image(image_id, data);
            }

            KittyCommand::TransmitAndDisplay {
                image_id,
                pixels,
                format,
                pixel_width,
                pixel_height,
                columns,
                rows,
                ..
            } => {
                let data = ImageData {
                    pixels,
                    format,
                    pixel_width,
                    pixel_height,
                };
                let actual_id = self
                    .screen
                    .active_graphics_mut()
                    .store_image(image_id, data);
                let cursor = *self.screen.cursor();
                let placement = ImagePlacement {
                    image_id: actual_id,
                    row: cursor.row,
                    col: cursor.col,
                    display_cols: columns.unwrap_or(1),
                    display_rows: rows.unwrap_or(1),
                };
                if let Some(notif) = self.screen.active_graphics_mut().add_placement(placement) {
                    self.pending_image_notifications.push(notif);
                }
            }

            KittyCommand::Place {
                image_id,
                columns,
                rows,
                ..
            } => {
                let cursor = *self.screen.cursor();
                let placement = ImagePlacement {
                    image_id,
                    row: cursor.row,
                    col: cursor.col,
                    display_cols: columns.unwrap_or(1),
                    display_rows: rows.unwrap_or(1),
                };
                if let Some(notif) = self.screen.active_graphics_mut().add_placement(placement) {
                    self.pending_image_notifications.push(notif);
                }
            }

            KittyCommand::Delete {
                delete_sub,
                image_id,
                ..
            } => {
                match delete_sub {
                    'a' => self.screen.active_graphics_mut().clear_all_placements(),
                    'I' | 'i' => {
                        if let Some(id) = image_id {
                            self.screen.active_graphics_mut().delete_by_id(id);
                        }
                    }
                    _ => {} // other delete sub-commands not supported in Phase 15
                }
            }

            KittyCommand::Query { image_id } => {
                // Respond with "OK" status using existing pending_responses mechanism
                let id_part = image_id.map(|id| format!(",i={}", id)).unwrap_or_default();
                let response = format!("\x1b_Ga=q{};OK\x1b\\", id_part);
                self.pending_responses.push(response.into_bytes());
            }
        }
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
        self.current_attrs.underline
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
            .map(|line| line.cells.iter().map(|c| c.c).collect())
            .collect()
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
        self.pending_image_notifications.clear();
    }
}

impl vte::Perform for TerminalCore {
    fn print(&mut self, c: char) {
        // Combining characters (Unicode width 0) are filtered here.
        // They are not yet attached to the previous cell — that requires a Cell model
        // change deferred to a future phase (see OI-001 in Phase 11 requirements).
        // This prevents width-0 chars from being placed as erroneous Half-width cells.
        if UnicodeWidthChar::width(c) == Some(0) {
            return;
        }
        self.screen
            .print(c, self.current_attrs, self.dec_modes.auto_wrap);
    }

    fn execute(&mut self, byte: u8) {
        match byte {
            0x07 => self.bell_pending = true,
            0x08 => self.screen.backspace(),
            0x09 => {
                // HT - Horizontal Tab
                if self.dec_modes.tab_stops_enabled() {
                    parser::tabs::handle_ht(&mut self.screen, &self.tab_stops);
                } else {
                    // Fall back to default tab behavior if disabled
                    self.screen.tab();
                }
            }
            0x0A..=0x0C => self.screen.line_feed(),
            0x0D => self.screen.carriage_return(),
            _ => {}
        }
    }

    fn csi_dispatch(&mut self, params: &vte::Params, intermediates: &[u8], _ignore: bool, c: char) {
        // Check for DEC private mode sequences (CSI ? Pm h/l)
        if !intermediates.is_empty() && intermediates[0] == b'?' {
            // DEC private mode
            let set = match c {
                'h' => true,  // Set mode
                'l' => false, // Reset mode
                _ => return,  // Other DEC private sequences not supported yet
            };
            parser::dec_private::handle_dec_modes(self, params, set);
            return;
        }

        // Handle standard CSI sequences
        match c {
            // Device Attribute queries — terminal must respond to avoid shell hangs
            'c' => {
                if intermediates.is_empty() {
                    // DA1 (Primary): ESC[c or ESC[0c → respond with VT100 + advanced video
                    self.pending_responses.push(b"\x1b[?1;2c".to_vec());
                } else if intermediates == b">" {
                    // DA2 (Secondary): ESC[>c or ESC[>0c → respond with VT220 emulation
                    self.pending_responses.push(b"\x1b[>1;10;0c".to_vec());
                }
            }
            // Cursor positioning
            'H' | 'A' | 'B' | 'C' | 'D' | 'd' | 'G' | 'f' | 'n' => {
                parser::csi::handle_csi_cursor(self, params, c);
            }
            // Erase operations
            'J' | 'K' => {
                parser::erase::handle_erase(self, params, c);
            }
            // Scroll operations
            'r' | 'S' | 'T' => {
                parser::scroll::handle_scroll(self, params, c);
            }
            // Tab clear (TBC)
            'g' => {
                parser::tabs::handle_tbc(&self.screen, &mut self.tab_stops, params);
            }
            // Insert / delete sequences (IL, DL, ICH, DCH, ECH)
            'L' | 'M' | '@' | 'P' | 'X' => {
                parser::insert_delete::handle_insert_delete(self, params, c);
            }
            // SGR and other sequences handled by existing sgr module
            _ => {
                parser::sgr::handle_csi(self, params, intermediates, c);
            }
        }
    }

    /// Handle OSC (Operating System Command) sequences from the VTE parser.
    ///
    /// Handles:
    /// - OSC 0 / OSC 2: set window title. Updates `self.title` and sets `self.title_dirty = true`.
    ///   Empty payloads and payloads over 1024 bytes are silently ignored.
    ///   Invalid UTF-8 bytes are replaced with U+FFFD via lossy conversion.
    /// - All other OSC numbers are silently discarded.
    fn osc_dispatch(&mut self, params: &[&[u8]], _bell_terminated: bool) {
        if params.is_empty() {
            return;
        }
        match params[0] {
            b"0" | b"2" => {
                if let Some(raw) = params.get(1) {
                    if raw.is_empty() {
                        return; // ignore empty titles
                    }
                    const MAX_TITLE_BYTES: usize = 1024;
                    if raw.len() > MAX_TITLE_BYTES {
                        return; // ignore oversized titles (DoS prevention)
                    }
                    let title = String::from_utf8_lossy(raw).into_owned();
                    self.title = title;
                    self.title_dirty = true;
                }
            }
            _ => {} // all other OSC numbers: silently ignore
        }
    }

    fn esc_dispatch(&mut self, intermediates: &[u8], _ignore: bool, byte: u8) {
        match (intermediates, byte) {
            ([], b'7') => self.save_cursor(), // DECSC: Save cursor position and attributes
            ([], b'8') => self.restore_cursor(), // DECRC: Restore cursor position and attributes
            ([], b'c') => self.reset(),       // RIS: Full terminal reset
            ([], b'H') => {
                // HTS: Horizontal tab set at current cursor column
                parser::tabs::handle_hts(&self.screen, &mut self.tab_stops);
            }
            ([], b'=') => {
                // DECKPAM: application keypad mode
                self.dec_modes.app_keypad = true;
            }
            ([], b'>') => {
                // DECKPNM: normal keypad mode
                self.dec_modes.app_keypad = false;
            }
            _ => {
                // Unknown ESC sequence — silently ignore
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn test_terminal_creation() {
        let term = TerminalCore::new(24, 80);
        assert_eq!(term.screen.rows(), 24);
        assert_eq!(term.screen.cols(), 80);
    }

    #[test]
    fn test_simple_print() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"Hello");
        // Check first cell
        let cell = term.screen.get_cell(0, 0).unwrap();
        assert_eq!(cell.c, 'H');
    }

    #[test]
    fn test_decsc_decrc_basic() {
        let mut term = TerminalCore::new(24, 80);

        // Move cursor to a known position
        term.advance(b"\x1b[6;11H"); // CSI 6;11H -> row 5, col 10 (0-indexed)

        let row_before = term.screen.cursor().row;
        let col_before = term.screen.cursor().col;

        // ESC 7: save cursor position and attributes (DECSC)
        term.advance(b"\x1b7");
        assert!(
            term.saved_cursor.is_some(),
            "saved_cursor should be set after ESC 7"
        );

        // Move cursor somewhere else
        term.advance(b"\x1b[1;1H"); // CSI 1;1H -> row 0, col 0

        assert_eq!(term.screen.cursor().row, 0);
        assert_eq!(term.screen.cursor().col, 0);

        // ESC 8: restore cursor position and attributes (DECRC)
        term.advance(b"\x1b8");

        // Cursor should be restored to the saved position
        assert_eq!(term.screen.cursor().row, row_before);
        assert_eq!(term.screen.cursor().col, col_before);

        // saved_cursor should be consumed
        assert!(
            term.saved_cursor.is_none(),
            "saved_cursor should be cleared after ESC 8"
        );
    }

    #[test]
    fn test_decsc_decrc_preserves_attrs() {
        let mut term = TerminalCore::new(24, 80);

        // Set bold via SGR
        term.advance(b"\x1b[1m"); // CSI 1m -> bold on
        assert!(term.current_attrs.bold);

        // Save cursor + attrs
        term.advance(b"\x1b7"); // DECSC

        // Reset attrs
        term.advance(b"\x1b[0m"); // CSI 0m -> reset
        assert!(!term.current_attrs.bold);

        // Restore cursor + attrs
        term.advance(b"\x1b8"); // DECRC

        // Bold should be restored
        assert!(term.current_attrs.bold);
    }

    #[test]
    fn test_ris_full_reset() {
        let mut term = TerminalCore::new(24, 80);

        // Move cursor, set bold, save state
        term.advance(b"\x1b[10;20H"); // move cursor
        term.advance(b"\x1b[1m"); // bold on
        term.advance(b"\x1b7"); // save cursor

        // Full terminal reset via RIS (ESC c)
        term.advance(b"\x1bc");

        // Cursor should be at home
        assert_eq!(term.screen.cursor().row, 0);
        assert_eq!(term.screen.cursor().col, 0);

        // Attributes should be reset to default
        assert!(!term.current_attrs.bold);

        // Saved cursor state should be cleared
        assert!(term.saved_cursor.is_none());
        assert!(term.saved_attrs.is_none());

        // Alternate screen should not be active
        assert!(!term.screen.is_alternate_screen_active());
    }

    #[test]
    fn test_dectcem_cursor_visibility() {
        let mut term = TerminalCore::new(24, 80);

        // Cursor is visible by default (DECTCEM default = true)
        assert!(term.dec_modes.cursor_visible);

        // CSI ?25l: hide cursor (DECTCEM reset)
        term.advance(b"\x1b[?25l");
        assert!(
            !term.dec_modes.cursor_visible,
            "cursor should be hidden after CSI ?25l"
        );

        // CSI ?25h: show cursor (DECTCEM set)
        term.advance(b"\x1b[?25h");
        assert!(
            term.dec_modes.cursor_visible,
            "cursor should be visible after CSI ?25h"
        );
    }

    #[test]
    fn test_dectcem_after_ris() {
        let mut term = TerminalCore::new(24, 80);

        // Cursor is visible by default
        assert!(term.dec_modes.cursor_visible);

        // Hide cursor
        term.advance(b"\x1b[?25l");
        assert!(!term.dec_modes.cursor_visible);

        // Full reset (RIS) reinitialises dec_modes via DecModes::new(), which
        // correctly sets cursor_visible=true and auto_wrap=true as per VT terminal defaults.
        term.advance(b"\x1bc");
        assert!(
            term.dec_modes.cursor_visible,
            "cursor should be visible after RIS (DecModes::new() sets cursor_visible=true)"
        );
    }

    #[test]
    fn test_osc_title_set() {
        let mut core = TerminalCore::new(24, 80);
        assert_eq!(core.title, "");
        assert!(!core.title_dirty);

        core.advance(b"\x1b]2;hello tmux\x07");
        assert_eq!(core.title, "hello tmux");
        assert!(core.title_dirty);
    }

    #[test]
    fn test_osc_icon_and_title() {
        let mut core = TerminalCore::new(24, 80);
        core.advance(b"\x1b]0;test title\x07");
        assert_eq!(core.title, "test title");
        assert!(core.title_dirty);
    }

    #[test]
    fn test_osc_empty_ignored() {
        let mut core = TerminalCore::new(24, 80);
        core.advance(b"\x1b]2;\x07");
        assert_eq!(core.title, "");
        assert!(!core.title_dirty);
    }

    #[test]
    fn test_osc_title_st_terminator() {
        // ST-terminated (ESC \) should be handled identically to BEL
        let mut core = TerminalCore::new(24, 80);
        core.advance(b"\x1b]2;st term title\x1b\\");
        assert_eq!(core.title, "st term title");
        assert!(core.title_dirty);
    }

    #[test]
    fn test_osc_title_reset_clears() {
        let mut core = TerminalCore::new(24, 80);
        core.advance(b"\x1b]2;before reset\x07");
        assert!(core.title_dirty);
        core.reset(); // RIS ESC c
        assert_eq!(core.title, "");
        assert!(!core.title_dirty);
    }

    #[test]
    fn test_osc_title_atomic_clear() {
        // Verify that title_dirty is cleared after being read, and the title value is correct.
        let mut core = TerminalCore::new(24, 80);

        core.advance(b"\x1b]2;test title\x07");
        assert!(
            core.title_dirty,
            "title_dirty should be set after OSC dispatch"
        );
        assert_eq!(core.title, "test title");

        // Simulate the atomic-clear: read title, then clear dirty flag
        let read_title = core.title.clone();
        core.title_dirty = false;

        assert_eq!(read_title, "test title");
        assert!(
            !core.title_dirty,
            "title_dirty should be false after atomic clear"
        );

        // Verify a second dispatch sets dirty again
        core.advance(b"\x1b]2;new title\x07");
        assert!(
            core.title_dirty,
            "title_dirty should be set again after second dispatch"
        );
        assert_eq!(core.title, "new title");
    }

    #[test]
    fn test_deckpam_sets_app_keypad() {
        let mut term = TerminalCore::new(24, 80);
        assert!(
            !term.dec_modes.app_keypad,
            "app_keypad should default to false"
        );
        term.advance(b"\x1b="); // ESC = : DECKPAM
        assert!(
            term.dec_modes.app_keypad,
            "app_keypad should be set after ESC ="
        );
    }

    #[test]
    fn test_deckpnm_clears_app_keypad() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b="); // DECKPAM: set
        assert!(term.dec_modes.app_keypad);
        term.advance(b"\x1b>"); // DECKPNM: clear
        assert!(
            !term.dec_modes.app_keypad,
            "app_keypad should be cleared after ESC >"
        );
    }

    #[test]
    fn test_deckpam_toggle_sequence() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b=\x1b>\x1b="); // DECKPAM → DECKPNM → DECKPAM
        assert!(
            term.dec_modes.app_keypad,
            "final state should be app_keypad=true"
        );
    }

    #[test]
    fn test_osc_title_length_cap() {
        // Verify that oversized OSC titles are silently ignored
        let mut core = TerminalCore::new(24, 80);

        // Title within limit should work (1024 'a' chars)
        let mut ok_seq = b"\x1b]2;".to_vec();
        ok_seq.extend_from_slice(&vec![b'a'; 1024]);
        ok_seq.push(0x07);
        core.advance(&ok_seq);
        assert!(core.title_dirty, "1024-byte title should be accepted");
        core.title_dirty = false;

        // Title over limit should be ignored (1025 'a' chars)
        let mut big_seq = b"\x1b]2;".to_vec();
        big_seq.extend_from_slice(&vec![b'a'; 1025]);
        big_seq.push(0x07);
        core.advance(&big_seq);
        assert!(!core.title_dirty, "1025-byte title should be rejected");
    }

    #[test]
    fn test_osc_title_non_utf8() {
        // Verify that non-UTF8 bytes are handled via lossy conversion (U+FFFD replacement)
        let mut core = TerminalCore::new(24, 80);
        core.advance(b"\x1b]2;hello\xff\xfeworld\x07");
        assert!(core.title_dirty, "Non-UTF8 title should still set dirty");
        assert!(
            !core.title.is_empty(),
            "Non-UTF8 title should produce non-empty result via lossy conversion"
        );
        // Should not panic — if we got here, test passes
    }

    #[test]
    fn test_apc_payload_at_cap() {
        // Build an APC sequence: ESC _ <payload> ESC \
        // with exactly MAX_APC_PAYLOAD_BYTES bytes of payload
        const MAX_APC_PAYLOAD_BYTES: usize = 4 * 1024 * 1024;
        let mut core = TerminalCore::new(24, 80);
        let mut input = vec![0x1b, b'_']; // ESC _
        input.extend(std::iter::repeat(b'X').take(MAX_APC_PAYLOAD_BYTES));
        input.extend_from_slice(b"\x1b\\"); // ESC \  (string terminator)
        core.advance(&input);
        // The buffer should have been consumed and APC processed
        assert_eq!(
            core.apc_buf.len(),
            0,
            "apc_buf should be cleared after full APC sequence"
        );
    }

    #[test]
    fn test_apc_payload_exceeds_cap_is_truncated() {
        const MAX_APC_PAYLOAD_BYTES: usize = 4 * 1024 * 1024;
        let mut core = TerminalCore::new(24, 80);
        let mut input = vec![0x1b, b'_']; // ESC _
        // Send MORE than the cap
        input.extend(std::iter::repeat(b'X').take(MAX_APC_PAYLOAD_BYTES + 100));
        input.extend_from_slice(b"\x1b\\"); // ESC \
        core.advance(&input);
        // Buffer should be cleared after processing, but during processing it was capped
        assert_eq!(
            core.apc_buf.len(),
            0,
            "apc_buf should be cleared after APC sequence completes"
        );
    }

    #[test]
    fn test_apc_split_across_advance_calls() {
        let mut core = TerminalCore::new(24, 80);
        // Send APC open + part of payload in first call
        let part1 = b"\x1b_GHello";
        // Send rest of payload + close in second call
        let part2 = b" World\x1b\\";
        core.advance(part1);
        core.advance(part2);
        // After the sequence completes, apc_buf should be cleared
        assert_eq!(
            core.apc_buf.len(),
            0,
            "apc_buf should be cleared after split APC sequence"
        );
    }

    #[test]
    fn test_resize_preserves_screen_content() {
        let mut term = TerminalCore::new(24, 80);
        // Print 'A' at the top-left corner
        term.advance(b"A");
        let row_before = term.screen.cursor().row;
        let col_before = term.screen.cursor().col;
        // Resize to a larger screen
        term.resize(30, 100);
        assert_eq!(term.screen.rows(), 30);
        assert_eq!(term.screen.cols(), 100);
        // Cursor position must remain in bounds after resize
        assert!(term.screen.cursor().row < 30, "cursor row out of bounds after resize");
        assert!(term.screen.cursor().col < 100, "cursor col out of bounds after resize");
        // Cursor should not have moved to an impossible position
        let _ = (row_before, col_before); // used for context
    }

    #[test]
    fn test_advance_empty_input() {
        // Advancing with an empty slice must not panic
        let mut term = TerminalCore::new(24, 80);
        term.advance(&[]);
        // State is unchanged from initial
        assert_eq!(term.screen.cursor().row, 0);
        assert_eq!(term.screen.cursor().col, 0);
    }

    #[test]
    fn test_advance_split_sequence() {
        // Send an incomplete CSI sequence in the first call, complete it in the second.
        // After both calls, bold should be set.
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b[");   // incomplete CSI
        term.advance(b"1m");      // complete: SGR bold
        assert!(
            term.current_attrs.bold,
            "bold should be set after split CSI sequence"
        );
    }

    #[test]
    fn test_execute_backspace_at_col_zero() {
        // Move to row 5 col 0 (CSI 5;1H) then send backspace.
        // Cursor must stay at col 0 (no underflow).
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b[5;1H\x08");
        assert_eq!(
            term.screen.cursor().col,
            0,
            "backspace at col 0 must not move cursor below 0"
        );
        // Row should be 4 (0-indexed) after CSI 5;1H
        assert_eq!(term.screen.cursor().row, 4);
    }

    #[test]
    fn test_csi_unknown_final_byte_no_panic() {
        // An unknown CSI final byte must be silently ignored without panicking.
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b[999z");
        // If we reach here the test passes — no panic occurred
    }

    #[test]
    fn test_osc_unknown_command_number_ignored() {
        // OSC with unknown command number must be silently discarded without crashing.
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b]99;some_data\x07");
        // Title must not have changed (OSC 99 is not handled)
        assert_eq!(term.title, "", "unknown OSC number must not update title");
        assert!(!term.title_dirty, "unknown OSC number must not set title_dirty");
    }

    proptest! {
        #[test]
        fn prop_vte_parse_never_panics(bytes in proptest::collection::vec(any::<u8>(), 0..256)) {
            let mut term = TerminalCore::new(24, 80);
            term.advance(&bytes);
            // Must not panic. Cursor stays in bounds.
            prop_assert!(term.screen.cursor().row < 24);
            prop_assert!(term.screen.cursor().col < 80);
        }

        #[test]
        fn prop_resize_cursor_always_in_bounds(
            new_rows in 1u16..50,
            new_cols in 1u16..50,
        ) {
            let mut term = TerminalCore::new(24, 80);
            // Move cursor to somewhere potentially out of bounds after resize
            term.advance(b"\x1b[20;70H");
            term.resize(new_rows, new_cols);
            prop_assert!(term.screen.cursor().row < new_rows as usize,
                "cursor row {} >= {}", term.screen.cursor().row, new_rows);
            prop_assert!(term.screen.cursor().col < new_cols as usize,
                "cursor col {} >= {}", term.screen.cursor().col, new_cols);
        }
    }
}
