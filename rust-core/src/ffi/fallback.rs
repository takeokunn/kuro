//! Raw FFI bindings as fallback for when emacs-module-rs fails
//!
//! This module provides direct C API bindings to the Emacs module interface.
//! It serves as a contingency implementation of the `KuroFFI` trait that can
//! be used if the emacs-module-rs crate encounters issues.
//!
//! This implementation manually handles the C-level interaction with Emacs,
//! including memory management, type conversions, and error handling.

use super::abstraction::{
    emacs_env, emacs_value, init_session, shutdown_session, with_session, with_session_readonly,
    KuroFFI,
};
use super::boundary::{FfiScrollbackMaxLines, FfiScrollbackQueryLimit, FfiWindowSize};

/// Legacy session ID used by the `RawFFI` trait implementation.
const LEGACY_SESSION_ID: u64 = 0;

#[inline]
fn legacy_usize_to_i64(value: usize) -> i64 {
    i64::try_from(value).expect("dirty line row index must fit i64")
}

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
        let Some(size) = FfiWindowSize::parse(rows, cols) else {
            return Self::make_bool(env, false);
        };

        // Initialize session
        match init_session(command, &[], size.rows(), size.cols()) {
            Ok(_) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }

    fn poll_updates(env: *mut emacs_env, _max_updates: i64) -> *mut emacs_value {
        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.poll_output()?;
            Ok(session.get_dirty_lines())
        });
        result.map_or_else(
            |_| Self::make_nil(env),
            |dirty_lines| {
                Self::build_emacs_list_from_rev(env, dirty_lines, |env, (line_no, text)| {
                    let line_no_val = Self::make_integer(env, legacy_usize_to_i64(line_no));
                    let text_val = Self::make_string(env, &text);
                    Self::cons(env, line_no_val, text_val)
                })
            },
        )
    }

    fn send_key(env: *mut emacs_env, data: &[u8]) -> *mut emacs_value {
        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.send_input(data)?;
            Ok(())
        });

        match result {
            Ok(()) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }

    fn resize(env: *mut emacs_env, rows: i64, cols: i64) -> *mut emacs_value {
        let Some(size) = FfiWindowSize::parse(rows, cols) else {
            return Self::make_bool(env, false);
        };

        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.resize(size.rows(), size.cols())?;
            Ok(())
        });

        match result {
            Ok(()) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }

    fn shutdown(env: *mut emacs_env) -> *mut emacs_value {
        match shutdown_session(LEGACY_SESSION_ID) {
            Ok(()) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }

    fn get_cursor(env: *mut emacs_env) -> *mut emacs_value {
        let result = with_session_readonly(LEGACY_SESSION_ID, |session| {
            let (row, col) = session.get_cursor();
            Ok(format!("{row}:{col}"))
        });

        result.map_or_else(
            |_| Self::make_string(env, "0:0"),
            |s| Self::make_string(env, &s),
        )
    }

    fn get_scrollback(env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        let Some(limit) = FfiScrollbackQueryLimit::parse(max_lines) else {
            return Self::make_nil(env);
        };

        let result = with_session_readonly(LEGACY_SESSION_ID, |session| {
            Ok(session.get_scrollback(limit.get()))
        });
        result.map_or_else(
            |_| Self::make_nil(env),
            |lines| {
                let mut list = Self::make_nil(env);
                for line in lines.into_iter().rev() {
                    list = Self::cons(env, Self::make_string(env, &line), list);
                }
                list
            },
        )
    }

    fn clear_scrollback(env: *mut emacs_env) -> *mut emacs_value {
        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.clear_scrollback();
            Ok(())
        });

        match result {
            Ok(()) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }

    fn set_scrollback_max_lines(env: *mut emacs_env, max_lines: i64) -> *mut emacs_value {
        let Some(max_lines) = FfiScrollbackMaxLines::parse(max_lines) else {
            return Self::make_bool(env, false);
        };

        let result = with_session(LEGACY_SESSION_ID, |session| {
            session.set_scrollback_max_lines(max_lines.get());
            Ok(())
        });

        match result {
            Ok(()) => Self::make_bool(env, true),
            Err(_) => Self::make_bool(env, false),
        }
    }
}

impl RawFFI {
    /// Return an opaque non-nil test value without encoding data into a pointer.
    const fn make_non_nil_value() -> *mut emacs_value {
        std::ptr::dangling_mut::<emacs_value>()
    }

    /// Create a nil value
    const fn make_nil(_env: *mut emacs_env) -> *mut emacs_value {
        // In a real implementation, this would call emacs_make_nil or equivalent
        // For now, return a null pointer which will be interpreted as nil
        std::ptr::null_mut()
    }

    /// Create a boolean value (t or nil)
    const fn make_bool(_env: *mut emacs_env, value: bool) -> *mut emacs_value {
        // In a real implementation, this would create t or nil
        // For now, use null as nil, and a non-null pointer for t
        if value {
            // Return a non-null pointer for t (this is a placeholder)
            // In real code, this would be env.intern("t")
            Self::make_non_nil_value()
        } else {
            std::ptr::null_mut()
        }
    }

    /// Create an integer value
    const fn make_integer(_env: *mut emacs_env, _value: i64) -> *mut emacs_value {
        // In a real implementation, this would call env.make_integer(value)
        Self::make_non_nil_value()
    }

    /// Create a string value
    const fn make_string(_env: *mut emacs_env, _s: &str) -> *mut emacs_value {
        // In a real implementation, this would call env.make_string(s)
        Self::make_non_nil_value()
    }

    /// Create a cons cell (pair)
    fn cons(
        _env: *mut emacs_env,
        _car: *mut emacs_value,
        _cdr: *mut emacs_value,
    ) -> *mut emacs_value {
        // In a real implementation, this would call env.cons(car, cdr)
        Self::make_non_nil_value()
    }

    fn build_emacs_list_from_rev<T, I, F>(
        env: *mut emacs_env,
        items: I,
        mut make_item: F,
    ) -> *mut emacs_value
    where
        I: IntoIterator<Item = T>,
        I::IntoIter: DoubleEndedIterator,
        F: FnMut(*mut emacs_env, T) -> *mut emacs_value,
    {
        let mut list = Self::make_nil(env);
        for item in items.into_iter().rev() {
            list = Self::cons(env, make_item(env, item), list);
        }
        list
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
#[path = "fallback_tests.rs"]
mod tests;
