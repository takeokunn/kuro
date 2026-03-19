//! Protocol mode query functions: bracketed paste, focus events, synchronized output.

use emacs::defun;
use emacs::{Env, Result as EmacsResult, Value};

use super::super::super::query_session;

/// Get bracketed paste mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_bracketed_paste<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    query_session(env, false, |s| Ok(s.get_bracketed_paste()))
}

/// Get focus events mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_focus_events<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    query_session(env, false, |s| Ok(s.get_focus_events()))
}

/// Get synchronized output mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_sync_output<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    query_session(env, false, |s| Ok(s.get_synchronized_output()))
}
