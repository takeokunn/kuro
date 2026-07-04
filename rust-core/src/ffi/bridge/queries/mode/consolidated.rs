//! Consolidated mode query functions to reduce Mutex contention.
//!
//! Each function collects multiple terminal state values in a single lock
//! acquisition, returning a flat Lisp list for the Elisp layer to destructure.

use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

use super::super::super::{build_emacs_list_from_values, define_session_data_query_or_false};

type TerminalModes = (bool, bool, i64, bool, bool, bool, i64);

fn terminal_modes_to_lisp(env: &Env, modes: TerminalModes) -> EmacsResult<Value<'_>> {
    let (ack, ak, mm, ms, mp, bp, kf) = modes;
    build_emacs_list_from_values(
        env,
        [
            ack.into_lisp(env)?,
            ak.into_lisp(env)?,
            mm.into_lisp(env)?,
            ms.into_lisp(env)?,
            mp.into_lisp(env)?,
            bp.into_lisp(env)?,
            kf.into_lisp(env)?,
        ],
    )
}

define_session_data_query_or_false!(
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
kuro_core_get_terminal_modes,
    "get_terminal_modes",
    |session| {
        Ok((
            session.get_app_cursor_keys(),
            session.get_app_keypad(),
        i64::from(session.get_mouse_mode()),
        session.get_mouse_sgr(),
            session.get_mouse_pixel(),
            session.get_bracketed_paste(),
            i64::from(session.get_keyboard_flags()),
        ))
    },
    |kuro_env, modes| terminal_modes_to_lisp(kuro_env, modes)
);
