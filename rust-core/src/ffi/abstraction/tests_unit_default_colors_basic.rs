use super::support::advance;
use super::*;

// ---------------------------------------------------------------------------
// get_default_colors / take_default_colors_dirty / take_title_if_dirty
// ---------------------------------------------------------------------------

#[test]
fn test_get_default_colors_after_osc11_bg() {
    let mut session = make_session();
    advance(&mut session, b"\x1b]11;rgb:00/80/ff\x07");

    let (_fg, bg, _cursor) = session.get_default_colors();
    assert_ne!(bg, 0xFF00_0000u32);
}

#[test]
fn test_get_default_colors_after_osc12_cursor() {
    let mut session = make_session();
    advance(&mut session, b"\x1b]12;rgb:ff/ff/00\x07");

    let (_fg, _bg, cursor) = session.get_default_colors();
    assert_ne!(cursor, 0xFF00_0000u32);
}

#[test]
fn test_take_default_colors_dirty_set_by_osc11() {
    let mut session = make_session();
    advance(&mut session, b"\x1b]11;rgb:00/ff/80\x07");

    assert!(session.take_default_colors_dirty());
    assert!(!session.take_default_colors_dirty());
}

#[test]
fn test_take_title_if_dirty_via_osc0() {
    let mut session = make_session();
    advance(&mut session, b"\x1b]0;osc-zero-title\x07");

    let result = session.take_title_if_dirty();
    assert_eq!(result.as_deref(), Some("osc-zero-title"));
    assert!(session.take_title_if_dirty().is_none());
}
