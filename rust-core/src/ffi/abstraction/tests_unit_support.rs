use super::{SessionState, TerminalSession};

/// Assert that calling `$expr` once returns a truthy/`Some`/non-empty result,
/// then a second call returns a falsy/`None`/empty result (drain-once semantics).
///
/// Works with `bool`, `Option<_>`, and `Vec<_>` via the `$empty` pattern:
///   - bool: `assert_drain_once!(session.take_bell_pending(), false)`
///   - Option: `assert_drain_once!(session.take_title_if_dirty(), None::<String>)`
///   - Vec: `assert_drain_once!(session.take_clipboard_actions(), vec![])`
macro_rules! assert_drain_once {
    // bool variant
    ($first:expr, bool) => {{
        assert!($first, "first call must return true");
        assert!(!$first, "second call must return false (flag cleared)");
    }};
    // Option variant — checks first is Some, second is None
    ($session:expr, $method:ident, option) => {{
        assert!($session.$method().is_some(), "first call must return Some");
        assert!($session.$method().is_none(), "second call must return None");
    }};
    // Vec variant — checks first is non-empty, second is empty
    ($session:expr, $method:ident, vec) => {{
        assert!(
            !$session.$method().is_empty(),
            "first call must be non-empty"
        );
        assert!($session.$method().is_empty(), "second call must be empty");
    }};
}

/// Advance a session, then assert all listed row indices are present in `get_dirty_lines`.
macro_rules! assert_rows_dirty {
    ($session:expr, advance $bytes:expr, rows [$($row:literal),+]) => {{
        $session.core.advance($bytes);
        let dirty = $session.get_dirty_lines();
        $(
            assert!(
                dirty.iter().any(|(r, _)| *r == $row),
                "row {} must be dirty after advance",
                $row
            );
        )+
    }};
}

// Helper: construct a TerminalSession without spawning a real PTY.
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
