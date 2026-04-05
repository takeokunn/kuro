//! FFI abstraction trait for Emacs module integration
//!
//! This module provides a trait-based abstraction over the Emacs module API,
//! allowing the core terminal logic to be insulated from direct dependencies
//! on emacs-module-rs. This enables:
//! - Easy fallback to raw FFI if emacs-module-rs fails
//! - Simplified testing through trait mocking
//! - Future-proofing for alternative FFI implementations

pub mod dirty;
pub mod global;
pub mod session;

#[cfg(test)]
mod tests_integration;
#[cfg(test)]
mod tests_unit;

pub use super::kuro_ffi::{KuroFFI, emacs_env, emacs_value};
pub use global::{
    TERMINAL_SESSIONS, attach_session, detach_session, init_session, list_sessions,
    shutdown_session, with_session, with_session_readonly,
};
pub use session::{SessionState, TerminalSession};
