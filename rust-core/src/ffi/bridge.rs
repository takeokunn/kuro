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
    match &*impl_guard {
        FfiImplementation::EmacsModule => FfiImplementation::EmacsModule,
        FfiImplementation::Raw => FfiImplementation::Raw,
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
    let result: std::result::Result<Vec<(usize, String)>, KuroError> =
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let mut global = super::abstraction::TERMINAL_SESSION
                .lock()
                .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;

            if let Some(ref mut session) = *global {
                session.poll_output()?;
                Ok(session.get_dirty_lines())
            } else {
                Ok(Vec::new())
            }
        }))
        .unwrap_or_else(|_| Err(KuroError::Ffi("panic in poll_updates".to_string())));

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
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        let (row, col) = if let Some(ref session) = *global {
            session.get_cursor()
        } else {
            (0, 0)
        };
        Ok::<(usize, usize), KuroError>((row, col))
    }));
    match result {
        Ok(Ok((row, col))) => {
            let row_val = (row as i64).into_lisp(env)?;
            let col_val = (col as i64).into_lisp(env)?;
            env.cons(row_val, col_val)
        }
        Ok(Err(e)) => {
            let msg = format!("kuro: error in get_cursor: {}", e);
            let _ = env.message(&msg);
            false.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_cursor");
            false.into_lisp(env)
        }
    }
}

/// Get cursor visibility (DECTCEM state: t if visible, nil if hidden)
#[defun]
fn kuro_core_get_cursor_visible<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        let visible = if let Some(ref session) = *global {
            session.get_cursor_visible()
        } else {
            true
        };
        Ok::<bool, KuroError>(visible)
    }));
    match result {
        Ok(Ok(visible)) => {
            if visible {
                env.intern("t")
            } else {
                env.intern("nil")
            }
        }
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_cursor_visible: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_cursor_visible");
            env.intern("nil")
        }
    }
}

/// Get application cursor keys mode (DECCKM state: t if active, nil if not)
#[defun]
fn kuro_core_get_app_cursor_keys<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        let app_cursor_keys = if let Some(ref session) = *global {
            session.core.dec_modes.app_cursor_keys
        } else {
            false
        };
        Ok::<bool, KuroError>(app_cursor_keys)
    }));
    match result {
        Ok(Ok(v)) => {
            if v {
                env.intern("t")
            } else {
                env.intern("nil")
            }
        }
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_app_cursor_keys: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_app_cursor_keys");
            env.intern("nil")
        }
    }
}

/// Get application keypad mode state (t if DECKPAM active, nil if DECKPNM)
#[defun]
fn kuro_core_get_app_keypad<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        let app_keypad = if let Some(ref session) = *global {
            session.core.dec_modes.app_keypad
        } else {
            false
        };
        Ok::<bool, KuroError>(app_keypad)
    }));
    match result {
        Ok(Ok(v)) => {
            if v {
                env.intern("t")
            } else {
                env.intern("nil")
            }
        }
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_app_keypad: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_app_keypad");
            env.intern("nil")
        }
    }
}

/// Get and atomically clear the pending window title (OSC 0/2)
///
/// Returns the new title string if one has been set since the last call,
/// or nil if no title update is pending.
#[defun]
fn kuro_core_get_and_clear_title<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref mut session) = *global {
            if session.core.title_dirty {
                session.core.title_dirty = false;
                Ok::<Option<String>, KuroError>(Some(session.core.title.clone()))
            } else {
                Ok(None)
            }
        } else {
            Ok(None)
        }
    }));
    match result {
        Ok(Ok(Some(title))) => title.into_lisp(env),
        Ok(Ok(None)) => false.into_lisp(env),
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_and_clear_title: {}", e));
            false.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_and_clear_title");
            false.into_lisp(env)
        }
    }
}

/// Get bracketed paste mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_bracketed_paste<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        let bracketed_paste = if let Some(ref session) = *global {
            session.core.dec_modes.bracketed_paste
        } else {
            false
        };
        Ok::<bool, KuroError>(bracketed_paste)
    }));
    match result {
        Ok(Ok(v)) => {
            if v {
                env.intern("t")
            } else {
                env.intern("nil")
            }
        }
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_bracketed_paste: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_bracketed_paste");
            env.intern("nil")
        }
    }
}

