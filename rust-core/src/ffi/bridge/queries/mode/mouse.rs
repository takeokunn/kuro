//! Mouse mode query functions: mouse tracking mode, SGR extended coordinates, pixel coordinates.

use emacs::defun;
use emacs::{Env, Result as EmacsResult, Value};

use super::super::super::query_session;

/// Get mouse tracking mode (0=disabled, 1000=normal, 1002=button-event, 1003=any-event)
#[defun]
fn kuro_core_get_mouse_mode(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, 0i64, |s| Ok(i64::from(s.get_mouse_mode())))
}

/// Get mouse SGR extended coordinates modifier state (t if active, nil if not)
#[defun]
fn kuro_core_get_mouse_sgr(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, false, |s| Ok(s.get_mouse_sgr()))
}

/// Get mouse SGR pixel coordinate mode state (?1016: t if active, nil if not)
#[defun]
fn kuro_core_get_mouse_pixel(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, false, |s| Ok(s.get_mouse_pixel()))
}
