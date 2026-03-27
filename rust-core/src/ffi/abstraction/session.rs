//! Terminal session state and core operations
//!
//! This module contains the `TerminalSession` struct and methods for PTY I/O,
//! terminal encoding helpers, resize, cursor, scrollback, and viewport ops.
//! Dirty-line rendering logic lives in `dirty.rs`.

#[cfg(unix)]
use crate::pty::Pty;
use crate::{Result, TerminalCore};

/// Lifecycle state of a terminal session.
///
/// A session starts as `Bound` (attached to an Emacs buffer).  When the user
/// kills the buffer without terminating the process, it becomes `Detached` and
/// can later be re-attached via `kuro-attach`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum SessionState {
    /// Attached to an Emacs buffer and actively rendered.
    Bound,
    /// PTY process is alive but no buffer is attached.
    Detached,
}

/// Maximum bytes to parse per `poll_output()` call.
///
/// Limits how much PTY data is fed to the parser in a single render frame,
/// preventing high-throughput TUI apps (cmatrix, btop) from starving the
/// Emacs event loop.  Any excess data is held in `pending_input` and
/// processed on the next frame.
const MAX_BYTES_PER_POLL: usize = 128 * 1024;

/// Terminal session state (shared by all FFI implementations)
///
/// This struct contains the actual terminal logic, independent of any
/// specific FFI binding implementation.
pub struct TerminalSession {
    /// Terminal core
    pub(super) core: TerminalCore,
    /// PTY handle (Unix only)
    #[cfg(unix)]
    pub(super) pty: Option<Pty>,
    /// Shell command used to spawn this session (for `kuro-list-sessions`)
    pub(super) command: String,
    /// Current lifecycle state
    pub(super) state: SessionState,
    /// Buffered PTY data that exceeded `MAX_BYTES_PER_POLL` in the previous frame
    #[cfg(unix)]
    pub(super) pending_input: Vec<u8>,
    /// Per-row hash cache for skip-unchanged-rows optimisation.
    ///
    /// Indexed by `row_index → Some((line_version, content_hash, palette_epoch))`.
    ///
    /// Fast path: if `line.version == stored_version && palette_epoch == stored_epoch`,
    /// the row is skipped without computing a hash — O(1) per unchanged row.
    ///
    /// Slow path: compute hash and compare `content_hash + palette_epoch` as before.
    ///
    /// Vec outperforms HashMap here because row indices are bounded integers
    /// (≤ screen height, typically ≤ 200), making direct indexing O(1) with no
    /// hash overhead.  The Vec is grown lazily on first insert and reset to all
    /// `None` on resize or alt-screen switch.
    pub(super) row_hashes: Vec<Option<(u64, u64, u64)>>,
    /// Monotonically increasing counter, bumped whenever the 256-color palette
    /// changes (OSC 4 set, OSC 104 reset).  Stored alongside each row hash so
    /// that a palette change invalidates every cached row without clearing the
    /// entire `row_hashes` vec.
    pub(super) palette_epoch: u64,
    /// Tracks whether the alternate screen was active at the end of the last
    /// `get_dirty_lines_with_faces` call.  Used to detect DEC 1049 transitions
    /// and bump `palette_epoch` on alternate-screen enter/exit, which logically
    /// invalidates all cached row hashes without clearing the Vec.
    pub(super) was_alt_screen: bool,
}

/// Feed `data` into the terminal parser, limited by `budget`.
///
/// If `data.len() <= budget`, the entire slice is advanced and `budget` is
/// decremented by `data.len()`.  Otherwise, only the first `budget` bytes are
/// advanced, the remainder is appended to `overflow`, and `budget` is set to
/// zero.  Empty `data` is a no-op.
fn advance_with_budget(
    core: &mut crate::TerminalCore,
    data: &[u8],
    budget: &mut usize,
    overflow: &mut Vec<u8>,
) {
    if data.is_empty() {
        return;
    }
    if data.len() <= *budget {
        *budget -= data.len();
        core.advance(data);
    } else {
        core.advance(&data[..*budget]);
        overflow.extend_from_slice(&data[*budget..]);
        *budget = 0;
    }
}