/// Get mouse tracking mode (0=disabled, 1000=normal, 1002=button-event, 1003=any-event)
#[defun]
fn kuro_core_get_mouse_mode<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        let mouse_mode = if let Some(ref session) = *global {
            session.core.dec_modes.mouse_mode as i64
        } else {
            0i64
        };
        Ok::<i64, KuroError>(mouse_mode)
    }));
    match result {
        Ok(Ok(v)) => v.into_lisp(env),
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_mouse_mode: {}", e));
            0i64.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_mouse_mode");
            0i64.into_lisp(env)
        }
    }
}

/// Get mouse SGR extended coordinates modifier state (t if active, nil if not)
#[defun]
fn kuro_core_get_mouse_sgr<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        let mouse_sgr = if let Some(ref session) = *global {
            session.core.dec_modes.mouse_sgr
        } else {
            false
        };
        Ok::<bool, KuroError>(mouse_sgr)
    }));
    match result {
        Ok(Ok(v)) => {
            if v {
                env.intern("t")
            } else {
                env.intern("nil")
            }
        }
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_mouse_sgr: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_mouse_sgr");
            env.intern("nil")
        }
    }
}

/// Get scrollback buffer lines
#[defun]
fn kuro_core_get_scrollback<'e>(env: &'e Env, max_lines: usize) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref session) = *global {
            Ok::<Vec<String>, KuroError>(session.get_scrollback(max_lines))
        } else {
            Ok(Vec::new())
        }
    }));
    match result {
        Ok(Ok(scrollback_lines)) => {
            let mut list = false.into_lisp(env)?;
            for line in scrollback_lines.into_iter().rev() {
                let line_val = line.into_lisp(env)?;
                list = env.cons(line_val, list)?;
            }
            Ok(list)
        }
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_scrollback: {}", e));
            false.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_scrollback");
            false.into_lisp(env)
        }
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

/// Scroll the viewport up by n lines (toward older scrollback content)
#[defun]
fn kuro_core_scroll_up<'e>(env: &'e Env, n: usize) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        with_session(|session| {
            session.viewport_scroll_up(n);
            Ok(true)
        })
    })
}

/// Scroll the viewport down by n lines (toward live content)
#[defun]
fn kuro_core_scroll_down<'e>(env: &'e Env, n: usize) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        with_session(|session| {
            session.viewport_scroll_down(n);
            Ok(true)
        })
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

/// Get the current viewport scroll offset (0 = live view, N = scrolled back N lines)
#[defun]
fn kuro_core_get_scroll_offset<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    catch_panic(env, || with_session(|session| Ok(session.scroll_offset())))
}

/// Poll for terminal updates and return dirty lines with face information
#[defun]
#[allow(clippy::type_complexity)]
fn kuro_core_poll_updates_with_faces<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result: std::result::Result<
        Vec<(usize, String, Vec<(usize, usize, u32, u32, u64)>)>,
        KuroError,
    > = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;

        if let Some(ref mut session) = *global {
            session.poll_output()?;
            Ok(session.get_dirty_lines_with_faces())
        } else {
            Ok(Vec::new())
        }
    }))
    .unwrap_or_else(|_| {
        Err(KuroError::Ffi(
            "panic in poll_updates_with_faces".to_string(),
        ))
    });

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

/// Retrieve a stored Kitty Graphics image as a base64-encoded PNG string.
///
/// Returns the base64-encoded PNG string if the image exists, or nil if not found.
/// The Elisp caller should decode: `(base64-decode-string data t)` to get unibyte PNG bytes
/// suitable for `(create-image bytes 'png t)`.
#[defun]
fn kuro_core_get_image<'e>(env: &'e Env, image_id: u32) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref session) = *global {
            Ok::<String, KuroError>(session.get_image_png_base64(image_id))
        } else {
            Ok(String::new())
        }
    }));
    match result {
        Ok(Ok(b64)) => {
            if b64.is_empty() {
                false.into_lisp(env)
            } else {
                b64.into_lisp(env)
            }
        }
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_image: {}", e));
            false.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_image");
            false.into_lisp(env)
        }
    }
}

