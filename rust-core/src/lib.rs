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

use base64::Engine;
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
            pending_image_notifications: Vec::new(),
            osc_data: Default::default(),
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
        self.pending_image_notifications.clear();
        // Clear OSC data
        self.osc_data = Default::default();
    }
}

impl vte::Perform for TerminalCore {
    fn print(&mut self, c: char) {
        // Combining characters (Unicode width 0) are attached to the previous cell.
        if UnicodeWidthChar::width(c) == Some(0) {
            // Attach to the cell just before the current cursor position
            let cursor = *self.screen.cursor();
            let (row, col) = if cursor.col > 0 {
                (cursor.row, cursor.col - 1)
            } else if cursor.row > 0 {
                // Cursor is at column 0; attach to last cell of previous row
                let prev_row = cursor.row - 1;
                let last_col = self.screen.cols().saturating_sub(1) as usize;
                (prev_row, last_col)
            } else {
                // No previous cell available; discard
                return;
            };
            self.screen.attach_combining(row, col, c);
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
        // Check for DEC private mode sequences (CSI ? Pm h/l) and CSI ? u (query keyboard flags)
        if !intermediates.is_empty() && intermediates[0] == b'?' {
            match c {
                'h' | 'l' => {
                    let set = c == 'h';
                    parser::dec_private::handle_dec_modes(self, params, set);
                }
                'u' => {
                    // CSI ? u — Query keyboard flags
                    let response = format!("\x1b[?{}u", self.dec_modes.keyboard_flags);
                    self.pending_responses.push(response.into_bytes());
                }
                _ => {}
            }
            return;
        }

        // CSI > Ps u — Push and set keyboard flags (Kitty keyboard protocol)
        if !intermediates.is_empty() && intermediates[0] == b'>' {
            match c {
                'u' => {
                    let flags = params
                        .iter()
                        .next()
                        .and_then(|p| p.first().copied())
                        .unwrap_or(0);
                    if self.dec_modes.keyboard_flags_stack.len() < 64 {
                        self.dec_modes
                            .keyboard_flags_stack
                            .push(self.dec_modes.keyboard_flags);
                    }
                    self.dec_modes.keyboard_flags = flags as u32;
                }
                'c' => {
                    // DA2 (Secondary Device Attributes): ESC[>c or ESC[>0c
                    self.pending_responses.push(b"\x1b[>1;10;0c".to_vec());
                }
                _ => {}
            }
            return;
        }

        // CSI < u — Pop keyboard flags (Kitty keyboard protocol)
        if !intermediates.is_empty() && intermediates[0] == b'<' {
            if c == 'u' {
                if let Some(prev) = self.dec_modes.keyboard_flags_stack.pop() {
                    self.dec_modes.keyboard_flags = prev;
                } else {
                    self.dec_modes.keyboard_flags = 0;
                }
            }
            return;
        }

        // Handle standard CSI sequences
        match c {
            // Device Attribute queries — terminal must respond to avoid shell hangs
            // DA2 (Secondary, ESC[>c) is handled above in the '>' intermediates block.
            'c' => {
                if intermediates.is_empty() {
                    // DA1 (Primary): ESC[c or ESC[0c → respond with VT100 + advanced video
                    self.pending_responses.push(b"\x1b[?1;2c".to_vec());
                }
            }
            // DECSCUSR - Set Cursor Style (CSI Ps SP q)
            'q' if intermediates == &[b' '] => {
                let ps = params
                    .iter()
                    .next()
                    .and_then(|p| p.first().copied())
                    .unwrap_or(0);
                self.dec_modes.cursor_shape = match ps {
                    0 | 1 => types::cursor::CursorShape::BlinkingBlock,
                    2 => types::cursor::CursorShape::SteadyBlock,
                    3 => types::cursor::CursorShape::BlinkingUnderline,
                    4 => types::cursor::CursorShape::SteadyUnderline,
                    5 => types::cursor::CursorShape::BlinkingBar,
                    6 => types::cursor::CursorShape::SteadyBar,
                    _ => types::cursor::CursorShape::BlinkingBlock,
                };
            }
            // DECSTR - Soft Terminal Reset (CSI ! p)
            'p' if intermediates == &[b'!'] => {
                self.soft_reset();
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
            // SGR - Select Graphic Rendition
            'm' => {
                parser::sgr::handle_sgr(self, params);
            }
            // Unknown/unhandled CSI sequences are silently ignored
            _ => {}
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
            b"7" => {
                // OSC 7 - Current Working Directory: file://host/path
                if let Some(raw) = params.get(1) {
                    let url = String::from_utf8_lossy(raw);
                    // Strip file://hostname prefix to get just the path
                    if let Some(after_scheme) = url.strip_prefix("file://") {
                        // Skip hostname part (up to next /)
                        let path = after_scheme
                            .find('/')
                            .map(|i| &after_scheme[i..])
                            .unwrap_or(after_scheme);
                        if path.len() <= 4096 {
                            self.osc_data.cwd = Some(path.to_string());
                            self.osc_data.cwd_dirty = true;
                        }
                    }
                }
            }
            b"8" => {
                // OSC 8 - Hyperlinks: ESC]8;params;uri ST
                if let Some(params_raw) = params.get(1) {
                    let params_str = String::from_utf8_lossy(params_raw);
                    if let Some(uri_raw) = params.get(2) {
                        let uri = String::from_utf8_lossy(uri_raw);
                        if uri.is_empty() {
                            // Close hyperlink
                            self.osc_data.hyperlink = types::osc::HyperlinkState::default();
                        } else if uri.len() <= 8192 {
                            // Extract id from params if present
                            let id = params_str
                                .split(';')
                                .find_map(|p| p.strip_prefix("id="))
                                .map(String::from);
                            self.osc_data.hyperlink = types::osc::HyperlinkState {
                                uri: Some(uri.into_owned()),
                                id,
                            };
                        }
                    }
                }
            }
            b"52" => {
                // OSC 52 - Clipboard: ESC]52;selection;base64data ST
                if let Some(data_raw) = params.get(2) {
                    if data_raw == b"?" {
                        self.osc_data
                            .clipboard_actions
                            .push(types::osc::ClipboardAction::Query);
                    } else if data_raw.len() <= 1_048_576 {
                        // 1MB cap
                        if let Ok(decoded) =
                            base64::engine::general_purpose::STANDARD.decode(data_raw)
                        {
                            if let Ok(text) = String::from_utf8(decoded) {
                                self.osc_data
                                    .clipboard_actions
                                    .push(types::osc::ClipboardAction::Write(text));
                            }
                        }
                    }
                }
            }
            b"133" => {
                // OSC 133 - Shell integration prompt marks
                if let Some(mark_raw) = params.get(1) {
                    let mark = match mark_raw.first() {
                        Some(b'A') => Some(types::osc::PromptMark::PromptStart),
                        Some(b'B') => Some(types::osc::PromptMark::PromptEnd),
                        Some(b'C') => Some(types::osc::PromptMark::CommandStart),
                        Some(b'D') => Some(types::osc::PromptMark::CommandEnd),
                        _ => None,
                    };
                    if let Some(m) = mark {
                        let cursor = *self.screen.cursor();
                        self.osc_data
                            .prompt_marks
                            .push(types::osc::PromptMarkEvent {
                                mark: m,
                                row: cursor.row,
                                col: cursor.col,
                            });
                    }
                }
            }
            b"104" => {
                // OSC 104 - Reset color palette
                self.osc_data.palette_dirty = true;
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
        assert_eq!(cell.char(), 'H');
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
        assert!(
            term.screen.cursor().row < 30,
            "cursor row out of bounds after resize"
        );
        assert!(
            term.screen.cursor().col < 100,
            "cursor col out of bounds after resize"
        );
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
        term.advance(b"\x1b["); // incomplete CSI
        term.advance(b"1m"); // complete: SGR bold
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
        assert!(
            !term.title_dirty,
            "unknown OSC number must not set title_dirty"
        );
    }

    #[test]
    fn test_combining_char_attached_to_base() {
        let mut term = TerminalCore::new(24, 80);
        // Print 'e' followed by combining acute accent U+0301
        term.advance("e\u{0301}".as_bytes());
        let cell = term.get_cell(0, 0).unwrap();
        assert_eq!(cell.grapheme.as_str(), "e\u{0301}");
    }

    #[test]
    fn test_combining_char_at_col_zero_discarded() {
        let mut term = TerminalCore::new(24, 80);
        // Send combining char at position (0,0) with no previous cell
        term.advance("\u{0301}".as_bytes());
        // Should not panic; cell at (0,0) should still be default space
        let cell = term.get_cell(0, 0).unwrap();
        assert_eq!(cell.grapheme.as_str(), " ");
    }

    #[test]
    fn test_normal_chars_unchanged_after_grapheme_support() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"ABC");
        assert_eq!(term.get_cell(0, 0).unwrap().char(), 'A');
        assert_eq!(term.get_cell(0, 1).unwrap().char(), 'B');
        assert_eq!(term.get_cell(0, 2).unwrap().char(), 'C');
    }

    #[test]
    fn test_osc_7_stores_cwd() {
        let mut core = TerminalCore::new(24, 80);
        core.advance(b"\x1b]7;file://localhost/tmp/test\x07");
        assert!(core.osc_data.cwd_dirty);
        assert_eq!(core.osc_data.cwd, Some("/tmp/test".to_string()));
    }

    #[test]
    fn test_osc_133_stores_prompt_marks() {
        let mut core = TerminalCore::new(24, 80);
        core.advance(b"\x1b]133;A\x07");
        assert_eq!(core.osc_data.prompt_marks.len(), 1);
        assert_eq!(
            core.osc_data.prompt_marks[0].mark,
            types::osc::PromptMark::PromptStart
        );
    }

    #[test]
    fn test_osc_8_hyperlink() {
        let mut core = TerminalCore::new(24, 80);
        core.advance(b"\x1b]8;;https://example.com\x07");
        assert_eq!(
            core.osc_data.hyperlink.uri,
            Some("https://example.com".to_string())
        );
        // Close hyperlink
        core.advance(b"\x1b]8;;\x07");
        assert!(core.osc_data.hyperlink.uri.is_none());
    }

    #[test]
    fn test_osc_104_clears_palette() {
        let mut core = TerminalCore::new(24, 80);
        core.advance(b"\x1b]104\x07");
        assert!(core.osc_data.palette_dirty);
    }

    #[test]
    fn test_decscusr_sets_cursor_shape() {
        let mut term = TerminalCore::new(24, 80);
        // CSI 5 SP q → blinking bar
        term.advance(b"\x1b[5 q");
        assert_eq!(
            term.dec_modes.cursor_shape,
            types::cursor::CursorShape::BlinkingBar
        );
        // CSI 2 SP q → steady block
        term.advance(b"\x1b[2 q");
        assert_eq!(
            term.dec_modes.cursor_shape,
            types::cursor::CursorShape::SteadyBlock
        );
    }

    #[test]
    fn test_decstr_soft_reset() {
        let mut term = TerminalCore::new(24, 80);
        // Set some modes
        term.advance(b"\x1b[?1h"); // DECCKM on
        term.advance(b"\x1b[1m"); // Bold on
        term.advance(b"\x1b[10;20H"); // Move cursor
                                      // Soft reset
        term.advance(b"\x1b[!p");
        // Cursor keys should be reset
        assert!(!term.dec_modes.app_cursor_keys);
        // SGR should be reset
        assert!(!term.current_attrs.bold);
        // Cursor should be at home
        assert_eq!(term.cursor_row(), 0);
        assert_eq!(term.cursor_col(), 0);
        // Auto-wrap should be on
        assert!(term.dec_modes.auto_wrap);
    }

    #[test]
    fn test_decstr_preserves_screen_content() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"Hello");
        term.advance(b"\x1b[!p"); // Soft reset
                                  // Content should be preserved
        let cell = term.get_cell(0, 0).unwrap();
        assert_eq!(cell.char(), 'H');
    }

