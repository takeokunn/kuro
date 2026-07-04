//! FFI session-accessor tests for iTerm2 OSC 1337 user vars / remote host and
//! the ConEmu OSC 9;4 progress state.

use super::support::{advance, make_osc_session};

fn osc1337(payload: &str) -> Vec<u8> {
    format!("\x1b]1337;{payload}\x07").into_bytes()
}

#[test]
fn test_take_user_vars_if_dirty_returns_decoded_pairs() {
    let mut session = make_osc_session();
    // base64("hello") = "aGVsbG8="
    advance(&mut session, &osc1337("SetUserVar=greeting=aGVsbG8="));

    let vars = session.take_user_vars_if_dirty().expect("dirty after set");
    assert_eq!(vars, vec![("greeting".to_owned(), "hello".to_owned())]);

    // Non-destructive after read: subsequent poll returns None (not dirty).
    assert!(session.take_user_vars_if_dirty().is_none());
}

#[test]
fn test_take_user_vars_if_dirty_none_on_fresh_session() {
    let mut session = make_osc_session();
    assert!(session.take_user_vars_if_dirty().is_none());
}

#[test]
fn test_take_remote_host_if_dirty() {
    let mut session = make_osc_session();
    advance(&mut session, &osc1337("RemoteHost=bob@host.example"));

    assert_eq!(
        session.take_remote_host_if_dirty().as_deref(),
        Some("bob@host.example")
    );
    // Cleared after read.
    assert!(session.take_remote_host_if_dirty().is_none());
}

#[test]
fn test_take_progress_if_dirty_set_and_clear() {
    let mut session = make_osc_session();
    // OSC 9 ; 4 ; 1 ; 75 → Set(75) → (state=1, percent=75)
    advance(&mut session, &b"\x1b]9;4;1;75\x07"[..]);
    assert_eq!(session.take_progress_if_dirty(), Some((1, 75)));
    assert!(session.take_progress_if_dirty().is_none());

    // OSC 9 ; 4 ; 0 → None → (state=0, percent=0)
    advance(&mut session, &b"\x1b]9;4;0\x07"[..]);
    assert_eq!(session.take_progress_if_dirty(), Some((0, 0)));
}

#[test]
fn test_take_progress_if_dirty_variants() {
    let mut session = make_osc_session();
    // Indeterminate → (3, 0)
    advance(&mut session, &b"\x1b]9;4;3\x07"[..]);
    assert_eq!(session.take_progress_if_dirty(), Some((3, 0)));
    // Warning at 40 → (4, 40)
    advance(&mut session, &b"\x1b]9;4;4;40\x07"[..]);
    assert_eq!(session.take_progress_if_dirty(), Some((4, 40)));
    // Error at 10 → (2, 10)
    advance(&mut session, &b"\x1b]9;4;2;10\x07"[..]);
    assert_eq!(session.take_progress_if_dirty(), Some((2, 10)));
}
