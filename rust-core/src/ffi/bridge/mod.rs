//! FFI bridge implementation using emacs-module-rs
//!
//! This module provides the primary FFI implementation using the emacs-module-rs crate,
//! with the ability to fall back to raw FFI bindings if needed.

use std::panic::catch_unwind;

use emacs::{Env, IntoLisp, Result as EmacsResult, Value};

use crate::error::KuroError;

mod emacs_impl;
mod events;
mod images;
mod lifecycle;
mod queries;
mod render;

pub use emacs_impl::EmacsModuleFFI;

/// Lock `TERMINAL_SESSIONS` and map mutex-poison errors to `KuroError::State`.
///
/// The macro expands to the locked guard (a `MutexGuard<HashMap<u64, TerminalSession>>`).
/// The caller then indexes into it with `global.get(&id)` or `global.get_mut(&id)`.
///
/// ```rust,ignore
/// let global = lock_session!();                      // immutable guard
/// let mut global = lock_session!();                  // mutable guard
/// if let Some(session) = global.get_mut(&session_id) { ... }
/// ```
macro_rules! lock_session {
    () => {
        crate::ffi::abstraction::TERMINAL_SESSIONS
            .lock()
            .map_err(|_e| crate::error::KuroError::State(crate::ffi::error::StateError::NoTerminalSession))?
    };
}

pub(super) use lock_session;

/// Catch Rust panics and convert to Emacs errors
fn catch_panic<'e, R, F>(env: &'e Env, f: F) -> EmacsResult<Value<'e>>
where
    R: IntoLisp<'e> + 'static,
    F: std::panic::UnwindSafe + FnOnce() -> std::result::Result<R, KuroError>,
{
    let result = catch_unwind(f);

    match result {
        Ok(Ok(value)) => value.into_lisp(env),
        Ok(Err(e)) => {
            let msg = format!("Kuro error: {e}");
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
        Err(panic_payload) => {
            let msg = panic_payload.downcast::<String>().map_or_else(
                |p| p.downcast::<&'static str>().map_or_else(
                    |_| "Panic: Unknown panic payload".to_string(),
                    |msg| format!("Panic: {msg}"),
                ),
                |msg| format!("Panic: {msg}"),
            );
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
    }
}

/// Helper for FFI functions that read a single value from a specific session.
///
/// Calls `f(session)` when the session exists; returns `default` otherwise.
/// Wraps in `catch_panic` automatically.
pub(crate) fn query_session<'e, T, F>(
    env: &'e Env,
    session_id: u64,
    default: T,
    f: F,
) -> EmacsResult<Value<'e>>
where
    T: IntoLisp<'e> + std::panic::UnwindSafe + 'static,
    F: FnOnce(&crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>
        + std::panic::UnwindSafe,
{
    catch_panic(env, || {
        let global = lock_session!();
        global.get(&session_id).map_or(Ok(default), f)
    })
}

/// Helper for FFI functions that mutate a specific session.
///
/// Calls `f(session)` when the session exists; returns `default` otherwise.
/// Wraps in `catch_panic` automatically.
pub(crate) fn query_session_mut<'e, T, F>(
    env: &'e Env,
    session_id: u64,
    default: T,
    f: F,
) -> EmacsResult<Value<'e>>
where
    T: IntoLisp<'e> + std::panic::UnwindSafe + 'static,
    F: FnOnce(&mut crate::ffi::abstraction::TerminalSession) -> Result<T, KuroError>
        + std::panic::UnwindSafe,
{
    catch_panic(env, || {
        let mut global = lock_session!();
        global.get_mut(&session_id).map_or(Ok(default), f)
    })
}

/// Helper for FFI functions returning `Option<T>`.
///
/// Unlike [`query_session_mut`], the closure returns `Result<Option<T>>`.
/// `Some(v)` maps to the corresponding Lisp value; `None` and "no session"
/// both become `false`.
///
/// `AssertUnwindSafe` is applied unconditionally because the closure captures
/// `&mut TerminalSession`.
#[inline]
pub(crate) fn query_session_opt<'e, T, F>(
    env: &'e Env,
    session_id: u64,
    f: F,
) -> EmacsResult<Value<'e>>
where
    T: IntoLisp<'e>,
    F: FnOnce(&mut crate::ffi::abstraction::TerminalSession) -> Result<Option<T>, KuroError>
        + std::panic::UnwindSafe,
{
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = lock_session!();
        global.get_mut(&session_id).map_or(Ok(None), f)
    }));
    match result {
        Ok(Ok(Some(v))) => v.into_lisp(env),
        Ok(Ok(None)) => false.into_lisp(env),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: {e}"));
            false.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in query_session_opt");
            false.into_lisp(env)
        }
    }
}

/// Emacs plugin initialization (called from lib.rs via #[`emacs::module`])
///
/// # Errors
/// Returns `Err` if the Emacs environment rejects the module message.
pub fn module_init(env: &Env) -> EmacsResult<()> {
    env.message("Kuro terminal emulator module loaded")?;
    Ok(())
}

// Test FFI functions are in the dedicated `test_terminal` module.
// See: ffi/test_terminal.rs

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_emacs_module_ffi_is_zero_sized() {
        assert_eq!(std::mem::size_of::<EmacsModuleFFI>(), 0);
    }
}
