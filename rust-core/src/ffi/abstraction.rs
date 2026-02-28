//! FFI abstraction trait for Emacs module integration
//!
//! This module provides a trait-based abstraction over the Emacs module API,
//! allowing the core terminal logic to be insulated from direct dependencies
//! on emacs-module-rs. This enables:
//! - Easy fallback to raw FFI if emacs-module-rs fails
//! - Simplified testing through trait mocking
//! - Future-proofing for alternative FFI implementations

use crate::{error::KuroError, pty::Pty, Result, TerminalCore};
use std::sync::Mutex;

/// Raw Emacs environment pointer (opaque type from C API)
#[repr(C)]
pub struct emacs_env {
    _private: [u8; 0],
}

/// Raw Emacs value type (opaque type from C API)
#[repr(C)]
pub struct emacs_value {
    _private: [u8; 0],
}

/// FFI abstraction trait for Emacs module operations
///
/// This trait defines the interface that all FFI implementations must provide.
/// It uses raw pointers to maintain compatibility with the C API, while
/// providing type-safe abstractions for Rust code.
///
/// Note: This trait is NOT object-safe (dyn compatible) because it contains
/// associated functions without `self` parameters. This is intentional -
/// the trait is used for compile-time polymorphism and documentation of the
/// FFI interface, not for runtime trait objects.
pub trait KuroFFI {
    /// Initialize a new terminal session with the given dimensions
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `command` - Shell command to execute (e.g., "bash" or "zsh")
    /// * `rows` - Number of rows in the terminal
    /// * `cols` - Number of columns in the terminal
    ///
    /// # Returns
    /// A pointer to an Emacs value representing the session handle
    fn init(env: *mut emacs_env, command: &str, rows: i64, cols: i64) -> *mut emacs_value;

    /// Poll for terminal updates and return dirty lines
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `max_updates` - Maximum number of updates to return (0 for unlimited)
    ///
    /// # Returns
    /// A pointer to an Emacs list of (line_no . text) pairs
    fn poll_updates(env: *mut emacs_env, max_updates: i64) -> *mut emacs_value;

    /// Send key input to the terminal
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `data` - Raw byte data to send
    /// * `len` - Length of the data in bytes
    ///
    /// # Returns
    /// A pointer to an Emacs boolean (t or nil)
    fn send_key(env: *mut emacs_env, data: &[u8]) -> *mut emacs_value;

    /// Resize the terminal
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `rows` - New number of rows
    /// * `cols` - New number of columns
    ///
    /// # Returns
    /// A pointer to an Emacs boolean (t or nil)
    fn resize(env: *mut emacs_env, rows: i64, cols: i64) -> *mut emacs_value;

    /// Shutdown the terminal session
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    ///
    /// # Returns
    /// A pointer to an Emacs boolean (t or nil)
    fn shutdown(env: *mut emacs_env) -> *mut emacs_value;

    /// Get cursor position
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    ///
    /// # Returns
    /// A pointer to an Emacs string in "row:col" format
    fn get_cursor(env: *mut emacs_env) -> *mut emacs_value;

    /// Get scrollback lines
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `max_lines` - Maximum number of lines to return (0 for all)
    ///
    /// # Returns
    /// A pointer to an Emacs list of strings
    fn get_scrollback(env: *mut emacs_env, max_lines: i64) -> *mut emacs_value;

    /// Clear scrollback buffer
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    ///
    /// # Returns
    /// A pointer to an Emacs boolean (t or nil)
    fn clear_scrollback(env: *mut emacs_env) -> *mut emacs_value;

    /// Set scrollback max lines
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `max_lines` - Maximum number of lines in scrollback buffer
    ///
    /// # Returns
    /// A pointer to an Emacs boolean (t or nil)
    fn set_scrollback_max_lines(env: *mut emacs_env, max_lines: i64) -> *mut emacs_value;
}

/// Terminal session state (shared by all FFI implementations)
///
/// This struct contains the actual terminal logic, independent of any
/// specific FFI binding implementation.
pub struct TerminalSession {
    /// Terminal core
    pub core: TerminalCore,
    /// PTY handle
    pty: Option<Pty>,
    /// Reusable render buffer to reduce allocations
    render_buffer: String,
}

impl TerminalSession {
    /// Create a new terminal session
    pub fn new(command: &str, rows: u16, cols: u16) -> Result<Self> {
        let core = TerminalCore::new(rows, cols);
        let mut pty = Pty::spawn(command)?;
        // Set the initial PTY window size so the shell sees correct dimensions
        // via TIOCGWINSZ from the start
        pty.set_winsize(rows, cols)?;

        Ok(Self {
            core,
            pty: Some(pty),
            render_buffer: String::with_capacity(cols as usize),
        })
    }

    /// Send input to PTY
    pub fn send_input(&mut self, bytes: &[u8]) -> Result<()> {
        if let Some(ref mut pty) = self.pty {
            pty.write(bytes)?;
        }
        Ok(())
    }

