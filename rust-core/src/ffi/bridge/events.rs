//! OSC event polling: CWD, clipboard, prompt marks

use super::lock_session;
use crate::error::KuroError;
use emacs::defun;
use emacs::{Env, IntoLisp, Result as EmacsResult, Value};

/// Get the current working directory from OSC 7 and atomically clear the dirty flag.
///
/// Returns the CWD path string if one has been set since the last call,
/// or nil if no CWD update is pending.
#[defun]
fn kuro_core_get_cwd<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = lock_session!();
        if let Some(ref mut session) = *global {
            if session.core.osc_data.cwd_dirty {
                session.core.osc_data.cwd_dirty = false;
                Ok::<Option<String>, KuroError>(session.core.osc_data.cwd.clone())
            } else {
                Ok(None)
            }
        } else {
            Ok(None)
        }
    }));
    match result {
        Ok(Ok(Some(cwd))) => cwd.into_lisp(env),
        Ok(Ok(None)) => false.into_lisp(env),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_cwd: {}", e));
            false.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_cwd");
            false.into_lisp(env)
        }
    }
}

/// Poll for pending clipboard actions from OSC 52 and clear them.
///
/// Returns a list of clipboard actions. Each action is either:
///   - ("write" . TEXT) for a write action
///   - ("query" . nil) for a query action
#[defun]
fn kuro_core_poll_clipboard_actions<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let actions = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = lock_session!();
        if let Some(ref mut session) = *global {
            Ok::<Vec<_>, KuroError>(std::mem::take(&mut session.core.osc_data.clipboard_actions))
        } else {
            Ok(Vec::new())
        }
    }))
    .unwrap_or_else(|_| Ok(Vec::new()))
    .unwrap_or_default();

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
fn kuro_core_poll_prompt_marks<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let marks = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = lock_session!();
        if let Some(ref mut session) = *global {
            Ok::<Vec<_>, KuroError>(std::mem::take(&mut session.core.osc_data.prompt_marks))
        } else {
            Ok(Vec::new())
        }
    }))
    .unwrap_or_else(|_| Ok(Vec::new()))
    .unwrap_or_default();

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
fn kuro_core_has_pending_output<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        Ok::<bool, KuroError>(
            global.as_ref().map(|s| s.has_pending_output()).unwrap_or(false)
        )
    }));
    match result {
        Ok(Ok(has_data)) => has_data.into_lisp(env),
        _ => false.into_lisp(env),
    }
}

/// Get palette overrides from OSC 4 as a list of (index r g b) entries.
///
/// Returns a list of (INDEX R G B) for each palette entry overridden via OSC 4.
/// Only returns non-default (overridden) entries.
#[defun]
fn kuro_core_get_palette_updates<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let updates = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        Ok::<Vec<(u8, u8, u8, u8)>, KuroError>(
            global.as_ref().map(|s| s.get_palette_updates()).unwrap_or_default()
        )
    }))
    .unwrap_or_else(|_| Ok(Vec::new()))
    .unwrap_or_default();

    let mut list = false.into_lisp(env)?;
    for (idx, r, g, b) in updates.into_iter().rev() {
        let idx_val = (idx as i64).into_lisp(env)?;
        let r_val = (r as i64).into_lisp(env)?;
        let g_val = (g as i64).into_lisp(env)?;
        let b_val = (b as i64).into_lisp(env)?;

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
fn kuro_core_get_default_colors<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = lock_session!();
        if let Some(ref mut session) = *global {
            let dirty = session.take_default_colors_dirty();
            if dirty {
                let (fg, bg, cur) = session.get_default_colors();
                Ok::<Option<(u32, u32, u32)>, KuroError>(Some((fg, bg, cur)))
            } else {
                Ok(None)
            }
        } else {
            Ok(None)
        }
    }))
    .unwrap_or_else(|_| Ok(None))
    .unwrap_or(None);

    match result {
        Some((fg, bg, cur)) => {
            let fg_val = (fg as i64).into_lisp(env)?;
            let bg_val = (bg as i64).into_lisp(env)?;
            let cur_val = (cur as i64).into_lisp(env)?;
            let inner = env.cons(cur_val, false.into_lisp(env)?)?;
            let inner = env.cons(bg_val, inner)?;
            env.cons(fg_val, inner)
        }
        None => false.into_lisp(env),
    }
}
