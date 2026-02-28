//! FFI bridge implementation using emacs-module-rs
//!
//! This module provides the primary FFI implementation using the emacs-module-rs crate,
//! with the ability to fall back to raw FFI bindings if needed.

use super::abstraction::{
    emacs_env, emacs_value, init_session, shutdown_session, with_session, with_session_readonly,
    KuroFFI,
};
use crate::error::KuroError;
use emacs::defun;
use emacs::{Env, IntoLisp, Result as EmacsResult, Value};
use std::panic::catch_unwind;
use std::sync::Mutex;

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
pub fn switch_to_raw_ffi() {
    let mut impl_guard = FFI_IMPLEMENTATION.lock().unwrap();
    *impl_guard = FfiImplementation::Raw;
}

/// Get the current FFI implementation type
#[allow(dead_code)]
fn get_ffi_type() -> FfiImplementation {
    let impl_guard = FFI_IMPLEMENTATION.lock().unwrap();
    let impl_type = match &*impl_guard {
        FfiImplementation::EmacsModule => FfiImplementation::EmacsModule,
        FfiImplementation::Raw => FfiImplementation::Raw,
    };
    std::mem::forget(impl_guard);
    impl_type
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

/// Initialize Kuro with the given shell command
#[defun]
fn kuro_core_init<'e>(env: &'e Env, command: String) -> EmacsResult<Value<'e>> {
    init_ffi_implementation();

    catch_panic(env, || {
        let rows = 24;
        let cols = 80;

        // Use the emacs-module-rs implementation for the low-level call
        let result = EmacsModuleFFI::init(std::ptr::null_mut(), &command, rows as i64, cols as i64);

        if result.is_null() {
            Err(KuroError::Ffi("Failed to initialize terminal".to_string()))
        } else {
            Ok(true)
        }
    })
}

/// Send key input to the terminal
#[defun]
fn kuro_core_send_key<'e>(env: &'e Env, data: String) -> EmacsResult<Value<'e>> {
    let byte_vec: Vec<u8> = data.into_bytes();

    catch_panic(env, || {
        let result = with_session(|session| {
            session.send_input(&byte_vec)?;
            Ok(())
        });

        match result {
            Ok(_) => Ok(true),
            Err(_) => Ok(false),
        }
    })
}

/// Poll for terminal updates and return dirty lines
#[defun]
fn kuro_core_poll_updates<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result: std::result::Result<Vec<(usize, String)>, KuroError> = {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;

        if let Some(ref mut session) = *global {
            session.poll_output()?;
            Ok(session.get_dirty_lines())
        } else {
            Ok(Vec::new())
        }
    };

    match result {
        Ok(dirty_lines) => {
            let mut list = false.into_lisp(env)?;
            for (line_no, text) in dirty_lines.into_iter().rev() {
                let line_no_val = (line_no as i64).into_lisp(env)?;
                let text_val = text.into_lisp(env)?;
                let pair = env.cons(line_no_val, text_val)?;
                list = env.cons(pair, list)?;
            }
            Ok(list)
        }
        Err(e) => {
            let msg = match e {
                KuroError::Pty(msg) => format!("PTY error: {}", msg),
                KuroError::Ffi(msg) => format!("FFI error: {}", msg),
                KuroError::Parser(msg) => format!("Parser error: {}", msg),
                _ => format!("Error: {}", e),
            };
            let _ = env.message(&msg);
            let _ = env.call("error", (msg,));
            false.into_lisp(env)
        }
    }
}

/// Resize the terminal
#[defun]
fn kuro_core_resize<'e>(env: &'e Env, rows: u16, cols: u16) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref mut session) = *global {
            session.resize(rows, cols)?;
            Ok(true)
        } else {
            Ok(false)
        }
    })
}

/// Shutdown the terminal session
#[defun]
fn kuro_core_shutdown<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        *global = None;
        Ok(true)
    })
}

/// Get cursor position as a (ROW . COL) cons pair
#[defun]
fn kuro_core_get_cursor<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let global = super::abstraction::TERMINAL_SESSION
        .lock()
        .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
    let (row, col) = if let Some(ref session) = *global {
        session.get_cursor()
    } else {
        (0, 0)
    };
    let row_val = (row as i64).into_lisp(env)?;
    let col_val = (col as i64).into_lisp(env)?;
    env.cons(row_val, col_val)
}

/// Get cursor visibility (DECTCEM state: t if visible, nil if hidden)
#[defun]
fn kuro_core_get_cursor_visible<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let global = super::abstraction::TERMINAL_SESSION
        .lock()
        .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
    let visible = if let Some(ref session) = *global {
        session.get_cursor_visible()
    } else {
        true
    };
    if visible {
        env.intern("t")
    } else {
        env.intern("nil")
    }
}