// TerminalSession Facade
// -----------------------
// Current public method count: 38.
// Review trigger at 50+ methods: consider introducing a DecModesView sub-struct
// to group the 12 mode-query accessor methods (get_mouse_mode, get_app_cursor_keys,
// get_keyboard_flags, etc.) and reduce the surface area of this facade.
// All bridge code MUST use these methods; direct `.core.*` access is intentionally
// blocked by `pub(super)` on the `core` field.
impl TerminalSession {
    /// Create a new terminal session
    ///
    /// # Errors
    /// Returns `Err` if the PTY process fails to spawn or the window size cannot be set.
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
                command: command.to_owned(),
                state: SessionState::Bound,
                pending_input: Vec::new(),
                row_hashes: Vec::new(),
                palette_epoch: 0,
                was_alt_screen: false,
            })
        }

        #[cfg(not(unix))]
        Ok(Self {
            core,
            command: command.to_string(),
            state: SessionState::Bound,
            row_hashes: Vec::new(),
            palette_epoch: 0,
            was_alt_screen: false,
        })
    }

    /// Send input to PTY
    ///
    /// # Errors
    /// Returns `Err` if writing to the PTY file descriptor fails.
    pub fn send_input(&mut self, bytes: &[u8]) -> Result<()> {
        #[cfg(unix)]
        if let Some(ref mut pty) = self.pty {
            pty.write(bytes)?;
        }
        #[cfg(not(unix))]
        let _ = bytes;
        Ok(())
    }

    /// Poll for PTY output and update terminal.
    ///
    /// Drains the crossbeam channel twice: once for the initial batch, then
    /// yields the current thread and drains again to catch bytes that the
    /// reader thread pushed while we were processing the first batch.
    /// This reduces the chance of rendering a partial screen update when
    /// a TUI app sends a large escape-sequence burst (e.g. Claude Code
    /// redrawing all 32 rows on up-arrow).
    ///
    /// # Errors
    /// Returns `Err` if reading from or writing to the PTY file descriptor fails.
    pub fn poll_output(&mut self) -> Result<()> {
        #[cfg(unix)]
        if let Some(ref mut pty) = self.pty {
            let mut budget = MAX_BYTES_PER_POLL;

            // Drain pending_input from previous frame first
            if !self.pending_input.is_empty() {
                let pending = std::mem::take(&mut self.pending_input);
                advance_with_budget(
                    &mut self.core,
                    &pending,
                    &mut budget,
                    &mut self.pending_input,
                );
            }

            // Drain channel data up to the remaining budget
            if budget > 0 {
                let data = pty.read()?;
                advance_with_budget(&mut self.core, &data, &mut budget, &mut self.pending_input);
            }

            // Second drain: yield to let the reader thread push any
            // in-flight data, then drain again.  This coalesces two
            // chunks that would otherwise require two render cycles.
            if budget > 0 {
                std::thread::yield_now();
                let more = pty.read()?;
                advance_with_budget(&mut self.core, &more, &mut budget, &mut self.pending_input);
            }

            // Write any queued responses back to the PTY (e.g. DA1/DA2 replies)
            for response in self.core.meta.pending_responses.drain(..) {
                pty.write(&response)?;
            }
        }
        Ok(())
    }

    /// Get dirty lines from screen (text only, no face ranges)
    pub fn get_dirty_lines(&mut self) -> Vec<(usize, String)> {
        // Helper: encode a single dirty row as (row, text)
        fn encode_row(screen: &crate::grid::screen::Screen, row: usize) -> Option<(usize, String)> {
            screen.get_line(row).map(|line| {
                // Wide placeholder cells (CellWidth::Wide) are included as ' ' chars,
                // maintaining the grid_col == buffer_char_offset invariant (Phase 11).
                let s: String = line
                    .cells
                    .iter()
                    .map(crate::types::cell::Cell::char)
                    .collect();
                // NOTE: trailing spaces are intentionally NOT trimmed.
                // Trimming would cause the Emacs-side cursor clamp
                // `(min (+ line-start col) line-end)` to place the cursor at
                // the wrong column when the terminal cursor is inside whitespace
                // (e.g. after pressing SPC at a bash prompt).
                (row, s)
            })
        }

        // Fast path: full_dirty → iterate 0..rows directly without allocating index Vec
        if self.core.screen.is_full_dirty() {
            let rows = self.core.screen.rows() as usize;
            self.core.screen.clear_dirty();
            let mut result = Vec::with_capacity(rows);
            for row in 0..rows {
                if let Some(entry) = encode_row(&self.core.screen, row) {
                    result.push(entry);
                }
            }
            return result;
        }

        let dirty_indices = self.core.screen.take_dirty_lines();
        let mut result = Vec::with_capacity(dirty_indices.len());
        for row in dirty_indices {
            if let Some(entry) = encode_row(&self.core.screen, row) {
                result.push(entry);
            }
        }
        result
    }

    /// Encode a `Color` as a `u32` for FFI transfer.
    ///
    /// Delegates to [`crate::ffi::codec::encode_color`].
    #[inline]
    #[must_use]
    pub fn encode_color(color: &crate::types::Color) -> u32 {
        crate::ffi::codec::encode_color(color)
    }

    /// Encode `SgrAttributes` as a `u64` bitmask for FFI transfer.
    ///
    /// Delegates to [`crate::ffi::codec::encode_attrs`].
    #[inline]
    #[must_use]
    pub fn encode_attrs(attrs: &crate::types::cell::SgrAttributes) -> u64 {
        crate::ffi::codec::encode_attrs(attrs)
    }

    /// Encode a single line's cells into (row, text, `face_ranges`, `col_to_buf`).
    ///
    /// This is a pure function (no `self` dependency) so it can be called
    /// while holding a shared borrow of the screen — eliminating the need to
    /// `clone()` the cell slice just to satisfy the borrow checker.
    ///
    /// Returns `EncodedLine` where:
    /// - `text` has wide placeholder cells removed (CJK renders correctly in Emacs)
    /// - `face_ranges` use buffer offsets (not grid column indices)
    /// - `col_to_buf[col]` maps grid column to buffer character offset
    #[must_use]
    pub fn encode_line_faces(
        row: usize,
        cells: &[crate::types::cell::Cell],
    ) -> crate::ffi::codec::EncodedLine {
        let (text, face_ranges, col_to_buf) = crate::ffi::codec::encode_line(cells);
        (row, text, face_ranges, col_to_buf)
    }

    /// Resize terminal
    ///
    /// # Errors
    /// Returns `Err` if the PTY window-size ioctl fails.
    pub fn resize(&mut self, rows: u16, cols: u16) -> Result<()> {
        self.core.resize(rows, cols);
        // Row hashes are invalidated by a resize because row count / col count
        // may change, making the old per-row hashes stale.  Truncate to new row
        // count (in case it shrank) then fill all slots with None.
        let new_rows = rows as usize;
        self.row_hashes.truncate(new_rows);
        self.row_hashes.fill(None);
        #[cfg(unix)]
        if let Some(ref mut pty) = self.pty {
            pty.set_winsize(rows, cols)?;
        }
        Ok(())
    }

    /// Get cursor position
    #[must_use]
    pub fn get_cursor(&self) -> (usize, usize) {
        let c = self.core.screen.cursor();
        (c.row, c.col)
    }

    /// Get cursor visibility (DECTCEM state)
    #[must_use]
    pub const fn get_cursor_visible(&self) -> bool {
        self.core.dec_modes.cursor_visible
    }

    /// Get scrollback lines
    #[must_use]
    pub fn get_scrollback(&self, max_lines: usize) -> Vec<String> {
        let lines = self.core.screen.get_scrollback_lines(max_lines);
        lines.iter().map(std::string::ToString::to_string).collect()
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
    #[must_use]
    pub fn get_image_png_base64(&self, image_id: u32) -> String {
        self.core.screen.get_image_png_base64(image_id)
    }

    /// Drain and return all pending image placement notifications.
    pub fn take_pending_image_notifications(
        &mut self,
    ) -> Vec<crate::grid::screen::ImageNotification> {
        std::mem::take(&mut self.core.kitty.pending_image_notifications)
    }

    /// Get scrollback line count
    #[must_use]
    pub const fn get_scrollback_count(&self) -> usize {
        self.core.screen.scrollback_line_count
    }

    /// Scroll the viewport up by n lines (toward older scrollback content)
    pub fn viewport_scroll_up(&mut self, n: usize) {
        self.core.screen.viewport_scroll_up(n);
    }

    /// Scroll the viewport down by n lines (toward live content)
    pub const fn viewport_scroll_down(&mut self, n: usize) {
        self.core.screen.viewport_scroll_down(n);
    }

    /// Return the current viewport scroll offset (0 = live view)
    #[must_use]
    pub const fn scroll_offset(&self) -> usize {
        self.core.screen.scroll_offset()
    }

    /// Check if the PTY channel has pending unread data (without consuming it).
    ///
    /// Used by Elisp to trigger immediate rendering when streaming output arrives.
    #[cfg(unix)]
    #[must_use]
    pub fn has_pending_output(&self) -> bool {
        !self.pending_input.is_empty()
            || self
                .pty
                .as_ref()
                .is_some_and(crate::pty::posix::Pty::has_pending_data)
    }

    /// Check if the PTY channel has pending unread data (without consuming it).
    ///
    /// Always returns `false` on non-Unix platforms where PTY support is unavailable.
    #[cfg(not(unix))]
    pub fn has_pending_output(&self) -> bool {
        false
    }

    /// Returns true if the PTY child process has not yet exited.
    ///
    /// On Unix: reads the `process_exited` flag written by the reader thread on EOF.
    /// Returns `true` when `pty` is `None` (test sessions without a real PTY) so that
    /// test buffers are never auto-killed.
    /// On non-Unix: always returns `true` (no PTY process to track).
    #[cfg(unix)]
    #[inline]
    #[must_use]
    pub fn is_process_alive(&self) -> bool {
        self.pty
            .as_ref()
            .is_none_or(crate::pty::posix::Pty::is_alive)
    }

    #[cfg(not(unix))]
    #[inline]
    pub fn is_process_alive(&self) -> bool {
        true
    }

    /// Return the shell command used to spawn this session.
    #[inline]
    #[must_use]
    pub fn command(&self) -> &str {
        &self.command
    }

    /// Return `true` if this session is in the `Detached` state.
    #[inline]
    #[must_use]
    pub fn is_detached(&self) -> bool {
        self.state == SessionState::Detached
    }

    /// Mark this session as `Detached` (keeps PTY alive, no buffer attached).
    #[inline]
    pub const fn set_detached(&mut self) {
        self.state = SessionState::Detached;
    }

    /// Mark this session as `Bound` (re-attaching it to a buffer).
    #[inline]
    pub const fn set_bound(&mut self) {
        self.state = SessionState::Bound;
    }

    /// Return the PID of the PTY child process, if available.
    ///
    /// Returns `None` on non-Unix platforms or when no PTY is attached.
    #[must_use]
    pub const fn pid(&self) -> Option<u32> {
        #[cfg(unix)]
        if let Some(pty) = &self.pty {
            return Some(pty.pid());
        }
        None
    }

    /// Get mouse pixel mode state (?1016)
    #[must_use]
    pub const fn get_mouse_pixel(&self) -> bool {
        self.core.dec_modes.mouse_pixel
    }

    /// Get current 256-color palette overrides (non-None entries only).
    ///
    /// Returns a Vec of (index, R, G, B) for each overridden palette entry.
    #[must_use]
    #[expect(
        clippy::cast_possible_truncation,
        reason = "palette index is enumerate() over a 256-element array; i ≤ 255 always fits in u8"
    )]
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
    /// Returns (`fg_encoded`, `bg_encoded`, `cursor_encoded`) as u32 FFI color values.
    #[must_use]
    pub fn get_default_colors(&self) -> (u32, u32, u32) {
        let encode = |color: &Option<crate::types::Color>| -> u32 {
            color.as_ref().map_or(
                crate::ffi::codec::COLOR_DEFAULT_SENTINEL,
                Self::encode_color,
            )
        };
        (
            encode(&self.core.osc_data.default_fg),
            encode(&self.core.osc_data.default_bg),
            encode(&self.core.osc_data.cursor_color),
        )
    }

    /// Check and unconditionally clear the default-colors-dirty flag.
    ///
    /// Returns `true` if the flag was set (i.e., the default colors changed since
    /// the last call), then resets the flag to `false` regardless of its value.
    /// Subsequent calls return `false` until the flag is set again by the parser.
    pub const fn take_default_colors_dirty(&mut self) -> bool {
        let dirty = self.core.osc_data.default_colors_dirty;
        self.core.osc_data.default_colors_dirty = false;
        dirty
    }

    /// Check and clear the pending bell flag.
    ///
    /// Returns `true` if a BEL character has been received since the last call,
    /// then unconditionally resets the flag to `false`.
    /// Subsequent calls return `false` until another BEL is received.
    pub const fn take_bell_pending(&mut self) -> bool {
        let was_pending = self.core.meta.bell_pending;
        self.core.meta.bell_pending = false;
        was_pending
    }

    /// Return the window title if it has been updated since the last call, clearing the dirty flag.
    pub fn take_title_if_dirty(&mut self) -> Option<String> {
        if self.core.meta.title_dirty {
            self.core.meta.title_dirty = false;
            Some(self.core.meta.title.clone())
        } else {
            None
        }
    }

    /// Return the working directory if it has been updated since the last call, clearing the dirty flag.
    /// Returns None if not dirty or if no cwd has been set.
    pub fn take_cwd_if_dirty(&mut self) -> Option<String> {
        if self.core.osc_data.cwd_dirty {
            self.core.osc_data.cwd_dirty = false;
            self.core.osc_data.cwd.clone()
        } else {
            None
        }
    }

    /// Drain and return all pending clipboard actions (OSC 52).
    pub fn take_clipboard_actions(&mut self) -> Vec<crate::types::osc::ClipboardAction> {
        std::mem::take(&mut self.core.osc_data.clipboard_actions)
    }

    /// Drain and return all pending prompt mark events (OSC 133).
    pub fn take_prompt_marks(&mut self) -> Vec<crate::types::osc::PromptMarkEvent> {
        std::mem::take(&mut self.core.osc_data.prompt_marks)
    }

    /// Get the current mouse tracking mode.
    #[must_use]
    pub const fn get_mouse_mode(&self) -> u16 {
        self.core.dec_modes.mouse_mode
    }

    /// Get whether SGR mouse coordinate encoding is active.
    #[must_use]
    pub const fn get_mouse_sgr(&self) -> bool {
        self.core.dec_modes.mouse_sgr
    }

    /// Get whether application cursor keys mode (DECCKM) is active.
    #[must_use]
    pub const fn get_app_cursor_keys(&self) -> bool {
        self.core.dec_modes.app_cursor_keys
    }

    /// Get whether application keypad mode is active.
    #[must_use]
    pub const fn get_app_keypad(&self) -> bool {
        self.core.dec_modes.app_keypad
    }

    /// Get the kitty keyboard protocol flags bitmask.
    #[must_use]
    pub const fn get_keyboard_flags(&self) -> u32 {
        self.core.dec_modes.keyboard_flags
    }

    /// Get the current cursor shape.
    #[must_use]
    pub const fn get_cursor_shape(&self) -> crate::types::cursor::CursorShape {
        self.core.dec_modes.cursor_shape
    }

    /// Get whether bracketed paste mode is active.
    #[must_use]
    pub const fn get_bracketed_paste(&self) -> bool {
        self.core.dec_modes.bracketed_paste
    }

    /// Get whether focus event reporting is active.
    #[must_use]
    pub const fn get_focus_events(&self) -> bool {
        self.core.dec_modes.focus_events
    }

    /// Get whether synchronized output mode (DEC ?2026) is active.
    #[must_use]
    pub const fn get_synchronized_output(&self) -> bool {
        self.core.dec_modes.synchronized_output
    }
}

