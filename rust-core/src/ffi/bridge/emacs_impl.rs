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

/// Legacy session ID used by the `KuroFFI` trait implementation.
const LEGACY_SESSION_ID: u64 = 0;

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

        init_session(command, &[], rows, cols)
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
                    let line_no_val = Self::make_integer(env, line_no as i64);
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

        legacy_session_bool_ptr!(with_session, |session| {
            session.resize(rows, cols)?;
            Ok(())
        })
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
        legacy_session_map_ptr!(
            with_session_readonly,
            "0:0".as_ptr() as *mut emacs_value,
            |session| {
                let (row, col) = session.get_cursor();
                Ok(format!("{row}:{col}"))
            },
            |s| { s.as_ptr() as *mut emacs_value }
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

        legacy_session_map_ptr!(
            with_session_readonly,
            ptr::null_mut(),
            |session| session.get_scrollback(max_lines),
            |_lines| { ptr::dangling_mut::<emacs_value>() }
        )
    }

    fn clear_scrollback(_env: *mut emacs_env) -> *mut emacs_value {
        legacy_session_bool_ptr!(with_session, |session| {
            session.clear_scrollback();
            Ok(())
        })
    }

    #[expect(
        clippy::cast_sign_loss,
        clippy::cast_possible_truncation,
        reason = "KuroFFI trait requires i64; caller passes non-negative scrollback limit"
    )]
    fn set_scrollback_max_lines(_env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        legacy_session_bool_ptr!(with_session, |session| {
            session.set_scrollback_max_lines(max_lines as usize);
            Ok(())
        })
    }
}

impl EmacsModuleFFI {
    const fn make_nil(_env: *mut emacs_env) -> *mut emacs_value {
        ptr::null_mut()
    }

    const fn make_integer(_env: *mut emacs_env, value: i64) -> *mut emacs_value {
        (value as usize + 0x1000) as *mut emacs_value
    }

    #[expect(
        clippy::as_ptr_cast_mut,
        reason = "legacy C ABI stub: &str has no as_mut_ptr(); *mut emacs_value is an opaque pointer type"
    )]
    const fn make_string(_env: *mut emacs_env, s: &str) -> *mut emacs_value {
        s.as_ptr() as *mut emacs_value
    }

    #[expect(
        clippy::similar_names,
        reason = "car_val/cdr_val are standard Lisp car/cdr terminology; renaming would obscure the intent"
    )]
    fn cons(
        _env: *mut emacs_env,
        car: *mut emacs_value,
        cdr: *mut emacs_value,
    ) -> *mut emacs_value {
        let car_val = car as usize;
        let cdr_val = cdr as usize;
        ((car_val << 32) | cdr_val) as *mut emacs_value
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
