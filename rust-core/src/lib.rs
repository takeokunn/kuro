//! Kuro Terminal Emulator Core
//!
//! This library provides the core functionality for the Kuro terminal emulator,
//! including VTE parsing, virtual screen management, PTY handling, and Emacs
//! dynamic module FFI bindings.

#![warn(missing_docs)]
#![warn(clippy::all)]

pub mod error;
pub mod ffi;
pub mod grid;
pub mod parser;
pub mod pty;
pub mod terminal;
pub mod types;

#[cfg(test)]
mod vttest;

use emacs::Env;

emacs::plugin_is_GPL_compatible!();

#[emacs::module(
    name = "kuro-core",
    defun_prefix = "",
    separator = "",
    mod_in_name = false
)]
fn init(env: &Env) -> emacs::Result<()> {
    ffi::bridge::module_init(env)
}

// Re-exports for convenience
pub use error::KuroError;
pub use grid::screen::Screen;
pub use types::{cell::Cell, cell::UnderlineStyle, color::Color, cursor::CursorShape};

// Re-export FFI abstraction layer
pub use ffi::{EmacsModuleFFI, KuroFFI, RawFFI, TerminalSession, TERMINAL_SESSION};

/// Result type for Kuro operations
pub type Result<T> = std::result::Result<T, KuroError>;

// Re-export ApcScanState from the dedicated parser module
pub use parser::apc::ApcScanState;

// Re-export TerminalCore from dedicated module
pub use terminal::TerminalCore;

#[cfg(test)]
mod tests;
