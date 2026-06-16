use crate::ffi::abstraction::session::TerminalSession;

pub(crate) fn advance(session: &mut TerminalSession, bytes: &[u8]) {
    session.core.advance(bytes);
}
