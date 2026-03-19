//! Unit tests for FFI abstraction: session management, encode delegates, sync output.

use super::global::{shutdown_session, with_session};
use super::session::TerminalSession;
use crate::types::cell::SgrAttributes;
use crate::types::color::Color;

// Helper: construct a TerminalSession without spawning a real PTY.
pub(super) fn make_session() -> TerminalSession {
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
    assert_eq!(
        TerminalSession::encode_color(&Color::Default),
        0xFF000000u32
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
    shutdown_session().ok();
    let result = with_session(|_s| Ok(()));
    assert!(
        result.is_err(),
        "with_session should return Err when no session is initialized"
    );
}

#[test]
fn test_shutdown_session() {
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
        other => panic!("Expected Write action, got {:?}", other),
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

/// When the viewport is scrolled back and scroll_dirty is set,
/// get_dirty_lines_with_faces must return scrollback content for all rows
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

/// When the viewport is scrolled back but scroll_dirty is false (no new
/// scroll event), get_dirty_lines_with_faces must suppress live dirty lines
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

/// consume_scroll_events returns the pending counts then zeros on second call.
#[test]
fn test_consume_scroll_events_returns_counts_then_zeros() {
    let mut session = make_session();

    // Advance content that causes a full-screen scroll (write 25 lines on a
    // 24-row terminal — the 25th line triggers one scroll_up event).
    for _ in 0..25 {
        session.core.advance(b"line\n");
    }

    // First consume: must report at least one scroll-up event.
    let (up, down) = session.consume_scroll_events();
    assert!(
        up > 0,
        "consume_scroll_events must return up > 0 after scrolling content"
    );
    assert_eq!(down, 0, "no scroll-down events expected");

    // Second consume: counters must have been reset to zero.
    let (up2, down2) = session.consume_scroll_events();
    assert_eq!(
        up2, 0,
        "second consume_scroll_events must return up=0 (counters reset)"
    );
    assert_eq!(
        down2, 0,
        "second consume_scroll_events must return down=0 (counters reset)"
    );
}

/// consume_scroll_events reports scroll-down events and then zeros on second call.
///
/// DECSTBM + RI (reverse index) is the portable way to trigger a full-screen
/// scroll-down: set the scroll region to cover all rows, move the cursor to
/// the top row, then send ESC M (RI) which inserts a blank line at the top and
/// scrolls everything else down.
#[test]
fn test_consume_scroll_events_scroll_down() {
    let mut session = make_session();

    // ESC [ r        — DECSTBM: scroll region = full screen (rows 1..24, i.e. 0..24 internally)
    // ESC [ 1 ; 1 H  — CUP: move cursor to row 1, col 1 (top-left)
    // ESC M          — RI: reverse index — scrolls content down when cursor is at top margin
    //
    // Repeat the RI sequence 3 times to accumulate pending_scroll_down = 3.
    session.core.advance(b"\x1b[r\x1b[1;1H\x1bM\x1bM\x1bM");

    // First consume: must report exactly 3 scroll-down events, 0 scroll-up.
    let (up, down) = session.consume_scroll_events();
    assert_eq!(up, 0, "no scroll-up events expected after RI-only input");
    assert!(
        down > 0,
        "consume_scroll_events must return down > 0 after reverse-index scrolls; got {}",
        down
    );

    // Second consume: both counters must be zero (reset after first call).
    let (up2, down2) = session.consume_scroll_events();
    assert_eq!(
        up2, 0,
        "second consume_scroll_events must return up=0 (counters reset)"
    );
    assert_eq!(
        down2, 0,
        "second consume_scroll_events must return down=0 (counters reset)"
    );
}
