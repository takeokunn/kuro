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
            })
        }

        #[cfg(not(unix))]
        Ok(Self {
            core,
            command: command.to_string(),
            state: SessionState::Bound,
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
    pub fn poll_output(&mut self) -> Result<Vec<u8>> {
        #[cfg(unix)]
        if let Some(ref mut pty) = self.pty {
            let mut all_data = pty.read()?;
            if !all_data.is_empty() {
                self.core.advance(&all_data);

                // Second drain: yield to let the reader thread push any
                // in-flight data, then drain again.  This coalesces two
                // chunks that would otherwise require two render cycles.
                std::thread::yield_now();
                let more = pty.read()?;
                if !more.is_empty() {
                    self.core.advance(&more);
                    all_data.extend(more);
                }

                // Write any queued responses back to the PTY (e.g. DA1/DA2 replies)
                for response in self.core.meta.pending_responses.drain(..) {
                    pty.write(&response)?;
                }

                return Ok(all_data);
            }
        }
        Ok(Vec::new())
    }

    /// Get dirty lines from screen (text only, no face ranges)
    pub fn get_dirty_lines(&mut self) -> Vec<(usize, String)> {
        let dirty_indices = self.core.screen.take_dirty_lines();
        let mut result = Vec::with_capacity(dirty_indices.len());

        for row in dirty_indices {
            let text_opt: Option<String> = self.core.screen.get_line(row).map(|line| {
                // Wide placeholder cells (CellWidth::Wide) are included as ' ' chars,
                // maintaining the grid_col == buffer_char_offset invariant (Phase 11).
                let s: String = line.cells.iter().map(crate::types::cell::Cell::char).collect();
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
    /// Returns [`crate::ffi::codec::EncodedLine`] where:
    /// - `text` has wide placeholder cells removed (CJK renders correctly in Emacs)
    /// - `face_ranges` use buffer offsets (not grid column indices)
    /// - `col_to_buf[col]` maps grid column to buffer character offset
    #[must_use] 
    pub fn encode_line_faces(row: usize, cells: &[crate::types::cell::Cell]) -> crate::ffi::codec::EncodedLine {
        let (text, face_ranges, col_to_buf) = crate::ffi::codec::encode_line(cells);
        (row, text, face_ranges, col_to_buf)
    }

    /// Resize terminal
    ///
    /// # Errors
    /// Returns `Err` if the PTY window-size ioctl fails.
    pub fn resize(&mut self, rows: u16, cols: u16) -> Result<()> {
        self.core.resize(rows, cols);
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
        self.pty.as_ref().is_some_and(crate::pty::posix::Pty::has_pending_data)
    }

    #[cfg(not(unix))]
    /// Check if the PTY channel has pending unread data (without consuming it).
    ///
    /// Always returns `false` on non-Unix platforms where PTY support is unavailable.
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
        self.pty.as_ref().is_none_or(crate::pty::posix::Pty::is_alive)
    }

    #[cfg(not(unix))]
    #[inline(always)]
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
    #[expect(clippy::cast_possible_truncation, reason = "palette index is enumerate() over a 256-element array; i ≤ 255 always fits in u8")]
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
            color.as_ref().map_or(0xFF00_0000u32, Self::encode_color)
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
