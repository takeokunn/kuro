//! Global terminal session state and accessor functions
//!
//! This module owns the `TERMINAL_SESSIONS` HashMap and provides
//! the public API for initializing, accessing, and tearing down
//! per-session terminal state.  Multiple sessions can coexist;
//! each is keyed by a unique `u64` ID returned from `init_session`.

use super::session::TerminalSession;
use crate::{error::KuroError, Result};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex};

/// Global terminal sessions map (wrapped in Mutex for thread safety).
///
/// Each entry is keyed by the unique session ID returned from `init_session`.
/// `LazyLock` is required because `HashMap::new()` is not const.
pub static TERMINAL_SESSIONS: LazyLock<Mutex<HashMap<u64, TerminalSession>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Auto-incrementing session ID counter.  The first session receives ID 0,
/// preserving backward compatibility with Elisp callers that test
/// `(not (null result))` — any non-negative integer is truthy in Elisp.
static SESSION_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Lock `TERMINAL_SESSIONS` and map mutex-poison errors to `KuroError::State`.
macro_rules! lock_terminals {
    () => {
        TERMINAL_SESSIONS
            .lock()
            .map_err(|_e| KuroError::State(crate::ffi::error::StateError::NoTerminalSession))?
    };
}

/// Initialize a new terminal session and return its unique session ID.
///
/// The first call returns `0`; subsequent calls return incrementing values.
///
/// # Safety
/// This function modifies a global static mutex and must be called safely.
pub fn init_session(command: &str, rows: u16, cols: u16) -> Result<u64> {
    let id = SESSION_COUNTER.fetch_add(1, Ordering::Relaxed);
    let session = TerminalSession::new(command, rows, cols)?;
    let mut global = lock_terminals!();
    global.insert(id, session);
    Ok(id)
}

/// Get mutable reference to the specified terminal session.
///
/// Returns `Err` if no session with the given ID exists.
pub fn with_session<F, R>(id: u64, f: F) -> Result<R>
where
    F: FnOnce(&mut TerminalSession) -> Result<R>,
{
    let mut global = lock_terminals!();
    if let Some(session) = global.get_mut(&id) {
        f(session)
    } else {
        Err(KuroError::State(
            crate::ffi::error::StateError::NoTerminalSession,
        ))
    }
}

/// Get shared reference to the specified terminal session.
///
/// Returns `Err` if no session with the given ID exists.
pub fn with_session_readonly<F, R>(id: u64, f: F) -> Result<R>
where
    F: FnOnce(&TerminalSession) -> Result<R>,
{
    let global = lock_terminals!();
    if let Some(session) = global.get(&id) {
        f(session)
    } else {
        Err(KuroError::State(
            crate::ffi::error::StateError::NoTerminalSession,
        ))
    }
}

/// Remove and drop the specified terminal session, killing its PTY process.
pub fn shutdown_session(id: u64) -> Result<()> {
    let mut global = lock_terminals!();
    global.remove(&id);
    Ok(())
}

/// Mark a session as `Detached`, keeping its PTY alive without a buffer.
///
/// Returns `Err` if no session with the given ID exists.
pub fn detach_session(id: u64) -> Result<()> {
    let mut global = lock_terminals!();
    if let Some(session) = global.get_mut(&id) {
        session.set_detached();
        Ok(())
    } else {
        Err(KuroError::State(
            crate::ffi::error::StateError::NoTerminalSession,
        ))
    }
}

/// Mark a `Detached` session as `Bound`, reattaching it to a buffer.
///
/// Returns `Err(TerminalSessionExists)` if the session is already `Bound`
/// (preventing two buffers from owning the same session simultaneously).
/// Returns `Err(NoTerminalSession)` if no session with the given ID exists.
pub fn attach_session(id: u64) -> Result<()> {
    let mut global = lock_terminals!();
    if let Some(session) = global.get_mut(&id) {
        if !session.is_detached() {
            return Err(KuroError::State(
                crate::ffi::error::StateError::TerminalSessionExists,
            ));
        }
        session.set_bound();
        Ok(())
    } else {
        Err(KuroError::State(
            crate::ffi::error::StateError::NoTerminalSession,
        ))
    }
}

/// Collect metadata for all active sessions.
///
/// Returns `Vec<(session_id, command, is_detached, is_alive)>`.
/// The order of entries is unspecified (HashMap iteration order).
pub fn list_sessions() -> Vec<(u64, String, bool, bool)> {
    TERMINAL_SESSIONS
        .lock()
        .map(|guard| {
            guard
                .iter()
                .map(|(&id, s)| (id, s.command().to_string(), s.is_detached(), s.is_process_alive()))
                .collect()
        })
        .unwrap_or_default()
}
