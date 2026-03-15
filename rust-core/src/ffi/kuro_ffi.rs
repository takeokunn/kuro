//! KuroFFI trait and raw C FFI type declarations
//!
//! This module defines the `KuroFFI` trait (the interface for FFI implementations)
//! and the raw C struct types used by emacs_module.h.

/// Raw Emacs environment pointer (opaque type from C API)
#[repr(C)]
pub struct emacs_env {
    _private: [u8; 0],
}

/// Raw Emacs value type (opaque type from C API)
#[repr(C)]
pub struct emacs_value {
    _private: [u8; 0],
}

/// FFI abstraction trait for Emacs module operations
///
/// This trait defines the interface that all FFI implementations must provide.
/// It uses raw pointers to maintain compatibility with the C API, while
/// providing type-safe abstractions for Rust code.
///
/// Note: This trait is NOT object-safe (dyn compatible) because it contains
/// associated functions without `self` parameters. This is intentional -
/// the trait is used for compile-time polymorphism and documentation of the
/// FFI interface, not for runtime trait objects.
pub trait KuroFFI {
    /// Initialize a new terminal session with the given dimensions
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `command` - Shell command to execute (e.g., "bash" or "zsh")
    /// * `rows` - Number of rows in the terminal
    /// * `cols` - Number of columns in the terminal
    ///
    /// # Returns
    /// A pointer to an Emacs value representing the session handle
    fn init(env: *mut emacs_env, command: &str, rows: i64, cols: i64) -> *mut emacs_value;

    /// Poll for terminal updates and return dirty lines
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `max_updates` - Maximum number of updates to return (0 for unlimited)
    ///
    /// # Returns
    /// A pointer to an Emacs list of (line_no . text) pairs
    fn poll_updates(env: *mut emacs_env, max_updates: i64) -> *mut emacs_value;

    /// Send key input to the terminal
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `data` - Raw byte data to send
    /// * `len` - Length of the data in bytes
    ///
    /// # Returns
    /// A pointer to an Emacs boolean (t or nil)
    fn send_key(env: *mut emacs_env, data: &[u8]) -> *mut emacs_value;

    /// Resize the terminal
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `rows` - New number of rows
    /// * `cols` - New number of columns
    ///
    /// # Returns
    /// A pointer to an Emacs boolean (t or nil)
    fn resize(env: *mut emacs_env, rows: i64, cols: i64) -> *mut emacs_value;

    /// Shutdown the terminal session
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    ///
    /// # Returns
    /// A pointer to an Emacs boolean (t or nil)
    fn shutdown(env: *mut emacs_env) -> *mut emacs_value;

    /// Get cursor position
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    ///
    /// # Returns
    /// A pointer to an Emacs string in "row:col" format
    fn get_cursor(env: *mut emacs_env) -> *mut emacs_value;

    /// Get scrollback lines
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `max_lines` - Maximum number of lines to return (0 for all)
    ///
    /// # Returns
    /// A pointer to an Emacs list of strings
    fn get_scrollback(env: *mut emacs_env, max_lines: i64) -> *mut emacs_value;

    /// Clear scrollback buffer
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    ///
    /// # Returns
    /// A pointer to an Emacs boolean (t or nil)
    fn clear_scrollback(env: *mut emacs_env) -> *mut emacs_value;

    /// Set scrollback max lines
    ///
    /// # Arguments
    /// * `env` - Pointer to the Emacs environment
    /// * `max_lines` - Maximum number of lines in scrollback buffer
    ///
    /// # Returns
    /// A pointer to an Emacs boolean (t or nil)
    fn set_scrollback_max_lines(env: *mut emacs_env, max_lines: i64) -> *mut emacs_value;
}
