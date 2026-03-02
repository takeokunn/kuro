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
//! - **error.rs**: FFI-specific error types (InitError, StateError, RuntimeError)
//! - **safe_ref.rs**: Safe environment reference storage with lifetime management
//! - **abstraction.rs**: Defines the `KuroFFI` trait and shared session logic
//! - **bridge.rs**: Primary implementation using emacs-module-rs
//! - **fallback.rs**: Raw FFI bindings as contingency
//!
//! # Usage
//!
//! The core terminal logic uses the `TerminalSession` from `abstraction.rs`,
//! which is independent of any FFI binding implementation. The Emacs integration
//! (in `bridge.rs`) handles the actual FFI calls.
//!
//! # Benefits
//!
//! 1. Core logic never references emacs-module-rs directly
//! 2. Easy to switch to raw FFI if emacs-module-rs fails
//! 3. Simplifies testing (mock trait vs real implementation)
//! 4. Future-proofing for alternative FFI implementations

pub mod abstraction;
pub mod bridge;
pub mod error;
pub mod fallback;
pub mod init;
pub mod safe_ref;

// Re-export the trait and implementations
pub use abstraction::{init_session, shutdown_session, with_session, with_session_readonly};
pub use abstraction::{KuroFFI, TerminalSession, TERMINAL_SESSION};
pub use bridge::{switch_to_raw_ffi, EmacsModuleFFI};
pub use error::{InitError, RuntimeError, StateError};
pub use fallback::RawFFI;
pub use init::{
    get_exported_symbols, get_init_state, initialize, is_initialized, MIN_EMACS_VERSION,
};
pub use safe_ref::{
    env_ref_count, register_env_ref, unregister_env_ref, EnvRefRegistry, SafeEnvRef, ScopedEnvRef,
};

// Re-export for backward compatibility
