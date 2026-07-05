use crate::{SessionState, TerminalSession};

pub(crate) fn make_core() -> crate::TerminalCore {
    crate::TerminalCore::new(24, 80)
}

pub(crate) fn make_session() -> TerminalSession {
    TerminalSession {
        core: crate::TerminalCore::new(24, 80),
        #[cfg(unix)]
        pty: None,
        command: String::new(),
        state: SessionState::Bound,
        #[cfg(unix)]
        pending_input: Vec::new(),
        row_hashes: Vec::new(),
        palette_epoch: 0,
        was_alt_screen: false,
        encode_pool: crate::ffi::codec::EncodePool::new(),
        dirty_scratch: Vec::new(),
        texts_scratch: Vec::new(),
        buf_scratch: Vec::new(),
        sync_suppressed_polls: 0,
    }
}
