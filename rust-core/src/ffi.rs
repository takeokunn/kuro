//! FFI abstraction layer for Emacs dynamic module integration
//!
//! This module provides a trait-based abstraction over the Emacs module API,
//! allowing the core terminal logic to be insulated from direct dependencies
//! on emacs-module-rs. This enables:
//! - Easy fallback to raw FFI if emacs-module-rs fails
//! - Simplified testing through trait mocking
//! - Future-proofing for alternative FFI implementations
//!
//! # Architecture
//!
//! The FFI layer is organized as follows:
//!
//! - **init.rs**: Initialization validation and Emacs environment checks
//! - **error.rs**: FFI-specific error types (`InitError`, `StateError`, `RuntimeError`)
//! - **`safe_ref.rs`**: Safe environment reference storage with lifetime management
//! - **codec.rs**: Color/attribute encoding for compact FFI data transfer
//! - **abstraction.rs**: Defines the `KuroFFI` trait and shared session logic
//! - **bridge/**: Primary implementation using emacs-module-rs, split by concern:
//!   - **bridge/mod.rs**: Infrastructure (`lock_session`!, `bool_to_lisp`, `catch_panic`, `EmacsModuleFFI`)
//!   - **bridge/lifecycle.rs**: Session `init/send_key/resize/shutdown`
//!   - **bridge/queries.rs**: Cursor and mode getter functions
//!   - **bridge/render.rs**: Render polling, scrollback, viewport scroll, bell
//!   - **bridge/events.rs**: OSC event polling (CWD, clipboard, prompt marks, focus)
//!   - **bridge/images.rs**: Kitty Graphics Protocol image functions
//! - **fallback.rs**: Raw FFI bindings as contingency
//! - **`test_terminal.rs`**: Test-only `#[defun]` functions that bypass the PTY
//!
//! # Usage
//!
//! The core terminal logic uses the `TerminalSession` from `abstraction.rs`,
//! which is independent of any FFI binding implementation. The Emacs integration
//! (in `bridge/`) handles the actual FFI calls.
//!
//! # Benefits
//!
//! 1. Core logic never references emacs-module-rs directly
//! 2. Easy to switch to raw FFI if emacs-module-rs fails
//! 3. Simplifies testing (mock trait vs real implementation)
//! 4. Future-proofing for alternative FFI implementations

pub mod abstraction;
pub mod bridge;
pub mod codec;
pub mod error;
pub mod fallback;
pub mod init;
pub mod kuro_ffi;
pub mod safe_ref;
pub mod test_terminal;

// Re-export the trait and implementations
pub use abstraction::{
    attach_session, detach_session, init_session, list_sessions, shutdown_session, with_session,
    with_session_readonly,
};
pub use abstraction::{SessionState, TerminalSession, TERMINAL_SESSIONS};
pub use bridge::EmacsModuleFFI;
pub use error::{InitError, RuntimeError, StateError};
pub use fallback::RawFFI;
pub use init::{
    get_exported_symbols, get_init_state, initialize, is_initialized, MIN_EMACS_VERSION,
};
pub use kuro_ffi::{emacs_env, emacs_value, KuroFFI};
pub use safe_ref::{
    env_ref_count, register_env_ref, unregister_env_ref, EnvRefRegistry, SafeEnvRef, ScopedEnvRef,
};

// Re-export for backward compatibility
