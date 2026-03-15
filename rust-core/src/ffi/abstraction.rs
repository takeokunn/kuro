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

pub use super::kuro_ffi::{emacs_env, emacs_value, KuroFFI};

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
}

impl TerminalSession {
    /// Create a new terminal session
    pub fn new(command: &str, rows: u16, cols: u16) -> Result<Self> {
        let core = TerminalCore::new(rows, cols);

        #[cfg(unix)]
        {
            // Pty::spawn now takes rows/cols and passes them to openpty so the PTY
            // is created with the correct window size before the child process starts.
            // This prevents readline from seeing 0×0 columns on its first TIOCGWINSZ
            // query, which would otherwise put it into dumb terminal mode (causing
            // control characters to echo as ^X instead of moving the cursor).
            let mut pty = Pty::spawn(command, rows, cols)?;
            // Belt-and-suspenders: also call set_winsize after spawn to ensure
            // the slave-side window size is consistent across platforms.
            pty.set_winsize(rows, cols)?;

            Ok(Self {
                core,
                pty: Some(pty),
            })
        }

        #[cfg(not(unix))]
        Ok(Self { core })
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
                // NOTE: trailing spaces are intentionally NOT trimmed.
                // Trimming would cause the Emacs-side cursor clamp
                // `(min (+ line-start col) line-end)` to place the cursor at
                // the wrong column when the terminal cursor is inside whitespace
                // (e.g. after pressing SPC at a bash prompt).
                s
            });
            if let Some(text) = text_opt {
                result.push((row, text));
            }
        }

        result
    }

    /// Encode a `Color` as a `u32` for FFI transfer.
    ///
    /// Delegates to [`super::codec::encode_color`].
    #[inline]
    pub fn encode_color(color: &crate::types::Color) -> u32 {
        super::codec::encode_color(color)
    }

    /// Encode `SgrAttributes` as a `u64` bitmask for FFI transfer.
    ///
    /// Delegates to [`super::codec::encode_attrs`].
    #[inline]
    pub fn encode_attrs(attrs: &crate::types::cell::SgrAttributes) -> u64 {
        super::codec::encode_attrs(attrs)
    }

    /// Encode a single line's cells into (row, trimmed_text, face_ranges).
    ///
    /// This is a pure function (no `self` dependency) so it can be called
    /// while holding a shared borrow of the screen — eliminating the need to
    /// `clone()` the cell slice just to satisfy the borrow checker.
    ///
    /// Returns `(row, text, face_ranges, col_to_buf)` where:
    /// - `text` has wide placeholder cells removed (CJK renders correctly in Emacs)
    /// - `face_ranges` use buffer offsets (not grid column indices)
    /// - `col_to_buf[col]` maps grid column to buffer character offset
    #[allow(clippy::type_complexity)]
    fn encode_line_faces(
        row: usize,
        cells: &[crate::types::cell::Cell],
    ) -> (
        usize,
        String,
        Vec<(usize, usize, u32, u32, u64)>,
        Vec<usize>,
    ) {
        let (text, face_ranges, col_to_buf) = super::codec::encode_line(cells);
        (row, text, face_ranges, col_to_buf)
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

    /// Check if the PTY channel has pending unread data (without consuming it).
    ///
    /// Used by Elisp to trigger immediate rendering when streaming output arrives.
    #[cfg(unix)]
    pub fn has_pending_output(&self) -> bool {
        if let Some(ref pty) = self.pty {
            pty.has_pending_data()
        } else {
            false
        }
    }

    #[cfg(not(unix))]
    pub fn has_pending_output(&self) -> bool {
        false
    }

    /// Get mouse pixel mode state (?1016)
    pub fn get_mouse_pixel(&self) -> bool {
        self.core.dec_modes.mouse_pixel
    }

    /// Get current 256-color palette overrides (non-None entries only).
    ///
    /// Returns a Vec of (index, R, G, B) for each overridden palette entry.
    pub fn get_palette_updates(&self) -> Vec<(u8, u8, u8, u8)> {
        self.core
            .osc_data
            .palette
            .iter()
            .enumerate()
            .filter_map(|(i, entry)| entry.map(|[r, g, b]| (i as u8, r, g, b)))
            .collect()
    }

    /// Get default foreground/background/cursor colors (None = unset = use Emacs default).
    /// Returns (fg_encoded, bg_encoded, cursor_encoded) as u32 FFI color values.
    pub fn get_default_colors(&self) -> (u32, u32, u32) {
        let encode = |color: &Option<crate::types::Color>| -> u32 {
            match color {
                Some(c) => Self::encode_color(c),
                None => 0xFF000000u32, // Color::Default sentinel
            }
        };
        (
            encode(&self.core.osc_data.default_fg),
            encode(&self.core.osc_data.default_bg),
            encode(&self.core.osc_data.cursor_color),
        )
    }

    /// Check and clear the default-colors-dirty flag.
    pub fn take_default_colors_dirty(&mut self) -> bool {
        let dirty = self.core.osc_data.default_colors_dirty;
        self.core.osc_data.default_colors_dirty = false;
        dirty
    }

    /// Get dirty lines with face ranges from screen, with scrollback viewport support
    ///
    /// When the viewport is scrolled back (`scroll_offset > 0`) and `scroll_dirty` is
    /// set, returns all rows as scrollback content. Otherwise falls through to the
    /// standard live dirty-line path.
    ///
    /// Returns a list where each element is (line_no, text, face_ranges, col_to_buf)
    /// - face_ranges: list of (start_buf, end_buf, fg_color, bg_color, flags) in buffer offsets
    /// - col_to_buf: mapping from grid column index to buffer char offset (wide placeholders skipped)
    #[allow(clippy::type_complexity)]
    pub fn get_dirty_lines_with_faces(
        &mut self,
    ) -> Vec<(
        usize,
        String,
        Vec<(usize, usize, u32, u32, u64)>,
        Vec<usize>,
    )> {
        // Scrollback viewport path: when scroll_dirty, return scrollback lines instead of live lines
        if self.core.screen.is_scroll_dirty() && self.core.screen.scroll_offset() > 0 {
            self.core.screen.clear_scroll_dirty();
            let rows = self.core.screen.rows() as usize;
            let mut result = Vec::with_capacity(rows);
            for row in 0..rows {
                match self.core.screen.get_scrollback_viewport_line(row) {
                    Some(line) => {
                        let encoded = Self::encode_line_faces(row, &line.cells);
                        result.push(encoded);
                    }
                    None => {
                        result.push((row, String::new(), vec![], vec![]));
                    }
                }
            }
            return result;
        }

        // If viewport is scrolled but not dirty (scroll_dirty == false),
        // suppress live dirty lines to preserve the scrollback view.
        if self.core.screen.scroll_offset() > 0 {
            let _discard = self.core.screen.take_dirty_lines();
            return vec![];
        }

        // Synchronized Output mode (DEC ?2026): hold until batch complete.
        if self.core.dec_modes.synchronized_output {
            let _discard = self.core.screen.take_dirty_lines();
            return vec![];
        }

        let dirty_indices = self.core.screen.take_dirty_lines();
        let mut result = Vec::new();

        for row in dirty_indices {
            if let Some(line) = self.core.screen.get_line(row) {
                let encoded = Self::encode_line_faces(row, &line.cells);
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

/// Lock `TERMINAL_SESSION` and map mutex-poison errors to `KuroError::Ffi`.
///
/// Binding mutability is determined by the caller's `let`/`let mut` binding.
macro_rules! lock_terminal {
    () => {
        TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?
    };
}

/// Initialize the global terminal session
///
/// # Safety
/// This function modifies a global static mutex and must be called safely.
pub fn init_session(command: &str, rows: u16, cols: u16) -> Result<()> {
    let session = TerminalSession::new(command, rows, cols)?;
    let mut global = lock_terminal!();
    *global = Some(session);
    Ok(())
}

/// Get mutable reference to the global terminal session.
///
/// Returns `Err` if no session is initialized.
pub fn with_session<F, R>(f: F) -> Result<R>
where
    F: FnOnce(&mut TerminalSession) -> Result<R>,
{
    let mut global = lock_terminal!();
    if let Some(ref mut session) = *global {
        f(session)
    } else {
        Err(KuroError::Ffi(
            "No terminal session initialized".to_string(),
        ))
    }
}

/// Get shared reference to the global terminal session.
///
/// Returns `Err` if no session is initialized.
pub fn with_session_readonly<F, R>(f: F) -> Result<R>
where
    F: FnOnce(&TerminalSession) -> Result<R>,
{
    let global = lock_terminal!();
    if let Some(ref session) = *global {
        f(session)
    } else {
        Err(KuroError::Ffi(
            "No terminal session initialized".to_string(),
        ))
    }
}

/// Shutdown the global terminal session and release all resources.
pub fn shutdown_session() -> Result<()> {
    let mut global = lock_terminal!();
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

    // ---------------------------------------------------------------------------
    // Smoke tests: verify encode_color / encode_attrs delegate to codec::*
    // (exhaustive tests live in codec.rs)
    // ---------------------------------------------------------------------------

    #[test]
    fn test_encode_color_delegates_to_codec() {
        // Verify the wrapper delegates: default sentinel must match
        assert_eq!(
            TerminalSession::encode_color(&Color::Default),
            0xFF000000u32
        );
    }

    #[test]
    fn test_encode_attrs_delegates_to_codec() {
        // Verify the wrapper delegates: default attrs must encode as 0
        assert_eq!(
            TerminalSession::encode_attrs(&SgrAttributes::default()),
            0u64
        );
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
    // Synchronized Output mode (DEC ?2026) suppression tests
    // ---------------------------------------------------------------------------

    /// While ?2026h (synchronized output) is active, get_dirty_lines_with_faces must
    /// return an empty Vec. This prevents TUI apps (like claude code) from having
    /// partial frames rendered when the 60fps timer fires mid-batch.
    #[test]
    fn test_sync_output_suppresses_dirty_lines() {
        let mut session = make_session();

        // Print a line, then enable synchronized output, then print another line
        session.core.advance(b"Before sync");

        // Drain initial dirty lines so we start from a clean state
        session.core.screen.take_dirty_lines();

        // Enable synchronized output mode
        session.core.advance(b"\x1b[?2026h");
        assert!(session.core.dec_modes.synchronized_output);

        // Write content during sync
        session.core.advance(b"\x1b[2;1HDuring sync content");

        // get_dirty_lines_with_faces must return empty while sync is active
        let result = session.get_dirty_lines_with_faces();
        assert!(
            result.is_empty(),
            "get_dirty_lines_with_faces must return empty while ?2026h is active; got {} lines",
            result.len()
        );

        // Disable synchronized output — triggers full dirty flush
        session.core.advance(b"\x1b[?2026l");
        assert!(!session.core.dec_modes.synchronized_output);

        // Now all dirty lines should be available
        let result = session.get_dirty_lines_with_faces();
        assert!(
            !result.is_empty(),
            "get_dirty_lines_with_faces must return dirty lines after ?2026l; got 0"
        );
    }

    /// When ?2026l resets synchronized output, all rows must be marked dirty.
    /// This ensures the entire frame is re-rendered coherently after a sync batch.
    #[test]
    fn test_sync_output_reset_marks_all_dirty() {
        let mut session = make_session();

        // Enable sync, write content, simulate suppressed drain (as renderer would do)
        session.core.advance(b"\x1b[?2026hHello sync world");
        // Simulate suppression: drain dirty set without rendering
        session.core.screen.take_dirty_lines();

        // Reset sync: should mark_all_dirty()
        session.core.advance(b"\x1b[?2026l");

        // Verify all 24 rows are now dirty
        let dirty_count = session.core.screen.take_dirty_lines().len();
        assert_eq!(
            dirty_count, 24,
            "After ?2026l, all {} rows should be dirty; got {}",
            24, dirty_count
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
        /// Property: encode_line_faces must never panic with arbitrary cell slices.
        #[test]
        fn prop_encode_line_faces_no_panic(cells in prop::collection::vec(arb_cell(), 0..=80)) {
            let row = 0usize;
            // Should not panic regardless of cell content
            let _ = TerminalSession::encode_line_faces(row, &cells);
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
            let row = 0usize;
            let (_row, _text, face_ranges, _col_to_buf) = TerminalSession::encode_line_faces(row, &cells);

            // Invariant 1: non-empty output for non-empty input (may be empty if all wide placeholders)
            // Only assert non-empty if there are non-placeholder cells
            let non_placeholder_count = cells.iter().filter(|c| {
                !(c.width == crate::types::cell::CellWidth::Wide && c.grapheme.as_str() == " ")
            }).count();
            if non_placeholder_count > 0 {
                prop_assert!(!face_ranges.is_empty(),
                    "encode_line_faces returned empty vec for {} non-placeholder cells", non_placeholder_count);
            }

            // Invariant 2 & 3 only apply if face_ranges is non-empty
            if !face_ranges.is_empty() {
            // Invariant 2: first range starts at 0
            prop_assert_eq!(face_ranges[0].0, 0,
                "First range must start at 0, got {}", face_ranges[0].0);

            // Invariant 3: last range ends at buf_offset count (= non-placeholder cells)
            let last = face_ranges.last().unwrap();
            prop_assert_eq!(last.1, non_placeholder_count,
                "Last range must end at {}, got {}", non_placeholder_count, last.1);

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
            } // end if !face_ranges.is_empty()
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
        let (_row, text, face_ranges, _col_to_buf) = &results[0];
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
        let (_row, text, face_ranges, _col_to_buf) = &results[0];
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
        let (_row, text, face_ranges, _col_to_buf) = &results[0];
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
        let (_row, _text, face_ranges, _col_to_buf) = &results[0];
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
        let (_row, _text, face_ranges, _col_to_buf) = &results[0];
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
    // encode_line_faces and send_input edge cases
    // ---------------------------------------------------------------------------

    #[test]
    fn test_encode_line_faces_empty_line() {
        // An empty cell slice (zero-length row) must produce an empty face_ranges vec.
        let cells: Vec<crate::types::cell::Cell> = vec![];
        let (row, text, face_ranges, col_to_buf) = TerminalSession::encode_line_faces(0, &cells);
        assert_eq!(row, 0);
        assert_eq!(text, "", "empty cell slice should produce empty text");
        assert!(
            face_ranges.is_empty(),
            "empty cell slice should produce no face ranges"
        );
        assert!(
            col_to_buf.is_empty(),
            "empty cell slice should produce empty col_to_buf"
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
