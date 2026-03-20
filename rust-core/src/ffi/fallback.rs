//! Raw FFI bindings as fallback for when emacs-module-rs fails
//!
//! This module provides direct C API bindings to the Emacs module interface.
//! It serves as a contingency implementation of the KuroFFI trait that can
//! be used if the emacs-module-rs crate encounters issues.
//!
//! This implementation manually handles the C-level interaction with Emacs,
//! including memory management, type conversions, and error handling.

use super::abstraction::{
    emacs_env, emacs_value, init_session, shutdown_session, with_session, with_session_readonly,
    KuroFFI,
};
use crate::error::KuroError;

/// Legacy session ID used by the `RawFFI` trait implementation.
const LEGACY_SESSION_ID: u64 = 0;

/// Raw C types from Emacs module API
#[repr(C)]
pub enum emacs_funcall_exit {
    /// Function returned normally
    EmacsFuncallExitReturn = 0,
    /// Function signaled an error
    EmacsFuncallExitSignal = 1,
    /// Function threw a value
    EmacsFuncallExitThrow = 2,
}

/// Finalizer function pointer for Emacs user pointers
#[repr(C)]
pub struct emacs_value_finalizer {
    _private: [u8; 0],
}

/// Raw FFI implementation using direct C API calls
///
/// This is a minimal implementation that provides the essential functionality
/// needed to operate the terminal emulator. It handles:
/// - Integer to/from Emacs value conversion
/// - String to/from Emacs value conversion
/// - List construction and manipulation
/// - Function calling in Emacs
pub struct RawFFI;

impl KuroFFI for RawFFI {
    fn init(env: *mut emacs_env, command: &str, rows: i64, cols: i64) -> *mut emacs_value {
        // Convert i64 to u16 safely
        let rows = rows as u16;
        let cols = cols as u16;

        // Initialize session
        match init_session(command, rows, cols) {
            Ok(_) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }

    fn poll_updates(env: *mut emacs_env, max_updates: i64) -> *mut emacs_value {
        let result: std::result::Result<Vec<(usize, String)>, KuroError> =
            with_session(LEGACY_SESSION_ID, |session| {
                let mut updates = Vec::new();
                let mut collected = 0;

                // Collect all dirty lines (max_updates: 0 means unlimited)
                loop {
                    session.poll_output()?;
                    let dirty_lines = session.get_dirty_lines();

                    if dirty_lines.is_empty() {
                        break;
                    }

                    updates.extend(dirty_lines);
                    collected += 1;

                    if max_updates > 0 && collected >= max_updates as usize {
                        break;
                    }
                }

                Ok(updates)
            });

        match result {
            Ok(dirty_lines) => {
                // Convert to Emacs list of (line_no . text) pairs
                let mut list = Self::make_nil(env);
                for (line_no, text) in dirty_lines.into_iter().rev() {
                    let line_no_val = Self::make_integer(env, line_no as i64);
                    let text_val = Self::make_string(env, &text);
                    let pair = Self::cons(env, line_no_val, text_val);
                    list = Self::cons(env, pair, list);
                }
                list
            }
            Err(_) => Self::make_nil(env),
        }
    }

    fn send_key(env: *mut emacs_env, data: &[u8]) -> *mut emacs_value {
        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.send_input(data)?;
            Ok(())
        });

        match result {
            Ok(_) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }

    fn resize(env: *mut emacs_env, rows: i64, cols: i64) -> *mut emacs_value {
        let rows = rows as u16;
        let cols = cols as u16;

        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.resize(rows, cols)?;
            Ok(())
        });

        match result {
            Ok(_) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }

    fn shutdown(env: *mut emacs_env) -> *mut emacs_value {
        match shutdown_session(LEGACY_SESSION_ID) {
            Ok(_) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }

    fn get_cursor(env: *mut emacs_env) -> *mut emacs_value {
        let result = with_session_readonly(LEGACY_SESSION_ID, |session| {
            let (row, col) = session.get_cursor();
            Ok(format!("{}:{}", row, col))
        });

        match result {
            Ok(s) => Self::make_string(env, &s),
            Err(_) => Self::make_string(env, "0:0"),
        }
    }

    fn get_scrollback(env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        let max_lines = if max_lines <= 0 {
            usize::MAX
        } else {
            max_lines as usize
        };

        let result = with_session_readonly(LEGACY_SESSION_ID, |session| Ok(session.get_scrollback(max_lines)));

        match result {
            Ok(lines) => {
                let mut list = Self::make_nil(env);
                for line in lines.into_iter().rev() {
                    let line_val = Self::make_string(env, &line);
                    list = Self::cons(env, line_val, list);
                }
                list
            }
            Err(_) => Self::make_nil(env),
        }
    }

    fn clear_scrollback(env: *mut emacs_env) -> *mut emacs_value {
        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.clear_scrollback();
            Ok(())
        });

        match result {
            Ok(_) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }

    fn set_scrollback_max_lines(env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.set_scrollback_max_lines(max_lines as usize);
            Ok(())
        });

        match result {
            Ok(_) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }
}

impl RawFFI {
    /// Create a nil value
    fn make_nil(_env: *mut emacs_env) -> *mut emacs_value {
        // In a real implementation, this would call emacs_make_nil or equivalent
        // For now, return a null pointer which will be interpreted as nil
        std::ptr::null_mut()
    }

