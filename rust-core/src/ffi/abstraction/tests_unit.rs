//! Unit tests for FFI abstraction: session management, encode delegates, sync output.

use super::global::{attach_session, detach_session, list_sessions, shutdown_session, with_session, TERMINAL_SESSIONS};
use super::session::{SessionState, TerminalSession};
use crate::error::KuroError;
use crate::ffi::error::StateError;
use crate::types::cell::SgrAttributes;
use crate::types::color::Color;

// Helper: construct a TerminalSession without spawning a real PTY.
pub(super) fn make_session() -> TerminalSession {
    TerminalSession {
        core: crate::TerminalCore::new(24, 80),
        #[cfg(unix)]
        pty: None,
        command: String::new(),
        state: SessionState::Bound,
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

    let dirty_count = session.core.screen.take_dirty_lines().len();
    assert_eq!(
        dirty_count, 24,
        "After ?2026l, all {} rows should be dirty; got {}",
        24, dirty_count
    );
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
    assert!(result.is_ok(), "send_input with empty slice should return Ok");
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
    session.core.advance(b"\x1b]7;file://localhost/home/user\x07");

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
        other @ crate::types::osc::ClipboardAction::Query => panic!("Expected Write action, got {other:?}"),
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
    assert_eq!(up, 0, "full-screen scroll should not accumulate pending_scroll_up");
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
    assert_eq!(down, 0, "full-screen scroll should not accumulate pending_scroll_down");

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
// ---------------------------------------------------------------------------
// Global session state: detach / attach / list
// ---------------------------------------------------------------------------

/// Insert a fresh `Bound` session under an arbitrary sentinel key.
/// The caller must clean up with `shutdown_session(id)` when done.
fn insert_bound_session(id: u64) {
    let session = make_session(); // state: SessionState::Bound
    TERMINAL_SESSIONS.lock().unwrap().insert(id, session);
}

/// Insert a fresh `Detached` session under an arbitrary sentinel key.
fn insert_detached_session(id: u64) {
    let mut session = make_session();
    session.set_detached();
    TERMINAL_SESSIONS.lock().unwrap().insert(id, session);
}

/// `detach_session` transitions a Bound session to Detached and returns Ok.
#[test]
fn test_detach_session_bound_to_detached() {
    const ID: u64 = u64::MAX - 20;
    shutdown_session(ID).ok();
    insert_bound_session(ID);

    let result = detach_session(ID);
    assert!(result.is_ok(), "detach_session should succeed for a Bound session");

    let is_detached = TERMINAL_SESSIONS
        .lock()
        .unwrap()
        .get(&ID)
        .is_some_and(super::session::TerminalSession::is_detached);
    assert!(is_detached, "session must be Detached after detach_session");

    shutdown_session(ID).ok();
}

/// `attach_session` transitions a Detached session to Bound and returns Ok.
#[test]
fn test_attach_session_detached_to_bound() {
    const ID: u64 = u64::MAX - 21;
    shutdown_session(ID).ok();
    insert_detached_session(ID);

    let result = attach_session(ID);
    assert!(result.is_ok(), "attach_session should succeed for a Detached session");

    let is_detached = TERMINAL_SESSIONS
        .lock()
        .unwrap()
        .get(&ID)
        .is_none_or(super::session::TerminalSession::is_detached);
    assert!(!is_detached, "session must be Bound (not Detached) after attach_session");

    shutdown_session(ID).ok();
}

/// `attach_session` on a Bound session returns Err(TerminalSessionExists).
///
/// This guard prevents two Emacs buffers from owning the same session
/// simultaneously with competing render loops.
#[test]
fn test_attach_session_already_bound_returns_terminal_session_exists() {
    const ID: u64 = u64::MAX - 22;
    shutdown_session(ID).ok();
    insert_bound_session(ID); // already Bound

    let result = attach_session(ID);
    assert!(
        result.is_err(),
        "attach_session must return Err when the session is already Bound"
    );
    assert!(
        matches!(
            result.unwrap_err(),
            KuroError::State(StateError::TerminalSessionExists)
        ),
        "error must be TerminalSessionExists"
    );

    shutdown_session(ID).ok();
}

/// `detach_session` on a nonexistent ID returns Err(NoTerminalSession).
#[test]
fn test_detach_session_nonexistent_returns_no_session() {
    const ID: u64 = u64::MAX - 23;
    shutdown_session(ID).ok(); // ensure absent

    let result = detach_session(ID);
    assert!(result.is_err(), "detach_session must return Err for nonexistent ID");
    assert!(
        matches!(result.unwrap_err(), KuroError::State(StateError::NoTerminalSession)),
        "error must be NoTerminalSession"
    );
}

/// `attach_session` on a nonexistent ID returns Err(NoTerminalSession).
#[test]
fn test_attach_session_nonexistent_returns_no_session() {
    const ID: u64 = u64::MAX - 24;
    shutdown_session(ID).ok(); // ensure absent

    let result = attach_session(ID);
    assert!(result.is_err(), "attach_session must return Err for nonexistent ID");
    assert!(
        matches!(result.unwrap_err(), KuroError::State(StateError::NoTerminalSession)),
        "error must be NoTerminalSession"
    );
}

/// `list_sessions` tuple order: (id, command, `is_detached`, `is_alive`) at indices 0..3.
///
/// A Detached session must have `is_detached=true` at index 2 and
/// `is_alive=true` at index 3 (pty:None sessions always report alive).
/// This is the Rust-side mirror of the Elisp nth-index regression test.
#[test]
fn test_list_sessions_tuple_order_detached() {
    const ID: u64 = u64::MAX - 25;
    shutdown_session(ID).ok();
    insert_detached_session(ID); // Detached, command = ""

    let sessions = list_sessions();
    let entry = sessions.iter().find(|(id, ..)| *id == ID);
    assert!(entry.is_some(), "list_sessions must include the inserted session");

    let (found_id, _command, is_detached, is_alive) = entry.unwrap();
    assert_eq!(*found_id, ID, "index 0 must be the session ID");
    assert!(*is_detached, "index 2 must be is_detached=true for a Detached session");
    assert!(*is_alive, "index 3 must be is_alive=true (pty:None reports alive)");

    shutdown_session(ID).ok();
}

/// `list_sessions`: a Bound session has `is_detached=false` at index 2.
#[test]
fn test_list_sessions_bound_session_not_detached() {
    const ID: u64 = u64::MAX - 26;
    shutdown_session(ID).ok();
    insert_bound_session(ID);

    let sessions = list_sessions();
    let entry = sessions.iter().find(|(id, ..)| *id == ID);
    assert!(entry.is_some(), "list_sessions must include the inserted session");

    let (_, _, is_detached, is_alive) = entry.unwrap();
    assert!(!is_detached, "index 2 must be is_detached=false for a Bound session");
    assert!(*is_alive, "index 3 must be is_alive=true for a Bound session with pty:None");

    shutdown_session(ID).ok();
}

/// `list_sessions` does not include the sentinel ID when that ID has been cleaned up.
///
/// This verifies that `shutdown_session` actually removes the entry so the
/// test sentinel IDs do not pollute subsequent `list_sessions` calls.
#[test]
fn test_list_sessions_cleaned_up_id_absent() {
    const ID: u64 = u64::MAX - 27;
    shutdown_session(ID).ok();
    insert_bound_session(ID);
    shutdown_session(ID).ok();

    let sessions = list_sessions();
    assert!(
        sessions.iter().all(|(id, ..)| *id != ID),
        "list_sessions must not include a session that was shut down"
    );
}

/// `list_sessions` includes the non-empty `command` string in tuple index 1.
#[test]
fn test_list_sessions_command_field_included() {
    const ID: u64 = u64::MAX - 28;
    shutdown_session(ID).ok();
    let mut session = make_session();
    session.command = "fish".to_owned();
    TERMINAL_SESSIONS.lock().unwrap().insert(ID, session);

    let sessions = list_sessions();
    let entry = sessions.iter().find(|(id, ..)| *id == ID);
    assert!(entry.is_some(), "list_sessions must include the inserted session");
    let (_, command, _, _) = entry.unwrap();
    assert_eq!(command, "fish", "command field must match the session's command string");

    shutdown_session(ID).ok();
}

/// `list_sessions` returns entries for both Bound and Detached sessions.
#[test]
fn test_list_sessions_mixed_bound_and_detached() {
    const BOUND_ID: u64 = u64::MAX - 29;
    const DETACHED_ID: u64 = u64::MAX - 30;
    shutdown_session(BOUND_ID).ok();
    shutdown_session(DETACHED_ID).ok();
    insert_bound_session(BOUND_ID);
    insert_detached_session(DETACHED_ID);

    let sessions = list_sessions();
    let bound_entry = sessions.iter().find(|(id, ..)| *id == BOUND_ID);
    let detached_entry = sessions.iter().find(|(id, ..)| *id == DETACHED_ID);

    assert!(bound_entry.is_some(), "list_sessions must include the Bound session");
    assert!(detached_entry.is_some(), "list_sessions must include the Detached session");

    let (_, _, is_detached_b, _) = bound_entry.unwrap();
    let (_, _, is_detached_d, _) = detached_entry.unwrap();
    assert!(!is_detached_b, "Bound session must have is_detached=false");
    assert!(*is_detached_d, "Detached session must have is_detached=true");

    shutdown_session(BOUND_ID).ok();
    shutdown_session(DETACHED_ID).ok();
}

/// `list_sessions` does NOT reap a detached session whose PTY is None (alive=true).
///
/// The retain predicate `is_detached && !is_alive` must NOT fire for sessions
/// with `pty: None` since `is_process_alive()` returns `true` for those.
/// This is the regression guard for the opportunistic-reap change in FR-D.
#[test]
fn test_list_sessions_live_detached_not_reaped() {
    const ID: u64 = u64::MAX - 31;
    shutdown_session(ID).ok();
    insert_detached_session(ID); // pty: None => is_alive=true

    let sessions = list_sessions();
    let entry = sessions.iter().find(|(id, ..)| *id == ID);
    assert!(
        entry.is_some(),
        "list_sessions must NOT reap a detached session whose PTY reports alive \
         (pty:None sessions always report alive and must survive the retain call)"
    );

    shutdown_session(ID).ok();
}

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
    assert_eq!(up, 0, "scroll events must be suppressed during scrollback view");
    assert_eq!(down, 0, "scroll events must be suppressed during scrollback view");
}
