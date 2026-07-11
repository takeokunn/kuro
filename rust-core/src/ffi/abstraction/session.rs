//! Terminal session state and core operations
//!
//! This module contains the `TerminalSession` struct and methods for PTY I/O,
//! terminal encoding helpers, resize, cursor, scrollback, and viewport ops.
//! Dirty-line rendering logic lives in `dirty.rs`.

#[cfg(unix)]
use crate::pty::Pty;
use crate::TerminalCore;

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
///
/// 32 KB parses in well under a millisecond (the vte state machine plus
/// grid writes run at hundreds of MB/s) while sustaining ~4 MB/s of PTY
/// throughput at the 120 fps poll rate.  The previous 4 KB budget capped
/// throughput at ~480 KB/s — and a mere ~20 KB/s once the TUI-mode
/// throttle dropped polling to 5 fps — so AI-agent output bursts fell
/// progressively behind and rendered as visible chunks.
const MAX_BYTES_PER_POLL: usize = 32 * 1024;

/// Cached render identity for one visible row.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct RowRenderCache {
    pub(super) line_version: u64,
    pub(super) content_hash: u64,
    pub(super) palette_epoch: u64,
}

impl RowRenderCache {
    #[inline]
    pub(super) const fn new(line_version: u64, content_hash: u64, palette_epoch: u64) -> Self {
        Self {
            line_version,
            content_hash,
            palette_epoch,
        }
    }
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
    /// Buffered PTY data that exceeded `MAX_BYTES_PER_POLL` in the previous frame
    #[cfg(unix)]
    pub(super) pending_input: Vec<u8>,
    /// Per-row hash cache for skip-unchanged-rows optimisation.
    ///
    /// Indexed by `row_index → Some(RowRenderCache)`.
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
    pub(super) row_hashes: Vec<Option<RowRenderCache>>,
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
    /// `get_dirty_lines_binary_payload` clears this and then `mem::take`s it
    /// on return: the row `String`s must be owned by the caller for the FFI
    /// transfer, so only the outer Vec's pointer-array allocation is paid per
    /// frame.
    pub(super) texts_scratch: Vec<String>,
    /// Reusable scratch buffer for binary frame serialisation bytes.
    ///
    /// Cleared (capacity retained) by `begin_binary_dirty_frame`, then read
    /// **in place** by `get_dirty_lines_binary_payload`'s Latin-1 transcode —
    /// never moved out.  The serialised frame is typically 2–50 KB; keeping
    /// the buffer resident eliminates the realloc-and-regrow cycle that a
    /// `mem::take` would reintroduce on every poll.
    pub(super) buf_scratch: Vec<u8>,
    /// Consecutive polls suppressed by an open synchronized-output batch
    /// (DEC 2026).  Guards against an application that sets `?2026 h` and
    /// never sends the closing `l` freezing the display forever; see
    /// `suppress_live_dirty_if_scrolled_or_sync` in `dirty.rs`.
    pub(super) sync_suppressed_polls: u32,
    /// Cursor state carried by the most recently emitted v4 binary frame.
    ///
    /// `build_binary_dirty_frame` compares the live cursor against this to
    /// decide whether a rows-free frame must still be emitted (pure cursor
    /// movement — e.g. arrow keys at a shell prompt — produces no dirty
    /// rows).  `None` until the first frame is emitted, forcing the initial
    /// frame to carry cursor state.
    pub(super) last_sent_cursor: Option<super::dirty::CursorWire>,
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
// Public methods are split across session_init.rs, session_io.rs, session_view.rs,
// session_state.rs, and session_osc_modes.rs to keep this file focused on shared
// helpers and the type definition itself.
#[path = "session_state.rs"]
mod state;

#[path = "session_osc_modes.rs"]
mod osc_modes;

#[path = "session_init.rs"]
mod init;
pub use init::PasteText;

#[path = "session_io.rs"]
mod io;

#[path = "session_view.rs"]
mod view;

#[cfg(test)]
#[path = "session_tests.rs"]
mod tests;
