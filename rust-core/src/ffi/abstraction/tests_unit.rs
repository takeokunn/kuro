//! Unit tests for FFI abstraction: session management, encode delegates, sync output.

use super::global::{
    attach_session, detach_session, list_sessions, shutdown_session, with_session,
    TERMINAL_SESSIONS,
};
use super::session::{SessionState, TerminalSession};
use crate::error::KuroError;
use crate::ffi::error::StateError;
use crate::types::cell::SgrAttributes;
use crate::types::color::Color;

// ---------------------------------------------------------------------------
// Test macros
// ---------------------------------------------------------------------------

/// Assert that calling `$expr` once returns a truthy/`Some`/non-empty result,
/// then a second call returns a falsy/`None`/empty result (drain-once semantics).
///
/// Works with `bool`, `Option<_>`, and `Vec<_>` via the `$empty` pattern:
///   - bool: `assert_drain_once!(session.take_bell_pending(), false)`
///   - Option: `assert_drain_once!(session.take_title_if_dirty(), None::<String>)`
///   - Vec: `assert_drain_once!(session.take_clipboard_actions(), vec![])`
macro_rules! assert_drain_once {
    // bool variant
    ($first:expr, bool) => {{
        assert!($first, "first call must return true");
        assert!(!$first, "second call must return false (flag cleared)");
    }};
    // Option variant — checks first is Some, second is None
    ($session:expr, $method:ident, option) => {{
        assert!($session.$method().is_some(), "first call must return Some");
        assert!($session.$method().is_none(), "second call must return None");
    }};
    // Vec variant — checks first is non-empty, second is empty
    ($session:expr, $method:ident, vec) => {{
        assert!(
            !$session.$method().is_empty(),
            "first call must be non-empty"
        );
        assert!($session.$method().is_empty(), "second call must be empty");
    }};
}

/// Assert that a session's `core.screen.take_dirty_lines()` returns exactly `$count` rows.
macro_rules! assert_dirty_count {
    ($session:expr, $count:expr) => {{
        let dirty = $session.core.screen.take_dirty_lines();
        assert_eq!(
            dirty.len(),
            $count,
            "expected {} dirty rows, got {}",
            $count,
            dirty.len()
        );
    }};
}

/// Advance a session, then assert all listed row indices are present in `get_dirty_lines`.
macro_rules! assert_rows_dirty {
    ($session:expr, advance $bytes:expr, rows [$($row:literal),+]) => {{
        $session.core.advance($bytes);
        let dirty = $session.get_dirty_lines();
        $(
            assert!(
                dirty.iter().any(|(r, _)| *r == $row),
                "row {} must be dirty after advance",
                $row
            );
        )+
    }};
}

// Helper: construct a TerminalSession without spawning a real PTY.
pub(super) fn make_session() -> TerminalSession {
    TerminalSession {
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
    assert_eq!(
        TerminalSession::encode_color(&Color::Default),
        0xFF00_0000u32
    );
}

#[test]
fn test_encode_attrs_delegates_to_codec() {
    assert_eq!(
        TerminalSession::encode_attrs(&SgrAttributes::default()),
        0u64
    );
}

#[test]
fn test_with_session_no_session() {
    // Use a session ID that will never be created by real usage.
    shutdown_session(u64::MAX).ok();
    let result = with_session(u64::MAX, |_s| Ok(()));
    assert!(
        result.is_err(),
        "with_session should return Err when no session is initialized"
    );
}

#[test]
fn test_shutdown_session() {
    // Shutting down a non-existent session should succeed (no-op).
    let result = shutdown_session(u64::MAX);
    assert!(
        result.is_ok(),
        "shutdown_session should succeed even with no active session"
    );
}

// ---------------------------------------------------------------------------
// Synchronized Output mode (DEC ?2026) suppression tests
// ---------------------------------------------------------------------------

/// While ?2026h (synchronized output) is active, `get_dirty_lines_with_faces` must
/// return an empty Vec.
#[test]
fn test_sync_output_suppresses_dirty_lines() {
    let mut session = make_session();

    session.core.advance(b"Before sync");
    session.core.screen.take_dirty_lines();

    session.core.advance(b"\x1b[?2026h");
    assert!(session.core.dec_modes.synchronized_output);

    session.core.advance(b"\x1b[2;1HDuring sync content");

    let result = session.get_dirty_lines_with_faces();
    assert!(
        result.is_empty(),
        "get_dirty_lines_with_faces must return empty while ?2026h is active; got {} lines",
        result.len()
    );

    session.core.advance(b"\x1b[?2026l");
    assert!(!session.core.dec_modes.synchronized_output);

    let result = session.get_dirty_lines_with_faces();
    assert!(
        !result.is_empty(),
        "get_dirty_lines_with_faces must return dirty lines after ?2026l; got 0"
    );
}

/// When ?2026l resets synchronized output, all rows must be marked dirty.
#[test]
fn test_sync_output_reset_marks_all_dirty() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?2026hHello sync world");
    session.core.screen.take_dirty_lines();
    session.core.advance(b"\x1b[?2026l");
    assert_dirty_count!(session, 24);
}