    #[test]
    fn test_kitty_keyboard_push_pop() {
        let mut term = TerminalCore::new(24, 80);
        assert_eq!(term.dec_modes.keyboard_flags, 0);
        // Push flags=1 (disambiguate)
        term.advance(b"\x1b[>1u");
        assert_eq!(term.dec_modes.keyboard_flags, 1);
        // Push flags=3 (disambiguate + event types)
        term.advance(b"\x1b[>3u");
        assert_eq!(term.dec_modes.keyboard_flags, 3);
        assert_eq!(term.dec_modes.keyboard_flags_stack.len(), 2);
        // Pop
        term.advance(b"\x1b[<u");
        assert_eq!(term.dec_modes.keyboard_flags, 1);
        // Pop again
        term.advance(b"\x1b[<u");
        assert_eq!(term.dec_modes.keyboard_flags, 0);
        // Pop on empty stack → stays at 0
        term.advance(b"\x1b[<u");
        assert_eq!(term.dec_modes.keyboard_flags, 0);
    }

    #[test]
    fn test_kitty_keyboard_query() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b[>5u"); // Set flags=5
        term.advance(b"\x1b[?u"); // Query
        assert_eq!(term.pending_responses.len(), 1);
        assert_eq!(term.pending_responses[0], b"\x1b[?5u");
    }

