use super::support::advance;
use super::*;

// ---------------------------------------------------------------------------
// scrollback, viewport, resize
// ---------------------------------------------------------------------------

#[test]
fn test_set_scrollback_max_lines_caps_buffer() {
    let mut session = make_session();
    session.set_scrollback_max_lines(5);

    for _ in 0..50 {
        advance(&mut session, b"line\n");
    }

    assert!(session.get_scrollback_count() <= 5);
}

#[test]
fn test_viewport_scroll_down_noop_at_zero_offset() {
    let mut session = make_session();

    assert_eq!(session.scroll_offset(), 0);
    session.viewport_scroll_down(5);
    assert_eq!(session.scroll_offset(), 0);
}

#[test]
fn test_resize_idempotent_same_dimensions() {
    let mut session = make_session();
    session.resize(24, 80).expect("first resize must not fail");
    session
        .resize(24, 80)
        .expect("second resize with same dims must not fail");

    assert_eq!(session.core.screen.rows(), 24);
    assert_eq!(session.core.screen.cols(), 80);
}
