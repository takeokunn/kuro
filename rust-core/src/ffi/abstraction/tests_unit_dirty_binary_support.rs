use super::make_session;
use super::TerminalSession;

pub(crate) fn make_binary_session() -> TerminalSession {
    make_session()
}

pub(crate) fn consume_initial_dirty(session: &mut TerminalSession) {
    let _ = session.get_dirty_lines_binary_direct();
}

pub(crate) fn fill_scrollback(session: &mut TerminalSession, count: usize) {
    for _ in 0..count {
        session.core.advance(&b"\n".repeat(24));
    }
}

pub(crate) fn enter_alt_screen(session: &mut TerminalSession) {
    session.core.advance(b"\x1b[?1049h");
}

pub(crate) fn enable_sync_output(session: &mut TerminalSession) {
    session.core.advance(b"\x1b[?2026h");
}

pub(crate) fn binary_num_rows(buf: &[u8]) -> u32 {
    // Header layout: [version: u32][num_rows: u32][rows...]
    u32::from_le_bytes(buf[4..8].try_into().unwrap())
}
