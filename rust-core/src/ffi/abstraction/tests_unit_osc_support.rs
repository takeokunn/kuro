use crate::ffi::abstraction::session::TerminalSession;
use crate::ffi::abstraction::tests_unit::make_session;

pub(crate) fn make_osc_session() -> TerminalSession {
    make_session()
}

pub(crate) fn advance(session: &mut TerminalSession, bytes: &[u8]) {
    session.core.advance(bytes);
}

pub(crate) fn osc7(uri: &str) -> Vec<u8> {
    format!("\x1b]7;{uri}\x07").into_bytes()
}

pub(crate) fn osc10(spec: &str) -> Vec<u8> {
    format!("\x1b]10;{spec}\x07").into_bytes()
}

pub(crate) fn osc8(uri: &str, text: &str) -> Vec<u8> {
    format!("\x1b]8;;{uri}\x07{text}\x1b]8;;\x07").into_bytes()
}

pub(crate) fn decscusr(param: u8) -> Vec<u8> {
    format!("\x1b[{param} q").into_bytes()
}