// ---------------------------------------------------------------------------
// encode_line_faces and send_input edge cases
// ---------------------------------------------------------------------------

#[test]
fn test_encode_line_faces_empty_line() {
    let cells: Vec<crate::types::cell::Cell> = vec![];
    let (row, text, face_ranges, col_to_buf) = TerminalSession::encode_line_faces(0, &cells);
    assert_eq!(row, 0);
    assert_eq!(text, "", "empty cell slice should produce empty text");
    assert!(face_ranges.is_empty());
    assert!(col_to_buf.is_empty());
}

#[test]
fn test_session_send_input_empty() {
    let mut session = make_session();
    let result = session.send_input(&[]);
    assert!(
        result.is_ok(),
        "send_input with empty slice should return Ok"
    );
}

// ---------------------------------------------------------------------------
// take_title_if_dirty: atomic read-and-clear semantics
// ---------------------------------------------------------------------------

#[test]
fn test_take_title_if_dirty_clears_flag() {
    let mut session = make_session();

    // OSC 2 sets the window title and raises title_dirty
    session.core.advance(b"\x1b]2;my-title\x07");

    // First call: flag is set, should return the title and clear the flag
    let result = session.take_title_if_dirty();
    assert_eq!(
        result.as_deref(),
        Some("my-title"),
        "take_title_if_dirty should return Some(title) on first call"
    );

    // Second call: flag was cleared, should return None
    let result2 = session.take_title_if_dirty();
    assert!(
        result2.is_none(),
        "take_title_if_dirty should return None after the flag has been cleared"
    );
}

#[test]
fn test_take_title_if_dirty_returns_none_when_not_set() {
    let mut session = make_session();
    // No title sequence sent — flag should be false from the start
    let result = session.take_title_if_dirty();
    assert!(
        result.is_none(),
        "take_title_if_dirty should return None when title was never set"
    );
}

// ---------------------------------------------------------------------------
// take_cwd_if_dirty: atomic read-and-clear semantics
// ---------------------------------------------------------------------------

#[test]
fn test_take_cwd_if_dirty_with_cwd_set() {
    let mut session = make_session();

    // OSC 7 sets the current working directory
    session
        .core
        .advance(b"\x1b]7;file://localhost/home/user\x07");

    // First call: dirty flag set, should return the path and clear the flag
    let result = session.take_cwd_if_dirty();
    assert!(
        result.is_some(),
        "take_cwd_if_dirty should return Some(path) after OSC 7"
    );
    assert_eq!(
        result.as_deref(),
        Some("/home/user"),
        "take_cwd_if_dirty should return the stripped path"
    );

    // Second call: flag was cleared, should return None
    let result2 = session.take_cwd_if_dirty();
    assert!(
        result2.is_none(),
        "take_cwd_if_dirty should return None after the flag has been cleared"
    );
}

#[test]
fn test_take_cwd_if_dirty_when_cwd_is_none() {
    let mut session = make_session();

    // Manually raise the dirty flag without setting cwd
    session.core.osc_data.cwd_dirty = true;
    session.core.osc_data.cwd = None;

    // Returns None (not empty string) and clears the dirty flag
    let result = session.take_cwd_if_dirty();
    assert!(
        result.is_none(),
        "take_cwd_if_dirty should return None when cwd field is None even if dirty"
    );

    // Flag must be cleared regardless
    assert!(
        !session.core.osc_data.cwd_dirty,
        "cwd_dirty flag must be cleared even when cwd was None"
    );
}

