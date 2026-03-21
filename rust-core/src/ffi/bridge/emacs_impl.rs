//! Primary FFI implementation using emacs-module-rs
//!
//! `EmacsModuleFFI` is the concrete type that implements `KuroFFI` using the
//! high-level bindings from the `emacs` crate.
//!
//! NOTE: This implementation uses session ID 0 for all operations.  It exists
//! for legacy compatibility and is no longer the primary entry point; all new
//! code goes through the `#[defun]` functions in the other bridge modules.

use std::ptr;
use std::result::Result;

use crate::error::KuroError;
use crate::ffi::abstraction::{
    emacs_env, emacs_value, init_session, shutdown_session, with_session, with_session_readonly,
    KuroFFI,
};

/// Legacy session ID used by the `KuroFFI` trait implementation.
const LEGACY_SESSION_ID: u64 = 0;

/// Primary FFI implementation using emacs-module-rs
///
/// This is the default implementation that leverages the high-level
/// bindings provided by emacs-module-rs.
pub struct EmacsModuleFFI;

impl KuroFFI for EmacsModuleFFI {
    fn init(_env: *mut emacs_env, command: &str, rows: i64, cols: i64) -> *mut emacs_value {
        #[expect(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "KuroFFI trait requires i64; Emacs window dimensions never exceed u16::MAX (max observed: ~500 rows × ~1000 cols)"
        )]
        let rows = rows as u16;
        #[expect(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "KuroFFI trait requires i64; Emacs window dimensions never exceed u16::MAX (max observed: ~500 rows × ~1000 cols)"
        )]
        let cols = cols as u16;

        init_session(command, rows, cols)
            .map_or(ptr::null_mut(), |_id| ptr::dangling_mut::<emacs_value>())
    }

    fn poll_updates(_env: *mut emacs_env, _max_updates: i64) -> *mut emacs_value {
        let result: Result<Vec<(usize, String)>, KuroError> =
            with_session(LEGACY_SESSION_ID, |session| {
                session.poll_output()?;
                Ok(session.get_dirty_lines())
            });

        match result {
            Ok(_) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }

    fn send_key(_env: *mut emacs_env, data: &[u8]) -> *mut emacs_value {
        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.send_input(data)?;
            Ok(())
        });

        match result {
            Ok(()) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }

    fn resize(_env: *mut emacs_env, rows: i64, cols: i64) -> *mut emacs_value {
        #[expect(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "KuroFFI trait requires i64; Emacs window dimensions never exceed u16::MAX (max observed: ~500 rows × ~1000 cols)"
        )]
        let rows = rows as u16;
        #[expect(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "KuroFFI trait requires i64; Emacs window dimensions never exceed u16::MAX (max observed: ~500 rows × ~1000 cols)"
        )]
        let cols = cols as u16;

        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.resize(rows, cols)?;
            Ok(())
        });

        match result {
            Ok(()) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }

    fn shutdown(_env: *mut emacs_env) -> *mut emacs_value {
        match shutdown_session(LEGACY_SESSION_ID) {
            Ok(()) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }

    #[expect(
        clippy::as_ptr_cast_mut,
        reason = "legacy C ABI stub: &str has no as_mut_ptr(); *mut emacs_value is an opaque pointer type"
    )]
    fn get_cursor(_env: *mut emacs_env) -> *mut emacs_value {
        let result = with_session_readonly(LEGACY_SESSION_ID, |session| {
            let (row, col) = session.get_cursor();
            Ok(format!("{row}:{col}"))
        });

        result.map_or_else(
            |_| "0:0".as_ptr() as *mut emacs_value,
            |s| s.as_ptr() as *mut emacs_value,
        )
    }

    #[expect(
        clippy::cast_sign_loss,
        clippy::cast_possible_truncation,
        reason = "max_lines ≤ 0 is handled above; positive values bounded by practical terminal scrollback limits"
    )]
    fn get_scrollback(_env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        let max_lines = if max_lines <= 0 {
            usize::MAX
        } else {
            max_lines as usize
        };

        let result = with_session_readonly(LEGACY_SESSION_ID, |session| {
            Ok(session.get_scrollback(max_lines))
        });

        match result {
            Ok(_) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }

    fn clear_scrollback(_env: *mut emacs_env) -> *mut emacs_value {
        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.clear_scrollback();
            Ok(())
        });

        match result {
            Ok(()) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }

    #[expect(
        clippy::cast_sign_loss,
        clippy::cast_possible_truncation,
        reason = "KuroFFI trait requires i64; caller passes non-negative scrollback limit"
    )]
    fn set_scrollback_max_lines(_env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.set_scrollback_max_lines(max_lines as usize);
            Ok(())
        });

        match result {
            Ok(()) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }
}
