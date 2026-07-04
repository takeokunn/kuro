//! Cursor-related query functions: position, visibility, shape (DECSCUSR).

use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

use super::super::super::{
    build_emacs_list_from_values, define_session_data_query, define_session_data_query_or_false,
    define_session_query_default, query_session, usize_to_lisp_i64,
};

type CursorState = (usize, usize, bool, i64);

define_session_data_query_or_false!(
    /// Get cursor position as a (ROW . COL) cons pair
    kuro_core_get_cursor,
    "get_cursor",
    |session| session.get_cursor(),
    |kuro_env, (row, col)| {
        let row_val = usize_to_lisp_i64(row, "cursor row must fit i64").into_lisp(kuro_env)?;
        let col_val = usize_to_lisp_i64(col, "cursor column must fit i64").into_lisp(kuro_env)?;
        kuro_env.cons(row_val, col_val)
    }
);

define_session_query_default!(
    /// Get cursor visibility (DECTCEM state: t if visible, nil if hidden)
    kuro_core_get_cursor_visible,
    true,
    query_session,
    |s| s.get_cursor_visible()
);

define_session_query_default!(
    /// Get cursor shape as an integer (DECSCUSR value)
    ///
    /// Returns:
    ///   0 = `BlinkingBlock` (default)
    ///   2 = `SteadyBlock`
    ///   3 = `BlinkingUnderline`
    ///   4 = `SteadyUnderline`
    ///   5 = `BlinkingBar`
    ///   6 = `SteadyBar`
    kuro_core_get_cursor_shape,
    0i64,
    query_session,
    |s| i64::from(s.get_cursor_shape())
);

fn cursor_state_to_lisp(
    env: &Env,
    (row, col, visible, shape): CursorState,
) -> EmacsResult<Value<'_>> {
    build_emacs_list_from_values(
        env,
        [
            usize_to_lisp_i64(row, "cursor row must fit i64").into_lisp(env)?,
            usize_to_lisp_i64(col, "cursor column must fit i64").into_lisp(env)?,
            visible.into_lisp(env)?,
            shape.into_lisp(env)?,
        ],
    )
}

define_session_data_query!(
    /// Get all cursor state in a single Mutex acquisition: position, visibility, shape.
    ///
    /// Returns a flat list `(row col visible shape)` where:
    ///   - row, col: cursor position (integers)
    ///   - visible: t or nil (DECTCEM state)
    ///   - shape: DECSCUSR integer (0-6)
    ///
    /// On error or missing session, returns `(0 0 t 0)`.
    kuro_core_get_cursor_state,
    "get_cursor_state",
    |session| {
        let (row, col) = session.get_cursor();
        Ok((
            row,
            col,
            session.get_cursor_visible(),
            i64::from(session.get_cursor_shape()),
        ))
    },
    |env, state| cursor_state_to_lisp(env, state),
    |env| cursor_state_to_lisp(env, (0usize, 0usize, true, 0i64))
);
