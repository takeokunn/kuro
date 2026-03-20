//! Protocol mode query functions: bracketed paste, focus events, synchronized output.

use emacs::defun;
use emacs::{Env, Result as EmacsResult, Value};

use super::super::super::query_session;

/// Get bracketed paste mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_bracketed_paste(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, false, |s| Ok(s.get_bracketed_paste()))
}

/// Get focus events mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_focus_events(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, false, |s| Ok(s.get_focus_events()))
}

/// Get synchronized output mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_sync_output(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, false, |s| Ok(s.get_synchronized_output()))
}