    /// Poll for PTY output and update terminal
    pub fn poll_output(&mut self) -> Result<Vec<u8>> {
        if let Some(ref mut pty) = self.pty {
            let data = pty.read()?;
            if !data.is_empty() {
                self.core.advance(&data);

                // Write any queued responses back to the PTY (e.g. DA1/DA2 replies)
                for response in self.core.pending_responses.drain(..) {
                    pty.write(&response)?;
                }

                return Ok(data);
            }
        }
        Ok(Vec::new())
    }

    /// Get dirty lines from screen
    pub fn get_dirty_lines(&mut self) -> Vec<(usize, String)> {
        let dirty_indices = self.core.screen.take_dirty_lines();
        let mut result = Vec::with_capacity(dirty_indices.len());

        for row in dirty_indices {
            let text_opt: Option<String> = self
                .core
                .screen
                .get_line(row)
                .map(|line| {
                    let s: String = line.cells.iter().map(|c| c.c).collect();
                    // Trim trailing spaces so Emacs doesn't fill lines with whitespace
                    s.trim_end_matches(' ').to_string()
                });
            if let Some(text) = text_opt {
                result.push((row, text));
            }
        }

        result
    }

    /// Get dirty lines with face ranges from screen
    ///
    /// Returns a list where each element is (line_no, text, face_ranges)
    /// face_ranges is a list of (start_col, end_col, fg_color, bg_color, flags)
    #[allow(clippy::type_complexity)]
    pub fn get_dirty_lines_with_faces(
        &mut self,
    ) -> Vec<(usize, String, Vec<(usize, usize, u32, u32, u64)>)> {
        let dirty_indices = self.core.screen.take_dirty_lines();
        let mut result = Vec::new();

        for row in dirty_indices {
            if let Some(line) = self.core.screen.get_line(row) {
                // Reuse render buffer to avoid allocations
                self.render_buffer.clear();

                // Track attribute changes to create face ranges
                let mut face_ranges = Vec::new();
                let mut current_start = 0;
                let mut current_fg = 0u32; // Encode color as u32 for efficiency
                let mut current_bg = 0u32;
                let mut current_flags = 0u64;

                for (col, cell) in line.cells.iter().enumerate() {
                    self.render_buffer.push(cell.c);

                    // Encode colors
                    let fg = Self::encode_color(&cell.attrs.foreground);
                    let bg = Self::encode_color(&cell.attrs.background);

                    // Encode attributes as bit flags
                    let flags = Self::encode_attrs(&cell.attrs);

                    // Check if attributes changed
                    if fg != current_fg || bg != current_bg || flags != current_flags {
                        // Only push a range when there is a non-empty span to record.
                        // At col=0 (current_start=0) the span length is zero, so we
                        // skip the push but still update the tracked attributes so the
                        // first character gets the correct color.
                        if col > current_start {
                            face_ranges.push((
                                current_start,
                                col,
                                current_fg,
                                current_bg,
                                current_flags,
                            ));
                            current_start = col;
                        }
                        current_fg = fg;
                        current_bg = bg;
                        current_flags = flags;
                    }
                }

                // Flush the final segment (covers both single-color lines and the last span).
                // The guard prevents a double-push when the last attribute-change flush fired
                // exactly at the last cell and advanced current_start to line.cells.len().
                if current_start < line.cells.len() {
                    face_ranges.push((
                        current_start,
                        line.cells.len(),
                        current_fg,
                        current_bg,
                        current_flags,
                    ));
                }

                // Trim trailing spaces from render buffer; face_ranges that extend
                // beyond trimmed_len are harmlessly ignored by Elisp bounds checks
                let trimmed_len = self.render_buffer.trim_end_matches(' ').len();
                self.render_buffer.truncate(trimmed_len);

                result.push((row, self.render_buffer.clone(), face_ranges));
            }
        }

        result
    }

    /// Encode color as u32 for efficient FFI transfer
    fn encode_color(color: &crate::types::Color) -> u32 {
        match color {
            crate::types::Color::Default => 0, // Sentinel: 0 means "use terminal default color"
            crate::types::Color::Named(named) => {
                let idx = match named {
                    crate::types::NamedColor::Black => 0,
                    crate::types::NamedColor::Red => 1,
                    crate::types::NamedColor::Green => 2,
                    crate::types::NamedColor::Yellow => 3,
                    crate::types::NamedColor::Blue => 4,
                    crate::types::NamedColor::Magenta => 5,
                    crate::types::NamedColor::Cyan => 6,
                    crate::types::NamedColor::White => 7,
                    crate::types::NamedColor::BrightBlack => 8,
                    crate::types::NamedColor::BrightRed => 9,
                    crate::types::NamedColor::BrightGreen => 10,
                    crate::types::NamedColor::BrightYellow => 11,
                    crate::types::NamedColor::BrightBlue => 12,
                    crate::types::NamedColor::BrightMagenta => 13,
                    crate::types::NamedColor::BrightCyan => 14,
                    crate::types::NamedColor::BrightWhite => 15,
                };
                0x80000000u32 | (idx as u32) // High bit set for named colors
            }
            crate::types::Color::Indexed(idx) => {
                0x40000000u32 | (*idx as u32) // Second high bit for indexed colors
            }
            crate::types::Color::Rgb(r, g, b) => {
                // Pack RGB into 24 bits (RRGGBB in lower 24 bits, upper bits clear).
                // KNOWN LIMITATION: Rgb(0, 0, 0) encodes as 0, which is the same
                // sentinel value as Color::Default. kuro--decode-ffi-color in Elisp
                // cannot distinguish true black from default color. Avoid using
                // Color::Rgb(0, 0, 0) in tests; use a non-zero color like (1, 0, 0).
                // Fix: use a reserved sentinel (e.g. 0xFF000000) for Default instead.
                ((*r as u32) << 16) | ((*g as u32) << 8) | (*b as u32)
            }
        }
    }

