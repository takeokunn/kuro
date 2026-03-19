//! Global terminal session state and accessor functions
//!
//! This module owns the global `TERMINAL_SESSION` mutex and provides
//! the public API for initializing, accessing, and tearing down the
//! single terminal session that backs the Emacs module.

use super::session::TerminalSession;
use crate::{error::KuroError, Result};
use std::sync::Mutex;

/// Global terminal session (wrapped in Mutex for thread safety)
///
/// This is shared across all FFI implementations to ensure a single
/// terminal session per Emacs module instance.
pub static TERMINAL_SESSION: Mutex<Option<TerminalSession>> = Mutex::new(None);

/// Lock `TERMINAL_SESSION` and map mutex-poison errors to `KuroError::State`.
///
/// Binding mutability is determined by the caller's `let`/`let mut` binding.
macro_rules! lock_terminal {
    () => {
        TERMINAL_SESSION
            .lock()
            .map_err(|_e| KuroError::State(crate::ffi::error::StateError::NoTerminalSession))?
    };
}

/// Initialize the global terminal session
///
/// # Safety
/// This function modifies a global static mutex and must be called safely.
pub fn init_session(command: &str, rows: u16, cols: u16) -> Result<()> {
    let session = TerminalSession::new(command, rows, cols)?;
    let mut global = lock_terminal!();
    *global = Some(session);
    Ok(())
}

/// Get mutable reference to the global terminal session.
///
/// Returns `Err` if no session is initialized.
pub fn with_session<F, R>(f: F) -> Result<R>
where
    F: FnOnce(&mut TerminalSession) -> Result<R>,
{
    let mut global = lock_terminal!();
    if let Some(ref mut session) = *global {
        f(session)
    } else {
        Err(KuroError::State(
            crate::ffi::error::StateError::NoTerminalSession,
        ))
    }
}

/// Get shared reference to the global terminal session.
///
/// Returns `Err` if no session is initialized.
pub fn with_session_readonly<F, R>(f: F) -> Result<R>
where
    F: FnOnce(&TerminalSession) -> Result<R>,
{
    let global = lock_terminal!();
    if let Some(ref session) = *global {
        f(session)
    } else {
        Err(KuroError::State(
            crate::ffi::error::StateError::NoTerminalSession,
        ))
    }
}

/// Shutdown the global terminal session and release all resources.
pub fn shutdown_session() -> Result<()> {
    let mut global = lock_terminal!();
    *global = None;
    Ok(())
}