#[test]
fn test_take_cwd_if_dirty_returns_none_when_not_dirty() {
    let mut session = make_session();
    // No OSC 7 sent — cwd_dirty is false
    let result = session.take_cwd_if_dirty();
    assert!(
        result.is_none(),
        "take_cwd_if_dirty should return None when cwd_dirty is false"
    );
}

// ---------------------------------------------------------------------------
// take_clipboard_actions: drain-once semantics
// ---------------------------------------------------------------------------

#[test]
fn test_take_clipboard_actions_drains_queue() {
    let mut session = make_session();

    // OSC 52 write: base64("hello") = "aGVsbG8="
    session.core.advance(b"\x1b]52;c;aGVsbG8=\x07");

    // First call: should return the queued write action
    let actions = session.take_clipboard_actions();
    assert_eq!(
        actions.len(),
        1,
        "take_clipboard_actions should return 1 action after OSC 52 write"
    );
    match &actions[0] {
        crate::types::osc::ClipboardAction::Write(text) => {
            assert_eq!(text, "hello", "Write action should contain decoded text");
        }
        other @ crate::types::osc::ClipboardAction::Query => {
            panic!("Expected Write action, got {other:?}")
        }
    }

    // Second call: queue was drained, should return empty Vec
    let actions2 = session.take_clipboard_actions();
    assert!(
        actions2.is_empty(),
        "take_clipboard_actions should return empty Vec after draining"
    );
}

#[test]
fn test_take_clipboard_actions_query_action() {
    let mut session = make_session();

    // OSC 52 query: data field is "?"
    session.core.advance(b"\x1b]52;c;?\x07");

    let actions = session.take_clipboard_actions();
    assert_eq!(actions.len(), 1, "Expected 1 clipboard query action");
    assert!(
        matches!(actions[0], crate::types::osc::ClipboardAction::Query),
        "Expected Query variant"
    );

    // Drain idempotency
    assert!(session.take_clipboard_actions().is_empty());
}

#[test]
fn test_take_clipboard_actions_empty_when_no_osc52() {
    let mut session = make_session();
    let actions = session.take_clipboard_actions();
    assert!(
        actions.is_empty(),
        "take_clipboard_actions should return empty Vec when no OSC 52 was sent"
    );
}

// ---------------------------------------------------------------------------
// take_bell_pending: atomic read-and-clear semantics
// ---------------------------------------------------------------------------

#[test]
fn test_bell_pending_cleared_after_take() {
    let mut session = make_session();

    // BEL character (\x07) raises bell_pending
    session.core.advance(b"\x07");

    // First call: returns true (bell was pending) and clears the flag
    assert!(
        session.take_bell_pending(),
        "take_bell_pending should return true after receiving BEL"
    );

    // Second call: flag was cleared, should return false
    assert!(
        !session.take_bell_pending(),
        "take_bell_pending should return false after the flag has been cleared"
    );
}

#[test]
fn test_bell_not_pending_initially() {
    let mut session = make_session();
    assert!(
        !session.take_bell_pending(),
        "take_bell_pending should return false in a fresh session"
    );
}

#[test]
fn test_take_bell_pending_idempotent_when_false() {
    let mut session = make_session();
    // Calling take_bell_pending when already false must not panic or flip the flag
    assert!(!session.take_bell_pending());
    assert!(!session.take_bell_pending());
}

// ---------------------------------------------------------------------------
// take_default_colors_dirty: atomic read-and-clear semantics
// ---------------------------------------------------------------------------

#[test]
fn test_take_default_colors_dirty_clears_flag() {
    let mut session = make_session();

    // OSC 10 sets default fg color and raises default_colors_dirty
    session.core.advance(b"\x1b]10;rgb:ff/80/00\x07");

    assert!(
        session.take_default_colors_dirty(),
        "take_default_colors_dirty should return true after OSC 10"
    );
    assert!(
        !session.take_default_colors_dirty(),
        "take_default_colors_dirty should return false after being cleared"
    );
}

