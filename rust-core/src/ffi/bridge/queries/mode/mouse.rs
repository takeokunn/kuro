//! Mouse mode query functions: mouse tracking mode, SGR extended coordinates, pixel coordinates.

use emacs::defun;
use emacs::{Env, Result as EmacsResult, Value};

use super::super::super::{define_session_query_default, query_session};

define_session_query_default!(
    /// Get mouse tracking mode (0=disabled, 1000=normal, 1002=button-event, 1003=any-event)
    kuro_core_get_mouse_mode,
    0i64,
    query_session,
    |s| i64::from(s.get_mouse_mode())
);

define_session_query_default!(
    /// Get mouse SGR extended coordinates modifier state (t if active, nil if not)
    kuro_core_get_mouse_sgr,
    false,
    query_session,
    |s| s.get_mouse_sgr()
);

define_session_query_default!(
    /// Get mouse SGR pixel coordinate mode state (?1016: t if active, nil if not)
    kuro_core_get_mouse_pixel,
    false,
    query_session,
    |s| s.get_mouse_pixel()
);
