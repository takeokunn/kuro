//! Cursor-related query functions: position, visibility, shape (DECSCUSR).

use std::panic::{AssertUnwindSafe, catch_unwind};

use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

use super::super::super::{lock_session, query_session};
use crate::error::KuroError;

/// Get cursor position as a (ROW . COL) cons pair
#[defun]
#[expect(
    clippy::cast_possible_wrap,
    reason = "row/col are terminal dimensions (≤ 65535); usize→i64 never wraps"
)]
fn kuro_core_get_cursor(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    // Returns a cons pair (row . col) — cannot use query_session<T: IntoLisp> since
    // cons pairs require two separate into_lisp calls and do not fit a single T.
    let result = catch_unwind(AssertUnwindSafe(|| {
        let (row, col) = {
            let global = lock_session!();
            global
                .get(&session_id)
                .map_or((0, 0), crate::ffi::abstraction::TerminalSession::get_cursor)
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
    query_session(env, session_id, 0i64, |s| {
        Ok(i64::from(s.get_cursor_shape()))
    })
}

/// Get all cursor state in a single Mutex acquisition: position, visibility, shape.
///
/// Returns a flat list `(row col visible shape)` where:
///   - row, col: cursor position (integers)
///   - visible: t or nil (DECTCEM state)
///   - shape: DECSCUSR integer (0-6)
///
/// On error or missing session, returns `(0 0 t 0)`.
#[defun]
#[expect(
    clippy::cast_possible_wrap,
    reason = "row/col are terminal dimensions (≤ 65535); usize→i64 never wraps"
)]
fn kuro_core_get_cursor_state(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let (row, col, visible, shape) = {
            let global = lock_session!();
            global
                .get(&session_id)
                .map_or((0usize, 0usize, true, 0i64), |s| {
                    let (r, c) = s.get_cursor();
                    (
                        r,
                        c,
                        s.get_cursor_visible(),
                        i64::from(s.get_cursor_shape()),
                    )
                })
        };
        Ok::<(usize, usize, bool, i64), KuroError>((row, col, visible, shape))
    }));
    match result {
        Ok(Ok((row, col, visible, shape))) => {
            let nil = env.intern("nil")?;
            let list = env.cons(shape.into_lisp(env)?, nil)?;
            let list = env.cons(visible.into_lisp(env)?, list)?;
            let list = env.cons((col as i64).into_lisp(env)?, list)?;
            env.cons((row as i64).into_lisp(env)?, list)
        }
        Ok(Err(e)) => {
            let msg = format!("kuro: error in get_cursor_state: {e}");
            let _ = env.message(&msg);
            false.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_cursor_state");
            false.into_lisp(env)
        }
    }
}