#[cfg(test)]
mod tests {
    use super::advance_with_budget;
    use crate::ffi::codec::COLOR_DEFAULT_SENTINEL;

    fn make_core() -> crate::TerminalCore {
        crate::TerminalCore::new(24, 80)
    }

    #[test]
    fn test_advance_with_budget_under_budget() {
        let mut core = make_core();
        let mut budget = 100usize;
        let mut overflow = Vec::new();
        advance_with_budget(&mut core, b"hello", &mut budget, &mut overflow);
        assert_eq!(budget, 95);
        assert!(overflow.is_empty());
    }

    #[test]
    fn test_advance_with_budget_over_budget() {
        let mut core = make_core();
        let mut budget = 3usize;
        let mut overflow = Vec::new();
        advance_with_budget(&mut core, b"hello", &mut budget, &mut overflow);
        assert_eq!(budget, 0);
        assert_eq!(overflow, b"lo");
    }

    #[test]
    fn test_advance_with_budget_exact_fit() {
        let mut core = make_core();
        let mut budget = 5usize;
        let mut overflow = Vec::new();
        advance_with_budget(&mut core, b"hello", &mut budget, &mut overflow);
        assert_eq!(budget, 0);
        assert!(overflow.is_empty(), "exact fit must not produce overflow");
    }