/// Poll for pending Kitty Graphics image placement notifications.
///
/// Returns a list of image placement descriptors, each of the form:
///   (IMAGE-ID ROW COL CELL-WIDTH CELL-HEIGHT)
///
/// This is separate from `kuro-core-poll-updates-with-faces` for backward compatibility.
/// Call this after `kuro-core-poll-updates-with-faces` to check for new image placements.
#[defun]
fn kuro_core_poll_image_notifications<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let notifications = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref mut session) = *global {
            Ok::<Vec<_>, KuroError>(session.take_pending_image_notifications())
        } else {
            Ok(Vec::new())
        }
    }))
    .unwrap_or_else(|_| Ok(Vec::new()))
    .unwrap_or_default();

    // Build Elisp list: each item is (image-id row col cell-width cell-height)
    let mut list = false.into_lisp(env)?;
    for notif in notifications.into_iter().rev() {
        let id_val = (notif.image_id as i64).into_lisp(env)?;
        let row_val = (notif.row as i64).into_lisp(env)?;
        let col_val = (notif.col as i64).into_lisp(env)?;
        let cw_val = (notif.cell_width as i64).into_lisp(env)?;
        let ch_val = (notif.cell_height as i64).into_lisp(env)?;

        // Build proper list: (image-id row col cell-width cell-height)
        let nil = false.into_lisp(env)?;
        let item = env.cons(ch_val, nil)?;
        let item = env.cons(cw_val, item)?;
        let item = env.cons(col_val, item)?;
        let item = env.cons(row_val, item)?;
        let item = env.cons(id_val, item)?;
        list = env.cons(item, list)?;
    }
    Ok(list)
}

/// Get the current working directory from OSC 7 and atomically clear the dirty flag.
///
/// Returns the CWD path string if one has been set since the last call,
/// or nil if no CWD update is pending.
#[defun]
fn kuro_core_get_cwd<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref mut session) = *global {
            if session.core.osc_data.cwd_dirty {
                session.core.osc_data.cwd_dirty = false;
                Ok::<Option<String>, KuroError>(session.core.osc_data.cwd.clone())
            } else {
                Ok(None)
            }
        } else {
            Ok(None)
        }
    }));
    match result {
        Ok(Ok(Some(cwd))) => cwd.into_lisp(env),
        Ok(Ok(None)) => false.into_lisp(env),
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_cwd: {}", e));
            false.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_cwd");
            false.into_lisp(env)
        }
    }
}

/// Poll for pending clipboard actions from OSC 52 and clear them.
///
/// Returns a list of clipboard actions. Each action is either:
///   - ("write" . TEXT) for a write action
///   - ("query" . nil) for a query action
#[defun]
fn kuro_core_poll_clipboard_actions<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let actions = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref mut session) = *global {
            Ok::<Vec<_>, KuroError>(std::mem::take(&mut session.core.osc_data.clipboard_actions))
        } else {
            Ok(Vec::new())
        }
    }))
    .unwrap_or_else(|_| Ok(Vec::new()))
    .unwrap_or_default();

    let mut list = false.into_lisp(env)?;
    for action in actions.into_iter().rev() {
        let item = match action {
            crate::types::osc::ClipboardAction::Write(text) => {
                let tag = "write".into_lisp(env)?;
                let text_val = text.into_lisp(env)?;
                env.cons(tag, text_val)?
            }
            crate::types::osc::ClipboardAction::Query => {
                let tag = "query".into_lisp(env)?;
                let nil = false.into_lisp(env)?;
                env.cons(tag, nil)?
            }
        };
        list = env.cons(item, list)?;
    }
    Ok(list)
}

