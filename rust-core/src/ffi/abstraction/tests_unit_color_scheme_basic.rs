use super::support::make_color_scheme_session;

// ---------------------------------------------------------------------------
// set_color_scheme: public TerminalSession facade
// ---------------------------------------------------------------------------

/// Default `meta.color_scheme_dark` is `true` on a fresh session.
#[test]
fn test_session_default_color_scheme_dark_is_true() {
    let session = make_color_scheme_session();
    assert!(
        session.core.meta.color_scheme_dark,
        "TerminalMeta default must have color_scheme_dark = true"
    );
}

/// `set_color_scheme(false)` flips the stored value and reports `true`
/// (changed). Subsequent `set_color_scheme(false)` reports `false` (no-op).
#[test]
fn test_set_color_scheme_first_change_returns_true_then_idempotent() {
    let mut session = make_color_scheme_session();
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
    let mut session = make_color_scheme_session();
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
