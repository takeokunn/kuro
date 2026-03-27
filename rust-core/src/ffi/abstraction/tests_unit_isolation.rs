// ---------------------------------------------------------------------------
// Multi-session isolation tests
// ---------------------------------------------------------------------------

/// Two independent sessions must not share terminal state: dirty lines from
/// session2's `advance` must not appear in session1's `get_dirty_lines`.
#[test]
fn test_two_sessions_are_independent() {
    let mut session1 = make_session();
    let mut session2 = make_session();

    // Drain any construction-time full_dirty from both sessions.
    session1.core.screen.take_dirty_lines();
    session2.core.screen.take_dirty_lines();

    // Write distinct content to each session.
    session1.core.advance(b"AAA");
    session2.core.advance(b"BBB");

    // Collect dirty rows from session1 only.
    let dirty1 = session1.get_dirty_lines();
    assert!(
        !dirty1.is_empty(),
        "session1 must have dirty rows after writing 'AAA'"
    );

    // None of session1's dirty rows must contain session2's content.
    for (_, text) in &dirty1 {
        assert!(
            !text.contains("BBB"),
            "session1's dirty lines must not contain session2's content 'BBB', got: {text:?}"
        );
    }

    // session2's dirty rows must not contain session1's content.
    let dirty2 = session2.get_dirty_lines();
    for (_, text) in &dirty2 {
        assert!(
            !text.contains("AAA"),
            "session2's dirty lines must not contain session1's content 'AAA', got: {text:?}"
        );
    }
}

/// Moving the cursor in session1 must not affect session2's cursor position.
#[test]
fn test_get_cursor_independent_per_session() {
    let mut session1 = make_session();
    let session2 = make_session();

    // Move cursor in session1 to row 10, col 20 (1-based CUP → 0-based (9, 19)).
    session1.core.advance(b"\x1b[10;20H");

    let (row1, col1) = session1.get_cursor();
    assert_eq!(row1, 9, "session1 cursor row must be 9 after CUP 10;20H");
    assert_eq!(col1, 19, "session1 cursor col must be 19 after CUP 10;20H");

    // session2's cursor must remain at the initial position (0, 0).
    let (row2, col2) = session2.get_cursor();
    assert_eq!(
        row2, 0,
        "session2 cursor row must still be 0 (unaffected by session1's CUP)"
    );
    assert_eq!(
        col2, 0,
        "session2 cursor col must still be 0 (unaffected by session1's CUP)"
    );
}

/// Resizing session1 must not change session2's terminal dimensions.
#[test]
fn test_resize_independent_per_session() {
    let mut session1 = make_session();
    let session2 = make_session();

    // Resize session1 to 30 rows × 100 cols.
    session1
        .resize(30, 100)
        .expect("resize must not fail on test session");

    assert_eq!(
        session1.core.screen.rows(),
        30,
        "session1 rows must be 30 after resize(30, 100)"
    );

    // session2 must still have the default 24 rows.
    assert_eq!(
        session2.core.screen.rows(),
        24,
        "session2 rows must remain 24 (unaffected by session1's resize)"
    );
}

/// Bell state in session1 must not affect session2.
///
/// Sending BEL to session1 sets its `bell_pending`; session2 must remain
/// false so that independent bell delivery works correctly.
#[test]
fn test_bell_state_independent_per_session() {
    let mut session1 = make_session();
    let mut session2 = make_session();

    // Send BEL only to session1.
    session1.core.advance(b"\x07");

    assert!(
        session1.take_bell_pending(),
        "session1 must have bell_pending=true after receiving BEL"
    );
    assert!(
        !session2.take_bell_pending(),
        "session2 must have bell_pending=false (BEL was only sent to session1)"
    );
}

/// Scrollback in session1 must not bleed into session2.
///
/// Pushing lines into scrollback in session1 must leave session2's scrollback
/// count at 0.
#[test]
fn test_scrollback_independent_per_session() {
    let mut session1 = make_session();
    let session2 = make_session();

    // Push lines into session1's scrollback.
    let newlines = b"\n".repeat(24);
    session1.core.advance(b"MARKER");
    session1.core.advance(&newlines);

    assert!(
        session1.get_scrollback_count() > 0,
        "session1 scrollback must be non-empty after pushing lines"
    );
    assert_eq!(
        session2.get_scrollback_count(),
        0,
        "session2 scrollback must remain 0 (unaffected by session1)"
    );
}

/// Title dirty state in session1 must not affect session2.
///
/// Setting a title via OSC 2 in session1 must leave session2's
/// `take_title_if_dirty` returning `None`.
#[test]
fn test_title_dirty_independent_per_session() {
    let mut session1 = make_session();
    let mut session2 = make_session();

    // Set title only in session1.
    session1.core.advance(b"\x1b]2;session1-title\x07");

    assert!(
        session1.take_title_if_dirty().is_some(),
        "session1 must have title dirty after OSC 2"
    );
    assert!(
        session2.take_title_if_dirty().is_none(),
        "session2 must not have title dirty (OSC 2 was only sent to session1)"
    );
}

/// Clipboard actions in session1 must not bleed into session2.
///
/// An OSC 52 write sent to session1 must leave session2's clipboard queue empty.
#[test]
fn test_clipboard_actions_independent_per_session() {
    let mut session1 = make_session();
    let mut session2 = make_session();

    // Send OSC 52 only to session1.
    session1.core.advance(b"\x1b]52;c;aGVsbG8=\x07"); // base64("hello")

    assert!(
        !session1.take_clipboard_actions().is_empty(),
        "session1 must have clipboard actions after OSC 52"
    );
    assert!(
        session2.take_clipboard_actions().is_empty(),
        "session2 clipboard actions must remain empty (OSC 52 sent only to session1)"
    );
}

/// DEC mode state in session1 must not bleed into session2.
///
/// Enabling bracketed paste in session1 must leave session2's
/// `get_bracketed_paste` returning `false`.
#[test]
fn test_dec_mode_state_independent_per_session() {
    let mut session1 = make_session();
    let session2 = make_session();

    // Enable bracketed paste in session1.
    session1.core.advance(b"\x1b[?2004h");

    assert!(
        session1.get_bracketed_paste(),
        "session1 must have bracketed_paste=true after CSI ?2004h"
    );
    assert!(
        !session2.get_bracketed_paste(),
        "session2 bracketed_paste must remain false (mode set only in session1)"
    );
}
