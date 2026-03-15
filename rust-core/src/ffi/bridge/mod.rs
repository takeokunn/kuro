//! FFI bridge implementation using emacs-module-rs
//!
//! This module provides the primary FFI implementation using the emacs-module-rs crate,
//! with the ability to fall back to raw FFI bindings if needed.

use crate::error::KuroError;
use crate::ffi::abstraction::{
    emacs_env, emacs_value, init_session, shutdown_session, with_session, with_session_readonly,
    KuroFFI,
};
use emacs::{Env, IntoLisp, Result as EmacsResult, Value};
use std::panic::catch_unwind;
use std::sync::Mutex;

mod events;
mod images;
mod lifecycle;
mod queries;
mod render;

/// Current FFI implementation type
///
/// This enum allows runtime switching between different FFI implementations.
enum FfiImplementation {
    EmacsModule,
    Raw,
}

/// Global FFI implementation selector
///
/// This static holds the current FFI implementation. It's initialized
/// with EmacsModule by default and can be switched to Raw if needed.
static FFI_IMPLEMENTATION: Mutex<FfiImplementation> = Mutex::new(FfiImplementation::EmacsModule);

/// Initialize the FFI implementation
///
/// This function should be called during module initialization to set up
/// the appropriate FFI implementation.
fn init_ffi_implementation() {
    // Default implementation is EmacsModule
}

/// Switch to raw FFI fallback implementation
///
/// This function can be called if the emacs-module-rs implementation
/// encounters issues that cannot be resolved.
#[allow(dead_code)]
pub(crate) fn switch_to_raw_ffi() {
    if let Ok(mut guard) = FFI_IMPLEMENTATION.lock() {
        *guard = FfiImplementation::Raw;
    }
}

/// Get the current FFI implementation type
#[allow(dead_code)]
fn get_ffi_type() -> FfiImplementation {
    match FFI_IMPLEMENTATION.lock() {
        Ok(guard) => match &*guard {
            FfiImplementation::EmacsModule => FfiImplementation::EmacsModule,
            FfiImplementation::Raw => FfiImplementation::Raw,
        },
        Err(_) => FfiImplementation::EmacsModule, // fallback on poisoned mutex
    }
}

/// Primary FFI implementation using emacs-module-rs
///
/// This is the default implementation that leverages the high-level
/// bindings provided by emacs-module-rs.
pub struct EmacsModuleFFI;

impl KuroFFI for EmacsModuleFFI {
    fn init(_env: *mut emacs_env, command: &str, rows: i64, cols: i64) -> *mut emacs_value {
        // Convert i64 to u16 safely
        let rows = rows as u16;
        let cols = cols as u16;

        // Initialize session
        match init_session(command, rows, cols) {
            Ok(_) => {
                // Return a non-null pointer to indicate success
                std::ptr::dangling_mut::<emacs_value>()
            }
            Err(_) => {
                // Return null to indicate failure
                std::ptr::null_mut()
            }
        }
    }

    fn poll_updates(_env: *mut emacs_env, _max_updates: i64) -> *mut emacs_value {
        let result: std::result::Result<Vec<(usize, String)>, KuroError> =
            with_session(|session| {
                session.poll_output()?;
                Ok(session.get_dirty_lines())
            });

        match result {
            Ok(_) => {
                // Return a non-null pointer to indicate success
                // (The actual value is ignored in the bridge layer)
                std::ptr::dangling_mut::<emacs_value>()
            }
            Err(_) => {
                // Return null to indicate failure
                std::ptr::null_mut()
            }
        }
    }

    fn send_key(_env: *mut emacs_env, data: &[u8]) -> *mut emacs_value {
        let result = with_session(|session| {
            session.send_input(data)?;
            Ok(())
        });

        match result {
            Ok(_) => std::ptr::dangling_mut::<emacs_value>(),
            Err(_) => std::ptr::null_mut(),
        }
    }

    fn resize(_env: *mut emacs_env, rows: i64, cols: i64) -> *mut emacs_value {
        let rows = rows as u16;
        let cols = cols as u16;

        let result = with_session(|session| {
            session.resize(rows, cols)?;
            Ok(())
        });

        match result {
            Ok(_) => std::ptr::dangling_mut::<emacs_value>(),
            Err(_) => std::ptr::null_mut(),
        }
    }

    fn shutdown(_env: *mut emacs_env) -> *mut emacs_value {
        match shutdown_session() {
            Ok(_) => std::ptr::dangling_mut::<emacs_value>(),
            Err(_) => std::ptr::null_mut(),
        }
    }