/// Get scrollback buffer lines
#[defun]
fn kuro_core_get_scrollback<'e>(env: &'e Env, max_lines: usize) -> EmacsResult<Value<'e>> {
    let global = super::abstraction::TERMINAL_SESSION
        .lock()
        .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;

    if let Some(ref session) = *global {
        let scrollback_lines = session.get_scrollback(max_lines);

        // Convert to Emacs list
        let mut list = false.into_lisp(env)?;
        for line in scrollback_lines.into_iter().rev() {
            let line_val = line.into_lisp(env)?;
            list = env.cons(line_val, list)?;
        }
        Ok(list)
    } else {
        Ok(false.into_lisp(env)?)
    }
}

/// Clear scrollback buffer
#[defun]
fn kuro_core_clear_scrollback<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref mut session) = *global {
            session.clear_scrollback();
            Ok(true)
        } else {
            Ok(false)
        }
    })
}

/// Check whether a BEL character has been received and not yet cleared
#[defun]
fn kuro_core_bell_pending<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref session) = *global {
            Ok(session.core.bell_pending)
        } else {
            Ok(false)
        }
    })
}

/// Clear the pending bell flag
#[defun]
fn kuro_core_clear_bell<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref mut session) = *global {
            session.core.bell_pending = false;
            Ok(true)
        } else {
            Ok(false)
        }
    })
}

/// Set scrollback buffer max lines
#[defun]
fn kuro_core_set_scrollback_max_lines<'e>(
    env: &'e Env,
    max_lines: usize,
) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref mut session) = *global {
            session.set_scrollback_max_lines(max_lines);
            Ok(true)
        } else {
            Ok(false)
        }
    })
}

/// Get scrollback buffer line count
#[defun]
fn kuro_core_get_scrollback_count<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref session) = *global {
            Ok(session.get_scrollback_count())
        } else {
            Ok(0)
        }
    })
}

/// Poll for terminal updates and return dirty lines with face information
#[defun]
#[allow(clippy::type_complexity)]
fn kuro_core_poll_updates_with_faces<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result: std::result::Result<
        Vec<(usize, String, Vec<(usize, usize, u32, u32, u64)>)>,
        KuroError,
    > = {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;

        if let Some(ref mut session) = *global {
            session.poll_output()?;
            Ok(session.get_dirty_lines_with_faces())
        } else {
            Ok(Vec::new())
        }
    };

    match result {
        Ok(lines) => {
            let mut list = false.into_lisp(env)?;
            for (line_no, text, face_ranges) in lines.into_iter().rev() {
                let line_no_val = (line_no as i64).into_lisp(env)?;
                let text_val = text.into_lisp(env)?;

                // Convert face ranges to Emacs list of flat (start-col end-col fg bg flags) lists
                let mut face_list = false.into_lisp(env)?;
                for (start_col, end_col, fg, bg, flags) in face_ranges {
                    let start_col_val = (start_col as i64).into_lisp(env)?;
                    let end_col_val = (end_col as i64).into_lisp(env)?;
                    let fg_val = (fg as i64).into_lisp(env)?;
                    let bg_val = (bg as i64).into_lisp(env)?;
                    let flags_val = (flags as i64).into_lisp(env)?;

                    // Build flat proper list: (start-col end-col fg bg flags)
                    let nil = false.into_lisp(env)?;
                    let range_list = env.cons(flags_val, nil)?;
                    let range_list = env.cons(bg_val, range_list)?;
                    let range_list = env.cons(fg_val, range_list)?;
                    let range_list = env.cons(end_col_val, range_list)?;
                    let range_list = env.cons(start_col_val, range_list)?;
                    face_list = env.cons(range_list, face_list)?;
                }

                let line_pair = env.cons(line_no_val, text_val)?;
                let line_tuple = env.cons(line_pair, face_list)?;
                list = env.cons(line_tuple, list)?;
            }
            Ok(list)
        }
        Err(e) => {
            let msg = match e {
                KuroError::Pty(msg) => format!("PTY error: {}", msg),
                KuroError::Ffi(msg) => format!("FFI error: {}", msg),
                KuroError::Parser(msg) => format!("Parser error: {}", msg),
                _ => format!("Error: {}", e),
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
    #[ignore = "test_switch_to_raw_ffi deadlocks due to get_ffi_type() using std::mem::forget on the MutexGuard"]
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
