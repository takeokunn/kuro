// ---------------------------------------------------------------------------
// DEC mode accessor smoke tests
// ---------------------------------------------------------------------------

/// All DEC mode accessors return their expected defaults on a fresh session.
#[test]
fn test_dec_mode_accessors_initial_defaults() {
    let session = make_session();

    assert!(!session.get_mouse_pixel(), "mouse_pixel defaults to false");
    assert_eq!(session.get_mouse_mode(), 0, "mouse_mode defaults to 0");
    assert!(!session.get_mouse_sgr(), "mouse_sgr defaults to false");
    assert!(
        !session.get_app_cursor_keys(),
        "app_cursor_keys defaults to false"
    );
    assert!(!session.get_app_keypad(), "app_keypad defaults to false");
    assert_eq!(
        session.get_keyboard_flags(),
        0,
        "keyboard_flags defaults to 0"
    );
    assert!(
        !session.get_bracketed_paste(),
        "bracketed_paste defaults to false"
    );
    assert!(
        !session.get_focus_events(),
        "focus_events defaults to false"
    );
    assert!(
        !session.get_synchronized_output(),
        "synchronized_output defaults to false"
    );
}

/// `get_cursor_shape` starts at `BlinkingBlock`.
#[test]
fn test_get_cursor_shape_default() {
    use crate::types::cursor::CursorShape;
    let session = make_session();
    assert_eq!(
        session.get_cursor_shape(),
        CursorShape::BlinkingBlock,
        "cursor_shape must default to BlinkingBlock"
    );
}

/// `get_app_cursor_keys` returns `true` after `CSI ?1h` (DECCKM set).
#[test]
fn test_get_app_cursor_keys_set_by_decckm() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1h"); // DECCKM on
    assert!(
        session.get_app_cursor_keys(),
        "get_app_cursor_keys must return true after CSI ?1h"
    );
    session.core.advance(b"\x1b[?1l"); // DECCKM off
    assert!(
        !session.get_app_cursor_keys(),
        "get_app_cursor_keys must return false after CSI ?1l"
    );
}

/// `get_bracketed_paste` returns `true` after `CSI ?2004h`.
#[test]
fn test_get_bracketed_paste_set_by_mode() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?2004h");
    assert!(
        session.get_bracketed_paste(),
        "get_bracketed_paste must return true after CSI ?2004h"
    );
}

/// `get_focus_events` returns `true` after `CSI ?1004h`.
#[test]
fn test_get_focus_events_set_by_mode() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1004h");
    assert!(
        session.get_focus_events(),
        "get_focus_events must return true after CSI ?1004h"
    );
}

/// `get_keyboard_flags` reflects the kitty keyboard flags pushed by `CSI > Ps u`.
#[test]
fn test_get_keyboard_flags_after_push() {
    let mut session = make_session();
    session.core.advance(b"\x1b[>5u"); // push flags=5
    assert_eq!(
        session.get_keyboard_flags(),
        5,
        "get_keyboard_flags must return 5 after CSI >5u"
    );
}

// ---------------------------------------------------------------------------
// take_prompt_marks: drain-once semantics
// ---------------------------------------------------------------------------

/// `take_prompt_marks` returns empty on a fresh session.
#[test]
fn test_take_prompt_marks_empty_initially() {
    let mut session = make_session();
    assert!(
        session.take_prompt_marks().is_empty(),
        "take_prompt_marks must return empty vec on a fresh session"
    );
}

/// `take_prompt_marks` returns an event after OSC 133 and drains the queue.
#[test]
fn test_take_prompt_marks_drains_after_osc133() {
    let mut session = make_session();
    session.core.advance(b"\x1b]133;A\x1b\\");
    assert_drain_once!(session, take_prompt_marks, vec);
}

// ---------------------------------------------------------------------------
// get_image_png_base64 / take_pending_image_notifications
// ---------------------------------------------------------------------------

/// `get_image_png_base64` returns empty string for unknown image IDs.
#[test]
fn test_get_image_png_base64_unknown_id_returns_empty() {
    let session = make_session();
    let result = session.get_image_png_base64(999_999);
    assert!(
        result.is_empty(),
        "get_image_png_base64 must return empty string for unknown image ID"
    );
}

/// `take_pending_image_notifications` returns empty vec on a fresh session.
#[test]
fn test_take_pending_image_notifications_empty_initially() {
    let mut session = make_session();
    let notifs = session.take_pending_image_notifications();
    assert!(
        notifs.is_empty(),
        "take_pending_image_notifications must return empty vec on a fresh session"
    );
}

// ---------------------------------------------------------------------------
// has_pending_output: non-unix stub
// ---------------------------------------------------------------------------

/// `has_pending_output` returns `false` on test sessions with no PTY.
#[test]
fn test_has_pending_output_false_without_pty() {
    let session = make_session();
    // On Unix, pty is None so has_pending_output checks pending_input + pty.
    // Both are empty/None → must return false.
    assert!(
        !session.has_pending_output(),
        "has_pending_output must return false for a test session with no PTY"
    );
}

// ---------------------------------------------------------------------------
// get_cursor / get_cursor_visible
// ---------------------------------------------------------------------------

/// `get_cursor` starts at (0, 0) on a fresh session.
#[test]
fn test_get_cursor_initial_position() {
    let session = make_session();
    assert_eq!(
        session.get_cursor(),
        (0, 0),
        "cursor must start at (row=0, col=0) on a fresh session"
    );
}

