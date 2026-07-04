use super::make_session;
use super::TerminalSession;

pub(crate) fn make_dirty_session() -> TerminalSession {
    make_session()
}

pub(crate) fn advance_newlines(session: &mut TerminalSession, count: usize) {
    let newlines = b"\n".repeat(count);
    session.core.advance(&newlines);
}

pub(crate) fn push_scrollback_line(session: &mut TerminalSession, line: &[u8]) {
    session.core.advance(line);
    advance_newlines(session, 24);
}

pub(crate) fn push_scrollback_lines(session: &mut TerminalSession, count: usize) {
    for _ in 0..count {
        session.core.advance(b"line\n");
    }
    advance_newlines(session, 24);
}

pub(crate) fn assert_scrollback_contains(session: &TerminalSession, needle: &str) {
    let sb = session.get_scrollback(100);
    assert!(
        sb.iter().any(|line| line.contains(needle)),
        "scrollback must contain the written line"
    );
}