/// Poll for pending prompt mark events from OSC 133 and clear them.
///
/// Returns a list of prompt mark descriptors, each of the form:
///   (MARK-TYPE ROW COL)
/// where MARK-TYPE is one of: "prompt-start", "prompt-end", "command-start", "command-end"
#[defun]
fn kuro_core_poll_prompt_marks<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let marks = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref mut session) = *global {
            Ok::<Vec<_>, KuroError>(std::mem::take(&mut session.core.osc_data.prompt_marks))
        } else {
            Ok(Vec::new())
        }
    }))
    .unwrap_or_else(|_| Ok(Vec::new()))
    .unwrap_or_default();

    let mut list = false.into_lisp(env)?;
    for event in marks.into_iter().rev() {
        let mark_str = match event.mark {
            crate::types::osc::PromptMark::PromptStart => "prompt-start",
            crate::types::osc::PromptMark::PromptEnd => "prompt-end",
            crate::types::osc::PromptMark::CommandStart => "command-start",
            crate::types::osc::PromptMark::CommandEnd => "command-end",
        };
        let mark_val = mark_str.into_lisp(env)?;
        let row_val = (event.row as i64).into_lisp(env)?;
        let col_val = (event.col as i64).into_lisp(env)?;

        // Build proper list: (mark-type row col)
        let nil = false.into_lisp(env)?;
        let item = env.cons(col_val, nil)?;
        let item = env.cons(row_val, item)?;
        let item = env.cons(mark_val, item)?;
        list = env.cons(item, list)?;
    }
    Ok(list)
}

/// Get focus events mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_focus_events<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        let focus_events = if let Some(ref session) = *global {
            session.core.dec_modes.focus_events
        } else {
            false
        };
        Ok::<bool, KuroError>(focus_events)
    }));
    match result {
        Ok(Ok(v)) => {
            if v {
                env.intern("t")
            } else {
                env.intern("nil")
            }
        }
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_focus_events: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_focus_events");
            env.intern("nil")
        }
    }
}

/// Get synchronized output mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_sync_output<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        let sync_output = if let Some(ref session) = *global {
            session.core.dec_modes.synchronized_output
        } else {
            false
        };
        Ok::<bool, KuroError>(sync_output)
    }));
    match result {
        Ok(Ok(v)) => {
            if v {
                env.intern("t")
            } else {
                env.intern("nil")
            }
        }
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_sync_output: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_sync_output");
            env.intern("nil")
        }
    }
}

/// Get cursor shape as an integer (DECSCUSR value)
///
/// Returns:
///   0 = BlinkingBlock (default)
///   2 = SteadyBlock
///   3 = BlinkingUnderline
///   4 = SteadyUnderline
///   5 = BlinkingBar
///   6 = SteadyBar
#[defun]
fn kuro_core_get_cursor_shape<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        let shape_int: i64 = if let Some(ref session) = *global {
            match session.core.dec_modes.cursor_shape {
                crate::types::cursor::CursorShape::BlinkingBlock => 0,
                crate::types::cursor::CursorShape::SteadyBlock => 2,
                crate::types::cursor::CursorShape::BlinkingUnderline => 3,
                crate::types::cursor::CursorShape::SteadyUnderline => 4,
                crate::types::cursor::CursorShape::BlinkingBar => 5,
                crate::types::cursor::CursorShape::SteadyBar => 6,
            }
        } else {
            0
        };
        Ok::<i64, KuroError>(shape_int)
    }));
    match result {
        Ok(Ok(v)) => v.into_lisp(env),
        Ok(Err(e)) => {
            let _ = env.message(&format!("kuro: error in get_cursor_shape: {}", e));
            0i64.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_cursor_shape");
            0i64.into_lisp(env)
        }
    }
}

/// Get current Kitty keyboard protocol flags as an integer
///
/// Returns the current keyboard flags bitmask:
///   Bit 0 (1): Disambiguate escape codes
///   Bit 1 (2): Report event types (press/repeat/release)
///   Bit 2 (4): Report alternate keys
///   Bit 3 (8): Report all keys as escape codes
///   Bit 4 (16): Report associated text
#[defun]
fn kuro_core_get_keyboard_flags<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = super::abstraction::TERMINAL_SESSION
            .lock()
            .map_err(|e| KuroError::Ffi(format!("Mutex poisoned: {}", e)))?;
        if let Some(ref session) = *global {
            Ok::<i64, KuroError>(session.core.dec_modes.keyboard_flags as i64)
        } else {
            Ok(0i64)
        }
    }));
    match result {
        Ok(Ok(flags)) => flags.into_lisp(env),
        Ok(Err(e)) => {
            env.message(&format!("kuro: get-keyboard-flags error: {}", e))?;
            0i64.into_lisp(env)
        }
        Err(_) => {
            env.message("kuro: panic in get-keyboard-flags")?;
            0i64.into_lisp(env)
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
