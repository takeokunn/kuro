//! FFI abstraction trait for Emacs module integration
//!
//! This module provides a trait-based abstraction over the Emacs module API,
//! allowing the core terminal logic to be insulated from direct dependencies
//! on emacs-module-rs. This enables:
//! - Easy fallback to raw FFI if emacs-module-rs fails
//! - Simplified testing through trait mocking
//! - Future-proofing for alternative FFI implementations

#[cfg(unix)]
use crate::pty::Pty;
use crate::{error::KuroError, Result, TerminalCore};
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
    /// PTY handle (Unix only)
    #[cfg(unix)]
    pty: Option<Pty>,
    /// Reusable render buffer to reduce allocations
    render_buffer: String,
}

impl TerminalSession {
    /// Create a new terminal session
    pub fn new(command: &str, rows: u16, cols: u16) -> Result<Self> {
        let core = TerminalCore::new(rows, cols);

        #[cfg(unix)]
        {
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

        #[cfg(not(unix))]
        Ok(Self {
            core,
            render_buffer: String::with_capacity(cols as usize),
        })
    }

    /// Send input to PTY
    pub fn send_input(&mut self, bytes: &[u8]) -> Result<()> {
        #[cfg(unix)]
        if let Some(ref mut pty) = self.pty {
            pty.write(bytes)?;
        }
        #[cfg(not(unix))]
        let _ = bytes;
        Ok(())
    }

    /// Poll for PTY output and update terminal
    pub fn poll_output(&mut self) -> Result<Vec<u8>> {
        #[cfg(unix)]
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
            let text_opt: Option<String> = self.core.screen.get_line(row).map(|line| {
                // Wide placeholder cells (CellWidth::Wide) are included as ' ' chars,
                // maintaining the grid_col == buffer_char_offset invariant (Phase 11).
                let s: String = line.cells.iter().map(|c| c.char()).collect();
                // Trim trailing spaces so Emacs doesn't fill lines with whitespace
                s.trim_end_matches(' ').to_string()
            });
            if let Some(text) = text_opt {
                result.push((row, text));
            }
        }

        result
    }

