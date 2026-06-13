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
    /// Reusable scratch buffer for per-row encoding.
    ///
    /// `encode_line_into_buf` and `encode_line_with_pool` both call `pool.clear()`
    /// at the start of each row, so this field never needs to be reset between
    /// frames.  Persisting it here eliminates three heap allocations per frame
    /// (`String` + two `Vec`s) that were previously created by `EncodePool::new()`
    /// on every call to `get_dirty_lines_binary_direct` / `get_dirty_lines_with_faces`.
    pub(super) encode_pool: crate::ffi::codec::EncodePool,
    /// Reusable scratch vec for dirty row indices.
    ///
    /// `take_dirty_lines_into` fills this instead of allocating a fresh `Vec`
    /// each frame.  Capacity grows to the terminal height on the first full-dirty
    /// frame, then stays there — zero heap allocations per frame thereafter.
    pub(super) dirty_scratch: Vec<usize>,
    /// Reusable scratch vec for per-row text strings in the binary FFI path.
    ///
    /// `get_dirty_lines_binary_direct` clears this and then `mem::take`s it on
    /// return.  After the take the Vec is empty but retains its allocation, so the
    /// next frame re-uses the same backing buffer — eliminating one `Vec<String>`
    /// heap allocation per frame (~120/sec at 120fps).
    pub(super) texts_scratch: Vec<String>,
    /// Reusable scratch buffer for binary frame serialisation bytes.
    ///
    /// Same `clear()` + `mem::take()` pattern as `texts_scratch`.  The serialised
    /// frame is typically 2–50 KB; persisting the allocation eliminates one
    /// `Vec<u8>` heap allocation per frame on both the live and scrollback paths.
    pub(super) buf_scratch: Vec<u8>,
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

/// Generate a public `const fn` getter that reads a field from `self.core.dec_modes`.
///
/// Syntax: `dec_mode_getter!(/// doc fn get_name -> RetType = field_name);`
macro_rules! dec_mode_getter {
    ($(#[$doc:meta])* fn $name:ident -> $ret:ty = $field:ident) => {
        $(#[$doc])*
        #[must_use]
        pub const fn $name(&self) -> $ret {
            self.core.dec_modes.$field
        }
    };
}

/// Generate a method that clones an owned field, wraps it in `Some`, and clears the dirty flag.
macro_rules! take_some_if_dirty {
    ($(#[$doc:meta])* fn $name:ident from $owner:ident when $dirty:ident take $value:ident : $ty:ty) => {
        $(#[$doc])*
        pub fn $name(&mut self) -> Option<$ty> {
            if self.core.$owner.$dirty {
                self.core.$owner.$dirty = false;
                Some(self.core.$owner.$value.clone())
            } else {
                None
            }
        }
    };
}

/// Generate a method that clones an `Option<T>` field when dirty, then clears the dirty flag.
macro_rules! take_option_field_if_dirty {
    ($(#[$doc:meta])* fn $name:ident from $owner:ident when $dirty:ident take $value:ident : $ty:ty) => {
        $(#[$doc])*
        pub fn $name(&mut self) -> Option<$ty> {
            if self.core.$owner.$dirty {
                self.core.$owner.$dirty = false;
                self.core.$owner.$value.clone()
            } else {
                None
            }
        }
    };
}

/// Generate a method that drains a `Vec` field from a nested owner.
macro_rules! take_vec_field {
    ($(#[$doc:meta])* fn $name:ident from $owner:ident take $field:ident : $ty:ty) => {
        $(#[$doc])*
        pub fn $name(&mut self) -> Vec<$ty> {
            std::mem::take(&mut self.core.$owner.$field)
        }
    };
}

/// Generate a `const fn` that reads a `bool` flag from a nested owner, clears it, and returns
/// the old value.  Equivalent to a non-atomic `fetch_and_clear` on a plain `bool` field.
macro_rules! take_bool_field {
    ($(#[$doc:meta])* fn $name:ident from $owner:ident . $field:ident) => {
        $(#[$doc])*
        pub const fn $name(&mut self) -> bool {
            let v = self.core.$owner.$field;
            self.core.$owner.$field = false;
            v
        }
    };
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
    pub fn new(command: &str, shell_args: &[String], rows: u16, cols: u16) -> Result<Self> {
        let core = TerminalCore::new(rows, cols);

        #[cfg(unix)]
        {
            // Pty::spawn now takes rows/cols and passes them to openpty so the PTY
            // is created with the correct window size before the child process starts.
            // This prevents readline from seeing 0×0 columns on its first TIOCGWINSZ
            // query, which would otherwise put it into dumb terminal mode (causing
            // control characters to echo as ^X instead of moving the cursor).
            let mut pty = Pty::spawn(command, shell_args, rows, cols)?;
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
                encode_pool: crate::ffi::codec::EncodePool::new(),
                dirty_scratch: Vec::new(),
                texts_scratch: Vec::new(),
                buf_scratch: Vec::new(),
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
            encode_pool: crate::ffi::codec::EncodePool::new(),
            dirty_scratch: Vec::new(),
            texts_scratch: Vec::new(),
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

    dec_mode_getter!(
        /// Get cursor visibility (DECTCEM state)
        fn get_cursor_visible -> bool = cursor_visible
    );

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

    /// Update the stored Emacs color scheme (`true` = dark, `false` = light).
    ///
    /// Returns `true` if the value actually changed, `false` if it was already
    /// at the requested value (idempotent). When the value changes AND DEC mode
    /// 2031 is enabled, pushes a `CSI ? 997 ; Ps n` notification onto
    /// `pending_responses`. See `apply_color_scheme` in `parser::dec_private`.
    pub fn set_color_scheme(&mut self, is_dark: bool) -> bool {
        crate::parser::dec_private::apply_color_scheme(&mut self.core, is_dark)
    }

    /// Return a base64-encoded PNG string for the given image ID.
    /// Returns an empty string if the image is not found (orphan reference).
    #[must_use]
    pub fn get_image_png_base64(&self, image_id: u32) -> String {
        self.core.screen.get_image_png_base64(image_id)
    }

}

include!("session_state.rs");

include!("session_osc_modes.rs");

#[cfg(test)]
include!("session_tests.rs");
