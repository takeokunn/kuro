//! Consolidated mode query functions to reduce Mutex contention.
//!
//! Each function collects multiple terminal state values in a single lock
//! acquisition, returning a flat Lisp list for the Elisp layer to destructure.

use std::panic::{catch_unwind, AssertUnwindSafe};

use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

use super::super::super::lock_session;
use crate::error::KuroError;

/// Get all terminal mode flags in a single Mutex acquisition.
///
/// Returns a flat list:
///   `(app-cursor-keys app-keypad mouse-mode mouse-sgr mouse-pixel
///     bracketed-paste keyboard-flags)`
///
/// Where:
///   - app-cursor-keys: t or nil (DECCKM)
///   - app-keypad: t or nil (DECKPAM/DECKPNM)
///   - mouse-mode: integer (0/1000/1002/1003)
///   - mouse-sgr: t or nil (mode 1006)
///   - mouse-pixel: t or nil (mode 1016)
///   - bracketed-paste: t or nil (mode 2004)
///   - keyboard-flags: integer (Kitty keyboard protocol bitmask)
///
/// On error or missing session, returns nil.
#[defun]
fn kuro_core_get_terminal_modes(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let global = lock_session!();
        Ok::<_, KuroError>(global.get(&session_id).map(|s| {
            (
                s.get_app_cursor_keys(),
                s.get_app_keypad(),
                i64::from(s.get_mouse_mode()),
                s.get_mouse_sgr(),
                s.get_mouse_pixel(),
                s.get_bracketed_paste(),
                i64::from(s.get_keyboard_flags()),
            )
        }))
    }));
    match result {
        Ok(Ok(Some((ack, ak, mm, ms, mp, bp, kf)))) => {
            let nil = env.intern("nil")?;
            // Build list in reverse: (ack ak mm ms mp bp kf)
            let list = env.cons(kf.into_lisp(env)?, nil)?;
            let list = env.cons(bp.into_lisp(env)?, list)?;
            let list = env.cons(mp.into_lisp(env)?, list)?;
            let list = env.cons(ms.into_lisp(env)?, list)?;
            let list = env.cons(mm.into_lisp(env)?, list)?;
            let list = env.cons(ak.into_lisp(env)?, list)?;
            env.cons(ack.into_lisp(env)?, list)
        }
        Ok(Ok(None) | Err(_)) => false.into_lisp(env),
        Err(_) => {
            let _ = env.message("kuro: panic in get_terminal_modes");
            false.into_lisp(env)
        }
    }
}
