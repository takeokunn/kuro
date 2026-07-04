use super::support::advance;
use super::*;

// ---------------------------------------------------------------------------
// clipboard / liveness
// ---------------------------------------------------------------------------

#[test]
fn test_take_clipboard_actions_two_writes_drained_together() {
    let mut session = make_session();
    advance(&mut session, b"\x1b]52;c;aGVsbG8=\x07");
    advance(&mut session, b"\x1b]52;c;d29ybGQ=\x07");

    let actions = session.take_clipboard_actions();
    assert_eq!(actions.len(), 2);
    for action in &actions {
        assert!(matches!(
            action,
            crate::types::osc::ClipboardAction::Write { .. }
        ));
    }
    assert!(session.take_clipboard_actions().is_empty());
}

#[test]
fn test_is_process_alive_no_pty() {
    let session = make_session();
    assert!(session.is_process_alive());
}