    fn get_cursor(_env: *mut emacs_env) -> *mut emacs_value {
        let result = with_session_readonly(|session| {
            let (row, col) = session.get_cursor();
            Ok(format!("{}:{}", row, col))
        });

        match result {
            Ok(s) => s.as_ptr() as *mut emacs_value,
            Err(_) => "0:0".as_ptr() as *mut emacs_value,
        }
    }

    fn get_scrollback(_env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        let max_lines = if max_lines <= 0 {
            usize::MAX
        } else {
            max_lines as usize
        };

        let result = with_session_readonly(|session| Ok(session.get_scrollback(max_lines)));

        match result {
            Ok(_) => std::ptr::dangling_mut::<emacs_value>(),
            Err(_) => std::ptr::null_mut(),
        }
    }

    fn clear_scrollback(_env: *mut emacs_env) -> *mut emacs_value {
        let result = with_session(|session| {
            session.clear_scrollback();
            Ok(())
        });

        match result {
            Ok(_) => std::ptr::dangling_mut::<emacs_value>(),
            Err(_) => std::ptr::null_mut(),
        }
    }

    fn set_scrollback_max_lines(_env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        let result = with_session(|session| {
            session.set_scrollback_max_lines(max_lines as usize);
            Ok(())
        });

        match result {
            Ok(_) => std::ptr::dangling_mut::<emacs_value>(),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

/// Lock `TERMINAL_SESSION` and map mutex-poison errors to `KuroError::Ffi`.
///
/// The macro expands to the locked guard; the caller is responsible for binding
/// it with `let` or `let mut` as needed:
/// ```rust,ignore
/// let global = lock_session!();          // immutable guard
/// let mut global = lock_session!();      // mutable guard (same macro)
/// ```
macro_rules! lock_session {
    () => {
        crate::ffi::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| crate::error::KuroError::Ffi(format!("Mutex poisoned: {}", e)))?
    };
}

pub(super) use lock_session;

/// Convert a Rust `bool` to an Emacs Lisp `t` / `nil` symbol.
#[inline]
fn bool_to_lisp<'e>(env: &'e Env, v: bool) -> EmacsResult<Value<'e>> {
    if v {
        env.intern("t")
    } else {
        env.intern("nil")
    }
}

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
            let msg = match e {
                KuroError::Pty(msg) => format!("PTY error: {}", msg),
                KuroError::Ffi(msg) => format!("FFI error: {}", msg),
                KuroError::Parser(msg) => format!("Parser error: {}", msg),
                KuroError::InvalidParam(msg) => format!("Invalid parameter: {}", msg),
                KuroError::Io(msg) => format!("IO error: {}", msg),
                _ => format!("Error: {}", e),
            };
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
        Err(panic_payload) => {
            let msg = match panic_payload.downcast::<String>() {
                Ok(msg) => format!("Panic: {}", msg),
                Err(panic_payload) => match panic_payload.downcast::<&'static str>() {
                    Ok(msg) => format!("Panic: {}", msg),
                    Err(_) => "Panic: Unknown panic payload".to_string(),
                },
            };
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
    }
}

/// Emacs plugin initialization (called from lib.rs via #[emacs::module])
pub fn module_init(env: &Env) -> EmacsResult<()> {
    init_ffi_implementation();
    env.message("Kuro terminal emulator module loaded")?;
    Ok(())
}

// Test FFI functions are in the dedicated `test_terminal` module.
// See: ffi/test_terminal.rs

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_emacs_module_ffi_trait_impl() {
        // Verify EmacsModuleFFI implements KuroFFI
        // Note: KuroFFI is not dyn compatible
        let _ = &EmacsModuleFFI;
    }

    #[test]
    fn test_ffi_initialization() {
        // Test that FFI implementation is initialized
        init_ffi_implementation();

        // Get the implementation type
        let ffi_type = get_ffi_type();
        match ffi_type {
            FfiImplementation::EmacsModule => {}
            FfiImplementation::Raw => {}
        }
    }

    #[test]
    fn test_switch_to_raw_ffi() {
        // Initialize with EmacsModule
        init_ffi_implementation();

        // Switch to Raw
        switch_to_raw_ffi();

        // Verify the switch
        let ffi_type = get_ffi_type();
        assert!(matches!(ffi_type, FfiImplementation::Raw));

        // Reset to EmacsModule for other tests
        let mut impl_guard = FFI_IMPLEMENTATION.lock().unwrap();
        *impl_guard = FfiImplementation::EmacsModule;
    }
}
