//! Cursor and mode queries

use super::{bool_to_lisp, lock_session};
use crate::error::KuroError;
use emacs::defun;
use emacs::{Env, IntoLisp, Result as EmacsResult, Value};

/// Get cursor position as a (ROW . COL) cons pair
#[defun]
fn kuro_core_get_cursor<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        let (row, col) = if let Some(ref session) = *global {
            session.get_cursor()
        } else {
            (0, 0)
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
            let msg = format!("kuro: error in get_cursor: {}", e);
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
fn kuro_core_get_cursor_visible<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        let visible = if let Some(ref session) = *global {
            session.get_cursor_visible()
        } else {
            true
        };
        Ok::<bool, KuroError>(visible)
    }));
    match result {
        Ok(Ok(visible)) => bool_to_lisp(env, visible),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_cursor_visible: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_cursor_visible");
            env.intern("nil")
        }
    }
}

/// Get application cursor keys mode (DECCKM state: t if active, nil if not)
#[defun]
fn kuro_core_get_app_cursor_keys<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        let app_cursor_keys = if let Some(ref session) = *global {
            session.core.dec_modes.app_cursor_keys
        } else {
            false
        };
        Ok::<bool, KuroError>(app_cursor_keys)
    }));
    match result {
        Ok(Ok(v)) => bool_to_lisp(env, v),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_app_cursor_keys: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_app_cursor_keys");
            env.intern("nil")
        }
    }
}

/// Get application keypad mode state (t if DECKPAM active, nil if DECKPNM)
#[defun]
fn kuro_core_get_app_keypad<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        let app_keypad = if let Some(ref session) = *global {
            session.core.dec_modes.app_keypad
        } else {
            false
        };
        Ok::<bool, KuroError>(app_keypad)
    }));
    match result {
        Ok(Ok(v)) => bool_to_lisp(env, v),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_app_keypad: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_app_keypad");
            env.intern("nil")
        }
    }
}

/// Get and atomically clear the pending window title (OSC 0/2)
///
/// Returns the new title string if one has been set since the last call,
/// or nil if no title update is pending.
#[defun]
fn kuro_core_get_and_clear_title<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut global = lock_session!();
        if let Some(ref mut session) = *global {
            if session.core.title_dirty {
                session.core.title_dirty = false;
                Ok::<Option<String>, KuroError>(Some(session.core.title.clone()))
            } else {
                Ok(None)
            }
        } else {
            Ok(None)
        }
    }));
    match result {
        Ok(Ok(Some(title))) => title.into_lisp(env),
        Ok(Ok(None)) => false.into_lisp(env),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_and_clear_title: {}", e));
            false.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_and_clear_title");
            false.into_lisp(env)
        }
    }
}

/// Get bracketed paste mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_bracketed_paste<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        let bracketed_paste = if let Some(ref session) = *global {
            session.core.dec_modes.bracketed_paste
        } else {
            false
        };
        Ok::<bool, KuroError>(bracketed_paste)
    }));
    match result {
        Ok(Ok(v)) => bool_to_lisp(env, v),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_bracketed_paste: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_bracketed_paste");
            env.intern("nil")
        }
    }
}

/// Get mouse tracking mode (0=disabled, 1000=normal, 1002=button-event, 1003=any-event)
#[defun]
fn kuro_core_get_mouse_mode<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        let mouse_mode = if let Some(ref session) = *global {
            session.core.dec_modes.mouse_mode as i64
        } else {
            0i64
        };
        Ok::<i64, KuroError>(mouse_mode)
    }));
    match result {
        Ok(Ok(v)) => v.into_lisp(env),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_mouse_mode: {}", e));
            0i64.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_mouse_mode");
            0i64.into_lisp(env)
        }
    }
}

/// Get mouse SGR extended coordinates modifier state (t if active, nil if not)
#[defun]
fn kuro_core_get_mouse_sgr<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        let mouse_sgr = if let Some(ref session) = *global {
            session.core.dec_modes.mouse_sgr
        } else {
            false
        };
        Ok::<bool, KuroError>(mouse_sgr)
    }));
    match result {
        Ok(Ok(v)) => bool_to_lisp(env, v),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_mouse_sgr: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_mouse_sgr");
            env.intern("nil")
        }
    }
}