#[test]
fn test_take_default_colors_dirty_false_initially() {
    let mut session = make_session();
    assert!(
        !session.take_default_colors_dirty(),
        "default_colors_dirty should be false in a fresh session"
    );
}

// ---------------------------------------------------------------------------
// Scrollback viewport: get_dirty_lines_with_faces paths (dirty.rs lines ~30-52)
// ---------------------------------------------------------------------------

/// When the viewport is scrolled back and `scroll_dirty` is set,
/// `get_dirty_lines_with_faces` must return scrollback content for all rows
/// rather than live screen content.
#[test]
fn test_scrollback_viewport_dirty_returns_scrollback_content() {
    let mut session = make_session();

    // Write a distinctive marker, then scroll the screen enough to push
    // it into scrollback (advance 24 newlines after the marker so the
    // marker line is pushed off the top of the 24-row screen).
    session.core.advance(b"SCROLLBACK_MARKER");
    // 24 newlines push the marker line into the scrollback buffer.
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);

    // There must now be scrollback content.
    assert!(
        session.core.screen.scrollback_line_count > 0,
        "scrollback buffer must be non-empty after scrolling 24 lines"
    );

    // Clear live dirty state so only the viewport path fires.
    session.core.screen.take_dirty_lines();

    // Scroll the viewport up by 1 to enter the scrollback view.
    // This sets scroll_offset > 0 and raises scroll_dirty.
    session.viewport_scroll_up(1);
    assert!(
        session.core.screen.scroll_offset() > 0,
        "scroll_offset must be > 0 after viewport_scroll_up"
    );
    assert!(
        session.core.screen.is_scroll_dirty(),
        "scroll_dirty must be true after viewport_scroll_up"
    );

    // get_dirty_lines_with_faces must return exactly `rows` entries
    // (one per viewport row) from the scrollback path.
    let rows = session.core.screen.rows() as usize;
    let result = session.get_dirty_lines_with_faces();
    assert_eq!(
        result.len(),
        rows,
        "scrollback viewport path must return {} lines (one per row), got {}",
        rows,
        result.len()
    );

    // scroll_dirty must be cleared after the call.
    assert!(
        !session.core.screen.is_scroll_dirty(),
        "scroll_dirty must be cleared after get_dirty_lines_with_faces"
    );
}

/// When the viewport is scrolled back but `scroll_dirty` is false (no new
/// scroll event), `get_dirty_lines_with_faces` must suppress live dirty lines
/// to preserve the scrollback view.
#[test]
fn test_scrollback_not_dirty_suppresses_live_lines() {
    let mut session = make_session();

    // Push content into scrollback.
    session.core.advance(b"LIVE_CONTENT");
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);

    // Enter scrollback view (raises scroll_dirty).
    session.viewport_scroll_up(1);
    assert!(session.core.screen.is_scroll_dirty());

    // Consume the scroll_dirty by calling get_dirty_lines_with_faces once.
    let _ = session.get_dirty_lines_with_faces();
    assert!(
        !session.core.screen.is_scroll_dirty(),
        "scroll_dirty must be false after first get_dirty_lines_with_faces"
    );

    // Now write new live content — this marks live rows dirty.
    session.core.advance(b"NEW_LIVE_CONTENT");
    // Confirm live rows are dirty.
    assert!(
        !session.core.screen.take_dirty_lines().is_empty(),
        "live rows should be dirty after advance"
    );

    // Mark them dirty again (take consumed them above; re-mark for the test).
    session.core.advance(b"X");

    // With scroll_offset > 0 and scroll_dirty == false, the suppression
    // branch must fire: result must be empty.
    let result = session.get_dirty_lines_with_faces();
    assert!(
        result.is_empty(),
        "get_dirty_lines_with_faces must return empty vec when scrolled back \
         but scroll_dirty is false (suppression branch), got {} lines",
        result.len()
    );
}

