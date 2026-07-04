use super::*;

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
    let encoded = TerminalSession::encode_line_faces(0, &cells);
    assert_eq!(encoded.row_index, 0);
    assert_eq!(
        encoded.text, "",
        "empty cell slice should produce empty text"
    );
    assert!(encoded.face_ranges.is_empty());
    assert!(encoded.col_to_buf.is_empty());
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
        crate::types::osc::ClipboardAction::Write { data, .. } => {
            assert_eq!(data, "hello", "Write action should contain decoded text");
        }
        other @ crate::types::osc::ClipboardAction::Query { .. } => {
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
        matches!(actions[0], crate::types::osc::ClipboardAction::Query { .. }),
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
