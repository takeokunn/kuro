use super::support::advance;
use super::*;

// ---------------------------------------------------------------------------
// cursor shape and dirty rows
// ---------------------------------------------------------------------------

#[test]
fn test_get_cursor_shape_steady_block() {
    use crate::types::cursor::CursorShape;

    let mut session = make_session();
    advance(&mut session, b"\x1b[2 q");

    assert_eq!(session.get_cursor_shape(), CursorShape::SteadyBlock);
}

#[test]
fn test_get_cursor_shape_blinking_bar() {
    use crate::types::cursor::CursorShape;

    let mut session = make_session();
    advance(&mut session, b"\x1b[5 q");

    assert_eq!(session.get_cursor_shape(), CursorShape::BlinkingBar);
}

#[test]
fn test_get_cursor_shape_steady_bar() {
    use crate::types::cursor::CursorShape;

    let mut session = make_session();
    advance(&mut session, b"\x1b[6 q");

    assert_eq!(session.get_cursor_shape(), CursorShape::SteadyBar);
}

#[test]
fn test_get_dirty_lines_full_dirty_on_alt_screen_exit() {
    let mut session = make_session();
    advance(&mut session, b"\x1b[?1049h");
    let _ = session.core.screen.take_dirty_lines();

    advance(&mut session, b"ALT_CONTENT");
    let _ = session.core.screen.take_dirty_lines();

    advance(&mut session, b"\x1b[?1049l");
    let dirty = session.get_dirty_lines();
    assert_eq!(dirty.len(), 24);
}
