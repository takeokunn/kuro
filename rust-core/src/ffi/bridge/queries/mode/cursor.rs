//! Cursor-related query functions: position, visibility, shape (DECSCUSR).

use std::panic::{catch_unwind, AssertUnwindSafe};

use emacs::defun;
use emacs::{Env, IntoLisp, Result as EmacsResult, Value};

use crate::error::KuroError;
use super::super::super::{lock_session, query_session};

/// Get cursor position as a (ROW . COL) cons pair
#[defun]
fn kuro_core_get_cursor(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    // Returns a cons pair (row . col) — cannot use query_session<T: IntoLisp> since
    // cons pairs require two separate into_lisp calls and do not fit a single T.
    let result = catch_unwind(AssertUnwindSafe(|| {
        let global = lock_session!();
        let (row, col) = global.get(&session_id).map_or((0, 0), crate::ffi::abstraction::TerminalSession::get_cursor);
        Ok::<(usize, usize), KuroError>((row, col))
    }));
    match result {
        Ok(Ok((row, col))) => {
            let row_val = (row as i64).into_lisp(env)?;
            let col_val = (col as i64).into_lisp(env)?;
            env.cons(row_val, col_val)
        }
        Ok(Err(e)) => {
            let msg = format!("kuro: error in get_cursor: {e}");
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
fn kuro_core_get_cursor_visible(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, true, |s| Ok(s.get_cursor_visible()))
}

/// Get cursor shape as an integer (DECSCUSR value)
///
/// Returns:
///   0 = `BlinkingBlock` (default)
///   2 = `SteadyBlock`
///   3 = `BlinkingUnderline`
///   4 = `SteadyUnderline`
///   5 = `BlinkingBar`
///   6 = `SteadyBar`
#[defun]
fn kuro_core_get_cursor_shape(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, 0i64, |s| Ok(i64::from(s.get_cursor_shape())))
}
