use super::support::{
    assert_single_pending_response, clear_pending_responses, enable_color_scheme_notifications,
    make_color_scheme_session,
};

// ---------------------------------------------------------------------------
// Notification gating by DEC mode 2031
// ---------------------------------------------------------------------------

/// `set_color_scheme` change WITHOUT mode 2031 enabled — state changes but
/// no notification bytes are pushed.
#[test]
fn test_set_color_scheme_change_without_mode_2031_pushes_nothing() {
    let mut session = make_color_scheme_session();
    assert!(
        !session.core.dec_modes.color_scheme_notifications,
        "color_scheme_notifications must default to false"
    );
    let changed = session.set_color_scheme(false);
    assert!(changed);
    assert!(
        session.core.meta.pending_responses.is_empty(),
        "mode 2031 disabled must suppress proactive CSI ? 997 ; Ps n notification"
    );
}

/// `set_color_scheme` change WITH mode 2031 enabled — pushes exactly one
/// `CSI ? 997 ; 2 n` byte string for dark→light.
#[test]
fn test_set_color_scheme_change_with_mode_2031_pushes_light_response() {
    let mut session = make_color_scheme_session();
    enable_color_scheme_notifications(&mut session);
    let changed = session.set_color_scheme(false);
    assert!(changed);
    assert_single_pending_response(&session, b"\x1b[?997;2n");
}

/// `set_color_scheme(true)` after starting light + mode 2031 enabled — pushes
/// `CSI ? 997 ; 1 n` (Ps=1 = dark).
#[test]
fn test_set_color_scheme_light_to_dark_with_mode_2031_pushes_dark_response() {
    let mut session = make_color_scheme_session();
    enable_color_scheme_notifications(&mut session);
    // Start by switching to light; notification fires (Ps=2).
    let _ = session.set_color_scheme(false);
    clear_pending_responses(&mut session);
    // Now switch back to dark; notification fires (Ps=1).
    let changed = session.set_color_scheme(true);
    assert!(changed);
    assert_single_pending_response(&session, b"\x1b[?997;1n");
}

// ---------------------------------------------------------------------------
// DSR 996 query — independent of mode 2031
// ---------------------------------------------------------------------------

/// DSR 996 (CSI ? 996 n) on a fresh session — pushes `CSI ? 997 ; 1 n`
/// because `color_scheme_dark` defaults to `true` (dark).
#[test]
fn test_dsr_996_default_session_responds_with_dark() {
    let mut session = make_color_scheme_session();
    session.core.advance(b"\x1b[?996n");
    assert_single_pending_response(&session, b"\x1b[?997;1n");
}

/// DSR 996 after `set_color_scheme(false)` — pushes `CSI ? 997 ; 2 n`.
/// Mode 2031 is NOT enabled, so the change itself does not push; DSR 996
/// is the only response.
#[test]
fn test_dsr_996_after_set_color_scheme_light_responds_with_light() {
    let mut session = make_color_scheme_session();
    let _ = session.set_color_scheme(false);
    assert!(session.core.meta.pending_responses.is_empty());
    session.core.advance(b"\x1b[?996n");
    assert_single_pending_response(&session, b"\x1b[?997;2n");
}