/// After writing 3 chars, `get_cursor` column advances to 3.
#[test]
fn test_get_cursor_advances_after_write() {
    let mut session = make_session();
    session.core.advance(b"ABC");
    let (row, col) = session.get_cursor();
    assert_eq!(row, 0, "cursor row must remain 0 after writing to line 0");
    assert_eq!(col, 3, "cursor col must be 3 after writing 3 ASCII chars");
}

/// `get_cursor` reflects `CUP` (CSI H) escape sequences correctly.
#[test]
fn test_get_cursor_reflects_cup_escape() {
    let mut session = make_session();
    session.core.advance(b"\x1b[5;10H"); // move to row 5, col 10 (1-based)
    let (row, col) = session.get_cursor();
    assert_eq!(row, 4, "CUP row 5 must map to 0-based row 4");
    assert_eq!(col, 9, "CUP col 10 must map to 0-based col 9");
}

/// `get_cursor_visible` is true by default (DECTCEM default = on).
#[test]
fn test_get_cursor_visible_default_true() {
    let session = make_session();
    assert!(
        session.get_cursor_visible(),
        "cursor must be visible by default (DECTCEM on)"
    );
}

/// `get_cursor_visible` returns `false` after `CSI ?25l`.
#[test]
fn test_get_cursor_visible_hidden_by_escape() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?25l"); // DECTCEM off
    assert!(
        !session.get_cursor_visible(),
        "get_cursor_visible must return false after CSI ?25l"
    );
    session.core.advance(b"\x1b[?25h"); // DECTCEM on
    assert!(
        session.get_cursor_visible(),
        "get_cursor_visible must return true after CSI ?25h"
    );
}

// ---------------------------------------------------------------------------
// resize: row-hash invalidation
// ---------------------------------------------------------------------------

/// After `resize`, `row_hashes` must be empty (cache invalidated).
#[test]
fn test_resize_clears_row_hashes() {
    let mut session = make_session();
    // Write content so row-hash cache gets populated via get_dirty_lines_with_faces.
    session.core.advance(b"Hello");
    let _ = session.get_dirty_lines_with_faces();
    // Cache may have entries now; resize must clear them.
    session
        .resize(30, 100)
        .expect("resize must not fail on test session");
    assert!(
        session.row_hashes.iter().all(|slot| slot.is_none()),
        "resize must invalidate all row_hashes cache entries"
    );
}

/// After `resize`, terminal dimensions reflect the new values.
#[test]
fn test_resize_updates_terminal_dimensions() {
    let mut session = make_session();
    session.resize(30, 120).expect("resize must not fail");
    assert_eq!(
        session.core.screen.rows(),
        30,
        "rows must be 30 after resize(30, 120)"
    );
    assert_eq!(
        session.core.screen.cols(),
        120,
        "cols must be 120 after resize(30, 120)"
    );
}

// ---------------------------------------------------------------------------
// get_app_keypad / get_mouse_sgr / get_mouse_pixel
// ---------------------------------------------------------------------------

/// `get_app_keypad` returns `true` after `CSI ?1h` (DECKPAM on = DECCKM also).
/// Use `ESC =` (application keypad) to set app_keypad mode directly.
#[test]
fn test_get_app_keypad_set_by_escape() {
    let mut session = make_session();
    session.core.advance(b"\x1b="); // DECKPAM (application keypad on)
    assert!(
        session.get_app_keypad(),
        "get_app_keypad must return true after ESC ="
    );
    session.core.advance(b"\x1b>"); // DECKPNM (numeric keypad)
    assert!(
        !session.get_app_keypad(),
        "get_app_keypad must return false after ESC >"
    );
}

/// `get_mouse_sgr` returns `true` after `CSI ?1006h` (SGR mouse encoding).
#[test]
fn test_get_mouse_sgr_set_by_mode() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1006h");
    assert!(
        session.get_mouse_sgr(),
        "get_mouse_sgr must return true after CSI ?1006h"
    );
    session.core.advance(b"\x1b[?1006l");
    assert!(
        !session.get_mouse_sgr(),
        "get_mouse_sgr must return false after CSI ?1006l"
    );
}

/// `get_mouse_mode` reflects mouse tracking mode set by `CSI ?1000h`.
#[test]
fn test_get_mouse_mode_set_by_mode_1000() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1000h"); // X10 mouse tracking
    assert_eq!(
        session.get_mouse_mode(),
        1000,
        "get_mouse_mode must return 1000 after CSI ?1000h"
    );
    session.core.advance(b"\x1b[?1000l");
    assert_eq!(
        session.get_mouse_mode(),
        0,
        "get_mouse_mode must return 0 after CSI ?1000l"
    );
}

// ---------------------------------------------------------------------------
// assert_rows_dirty! macro smoke test
// ---------------------------------------------------------------------------

/// `get_dirty_lines` returns row 0 dirty after writing to row 0.
#[test]
fn test_assert_rows_dirty_macro_row_zero() {
    let mut session = make_session();
    // Drain any initial full_dirty state.
    session.core.screen.take_dirty_lines();
    assert_rows_dirty!(session, advance b"Hello", rows [0]);
}

/// Writing to a specific row via CUP marks only that row dirty.
#[test]
fn test_assert_rows_dirty_macro_specific_row() {
    let mut session = make_session();
    // Drain full_dirty from session construction.
    session.core.screen.take_dirty_lines();
    // Move to row 3 (0-based), col 0, then write.
    assert_rows_dirty!(session, advance b"\x1b[4;1HContent", rows [3]);
}
