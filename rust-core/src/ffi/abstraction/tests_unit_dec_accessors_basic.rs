use super::*;

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
