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

emacs::plugin_is_GPL_compatible!();

#[emacs::module(name = "kuro-core", defun_prefix = "", separator = "", mod_in_name = false)]
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

/// Terminal core state, integrating VTE parser, screen, and PTY
pub struct TerminalCore {
    /// Virtual screen buffer
    pub screen: Screen,
    /// Current SGR attributes
    pub current_attrs: types::cell::SgrAttributes,
    /// VTE parser (stored to maintain state across advance calls)
    parser: vte::Parser,
    /// DEC private mode state
    pub dec_modes: DecModes,
    /// Tab stop configuration
    pub tab_stops: TabStops,
    /// Whether a BEL character has been received and not yet cleared
    pub bell_pending: bool,
    /// Queued responses to write back to the PTY (e.g. DA1/DA2 replies)
    pub pending_responses: Vec<Vec<u8>>,
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
            bell_pending: false,
            pending_responses: Vec::new(),
        }
    }

    /// Advance the VTE parser with input bytes
    ///
    /// Parser state is preserved across calls, allowing proper handling of
    /// multi-byte escape sequences and CSI parameters.
    ///
    /// This method efficiently processes all bytes in a single call to the parser,
    /// avoiding per-byte allocation overhead and preserving multi-byte sequence context.
    pub fn advance(&mut self, bytes: &[u8]) {
        // Move parser out to avoid borrow checker conflict, then advance with all bytes at once
        let mut parser = std::mem::replace(&mut self.parser, vte::Parser::new());
        parser.advance(self, bytes);
        self.parser = parser;
    }

    /// Resize the terminal screen
    pub fn resize(&mut self, rows: u16, cols: u16) {
        self.screen.resize(rows, cols);
        self.tab_stops.resize(cols as usize);
    }
}

impl vte::Perform for TerminalCore {
    fn print(&mut self, c: char) {
        self.screen.print(c, self.current_attrs, self.dec_modes.auto_wrap);
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
                    self.pending_responses
                        .push(b"\x1b[?1;2c".to_vec());
                } else if intermediates == b">" {
                    // DA2 (Secondary): ESC[>c or ESC[>0c → respond with VT220 emulation
                    self.pending_responses
                        .push(b"\x1b[>1;10;0c".to_vec());
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
            // SGR and other sequences handled by existing sgr module
            _ => {
                parser::sgr::handle_csi(self, params, intermediates, c);
            }
        }
    }

    fn osc_dispatch(&mut self, params: &[&[u8]], bell_terminated: bool) {
        let _ = (params, bell_terminated);
        // TODO: Implement OSC sequences
    }

    fn esc_dispatch(&mut self, intermediates: &[u8], _ignore: bool, byte: u8) {
        let _ = (intermediates, byte);
        // TODO: Implement ESC sequences
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
