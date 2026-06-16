use super::support::{enable_color_scheme_notifications, make_color_scheme_session};

// ---------------------------------------------------------------------------
// Isolation: color_scheme_dark lives on TerminalMeta, NOT DecModes
// ---------------------------------------------------------------------------

/// Resetting DEC mode 2031 must NOT clear `color_scheme_dark`. The two pieces
/// of state are independent — mode 2031 only gates the proactive notification;
/// `color_scheme_dark` is the actual theme value.
#[test]
fn test_reset_mode_2031_does_not_clear_color_scheme_dark() {
    let mut session = make_color_scheme_session();
    enable_color_scheme_notifications(&mut session);
    let _ = session.set_color_scheme(false);
    assert!(!session.core.meta.color_scheme_dark);
    // Reset mode 2031.
    session.core.advance(b"\x1b[?2031l");
    assert!(
        !session.core.meta.color_scheme_dark,
        "resetting mode 2031 must not mutate color_scheme_dark — state is independent"
    );
}

/// `apply_mode(2031, ...)` only touches `dec_modes.color_scheme_notifications`.
/// `meta.color_scheme_dark` must be untouched even though both names share the
/// `color_scheme_` prefix.
#[test]
fn test_apply_mode_2031_does_not_touch_color_scheme_dark() {
    let mut session = make_color_scheme_session();
    let initial = session.core.meta.color_scheme_dark;
    session.core.dec_modes.apply_mode(2031, true);
    assert_eq!(
        session.core.meta.color_scheme_dark, initial,
        "DecModes::apply_mode(2031, ...) must not mutate meta.color_scheme_dark"
    );
}