    // === Resource limit tests ===

    #[test]
    fn test_oversized_osc7_cwd_rejected() {
        let mut term = TerminalCore::new(24, 80);
        let long_path = format!("\x1b]7;file://localhost/{}\x07", "a".repeat(5000));
        term.advance(long_path.as_bytes());
        // CWD should NOT be stored (over 4096 limit)
        assert!(
            term.osc_data.cwd.is_none() || term.osc_data.cwd.as_ref().unwrap().len() <= 4096,
            "CWD over 4096 bytes should be rejected"
        );
    }

    #[test]
    fn test_oversized_osc8_uri_rejected() {
        let mut term = TerminalCore::new(24, 80);
        let long_uri = format!("\x1b]8;;https://example.com/{}\x07", "x".repeat(9000));
        term.advance(long_uri.as_bytes());
        // Hyperlink should NOT be stored (over 8192 limit)
        assert!(
            term.osc_data.hyperlink.uri.is_none()
                || term.osc_data.hyperlink.uri.as_ref().unwrap().len() <= 8192,
            "Hyperlink URI over 8192 bytes should be rejected"
        );
    }

    #[test]
    fn test_apc_payload_cap_enforced() {
        let mut term = TerminalCore::new(24, 80);
        // Send an APC with payload > 4MiB
        let large_payload = vec![b'A'; 5 * 1024 * 1024];
        let mut data = Vec::new();
        data.extend_from_slice(b"\x1b_G");
        data.extend_from_slice(&large_payload);
        data.extend_from_slice(b"\x1b\\");
        term.advance(&data);
        // Should not panic and apc_buf should be cleared after sequence completes
        assert_eq!(
            term.apc_buf.len(),
            0,
            "apc_buf should be cleared after oversized APC sequence"
        );
    }

