//! Input mode query functions: application cursor keys, application keypad, keyboard flags.

use emacs::defun;
use emacs::{Env, Result as EmacsResult, Value};

use super::super::super::query_session;

/// Get application cursor keys mode (DECCKM state: t if active, nil if not)
#[defun]
fn kuro_core_get_app_cursor_keys<'e>(env: &'e Env, session_id: u64) -> EmacsResult<Value<'e>> {
    query_session(env, session_id, false, |s| Ok(s.get_app_cursor_keys()))
}

/// Get application keypad mode state (t if DECKPAM active, nil if DECKPNM)
#[defun]
fn kuro_core_get_app_keypad<'e>(env: &'e Env, session_id: u64) -> EmacsResult<Value<'e>> {
    query_session(env, session_id, false, |s| Ok(s.get_app_keypad()))
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
fn kuro_core_get_keyboard_flags<'e>(env: &'e Env, session_id: u64) -> EmacsResult<Value<'e>> {
    query_session(env, session_id, 0i64, |s| Ok(s.get_keyboard_flags() as i64))
}
