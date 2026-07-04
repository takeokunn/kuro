//! Input mode query functions: application cursor keys, application keypad, keyboard flags.

use emacs::defun;
use emacs::{Env, Result as EmacsResult, Value};

use super::super::super::{define_session_query_default, query_session};

define_session_query_default!(
    /// Get application cursor keys mode (DECCKM state: t if active, nil if not)
    kuro_core_get_app_cursor_keys,
    false,
    query_session,
    |s| s.get_app_cursor_keys()
);

define_session_query_default!(
    /// Get application keypad mode state (t if DECKPAM active, nil if DECKPNM)
    kuro_core_get_app_keypad,
    false,
    query_session,
    |s| s.get_app_keypad()
);

define_session_query_default!(
    /// Get current Kitty keyboard protocol flags as an integer
    ///
    /// Returns the current keyboard flags bitmask:
    ///   Bit 0 (1): Disambiguate escape codes
    ///   Bit 1 (2): Report event types (press/repeat/release)
    ///   Bit 2 (4): Report alternate keys
    ///   Bit 3 (8): Report all keys as escape codes
    ///   Bit 4 (16): Report associated text
    kuro_core_get_keyboard_flags,
    0i64,
    query_session,
    |s| i64::from(s.get_keyboard_flags())
);
