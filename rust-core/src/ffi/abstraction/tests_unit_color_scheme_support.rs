use super::super::make_session;
use crate::ffi::abstraction::session::TerminalSession;

pub(crate) fn make_color_scheme_session() -> TerminalSession {
    make_session()
}

pub(crate) fn enable_color_scheme_notifications(session: &mut TerminalSession) {
    session.core.advance(b"\x1b[?2031h");
}

pub(crate) fn clear_pending_responses(session: &mut TerminalSession) {
    session.core.meta.pending_responses.clear();
}

pub(crate) fn assert_single_pending_response(session: &TerminalSession, expected: &[u8]) {
    assert_eq!(session.core.meta.pending_responses.len(), 1);
    assert_eq!(session.core.meta.pending_responses[0], expected);
}