    #[test]
    fn test_title_sanitization_strips_control_chars() {
        let mut term = TerminalCore::new(24, 80);
        // Title with embedded BEL control character — the OSC parser splits on BEL,
        // so the title will be "Hello" (everything before the first BEL terminator)
        term.advance(b"\x1b]2;Hello\x07World\x07");
        // The title should not contain control characters
        assert!(
            !term.title.contains('\x07'),
            "Title should not contain BEL control character"
        );
    }

    // === SGR underline style tests ===

    #[test]
    fn test_sgr_4_colon_3_sets_curly_underline() {
        let mut term = TerminalCore::new(24, 80);
        // CSI 4:3 m — curly underline (colon sub-parameter form)
        term.advance(b"\x1b[4:3m");
        assert_eq!(
            term.current_attrs.underline_style,
            types::cell::UnderlineStyle::Curly,
            "SGR 4:3 should set curly underline"
        );
    }

    #[test]
    fn test_sgr_4_colon_5_sets_dashed_underline() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b[4:5m");
        assert_eq!(
            term.current_attrs.underline_style,
            types::cell::UnderlineStyle::Dashed,
            "SGR 4:5 should set dashed underline"
        );
    }

    #[test]
    fn test_sgr_21_sets_double_underline() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b[21m");
        assert_eq!(
            term.current_attrs.underline_style,
            types::cell::UnderlineStyle::Double,
            "SGR 21 should set double underline"
        );
    }

    #[test]
    fn test_sgr_24_clears_underline() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b[4:3m"); // Set curly
        assert!(
            term.current_attrs.underline(),
            "Curly underline should be active"
        );
        term.advance(b"\x1b[24m"); // Clear
        assert!(
            !term.current_attrs.underline(),
            "SGR 24 should clear underline"
        );
        assert_eq!(
            term.current_attrs.underline_style,
            types::cell::UnderlineStyle::None,
            "SGR 24 should set underline_style to None"
        );
    }

    #[test]
    fn test_sgr_58_5_sets_underline_color_indexed() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b[58;5;196m");
        assert_eq!(
            term.current_attrs.underline_color,
            types::color::Color::Indexed(196),
            "SGR 58;5;196 should set indexed underline color 196"
        );
    }

    #[test]
    fn test_sgr_58_2_sets_underline_color_rgb() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b[58;2;255;128;0m");
        assert_eq!(
            term.current_attrs.underline_color,
            types::color::Color::Rgb(255, 128, 0),
            "SGR 58;2;255;128;0 should set RGB underline color"
        );
    }

    #[test]
    fn test_sgr_59_resets_underline_color() {
        let mut term = TerminalCore::new(24, 80);
        term.advance(b"\x1b[58;5;196m");
        assert_ne!(
            term.current_attrs.underline_color,
            types::color::Color::Default,
            "Underline color should be set before reset"
        );
        term.advance(b"\x1b[59m");
        assert_eq!(
            term.current_attrs.underline_color,
            types::color::Color::Default,
            "SGR 59 should reset underline color to Default"
        );
    }

    // === Clean shutdown / drop test ===

    #[test]
    fn test_terminal_drop_does_not_panic() {
        // Create and immediately drop a terminal
        let term = TerminalCore::new(24, 80);
        drop(term);
        // If we get here, no panic during cleanup
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
