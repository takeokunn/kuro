//! OSC event polling: CWD, clipboard, prompt marks

use std::panic::{catch_unwind, AssertUnwindSafe};

use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

use super::{lock_session, query_session, query_session_opt};
use crate::error::KuroError;

/// Get the current working directory from OSC 7 and atomically clear the dirty flag.
///
/// Returns the CWD path string if one has been set since the last call,
/// or nil if no CWD update is pending.
#[defun]
fn kuro_core_get_cwd(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session_opt(env, session_id, |s| Ok(s.take_cwd_if_dirty()))
}

/// Drain a Vec from the specified session under a lock, handling panics and missing sessions.
///
/// Both `poll_clipboard_actions` and `poll_prompt_marks` follow the same pattern:
/// acquire the global session lock, drain a Vec, and return it for Emacs list building.
/// This helper encapsulates the lock + `catch_unwind` + drain boilerplate so each caller
/// only needs to supply the per-session drain closure and the panic message label.
#[inline]
fn drain_session_vec<T, F>(env: &Env, session_id: u64, label: &str, take: F) -> Vec<T>
where
    F: FnOnce(&mut crate::ffi::abstraction::TerminalSession) -> Vec<T> + std::panic::UnwindSafe,
{
    catch_unwind(AssertUnwindSafe(|| {
        let mut global = lock_session!();
        global.get_mut(&session_id).map_or_else(
            || Ok(Vec::new()),
            |session| Ok::<Vec<_>, KuroError>(take(session)),
        )
    }))
    .unwrap_or_else(|_| {
        let _ = env.message(format!("kuro: panic in {label}"));
        Ok(Vec::new())
    })
    .unwrap_or_default()
}

/// Poll for pending clipboard actions from OSC 52 and clear them.
///
/// Returns a list of clipboard actions. Each action is either:
///   - ("write" . TEXT) for a write action
///   - ("query" . nil) for a query action
#[defun]
fn kuro_core_poll_clipboard_actions(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    let actions = drain_session_vec(
        env,
        session_id,
        "poll_clipboard_actions",
        super::super::abstraction::session::TerminalSession::take_clipboard_actions,
    );

    let mut list = false.into_lisp(env)?;
    for action in actions.into_iter().rev() {
        let item = match action {
            crate::types::osc::ClipboardAction::Write(text) => {
                let tag = "write".into_lisp(env)?;
                let text_val = text.into_lisp(env)?;
                env.cons(tag, text_val)?
            }
            crate::types::osc::ClipboardAction::Query => {
                let tag = "query".into_lisp(env)?;
                let nil = false.into_lisp(env)?;
                env.cons(tag, nil)?
            }
        };
        list = env.cons(item, list)?;
    }
    Ok(list)
}

/// Poll for pending prompt mark events from OSC 133 and clear them.
///
/// Returns a list of prompt mark descriptors, each of the form:
///   (MARK-TYPE ROW COL)
/// where MARK-TYPE is one of: "prompt-start", "prompt-end", "command-start", "command-end"
#[defun]
#[expect(
    clippy::cast_possible_wrap,
    reason = "row/col are terminal dimensions (≤ 65535); usize→i64 never wraps"
)]
fn kuro_core_poll_prompt_marks(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    let marks = drain_session_vec(
        env,
        session_id,
        "poll_prompt_marks",
        super::super::abstraction::session::TerminalSession::take_prompt_marks,
    );

    let mut list = false.into_lisp(env)?;
    for event in marks.into_iter().rev() {
        let mark_str = match event.mark {
            crate::types::osc::PromptMark::PromptStart => "prompt-start",
            crate::types::osc::PromptMark::PromptEnd => "prompt-end",
            crate::types::osc::PromptMark::CommandStart => "command-start",
            crate::types::osc::PromptMark::CommandEnd => "command-end",
        };
        let mark_val = mark_str.into_lisp(env)?;
        let row_val = (event.row as i64).into_lisp(env)?;
        let col_val = (event.col as i64).into_lisp(env)?;

        // Build proper list: (mark-type row col)
        let nil = false.into_lisp(env)?;
        let item = env.cons(col_val, nil)?;
        let item = env.cons(row_val, item)?;
        let item = env.cons(mark_val, item)?;
        list = env.cons(item, list)?;
    }
    Ok(list)
}

/// Check if the PTY has pending unread output (non-blocking).
///
/// Returns t if the PTY channel has data waiting to be rendered,
/// nil otherwise.  Used by Emacs to trigger immediate render cycles
/// for low-latency streaming output (AI agents, etc.).
#[defun]
fn kuro_core_has_pending_output(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, false, |s| Ok(s.has_pending_output()))
}

/// Check if the PTY child process is still running.
///
/// Returns t if the shell process has not yet exited, nil if it has.
/// Used by Emacs to automatically kill the terminal buffer when the
/// process exits (e.g., user types `exit').
/// Returns nil (process gone) when no session is active.
#[defun]
fn kuro_core_is_process_alive(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    query_session(env, session_id, false, |s| Ok(s.is_process_alive()))
}

/// Get palette overrides from OSC 4 as a list of (index r g b) entries.
///
/// Returns a list of (INDEX R G B) for each palette entry overridden via OSC 4.
/// Only returns non-default (overridden) entries.
#[defun]
fn kuro_core_get_palette_updates(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    let updates: Vec<(u8, u8, u8, u8)> =
        catch_unwind(AssertUnwindSafe(|| -> crate::Result<Vec<_>> {
            let global = lock_session!();
            Ok(global
                .get(&session_id)
                .map(super::super::abstraction::session::TerminalSession::get_palette_updates)
                .unwrap_or_default())
        }))
        .unwrap_or_else(|_| Ok(Vec::new()))
        .unwrap_or_default();

    let mut list = false.into_lisp(env)?;
    for (idx, r, g, b) in updates.into_iter().rev() {
        let idx_val = i64::from(idx).into_lisp(env)?;
        let r_val = i64::from(r).into_lisp(env)?;
        let g_val = i64::from(g).into_lisp(env)?;
        let b_val = i64::from(b).into_lisp(env)?;

        let nil = false.into_lisp(env)?;
        let item = env.cons(b_val, nil)?;
        let item = env.cons(g_val, item)?;
        let item = env.cons(r_val, item)?;
        let item = env.cons(idx_val, item)?;
        list = env.cons(item, list)?;
    }
    Ok(list)
}

/// Get default terminal colors (OSC 10/11/12) as encoded u32 values.
///
/// Returns a cons cell (FG-ENC . (BG-ENC . CURSOR-ENC)) where each value is
/// a u32 FFI color encoding (0xFF000000 = default/unset).
/// Also clears the dirty flag atomically.
#[defun]
fn kuro_core_get_default_colors(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    let result: Option<(u32, u32, u32)> =
        catch_unwind(AssertUnwindSafe(|| -> crate::Result<Option<_>> {
            let mut global = lock_session!();
            Ok(global.get_mut(&session_id).and_then(|session| {
                session
                    .take_default_colors_dirty()
                    .then(|| session.get_default_colors())
            }))
        }))
        .unwrap_or(Ok(None))
        .unwrap_or(None);

    match result {
        Some((fg, bg, cur)) => {
            let fg_val = i64::from(fg).into_lisp(env)?;
            let bg_val = i64::from(bg).into_lisp(env)?;
            let cur_val = i64::from(cur).into_lisp(env)?;
            let inner = env.cons(cur_val, false.into_lisp(env)?)?;
            let inner = env.cons(bg_val, inner)?;
            env.cons(fg_val, inner)
        }
        None => false.into_lisp(env),
    }
}
