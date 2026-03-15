//! Session lifecycle: init / send_key / resize / shutdown

use super::{catch_panic, init_ffi_implementation, lock_session, EmacsModuleFFI};
use crate::error::KuroError;
use crate::ffi::abstraction::{with_session, KuroFFI};
use emacs::defun;
use emacs::{Env, Result as EmacsResult, Value};

/// Initialize Kuro with the given shell command and terminal dimensions.
///
/// ROWS and COLS must match the actual Emacs window dimensions so that the PTY
/// is created with the correct size from the start.  Spawning the shell with the
/// wrong size and then immediately resizing causes a SIGWINCH race: full-screen
/// programs (vim, htop, …) that start before the resize is processed will render
/// using the stale 24×80 geometry and never re-draw correctly.
#[defun]
fn kuro_core_init<'e>(
    env: &'e Env,
    command: String,
    rows: u16,
    cols: u16,
) -> EmacsResult<Value<'e>> {
    init_ffi_implementation();

    catch_panic(env, || {
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

/// Resize the terminal
#[defun]
fn kuro_core_resize<'e>(env: &'e Env, rows: u16, cols: u16) -> EmacsResult<Value<'e>> {
    catch_panic(env, || {
        let mut global = lock_session!();
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
        let mut global = lock_session!();
        *global = None;
        Ok(true)
    })
}