/// Get focus events mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_focus_events<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        let focus_events = if let Some(ref session) = *global {
            session.core.dec_modes.focus_events
        } else {
            false
        };
        Ok::<bool, KuroError>(focus_events)
    }));
    match result {
        Ok(Ok(v)) => bool_to_lisp(env, v),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_focus_events: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_focus_events");
            env.intern("nil")
        }
    }
}

/// Get synchronized output mode state (t if active, nil if not)
#[defun]
fn kuro_core_get_sync_output<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        let sync_output = if let Some(ref session) = *global {
            session.core.dec_modes.synchronized_output
        } else {
            false
        };
        Ok::<bool, KuroError>(sync_output)
    }));
    match result {
        Ok(Ok(v)) => bool_to_lisp(env, v),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_sync_output: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_sync_output");
            env.intern("nil")
        }
    }
}

/// Get cursor shape as an integer (DECSCUSR value)
///
/// Returns:
///   0 = BlinkingBlock (default)
///   2 = SteadyBlock
///   3 = BlinkingUnderline
///   4 = SteadyUnderline
///   5 = BlinkingBar
///   6 = SteadyBar
#[defun]
fn kuro_core_get_cursor_shape<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        let shape_int: i64 = if let Some(ref session) = *global {
            match session.core.dec_modes.cursor_shape {
                crate::types::cursor::CursorShape::BlinkingBlock => 0,
                crate::types::cursor::CursorShape::SteadyBlock => 2,
                crate::types::cursor::CursorShape::BlinkingUnderline => 3,
                crate::types::cursor::CursorShape::SteadyUnderline => 4,
                crate::types::cursor::CursorShape::BlinkingBar => 5,
                crate::types::cursor::CursorShape::SteadyBar => 6,
            }
        } else {
            0
        };
        Ok::<i64, KuroError>(shape_int)
    }));
    match result {
        Ok(Ok(v)) => v.into_lisp(env),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_cursor_shape: {}", e));
            0i64.into_lisp(env)
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_cursor_shape");
            0i64.into_lisp(env)
        }
    }
}

/// Get mouse SGR pixel coordinate mode state (?1016: t if active, nil if not)
#[defun]
fn kuro_core_get_mouse_pixel<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        let mouse_pixel = if let Some(ref session) = *global {
            session.core.dec_modes.mouse_pixel
        } else {
            false
        };
        Ok::<bool, KuroError>(mouse_pixel)
    }));
    match result {
        Ok(Ok(v)) => bool_to_lisp(env, v),
        Ok(Err(e)) => {
            let _ = env.message(format!("kuro: error in get_mouse_pixel: {}", e));
            env.intern("nil")
        }
        Err(_) => {
            let _ = env.message("kuro: panic in get_mouse_pixel");
            env.intern("nil")
        }
    }
}

/// Get current Kitty keyboard protocol flags as an integer
///
/// Returns the current keyboard flags bitmask:
///   Bit 0 (1): Disambiguate escape codes
///   Bit 1 (2): Report event types (press/repeat/release)
///   Bit 2 (4): Report alternate keys
///   Bit 3 (8): Report all keys as escape codes
///   Bit 4 (16): Report associated text
#[defun]
fn kuro_core_get_keyboard_flags<'e>(env: &'e Env) -> EmacsResult<Value<'e>> {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let global = lock_session!();
        if let Some(ref session) = *global {
            Ok::<i64, KuroError>(session.core.dec_modes.keyboard_flags as i64)
        } else {
            Ok(0i64)
        }
    }));
    match result {
        Ok(Ok(flags)) => flags.into_lisp(env),
        Ok(Err(e)) => {
            env.message(format!("kuro: get-keyboard-flags error: {}", e))?;
            0i64.into_lisp(env)
        }
        Err(_) => {
            env.message("kuro: panic in get-keyboard-flags")?;
            0i64.into_lisp(env)
        }
    }
}
