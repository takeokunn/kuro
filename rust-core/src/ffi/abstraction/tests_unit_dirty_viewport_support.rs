use super::make_session;
use super::TerminalSession;

pub(crate) fn make_viewport_session() -> TerminalSession {
    make_session()
}

pub(crate) fn scrollback_batch(session: &mut TerminalSession, count: usize) {
    for _ in 0..count {
        let newlines = b"\n".repeat(24);
        session.core.advance(&newlines);
    }
}

pub(crate) fn scrollback_with_marker(session: &mut TerminalSession, marker: &[u8]) {
    session.core.advance(marker);
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);
}

pub(crate) fn assert_scrollback_non_empty(session: &TerminalSession, context: &str) {
    assert!(session.core.screen.scrollback_line_count > 0, "{context}");
}
