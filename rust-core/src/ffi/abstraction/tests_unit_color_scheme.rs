// ── tests_unit_color_scheme.rs — FFI-level set_color_scheme + DSR 996 ────────
//
// Included into the parent abstraction-tests module via `include!()`.
// Mirrors the parser-level tests in `parser/tests/dec_private.rs` but exercises
// the public `TerminalSession::set_color_scheme(bool) -> bool` facade and
// asserts state stored on `TerminalMeta` (Emacs-owned host state) rather than
// `DecModes` (PTY-settable state).
//
// FR-125: color_scheme_dark + DSR 996 + mode 2031 notification path.

// ---------------------------------------------------------------------------
// set_color_scheme: public TerminalSession facade
// ---------------------------------------------------------------------------

/// Default `meta.color_scheme_dark` is `true` on a fresh session.
#[test]
fn test_session_default_color_scheme_dark_is_true() {
    let session = make_session();
    assert!(
        session.core.meta.color_scheme_dark,
        "TerminalMeta default must have color_scheme_dark = true"
    );
}

/// `set_color_scheme(false)` flips the stored value and reports `true`
/// (changed). Subsequent `set_color_scheme(false)` reports `false` (no-op).
#[test]
fn test_set_color_scheme_first_change_returns_true_then_idempotent() {
    let mut session = make_session();
    assert!(
        session.set_color_scheme(false),
        "first dark→light call must report changed = true"
    );
    assert!(
        !session.core.meta.color_scheme_dark,
        "set_color_scheme(false) must store color_scheme_dark = false"
    );
    assert!(
        !session.set_color_scheme(false),
        "second call with the same value must report changed = false (idempotent)"
    );
}

/// `set_color_scheme(true)` while already dark is a no-op (returns false,
/// pushes nothing).
#[test]
fn test_set_color_scheme_idempotent_when_already_dark() {
    let mut session = make_session();
    assert!(
        !session.set_color_scheme(true),
        "set_color_scheme(true) on default-dark session must report changed = false"
    );
    assert!(session.core.meta.color_scheme_dark);
    assert!(
        session.core.meta.pending_responses.is_empty(),
        "no-op call must not push any notification bytes"
    );
}

// ---------------------------------------------------------------------------
// Notification gating by DEC mode 2031
// ---------------------------------------------------------------------------

/// `set_color_scheme` change WITHOUT mode 2031 enabled — state changes but
/// no notification bytes are pushed.
#[test]
fn test_set_color_scheme_change_without_mode_2031_pushes_nothing() {
    let mut session = make_session();
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
    let mut session = make_session();
    session.core.advance(b"\x1b[?2031h"); // enable color scheme notifications
    let changed = session.set_color_scheme(false);
    assert!(changed);
    assert_eq!(session.core.meta.pending_responses.len(), 1);
    assert_eq!(
        session.core.meta.pending_responses[0],
        b"\x1b[?997;2n",
        "light theme notification must be Ps=2"
    );
}

/// `set_color_scheme(true)` after starting light + mode 2031 enabled — pushes
/// `CSI ? 997 ; 1 n` (Ps=1 = dark).
#[test]
fn test_set_color_scheme_light_to_dark_with_mode_2031_pushes_dark_response() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?2031h");
    // Start by switching to light; notification fires (Ps=2).
    let _ = session.set_color_scheme(false);
    session.core.meta.pending_responses.clear();
    // Now switch back to dark; notification fires (Ps=1).
    let changed = session.set_color_scheme(true);
    assert!(changed);
    assert_eq!(session.core.meta.pending_responses.len(), 1);
    assert_eq!(session.core.meta.pending_responses[0], b"\x1b[?997;1n");
}

// ---------------------------------------------------------------------------
// DSR 996 query — independent of mode 2031
// ---------------------------------------------------------------------------

/// DSR 996 (CSI ? 996 n) on a fresh session — pushes `CSI ? 997 ; 1 n`
/// because `color_scheme_dark` defaults to `true` (dark).
#[test]
fn test_dsr_996_default_session_responds_with_dark() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?996n");
    assert_eq!(session.core.meta.pending_responses.len(), 1);
    assert_eq!(session.core.meta.pending_responses[0], b"\x1b[?997;1n");
}

/// DSR 996 after `set_color_scheme(false)` — pushes `CSI ? 997 ; 2 n`.
/// Mode 2031 is NOT enabled, so the change itself does not push; DSR 996
/// is the only response.
#[test]
fn test_dsr_996_after_set_color_scheme_light_responds_with_light() {
    let mut session = make_session();
    let _ = session.set_color_scheme(false);
    assert!(session.core.meta.pending_responses.is_empty());
    session.core.advance(b"\x1b[?996n");
    assert_eq!(session.core.meta.pending_responses.len(), 1);
    assert_eq!(session.core.meta.pending_responses[0], b"\x1b[?997;2n");
}

// ---------------------------------------------------------------------------
// Isolation: color_scheme_dark lives on TerminalMeta, NOT DecModes
// ---------------------------------------------------------------------------

/// Resetting DEC mode 2031 must NOT clear `color_scheme_dark`. The two pieces
/// of state are independent — mode 2031 only gates the proactive notification;
/// `color_scheme_dark` is the actual theme value.
#[test]
fn test_reset_mode_2031_does_not_clear_color_scheme_dark() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?2031h");
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
    let mut session = make_session();
    let initial = session.core.meta.color_scheme_dark;
    session.core.dec_modes.apply_mode(2031, true);
    assert_eq!(
        session.core.meta.color_scheme_dark, initial,
        "DecModes::apply_mode(2031, ...) must not mutate meta.color_scheme_dark"
    );
}
