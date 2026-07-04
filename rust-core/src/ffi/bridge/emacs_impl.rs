//! Primary FFI implementation using emacs-module-rs
//!
//! `EmacsModuleFFI` is the concrete type that implements `KuroFFI` using the
//! high-level bindings from the `emacs` crate.
//!
//! NOTE: This implementation uses session ID 0 for all operations.  It exists
//! for legacy compatibility and is no longer the primary entry point; all new
//! code goes through the `#[defun]` functions in the other bridge modules.

use std::ptr;

use crate::ffi::abstraction::{
    emacs_env, emacs_value, init_session, shutdown_session, with_session, with_session_readonly,
    KuroFFI,
};
use crate::ffi::boundary::{FfiScrollbackMaxLines, FfiScrollbackQueryLimit, FfiWindowSize};

/// Legacy session ID used by the `KuroFFI` trait implementation.
const LEGACY_SESSION_ID: u64 = 0;

#[inline]
fn legacy_usize_to_i64(value: usize) -> i64 {
    i64::try_from(value).expect("dirty line row index must fit i64")
}

macro_rules! legacy_session_bool_ptr {
    ($accessor:ident, |$session:ident| $body:block) => {{
        match $accessor(LEGACY_SESSION_ID, |$session| $body) {
            Ok(()) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }};
}

macro_rules! legacy_session_map_ptr {
    ($accessor:ident, $fallback:expr, |$session:ident| $body:block, |$value:ident| $ok:block) => {{
        match $accessor(LEGACY_SESSION_ID, |$session| $body) {
            Ok($value) => $ok,
            Err(_) => $fallback,
        }
    }};
    ($accessor:ident, $fallback:expr, |$session:ident| $body:expr, |$value:ident| $ok:block) => {{
        match $accessor(LEGACY_SESSION_ID, |$session| Ok($body)) {
            Ok($value) => $ok,
            Err(_) => $fallback,
        }
    }};
}

/// Primary FFI implementation using emacs-module-rs
///
/// This is the default implementation that leverages the high-level
/// bindings provided by emacs-module-rs.
pub struct EmacsModuleFFI;

impl KuroFFI for EmacsModuleFFI {
    fn init(_env: *mut emacs_env, command: &str, rows: i64, cols: i64) -> *mut emacs_value {
        let Some(size) = FfiWindowSize::parse(rows, cols) else {
            return ptr::null_mut();
        };

        init_session(command, &[], size.rows(), size.cols())
            .map_or(ptr::null_mut(), |_id| ptr::dangling_mut::<emacs_value>())
    }

    fn poll_updates(env: *mut emacs_env, _max_updates: i64) -> *mut emacs_value {
        legacy_session_map_ptr!(
            with_session,
            ptr::null_mut(),
            |session| {
                session.poll_output()?;
                Ok(session.get_dirty_lines())
            },
            |dirty_lines| {
                Self::build_emacs_list_from_rev(env, dirty_lines, |env, (line_no, text)| {
                    let line_no_val = Self::make_integer(env, legacy_usize_to_i64(line_no));
                    let text_val = Self::make_string(env, &text);
                    Self::cons(env, line_no_val, text_val)
                })
            }
        )
    }

    fn send_key(_env: *mut emacs_env, data: &[u8]) -> *mut emacs_value {
        legacy_session_bool_ptr!(with_session, |session| {
            session.send_input(data)?;
            Ok(())
        })
    }

    fn resize(_env: *mut emacs_env, rows: i64, cols: i64) -> *mut emacs_value {
        let Some(size) = FfiWindowSize::parse(rows, cols) else {
            return ptr::null_mut();
        };

        legacy_session_bool_ptr!(with_session, |session| {
            session.resize(size.rows(), size.cols())?;
            Ok(())
        })
    }

    fn shutdown(_env: *mut emacs_env) -> *mut emacs_value {
        match shutdown_session(LEGACY_SESSION_ID) {
            Ok(()) => ptr::dangling_mut::<emacs_value>(),
            Err(_) => ptr::null_mut(),
        }
    }

    fn get_cursor(_env: *mut emacs_env) -> *mut emacs_value {
        legacy_session_map_ptr!(
            with_session_readonly,
            Self::make_non_nil_value(),
            |session| {
                let (row, col) = session.get_cursor();
                Ok(format!("{row}:{col}"))
            },
            |_s| { Self::make_non_nil_value() }
        )
    }

    fn get_scrollback(_env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        let Some(limit) = FfiScrollbackQueryLimit::parse(max_lines) else {
            return ptr::null_mut();
        };

        legacy_session_map_ptr!(
            with_session_readonly,
            ptr::null_mut(),
            |session| session.get_scrollback(limit.get()),
            |_lines| { ptr::dangling_mut::<emacs_value>() }
        )
    }

    fn clear_scrollback(_env: *mut emacs_env) -> *mut emacs_value {
        legacy_session_bool_ptr!(with_session, |session| {
            session.clear_scrollback();
            Ok(())
        })
    }

    fn set_scrollback_max_lines(_env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        let Some(max_lines) = FfiScrollbackMaxLines::parse(max_lines) else {
            return ptr::null_mut();
        };

        legacy_session_bool_ptr!(with_session, |session| {
            session.set_scrollback_max_lines(max_lines.get());
            Ok(())
        })
    }
}

impl EmacsModuleFFI {
    const fn make_non_nil_value() -> *mut emacs_value {
        ptr::dangling_mut::<emacs_value>()
    }

    const fn make_nil(_env: *mut emacs_env) -> *mut emacs_value {
        ptr::null_mut()
    }

    const fn make_integer(_env: *mut emacs_env, _value: i64) -> *mut emacs_value {
        Self::make_non_nil_value()
    }

    const fn make_string(_env: *mut emacs_env, _s: &str) -> *mut emacs_value {
        Self::make_non_nil_value()
    }

    fn cons(
        _env: *mut emacs_env,
        _car: *mut emacs_value,
        _cdr: *mut emacs_value,
    ) -> *mut emacs_value {
        Self::make_non_nil_value()
    }

    fn build_emacs_list_from_rev<T, I, F>(
        env: *mut emacs_env,
        items: I,
        mut make_item: F,
    ) -> *mut emacs_value
    where
        I: IntoIterator<Item = T>,
        I::IntoIter: DoubleEndedIterator,
        F: FnMut(*mut emacs_env, T) -> *mut emacs_value,
    {
        let mut list = Self::make_nil(env);
        for item in items.into_iter().rev() {
            list = Self::cons(env, make_item(env, item), list);
        }
        list
    }
}