    #[test]
    fn test_advance_with_budget_empty_data_is_noop() {
        let mut core = make_core();
        let mut budget = 100usize;
        let mut overflow = Vec::new();
        advance_with_budget(&mut core, &[], &mut budget, &mut overflow);
        assert_eq!(budget, 100, "budget must be unchanged for empty data");
        assert!(overflow.is_empty());
    }

    #[test]
    fn test_color_default_sentinel_is_outside_rgb_space() {
        // The sentinel must be outside the 24-bit RGB space (0x00FF_FFFF is the max).
        // Top byte is 0xFF, which encode_color never produces for a real color.
        assert_eq!(COLOR_DEFAULT_SENTINEL, 0xFF00_0000);
        const { assert!(COLOR_DEFAULT_SENTINEL > 0x00FF_FFFF) };
    }

    #[test]
    fn test_get_default_colors_unset_returns_sentinel() {
        use super::{SessionState, TerminalSession};
        let session = TerminalSession {
            core: crate::TerminalCore::new(24, 80),
            #[cfg(unix)]
            pty: None,
            command: String::new(),
            state: SessionState::Bound,
            #[cfg(unix)]
            pending_input: Vec::new(),
            row_hashes: Vec::new(),
            palette_epoch: 0,
            was_alt_screen: false,
        };
        let (fg, bg, cursor) = session.get_default_colors();
        // Before any OSC 10/11/12, all three are unset → sentinel
        assert_eq!(fg, COLOR_DEFAULT_SENTINEL);
        assert_eq!(bg, COLOR_DEFAULT_SENTINEL);
        assert_eq!(cursor, COLOR_DEFAULT_SENTINEL);
    }
}
