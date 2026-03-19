//! Primary FFI implementation using emacs-module-rs
//!
//! `EmacsModuleFFI` is the concrete type that implements `KuroFFI` using the
//! high-level bindings from the `emacs` crate.

use std::ptr;
use std::result::Result;

use crate::error::KuroError;
use crate::ffi::abstraction::{
    emacs_env, emacs_value, init_session, shutdown_session, with_session, with_session_readonly,
    KuroFFI,
};

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
                ptr::dangling_mut::<emacs_value>()
            }
            Err(_) => {
                // Return null to indicate failure
                ptr::null_mut()
            }
        }
    }

    fn poll_updates(_env: *mut emacs_env, _max_updates: i64) -> *mut emacs_value {
        let result: Result<Vec<(usize, String)>, KuroError> =
            with_session(|session| {
                session.poll_output()?;
                Ok(session.get_dirty_lines())
            });

        match result {
            Ok(_) => {
                // Return a non-null pointer to indicate success
                // (The actual value is ignored in the bridge layer)
                ptr::dangling_mut::<emacs_value>()
            }
            Err(_) => {
                // Return null to indicate failure
                ptr::null_mut()
            }
        }
    }

    fn send_key(_env: *mut emacs_env, data: &[u8]) -> *mut emacs_value {
        let result = with_session(|session| {
            session.send_input(data)?;
            Ok(())
        });

        match result {
            Ok(_) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
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
            Ok(_) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }

    fn shutdown(_env: *mut emacs_env) -> *mut emacs_value {
        match shutdown_session() {
            Ok(_) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
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
            Ok(_) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }

    fn clear_scrollback(_env: *mut emacs_env) -> *mut emacs_value {
        let result = with_session(|session| {
            session.clear_scrollback();
            Ok(())
        });

        match result {
            Ok(_) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }

    fn set_scrollback_max_lines(_env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        let result = with_session(|session| {
            session.set_scrollback_max_lines(max_lines as usize);
            Ok(())
        });

        match result {
            Ok(_) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }
}