/// Full-screen `scroll_up` uses `full_dirty` instead of `pending_scroll_up`.
///
/// After the scroll-accumulation fix, the full-screen fast path sets
/// `full_dirty = true` and does NOT increment `pending_scroll_up`, so
/// `consume_scroll_events` returns (0, 0).  The Emacs render cycle uses
/// `take_dirty_lines` (which returns all rows when `full_dirty` is set)
/// instead of the buffer-level shift.
#[test]
fn test_consume_scroll_events_returns_zero_after_full_screen_scroll() {
    let mut session = make_session();

    // Advance content that causes a full-screen scroll (write 25 lines on a
    // 24-row terminal — the 25th line triggers one scroll_up event).
    for _ in 0..25 {
        session.core.advance(b"line\n");
    }

    // Full-screen scroll now uses full_dirty, not pending_scroll_up.
    let (up, down) = session.consume_scroll_events();
    assert_eq!(
        up, 0,
        "full-screen scroll should not accumulate pending_scroll_up"
    );
    assert_eq!(down, 0, "no scroll-down events expected");

    // Verify full_dirty was set instead.
    let dirty = session.core.screen.take_dirty_lines();
    assert_eq!(
        dirty.len(),
        24,
        "full_dirty should cause take_dirty_lines to return all 24 rows"
    );
}

/// Full-screen `scroll_down` uses `full_dirty` instead of `pending_scroll_down`.
///
/// After the scroll-accumulation fix, reverse index (RI) on a full-screen
/// scroll region sets `full_dirty = true` and does NOT increment
/// `pending_scroll_down`.
#[test]
fn test_consume_scroll_events_scroll_down_returns_zero() {
    let mut session = make_session();

    // ESC [ r        — DECSTBM: scroll region = full screen
    // ESC [ 1 ; 1 H  — CUP: move cursor to top-left
    // ESC M          — RI: reverse index — scrolls content down at top margin
    session.core.advance(b"\x1b[r\x1b[1;1H\x1bM\x1bM\x1bM");

    // Full-screen scroll_down now uses full_dirty, not pending_scroll_down.
    let (up, down) = session.consume_scroll_events();
    assert_eq!(up, 0, "no scroll-up events expected after RI-only input");
    assert_eq!(
        down, 0,
        "full-screen scroll should not accumulate pending_scroll_down"
    );

    // Verify full_dirty was set instead.
    let dirty = session.core.screen.take_dirty_lines();
    assert_eq!(
        dirty.len(),
        24,
        "full_dirty should cause take_dirty_lines to return all 24 rows"
    );
}

/// `is_process_alive()` returns true when pty is None (test sessions).
///
/// Unit test sessions are constructed with `pty: None` via `make_session()`.
/// `is_process_alive()` must report `true` in that case so that test-only
/// sessions never trigger the auto-kill path.
#[test]
fn test_is_process_alive_no_pty() {
    let session = make_session();
    assert!(
        session.is_process_alive(),
        "session with pty: None should report process as alive (safe default)"
    );
}

// consume_scroll_events returns (0, 0) during scrollback view.
//
// With the full_dirty approach, consume_scroll_events always returns (0, 0)
// for full-screen scrolls.  This test verifies the scrollback path still
// returns (0, 0) and that full_dirty is cleared by take_dirty_lines.

include!("tests_unit_session.rs");

#[test]
fn test_consume_scroll_events_suppressed_during_scrollback() {
    let mut session = make_session();

    // Generate scrollback content
    for _ in 0..25 {
        session.core.advance(b"line\n");
    }
    // Drain dirty state from initial scrolling
    let _ = session.core.screen.take_dirty_lines();

    // Generate more scroll events
    for _ in 0..5 {
        session.core.advance(b"more\n");
    }

    // Enter scrollback view
    session.core.screen.viewport_scroll_up(10);
    assert!(session.core.screen.scroll_offset() > 0);

    // consume_scroll_events must return (0, 0) while in scrollback
    let (up, down) = session.consume_scroll_events();
    assert_eq!(
        up, 0,
        "scroll events must be suppressed during scrollback view"
    );
    assert_eq!(
        down, 0,
        "scroll events must be suppressed during scrollback view"
    );
}

include!("tests_unit_dirty.rs");

// ---------------------------------------------------------------------------
// New coverage: encode_line_faces, take_cwd_if_dirty, cursor shape, pid
// ---------------------------------------------------------------------------

