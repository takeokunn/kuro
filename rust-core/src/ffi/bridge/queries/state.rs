//! State-related query functions: CWD, title, scroll offset, scrollback lines,
//! image notifications, clipboard.

use emacs::defun;
use emacs::{Env, Result as EmacsResult, Value};

use super::super::{define_session_query_opt, query_session_opt};
define_session_query_opt!(
    /// Get and atomically clear the pending window title (OSC 0/2)
    ///
    /// Returns the new title string if one has been set since the last call,
    /// or nil if no title update is pending.
    kuro_core_get_and_clear_title,
    query_session_opt,
    |s| s.take_title_if_dirty()
);
