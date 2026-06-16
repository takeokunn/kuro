//! Input mode query functions: application cursor keys, application keypad, keyboard flags.

use emacs::defun;
use emacs::{Env, Result as EmacsResult, Value};

use super::super::super::query_session;

macro_rules! define_mode_query {
    (
        $(#[$doc:meta])*
        fn $name:ident,
        default = $default:expr,
        body = $body:expr
    ) => {
        $(#[$doc])*
        #[defun]
        fn $name(env: &Env, session_id: u64) -> EmacsResult<Value<'_>> {
            query_session(env, session_id, $default, $body)
        }
    };
}

define_mode_query!(
    /// Get application cursor keys mode (DECCKM state: t if active, nil if not)
    fn kuro_core_get_app_cursor_keys,
    default = false,
    body = |s| Ok(s.get_app_cursor_keys())
);

define_mode_query!(
    /// Get application keypad mode state (t if DECKPAM active, nil if DECKPNM)
    fn kuro_core_get_app_keypad,
    default = false,
    body = |s| Ok(s.get_app_keypad())
);

define_mode_query!(
    /// Get current Kitty keyboard protocol flags as an integer
    ///
    /// Returns the current keyboard flags bitmask:
    ///   Bit 0 (1): Disambiguate escape codes
    ///   Bit 1 (2): Report event types (press/repeat/release)
    ///   Bit 2 (4): Report alternate keys
    ///   Bit 3 (8): Report all keys as escape codes
    ///   Bit 4 (16): Report associated text
    fn kuro_core_get_keyboard_flags,
    default = 0i64,
    body = |s| Ok(i64::from(s.get_keyboard_flags()))
);