    /// Encode color as u32 for efficient FFI transfer
    fn encode_color(color: &crate::types::Color) -> u32 {
        match color {
            crate::types::Color::Default => 0xFF000000u32, // Sentinel: distinct from Rgb(0,0,0) which encodes as 0
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
                // Color::Default uses 0xFF000000 as sentinel so Rgb(0,0,0) encodes
                // unambiguously as 0 and is correctly decoded as true black in Elisp.
                ((*r as u32) << 16) | ((*g as u32) << 8) | (*b as u32)
            }
        }
    }

    /// Encode a single line's cells into (row, trimmed_text, face_ranges).
    ///
    /// This is the shared cell-iteration and face-encoding logic used by both the
    /// scrollback viewport path and the live dirty-line path in `get_dirty_lines_with_faces`.
    #[allow(clippy::type_complexity)]
    fn encode_line_faces(
        &mut self,
        row: usize,
        cells: &[crate::types::cell::Cell],
    ) -> (usize, String, Vec<(usize, usize, u32, u32, u64)>) {
        self.render_buffer.clear();

        let mut face_ranges = Vec::new();
        let mut current_start = 0usize;
        let mut current_fg = 0u32;
        let mut current_bg = 0u32;
        let mut current_flags = 0u64;

        for (col, cell) in cells.iter().enumerate() {
            self.render_buffer.push(cell.char());

            let fg = Self::encode_color(&cell.attrs.foreground);
            let bg = Self::encode_color(&cell.attrs.background);
            let flags = Self::encode_attrs(&cell.attrs);

            if fg != current_fg || bg != current_bg || flags != current_flags {
                if col > current_start {
                    face_ranges.push((current_start, col, current_fg, current_bg, current_flags));
                    current_start = col;
                }
                current_fg = fg;
                current_bg = bg;
                current_flags = flags;
            }
        }

        // Push final segment
        if current_start < cells.len() {
            face_ranges.push((
                current_start,
                cells.len(),
                current_fg,
                current_bg,
                current_flags,
            ));
        }

        // Trim trailing spaces
        let trimmed_len = self.render_buffer.trim_end_matches(' ').len();
        self.render_buffer.truncate(trimmed_len);

        (row, self.render_buffer.clone(), face_ranges)
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
        if attrs.underline() {
            flags |= 0x8;
        }
        // Encode underline style in bits 9-11 (0=None, 1=Straight, 2=Double, 3=Curly, 4=Dotted, 5=Dashed)
        let style_bits = match attrs.underline_style {
            crate::types::cell::UnderlineStyle::None => 0u64,
            crate::types::cell::UnderlineStyle::Straight => 1u64,
            crate::types::cell::UnderlineStyle::Double => 2u64,
            crate::types::cell::UnderlineStyle::Curly => 3u64,
            crate::types::cell::UnderlineStyle::Dotted => 4u64,
            crate::types::cell::UnderlineStyle::Dashed => 5u64,
        };
        flags |= style_bits << 9;
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
        #[cfg(unix)]
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

    /// Return a base64-encoded PNG string for the given image ID.
    /// Returns an empty string if the image is not found (orphan reference).
    pub fn get_image_png_base64(&self, image_id: u32) -> String {
        self.core.screen.get_image_png_base64(image_id)
    }

    /// Drain and return all pending image placement notifications.
    pub fn take_pending_image_notifications(
        &mut self,
    ) -> Vec<crate::grid::screen::ImageNotification> {
        std::mem::take(&mut self.core.pending_image_notifications)
    }

    /// Get scrollback line count
    pub fn get_scrollback_count(&self) -> usize {
        self.core.screen.scrollback_line_count
    }

    /// Scroll the viewport up by n lines (toward older scrollback content)
    pub fn viewport_scroll_up(&mut self, n: usize) {
        self.core.screen.viewport_scroll_up(n);
    }

    /// Scroll the viewport down by n lines (toward live content)
    pub fn viewport_scroll_down(&mut self, n: usize) {
        self.core.screen.viewport_scroll_down(n);
    }

    /// Return the current viewport scroll offset (0 = live view)
    pub fn scroll_offset(&self) -> usize {
        self.core.screen.scroll_offset()
    }

    /// Get dirty lines with face ranges from screen, with scrollback viewport support
    ///
    /// When the viewport is scrolled back (`scroll_offset > 0`) and `scroll_dirty` is
    /// set, returns all rows as scrollback content. Otherwise falls through to the
    /// standard live dirty-line path.
    ///
    /// Returns a list where each element is (line_no, text, face_ranges)
    /// face_ranges is a list of (start_col, end_col, fg_color, bg_color, flags)
    #[allow(clippy::type_complexity)]
    pub fn get_dirty_lines_with_faces(
        &mut self,
    ) -> Vec<(usize, String, Vec<(usize, usize, u32, u32, u64)>)> {
        // Scrollback viewport path: when scroll_dirty, return scrollback lines instead of live lines
        if self.core.screen.is_scroll_dirty() && self.core.screen.scroll_offset() > 0 {
            self.core.screen.clear_scroll_dirty();
            let rows = self.core.screen.rows() as usize;
            let mut result = Vec::with_capacity(rows);
            for row in 0..rows {
                match self.core.screen.get_scrollback_viewport_line(row) {
                    Some(line) => {
                        let cells = line.cells.clone(); // clone to avoid borrow conflict
                        let encoded = self.encode_line_faces(row, &cells);
                        result.push(encoded);
                    }
                    None => {
                        // No scrollback line at this viewport row — emit blank
                        result.push((row, String::new(), vec![]));
                    }
                }
            }
            return result;
        }

        // If viewport is scrolled but not dirty (scroll_dirty == false),
        // suppress live dirty lines to preserve the scrollback view.
        // PTY output still advances internal state but is not displayed.
        if self.core.screen.scroll_offset() > 0 {
            // Drain dirty set to prevent accumulation, but return empty
            // (full_dirty will be set by viewport_scroll_down on return to live)
            let _discard = self.core.screen.take_dirty_lines();
            return vec![];
        }

        let dirty_indices = self.core.screen.take_dirty_lines();
        let mut result = Vec::new();

        // WIDE-PLACEHOLDER INVARIANT (Phase 11):
        // Wide placeholder cells (CellWidth::Wide) emit their char (' ') to
        // render_buffer just like any other cell. This preserves the invariant:
        //
        //   grid_column_index == buffer_character_offset
        //
        // because every CellWidth::Full cell is immediately followed by exactly
        // one CellWidth::Wide placeholder, keeping column and buffer offset in sync.
        // kuro--update-cursor and kuro--apply-faces-from-ffi rely on this invariant.
        // DO NOT filter out Wide placeholder cells without updating both Elisp functions.
        for row in dirty_indices {
            if let Some(line) = self.core.screen.get_line(row) {
                let cells: Vec<crate::types::cell::Cell> = line.cells.clone();
                let encoded = self.encode_line_faces(row, &cells);
                result.push(encoded);
            }
        }

        result
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
    use super::*;
    use crate::types::cell::{Cell, SgrAttributes};
    use crate::types::color::{Color, NamedColor};
    use proptest::prelude::*;

    // Helper: construct a TerminalSession without spawning a real PTY.
    // Since this test module is a child of `abstraction`, it can access private fields.
    fn make_session() -> TerminalSession {
        TerminalSession {
            core: crate::TerminalCore::new(24, 80),
            #[cfg(unix)]
            pty: None,
            render_buffer: String::with_capacity(80),
        }
    }

    // ---------------------------------------------------------------------------
    // B-3: Unit tests
    // ---------------------------------------------------------------------------

    #[test]
    fn test_trait_object_safety() {
        // KuroFFI is intentionally NOT object-safe (dyn compatible).
        // This is by design - the trait uses associated functions without `self` parameters.
        // The trait is for compile-time polymorphism and documentation of the
        // FFI interface, not for runtime trait objects.
        // Concrete types like EmacsModuleFFI implement the trait.
    }

    #[test]
    fn test_encode_color_default() {
        // Color::Default must encode to the sentinel value 0xFF000000,
        // not 0 (which is reserved for true black Rgb(0,0,0)).
        assert_eq!(
            TerminalSession::encode_color(&Color::Default),
            0xFF000000u32
        );
    }

    #[test]
    fn test_encode_color_rgb_true_black() {
        // Rgb(0,0,0) must encode to 0 (true black), NOT the same as Default.
        assert_eq!(TerminalSession::encode_color(&Color::Rgb(0, 0, 0)), 0u32);
    }

    #[test]
    fn test_encode_color_named_red() {
        // Named(Red) has index 1, encoded with the 0x80000000 high-bit marker.
        let expected = 0x80000000u32 | 1u32;
        assert_eq!(
            TerminalSession::encode_color(&Color::Named(NamedColor::Red)),
            expected
        );
    }

    #[test]
    fn test_encode_color_indexed() {
        // Indexed(16) is encoded with the 0x40000000 second-high-bit marker.
        let expected = 0x40000000u32 | 16u32;
        assert_eq!(TerminalSession::encode_color(&Color::Indexed(16)), expected);
    }

    #[test]
    fn test_encode_attrs_all_false() {
        // All SGR boolean flags false → bitmask must be 0.
        let attrs = SgrAttributes::default();
        assert_eq!(TerminalSession::encode_attrs(&attrs), 0u64);
    }

    #[test]
    fn test_encode_attrs_bold() {
        // Bold sets bit 0 (0x1).
        let mut attrs = SgrAttributes::default();
        attrs.bold = true;
        assert_eq!(TerminalSession::encode_attrs(&attrs), 0x1u64);
    }

    #[test]
    fn test_encode_attrs_all_true() {
        // All 9 SGR flags true → all 9 bits set → 0x1FF.
        let attrs = SgrAttributes {
            foreground: Color::Default,
            background: Color::Default,
            bold: true,
            dim: true,
            italic: true,
            underline_style: crate::types::cell::UnderlineStyle::Straight,
            underline_color: Color::Default,
            blink_slow: true,
            blink_fast: true,
            inverse: true,
            hidden: true,
            strikethrough: true,
        };
        let result = TerminalSession::encode_attrs(&attrs);
        assert_ne!(result, 0u64);
        // Verify all 9 flag bits are set
        assert_eq!(result & 0x1FF, 0x1FFu64);
    }

    #[test]
    fn test_with_session_no_session() {
        // Ensure no session is active, then verify with_session returns an error.
        shutdown_session().ok();
        let result = with_session(|_s| Ok(()));
        assert!(
            result.is_err(),
            "with_session should return Err when no session is initialized"
        );
    }

    #[test]
    fn test_shutdown_session() {
        // shutdown_session must not panic, even when no session exists.
        let result = shutdown_session();
        assert!(
            result.is_ok(),
            "shutdown_session should succeed even with no active session"
        );
    }

    // ---------------------------------------------------------------------------
    // B-1: Property-based tests with proptest
    // ---------------------------------------------------------------------------

    // Strategy: generate arbitrary Color values.
    fn arb_color() -> impl Strategy<Value = Color> {
        prop_oneof![
            Just(Color::Default),
            (0u8..=15u8).prop_map(|idx| {
                let named = match idx {
                    0 => NamedColor::Black,
                    1 => NamedColor::Red,
                    2 => NamedColor::Green,
                    3 => NamedColor::Yellow,
                    4 => NamedColor::Blue,
                    5 => NamedColor::Magenta,
                    6 => NamedColor::Cyan,
                    7 => NamedColor::White,
                    8 => NamedColor::BrightBlack,
                    9 => NamedColor::BrightRed,
                    10 => NamedColor::BrightGreen,
                    11 => NamedColor::BrightYellow,
                    12 => NamedColor::BrightBlue,
                    13 => NamedColor::BrightMagenta,
                    14 => NamedColor::BrightCyan,
                    _ => NamedColor::BrightWhite,
                };
                Color::Named(named)
            }),
            any::<u8>().prop_map(Color::Indexed),
            (any::<u8>(), any::<u8>(), any::<u8>()).prop_map(|(r, g, b)| Color::Rgb(r, g, b)),
        ]
    }

    // Strategy: generate arbitrary SgrAttributes.
    fn arb_sgr_attrs() -> impl Strategy<Value = SgrAttributes> {
        (
            arb_color(),
            arb_color(),
            any::<bool>(),
            any::<bool>(),
            any::<bool>(),
            any::<bool>(),
            any::<bool>(),
            any::<bool>(),
            any::<bool>(),
            any::<bool>(),
            any::<bool>(),
        )
            .prop_map(
                |(
                    fg,
                    bg,
                    bold,
                    dim,
                    italic,
                    underline,
                    blink_slow,
                    blink_fast,
                    inverse,
                    hidden,
                    strikethrough,
                )| {
                    SgrAttributes {
                        foreground: fg,
                        background: bg,
                        bold,
                        dim,
                        italic,
                        underline_style: if underline {
                            crate::types::cell::UnderlineStyle::Straight
                        } else {
                            crate::types::cell::UnderlineStyle::None
                        },
                        underline_color: Color::Default,
                        blink_slow,
                        blink_fast,
                        inverse,
                        hidden,
                        strikethrough,
                    }
                },
            )
    }

    // Strategy: generate an arbitrary Cell.
    fn arb_cell() -> impl Strategy<Value = Cell> {
        (arb_sgr_attrs(), any::<char>()).prop_map(|(attrs, c)| Cell::with_attrs(c, attrs))
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(256))]
        /// Property: Color::Default must NEVER encode to 0.
        /// Color::Rgb(0,0,0) encodes to 0; all other variants must differ from 0 or
        /// match the expected sentinel (0xFF000000 for Default).
        #[test]
        fn prop_encode_color_no_collision(color in arb_color()) {
            let encoded = TerminalSession::encode_color(&color);
            match &color {
                Color::Default => {
                    prop_assert_eq!(encoded, 0xFF000000u32,
                        "Color::Default must encode to sentinel 0xFF000000");
                }
                Color::Rgb(0, 0, 0) => {
                    prop_assert_eq!(encoded, 0u32,
                        "Rgb(0,0,0) must encode to 0 (true black)");
                }
                _ => {
                    // All other colors must not collide with the Default sentinel
                    prop_assert_ne!(encoded, 0xFF000000u32,
                        "Non-Default color must not encode to the Default sentinel 0xFF000000");
                }
            }
        }

        /// Property: encode_attrs must never panic with arbitrary flag combinations,
        /// and the result must only have bits 0–11 set (9 SGR flags + 3 underline style bits).
        #[test]
        fn prop_encode_attrs_all_flags(attrs in arb_sgr_attrs()) {
            let result = TerminalSession::encode_attrs(&attrs);
            // Bits 0..=8 are the 9 SGR boolean flags; bits 9..=11 encode underline style (0-5)
            prop_assert_eq!(result & !0xFFFu64, 0u64,
                "encode_attrs must not set bits outside the 12 defined flag positions");
        }

        /// Property: encode_line_faces must never panic with arbitrary cell slices.
        #[test]
        fn prop_encode_line_faces_no_panic(cells in prop::collection::vec(arb_cell(), 0..=80)) {
            let mut session = make_session();
            let row = 0usize;
            // Should not panic regardless of cell content
            let _ = session.encode_line_faces(row, &cells);
        }
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(256))]
        #[test]
        // INVARIANT: encode_line_faces() face ranges form complete, non-overlapping coverage
        // of [0, cells.len()) with no gaps. The algorithm uses run-length merging,
        // so face_ranges.len() <= cells.len() (not equal).
        fn prop_encode_line_faces_coverage_invariant(
            cells in proptest::collection::vec(arb_cell(), 1..=80usize),
        ) {
            let mut session = make_session();
            let row = 0usize;
            let (_row, _text, face_ranges) = session.encode_line_faces(row, &cells);

            // Invariant 1: non-empty output for non-empty input
            prop_assert!(!face_ranges.is_empty(),
                "encode_line_faces returned empty vec for {} cells", cells.len());

            // Invariant 2: first range starts at column 0
            prop_assert_eq!(face_ranges[0].0, 0,
                "First range must start at column 0, got {}", face_ranges[0].0);

            // Invariant 3: last range ends at cells.len()
            let last = face_ranges.last().unwrap();
            prop_assert_eq!(last.1, cells.len(),
                "Last range must end at {}, got {}", cells.len(), last.1);

            // Invariant 4: consecutive ranges are contiguous (no gaps, no overlaps)
            for window in face_ranges.windows(2) {
                prop_assert_eq!(window[0].1, window[1].0,
                    "Gap/overlap between ranges: first ends at {}, next starts at {}",
                    window[0].1, window[1].0);
            }

            // Invariant 5: each range is non-empty (start < end)
            for (start, end, _, _, _) in &face_ranges {
                prop_assert!(start < end,
                    "Empty range found: start={}, end={}", start, end);
            }
        }
    }

    // ---------------------------------------------------------------------------
    // FR-007: SGR → Cell → FFI integration roundtrip tests
    // ---------------------------------------------------------------------------

    #[test]
    fn test_integration_bold_rgb_fg() {
        // SGR: bold (1) + truecolor fg Rgb(255, 0, 128) + print 'X'
        // Expected face_ranges[0] = (0, 1, 0x00FF0080, 0xFF000000, 0x01)
        //   fg = Rgb(255, 0, 128) = (255 << 16) | (0 << 8) | 128 = 0x00FF0080
        //   bg = Color::Default sentinel = 0xFF000000
        //   flags = bold = 0x01
        let mut session = make_session();
        session.core.advance(b"\x1b[1;38;2;255;0;128mX");
        let results = session.get_dirty_lines_with_faces();

        assert!(!results.is_empty(), "Expected dirty lines after advancing");
        let (_row, text, face_ranges) = &results[0];
        assert_eq!(text.trim_end(), "X", "Expected 'X' in line text");
        assert!(
            !face_ranges.is_empty(),
            "Expected face ranges for styled text"
        );

        // The FIRST face range covers the styled 'X' at column 0
        let (start, end, fg, bg, flags) = face_ranges[0];
        assert_eq!(start, 0, "First range should start at column 0");
        assert_eq!(end, 1, "First range for 'X' should end at column 1");
        assert_eq!(
            fg, 0x00FF0080u32,
            "fg should be Rgb(255,0,128) = 0x00FF0080"
        );
        assert_eq!(
            bg, 0xFF000000u32,
            "bg should be Default sentinel = 0xFF000000"
        );
        assert_eq!(flags, 0x01u64, "flags should have bold bit set (0x01)");
    }

    #[test]
    fn test_integration_named_color_red() {
        // Named color red: \x1b[31m sets foreground to Named(Red)
        // Named(Red) encodes as 0x80000001 (bit 31 set | index 1)
        let mut session = make_session();
        session.core.advance(b"\x1b[31mA");
        let results = session.get_dirty_lines_with_faces();

        assert!(!results.is_empty());
        let (_row, text, face_ranges) = &results[0];
        assert!(text.contains('A'));
        assert!(!face_ranges.is_empty());

        let (start, end, fg, _bg, _flags) = face_ranges[0];
        assert_eq!(start, 0);
        assert_eq!(end, 1);
        assert_eq!(fg, 0x80000001u32, "Named(Red) should encode as 0x80000001");
    }

    #[test]
    fn test_integration_indexed_color() {
        // 256-color indexed: \x1b[38;5;42m sets foreground to Indexed(42)
        // Indexed(42) encodes as 0x40000000 | 42 = 0x4000002A
        let mut session = make_session();
        session.core.advance(b"\x1b[38;5;42mB");
        let results = session.get_dirty_lines_with_faces();

        assert!(!results.is_empty());
        let (_row, text, face_ranges) = &results[0];
        assert!(text.contains('B'));
        assert!(!face_ranges.is_empty());

        let (_, _, fg, _, _) = face_ranges[0];
        assert_eq!(fg, 0x4000002Au32, "Indexed(42) should encode as 0x4000002A");
    }

    #[test]
    fn test_integration_true_black_vs_default() {
        // Rgb(0,0,0) (true black) should encode as 0 (not 0xFF000000)
        // Color::Default should encode as 0xFF000000 (sentinel)
        let mut session = make_session();

        // Print with true black foreground
        session.core.advance(b"\x1b[38;2;0;0;0mC");
        let results = session.get_dirty_lines_with_faces();

        assert!(!results.is_empty());
        let (_row, _text, face_ranges) = &results[0];
        assert!(!face_ranges.is_empty());

        let (_, _, fg, bg, _) = face_ranges[0];
        // True black: Rgb(0,0,0) = 0
        assert_eq!(
            fg, 0u32,
            "Rgb(0,0,0) must encode as 0 (true black), not 0xFF000000"
        );
        // Background is still default
        assert_eq!(bg, 0xFF000000u32, "Default bg should encode as 0xFF000000");
    }

    #[test]
    fn test_integration_default_color_sentinel() {
        // Without any color set, both fg and bg should use the Default sentinel
        let mut session = make_session();
        session.core.advance(b"D");
        let results = session.get_dirty_lines_with_faces();

        assert!(
            !results.is_empty(),
            "Expected dirty output after printing 'D'"
        );
        let (_row, _text, face_ranges) = &results[0];
        assert!(
            !face_ranges.is_empty(),
            "Expected face ranges for default-color cell"
        );
        let (_, _, fg, bg, flags) = face_ranges[0];
        assert_eq!(
            fg, 0xFF000000u32,
            "Default fg should be 0xFF000000 sentinel"
        );
        assert_eq!(
            bg, 0xFF000000u32,
            "Default bg should be 0xFF000000 sentinel"
        );
        assert_eq!(flags, 0u64, "No attributes set");
    }

    // ---------------------------------------------------------------------------
    // Named color encode_color tests (all variants except Red, which is tested above)
    // ---------------------------------------------------------------------------

    #[test]
    fn test_encode_color_named_black() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::Black));
        let expected = 0x80000000u32 | 0u32;
        assert_eq!(encoded, expected, "Black should encode as 0x80000000");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_green() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::Green));
        let expected = 0x80000000u32 | 2u32;
        assert_eq!(encoded, expected, "Green should encode as 0x80000002");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_yellow() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::Yellow));
        let expected = 0x80000000u32 | 3u32;
        assert_eq!(encoded, expected, "Yellow should encode as 0x80000003");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_blue() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::Blue));
        let expected = 0x80000000u32 | 4u32;
        assert_eq!(encoded, expected, "Blue should encode as 0x80000004");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_magenta() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::Magenta));
        let expected = 0x80000000u32 | 5u32;
        assert_eq!(encoded, expected, "Magenta should encode as 0x80000005");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_cyan() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::Cyan));
        let expected = 0x80000000u32 | 6u32;
        assert_eq!(encoded, expected, "Cyan should encode as 0x80000006");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_white() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::White));
        let expected = 0x80000000u32 | 7u32;
        assert_eq!(encoded, expected, "White should encode as 0x80000007");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_bright_black() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::BrightBlack));
        let expected = 0x80000000u32 | 8u32;
        assert_eq!(encoded, expected, "BrightBlack should encode as 0x80000008");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_bright_red() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::BrightRed));
        let expected = 0x80000000u32 | 9u32;
        assert_eq!(encoded, expected, "BrightRed should encode as 0x80000009");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_bright_green() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::BrightGreen));
        let expected = 0x80000000u32 | 10u32;
        assert_eq!(encoded, expected, "BrightGreen should encode as 0x8000000A");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_bright_yellow() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::BrightYellow));
        let expected = 0x80000000u32 | 11u32;
        assert_eq!(
            encoded, expected,
            "BrightYellow should encode as 0x8000000B"
        );
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_bright_blue() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::BrightBlue));
        let expected = 0x80000000u32 | 12u32;
        assert_eq!(encoded, expected, "BrightBlue should encode as 0x8000000C");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_bright_magenta() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::BrightMagenta));
        let expected = 0x80000000u32 | 13u32;
        assert_eq!(
            encoded, expected,
            "BrightMagenta should encode as 0x8000000D"
        );
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_bright_cyan() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::BrightCyan));
        let expected = 0x80000000u32 | 14u32;
        assert_eq!(encoded, expected, "BrightCyan should encode as 0x8000000E");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_encode_color_named_bright_white() {
        let encoded = TerminalSession::encode_color(&Color::Named(NamedColor::BrightWhite));
        let expected = 0x80000000u32 | 15u32;
        assert_eq!(encoded, expected, "BrightWhite should encode as 0x8000000F");
        assert_ne!(encoded, 0);
        assert_ne!(encoded, 0xFF000000u32);
    }

    #[test]
    fn test_named_colors_are_unique() {
        // All 16 named colors must produce distinct encoded values.
        use std::collections::HashSet;
        let colors = [
            NamedColor::Black,
            NamedColor::Red,
            NamedColor::Green,
            NamedColor::Yellow,
            NamedColor::Blue,
            NamedColor::Magenta,
            NamedColor::Cyan,
            NamedColor::White,
            NamedColor::BrightBlack,
            NamedColor::BrightRed,
            NamedColor::BrightGreen,
            NamedColor::BrightYellow,
            NamedColor::BrightBlue,
            NamedColor::BrightMagenta,
            NamedColor::BrightCyan,
            NamedColor::BrightWhite,
        ];
        let encoded_set: HashSet<u32> = colors
            .iter()
            .map(|c| TerminalSession::encode_color(&Color::Named(*c)))
            .collect();
        assert_eq!(
            encoded_set.len(),
            16,
            "All 16 named colors must have unique encodings"
        );
    }

    // ---------------------------------------------------------------------------
    // SGR attribute flag tests (all except bold and all_true which are already tested)
    // ---------------------------------------------------------------------------

    #[test]
    fn test_encode_attrs_dim() {
        let mut attrs = SgrAttributes::default();
        attrs.dim = true;
        let result = TerminalSession::encode_attrs(&attrs);
        assert_eq!(result, 0x2u64, "dim sets bit 1 (0x2)");
        assert_ne!(result, 0);
    }

    #[test]
    fn test_encode_attrs_italic() {
        let mut attrs = SgrAttributes::default();
        attrs.italic = true;
        let result = TerminalSession::encode_attrs(&attrs);
        assert_eq!(result, 0x4u64, "italic sets bit 2 (0x4)");
        assert_ne!(result, 0);
    }

    #[test]
    fn test_encode_attrs_underline() {
        let mut attrs = SgrAttributes::default();
        attrs.underline_style = crate::types::cell::UnderlineStyle::Straight;
        let result = TerminalSession::encode_attrs(&attrs);
        assert_eq!(result & 0x8u64, 0x8u64, "underline sets bit 3 (0x8)");
        assert_ne!(result, 0);
    }

    #[test]
    fn test_encode_attrs_blink_slow() {
        let mut attrs = SgrAttributes::default();
        attrs.blink_slow = true;
        let result = TerminalSession::encode_attrs(&attrs);
        assert_eq!(result, 0x10u64, "blink_slow sets bit 4 (0x10)");
        assert_ne!(result, 0);
    }

    #[test]
    fn test_encode_attrs_blink_fast() {
        let mut attrs = SgrAttributes::default();
        attrs.blink_fast = true;
        let result = TerminalSession::encode_attrs(&attrs);
        assert_eq!(result, 0x20u64, "blink_fast sets bit 5 (0x20)");
        assert_ne!(result, 0);
    }

    #[test]
    fn test_encode_attrs_inverse() {
        let mut attrs = SgrAttributes::default();
        attrs.inverse = true;
        let result = TerminalSession::encode_attrs(&attrs);
        assert_eq!(result, 0x40u64, "inverse sets bit 6 (0x40)");
        assert_ne!(result, 0);
    }

    #[test]
    fn test_encode_attrs_hidden() {
        let mut attrs = SgrAttributes::default();
        attrs.hidden = true;
        let result = TerminalSession::encode_attrs(&attrs);
        assert_eq!(result, 0x80u64, "hidden sets bit 7 (0x80)");
        assert_ne!(result, 0);
    }

    #[test]
    fn test_encode_attrs_strikethrough() {
        let mut attrs = SgrAttributes::default();
        attrs.strikethrough = true;
        let result = TerminalSession::encode_attrs(&attrs);
        assert_eq!(result, 0x100u64, "strikethrough sets bit 8 (0x100)");
        assert_ne!(result, 0);
    }

    #[test]
    fn test_sgr_flag_bits_are_distinct() {
        // Each individual SGR flag must produce a unique non-zero bitmask.
        use std::collections::HashSet;
        let mut bits = HashSet::new();

        let flags: &[(&str, fn(&mut SgrAttributes))] = &[
            ("bold", |a| a.bold = true),
            ("dim", |a| a.dim = true),
            ("italic", |a| a.italic = true),
            ("underline", |a: &mut SgrAttributes| {
                a.underline_style = crate::types::cell::UnderlineStyle::Straight
            }),
            ("blink_slow", |a| a.blink_slow = true),
            ("blink_fast", |a| a.blink_fast = true),
            ("inverse", |a| a.inverse = true),
            ("hidden", |a| a.hidden = true),
            ("strikethrough", |a| a.strikethrough = true),
        ];

        for (name, setter) in flags {
            let mut attrs = SgrAttributes::default();
            setter(&mut attrs);
            let encoded = TerminalSession::encode_attrs(&attrs);
            assert_ne!(
                encoded, 0,
                "Flag '{}' must produce a non-zero bitmask",
                name
            );
            assert!(
                bits.insert(encoded),
                "Flag '{}' produced a duplicate bitmask",
                name
            );
        }
    }

    // ---------------------------------------------------------------------------
    // encode_line_faces and send_input edge cases
    // ---------------------------------------------------------------------------

    #[test]
    fn test_encode_line_faces_empty_line() {
        // An empty cell slice (zero-length row) must produce an empty face_ranges vec.
        let mut session = make_session();
        let cells: Vec<crate::types::cell::Cell> = vec![];
        let (row, text, face_ranges) = session.encode_line_faces(0, &cells);
        assert_eq!(row, 0);
        assert_eq!(text, "", "empty cell slice should produce empty text");
        assert!(
            face_ranges.is_empty(),
            "empty cell slice should produce no face ranges"
        );
    }

    #[test]
    fn test_session_send_input_empty() {
        // send_input with an empty byte slice must not panic and must return Ok.
        let mut session = make_session();
        let result = session.send_input(&[]);
        assert!(
            result.is_ok(),
            "send_input with empty slice should return Ok"
        );
    }
}