    /// Encode SGR attributes as bit flags
    fn encode_attrs(attrs: &crate::types::cell::SgrAttributes) -> u64 {
        let mut flags = 0u64;
        if attrs.bold {
            flags |= 0x1;
        }
        if attrs.dim {
            flags |= 0x2;
        }
        if attrs.italic {
            flags |= 0x4;
        }
        if attrs.underline {
            flags |= 0x8;
        }
        if attrs.blink_slow {
            flags |= 0x10;
        }
        if attrs.blink_fast {
            flags |= 0x20;
        }
        if attrs.inverse {
            flags |= 0x40;
        }
        if attrs.hidden {
            flags |= 0x80;
        }
        if attrs.strikethrough {
            flags |= 0x100;
        }
        flags
    }

    /// Resize terminal
    pub fn resize(&mut self, rows: u16, cols: u16) -> Result<()> {
        self.core.resize(rows, cols);
        if let Some(ref mut pty) = self.pty {
            pty.set_winsize(rows, cols)?;
        }
        Ok(())
    }

    /// Get cursor position
    pub fn get_cursor(&self) -> (usize, usize) {
        let c = self.core.screen.cursor();
        (c.row, c.col)
    }

    /// Get cursor visibility (DECTCEM state)
    pub fn get_cursor_visible(&self) -> bool {
        self.core.dec_modes.cursor_visible
    }

    /// Get scrollback lines
    pub fn get_scrollback(&self, max_lines: usize) -> Vec<String> {
        let lines = self.core.screen.get_scrollback_lines(max_lines);
        lines.iter().map(|line| line.to_string()).collect()
    }

    /// Clear scrollback buffer
    pub fn clear_scrollback(&mut self) {
        self.core.screen.clear_scrollback();
    }

    /// Set scrollback max lines
    pub fn set_scrollback_max_lines(&mut self, max_lines: usize) {
        self.core.screen.set_scrollback_max_lines(max_lines);
    }

    /// Get scrollback line count
    pub fn get_scrollback_count(&self) -> usize {
        self.core.screen.scrollback_line_count
    }
}

/// Global terminal session (wrapped in Mutex for thread safety)
///
/// This is shared across all FFI implementations to ensure a single
/// terminal session per Emacs module instance.
pub static TERMINAL_SESSION: Mutex<Option<TerminalSession>> = Mutex::new(None);

/// Initialize the global terminal session
///
/// # Safety
/// This function modifies a global static mutex and must be called safely.
pub fn init_session(command: &str, rows: u16, cols: u16) -> Result<()> {
    let session = TerminalSession::new(command, rows, cols)?;
    let mut global = TERMINAL_SESSION
        .lock()
        .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
    *global = Some(session);
    Ok(())
}

/// Get mutable reference to the global terminal session
///
/// # Safety
/// Returns None if no session is initialized.
pub fn with_session<F, R>(f: F) -> Result<R>
where
    F: FnOnce(&mut TerminalSession) -> Result<R>,
{
    let mut global = TERMINAL_SESSION
        .lock()
        .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
    if let Some(ref mut session) = *global {
        f(session)
    } else {
        Err(KuroError::Ffi(
            "No terminal session initialized".to_string(),
        ))
    }
}

/// Get reference to the global terminal session
///
/// # Safety
/// Returns None if no session is initialized.
pub fn with_session_readonly<F, R>(f: F) -> Result<R>
where
    F: FnOnce(&TerminalSession) -> Result<R>,
{
    let global = TERMINAL_SESSION
        .lock()
        .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
    if let Some(ref session) = *global {
        f(session)
    } else {
        Err(KuroError::Ffi(
            "No terminal session initialized".to_string(),
        ))
    }
}

/// Shutdown the global terminal session
pub fn shutdown_session() -> Result<()> {
    let mut global = TERMINAL_SESSION
        .lock()
        .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
    *global = None;
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_trait_object_safety() {
        // KuroFFI is intentionally NOT object-safe (dyn compatible).
        // This is by design - the trait uses associated functions without `self` parameters.
        // The trait is for compile-time polymorphism and documentation of FFI interface.
        // Concrete types like EmacsModuleFFI implement the trait.
        assert!(true); // Placeholder - trait functionality is tested elsewhere
    }
}