/// `encode_line_faces` with three consecutive ASCII cells produces 1 or more
/// face ranges covering all three columns; text must be exactly "ABC".
#[test]
fn test_encode_line_faces_three_ascii_cells_text() {
    use crate::types::cell::{Cell, CellWidth, SgrAttributes};
    let cells = vec![
        Cell::with_char_and_width('A', SgrAttributes::default(), CellWidth::Half),
        Cell::with_char_and_width('B', SgrAttributes::default(), CellWidth::Half),
        Cell::with_char_and_width('C', SgrAttributes::default(), CellWidth::Half),
    ];
    let (row, text, face_ranges, col_to_buf) = TerminalSession::encode_line_faces(3, &cells);
    assert_eq!(row, 3, "row index must pass through unchanged");
    assert_eq!(text, "ABC", "three ASCII cells must produce text 'ABC'");
    assert!(
        !face_ranges.is_empty(),
        "three cells must produce at least one face range"
    );
    // All three cells are ASCII: col_to_buf must be empty (identity mapping).
    assert!(
        col_to_buf.is_empty(),
        "pure-ASCII three-cell line must return empty col_to_buf"
    );
}

/// `take_cwd_if_dirty` returns the path stripped of `file://hostname` prefix
/// when OSC 7 is sent with a full URI including hostname.
#[test]
fn test_take_cwd_if_dirty_strips_hostname_prefix() {
    let mut session = make_session();

    // OSC 7 with full file://hostname/path URI
    session.core.advance(b"\x1b]7;file://myhost/tmp/work\x07");

    let result = session.take_cwd_if_dirty();
    assert!(
        result.is_some(),
        "take_cwd_if_dirty must return Some after OSC 7 with hostname"
    );
    let path = result.unwrap();
    // The implementation strips `file://hostname` leaving `/tmp/work`
    assert!(
        path.starts_with('/'),
        "stripped path must start with '/', got: {path:?}"
    );
    assert!(
        path.contains("tmp") || path.contains("work"),
        "stripped path must contain the path component, got: {path:?}"
    );
}

/// `get_cursor_shape` changes to `SteadyUnderline` after `CSI 4 SP q`.
#[test]
fn test_get_cursor_shape_changes_via_decscusr() {
    use crate::types::cursor::CursorShape;
    let mut session = make_session();

    // CSI 4 SP q → SteadyUnderline (DECSCUSR param 4)
    session.core.advance(b"\x1b[4 q");
    let shape = session.get_cursor_shape();
    assert_eq!(
        shape,
        CursorShape::SteadyUnderline,
        "cursor shape must be SteadyUnderline after CSI 4 SP q"
    );
}

/// `encode_line_faces` with row index 23 (last row on a 24-row screen) passes
/// the row index through unchanged.
#[test]
fn test_encode_line_faces_last_row_index_preserved() {
    use crate::types::cell::{Cell, CellWidth, SgrAttributes};
    let cells = vec![Cell::with_char_and_width(
        'Z',
        SgrAttributes::default(),
        CellWidth::Half,
    )];
    let (row, text, _, _) = TerminalSession::encode_line_faces(23, &cells);
    assert_eq!(row, 23, "row index 23 must be preserved");
    assert_eq!(text, "Z");
}

/// `get_scrollback_count` returns 0 on a fresh session (nothing pushed yet).
#[test]
fn test_get_scrollback_count_zero_on_fresh_session() {
    let session = make_session();
    assert_eq!(
        session.get_scrollback_count(),
        0,
        "scrollback count must be 0 on a freshly constructed session"
    );
}

/// `clear_scrollback` is idempotent: calling it on an already-empty session
/// must not panic or corrupt state.
#[test]
fn test_clear_scrollback_idempotent_on_empty() {
    let mut session = make_session();
    // No content pushed — scrollback is already empty.
    session.clear_scrollback();
    session.clear_scrollback(); // second call must be safe
    assert_eq!(
        session.get_scrollback_count(),
        0,
        "scrollback count must remain 0 after two clear_scrollback calls on empty session"
    );
}

include!("tests_unit_isolation.rs");
