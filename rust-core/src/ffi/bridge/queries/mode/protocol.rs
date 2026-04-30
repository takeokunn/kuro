//! Protocol mode query functions: bracketed paste, focus events, synchronized output.

use emacs::defun;
use emacs::{Env, Result as EmacsResult, Value};

use super::super::super::{query_session, query_session_mut};

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

/// Update the stored Emacs color scheme.
///
/// `is-dark` is treated Lisp-style: any non-nil value means dark, `nil` means
/// light. When DEC private mode 2031 is enabled AND the new value differs from
/// the current stored value, pushes `CSI ? 997 ; Ps n` unsolicited notification
/// to `pending_responses` (Ps=1 dark, Ps=2 light).
///
/// Returns `t` if the stored state changed, `nil` if unchanged (no-op + zero
/// bytes pushed). Idempotent — repeated calls with the same value are safe
/// and cheap.
///
/// See: <https://contour-terminal.org/vt-extensions/color-palette-update-notifications/>
#[defun]
fn kuro_core_set_color_scheme<'e>(
    env: &'e Env,
    session_id: u64,
    is_dark: Value<'_>,
) -> EmacsResult<Value<'e>> {
    let dark = is_dark.is_not_nil();
    query_session_mut(env, session_id, false, move |session| {
        Ok(session.set_color_scheme(dark))
    })
}