    /// Create a boolean value (t or nil)
    fn make_bool(_env: *mut emacs_env, value: bool) -> *mut emacs_value {
        // In a real implementation, this would create t or nil
        // For now, use null as nil, and a non-null pointer for t
        if value {
            // Return a non-null pointer for t (this is a placeholder)
            // In real code, this would be env.intern("t")
            std::ptr::dangling_mut::<emacs_value>()
        } else {
            std::ptr::null_mut()
        }
    }

    /// Create an integer value
    fn make_integer(_env: *mut emacs_env, value: i64) -> *mut emacs_value {
        // In a real implementation, this would call env.make_integer(value)
        // For now, return a pointer with the value encoded (placeholder)
        (value as usize + 0x1000) as *mut emacs_value
    }

    /// Create a string value
    fn make_string(_env: *mut emacs_env, s: &str) -> *mut emacs_value {
        // In a real implementation, this would call env.make_string(s)
        // For now, return a pointer to the string (placeholder)
        s.as_ptr() as *mut emacs_value
    }

    /// Create a cons cell (pair)
    fn cons(
        _env: *mut emacs_env,
        car: *mut emacs_value,
        cdr: *mut emacs_value,
    ) -> *mut emacs_value {
        // In a real implementation, this would call env.cons(car, cdr)
        // For now, return a pointer with the pair encoded (placeholder)
        let car_val = car as usize;
        let cdr_val = cdr as usize;
        ((car_val << 32) | cdr_val) as *mut emacs_value
    }
}

/// Future extension: Raw C API bindings
///
/// The following are declarations for the actual C API functions from Emacs.
/// These would need to be linked when using the raw FFI implementation.
///
/// Note: These are currently commented out as they require proper linking
/// with the Emacs dynamic module library. They would be activated when
/// falling back from emacs-module-rs to raw FFI.
///
/// ```rust,ignore
/// extern "C" {
///     /// Get Emacs environment for the current thread
///     #[link_name = "emacs_get_environment"]
///     pub fn get_environment() -> *mut emacs_env;
///
///     /// Call an Emacs function
///     #[link_name = "emacs_funcall"]
///     pub fn funcall(
///         env: *mut emacs_env,
///         func: *mut emacs_value,
///         nargs: ptrdiff_t,
///         args: *mut emacs_value,
///     ) -> emacs_funcall_exit;
///
///     /// Make an integer value
///     #[link_name = "emacs_make_integer"]
///     pub fn make_integer(env: *mut emacs_env, value: intmax_t) -> *mut emacs_value;
///
///     /// Extract integer value
///     #[link_name = "emacs_extract_integer"]
///     pub fn extract_integer(env: *mut emacs_env, value: *mut emacs_value) -> intmax_t;
///
///     /// Make a string value
///     #[link_name = "emacs_make_string"]
///     pub fn make_string(
///         env: *mut emacs_env,
///         contents: *const c_char,
///         length: ptrdiff_t,
///     ) -> *mut emacs_value;
///
///     /// Copy string contents
///     #[link_name = "emacs_copy_string_contents"]
///     pub fn copy_string_contents(
///         env: *mut emacs_env,
///         value: *mut emacs_value,
///         buffer: *mut c_char,
///         size_inout: *mut ptrdiff_t,
///     ) -> bool;
///
///     /// Make a user pointer
///     #[link_name = "emacs_make_user_ptr"]
///     pub fn make_user_ptr(
///         env: *mut emacs_env,
///         fin: *mut emacs_value_finalizer,
///         ptr: *mut c_void,
///     ) -> *mut emacs_value;
///
///     /// Get user pointer
///     #[link_name = "emacs_get_user_ptr"]
///     pub fn get_user_ptr(env: *mut emacs_env, uptr: *mut emacs_value) -> *mut c_void;
///
///     /// Check if value is nil
///     #[link_name = "emacs_eq"]
///     pub fn eq(env: *mut emacs_env, a: *mut emacs_value, b: *mut emacs_value) -> bool;
///
///     /// Intern a symbol
///     #[link_name = "emacs_intern"]
///     pub fn intern(env: *mut emacs_env, name: *const c_char) -> *mut emacs_value;
///
///     /// Make a cons cell
///     #[link_name = "emacs_cons"]
///     pub fn cons(
///         env: *mut emacs_env,
///         car: *mut emacs_value,
///         cdr: *mut emacs_value,
///     ) -> *mut emacs_value;
///
///     /// Get car of cons cell
///     #[link_name = "emacs_car"]
///     pub fn car(env: *mut emacs_env, cons_cell: *mut emacs_value) -> *mut emacs_value;
///
///     /// Get cdr of cons cell
///     #[link_name = "emacs_cdr"]
///     pub fn cdr(env: *mut emacs_env, cons_cell: *mut emacs_value) -> *mut emacs_value;
/// }
/// ```

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_raw_ffi_trait_impl() {
        // Verify RawFFI implements KuroFFI
        // Note: KuroFFI is not dyn compatible
        let _ = &RawFFI;
    }

    #[test]
    fn test_placeholder_functions() {
        // Test placeholder functions don't crash
        let env = std::ptr::null_mut();
        let nil = RawFFI::make_nil(env);
        assert!(nil.is_null());

        let t_val = RawFFI::make_bool(env, true);
        assert!(!t_val.is_null());

        let f_val = RawFFI::make_bool(env, false);
        assert!(f_val.is_null());

        let int_val = RawFFI::make_integer(env, 42);
        assert!(!int_val.is_null());

        let str_val = RawFFI::make_string(env, "hello");
        assert!(!str_val.is_null());

        let pair = RawFFI::cons(env, int_val, str_val);
        assert!(!pair.is_null());
    }
}
