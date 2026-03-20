//! State-related query functions: CWD, title, scroll offset, scrollback lines,
//! image notifications, clipboard.

use emacs::defun;
use emacs::{Env, Result as EmacsResult, Value};

use super::super::query_session_opt;

/// Get and atomically clear the pending window title (OSC 0/2)
///
/// Returns the new title string if one has been set since the last call,
/// or nil if no title update is pending.
#[defun]
fn kuro_core_get_and_clear_title(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session_opt(env, session_id, |s| Ok(s.take_title_if_dirty()))
}
