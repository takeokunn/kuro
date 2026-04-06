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
pub(crate) mod util;

#[cfg(test)]
mod vttest;

// Emacs module registration — excluded when cfg(fuzzing) is active.
// bridge/test_terminal #[defun] ctor registrations + ASAN + ld64.lld
// -init_offsets are incompatible on arm64 macOS 15; cargo-fuzz sets this cfg.
#[cfg(not(fuzzing))]
use emacs::Env;

#[cfg(not(fuzzing))]
emacs::plugin_is_GPL_compatible!();

#[cfg(not(fuzzing))]
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

// Re-export FFI abstraction layer (EmacsModuleFFI only outside fuzzing)
#[cfg(not(fuzzing))]
pub use ffi::EmacsModuleFFI;
pub use ffi::{KuroFFI, RawFFI, SessionState, TerminalSession, TERMINAL_SESSIONS};

/// Result type for Kuro operations
pub type Result<T> = std::result::Result<T, KuroError>;

// Re-export ApcScanState from the dedicated parser module
pub use parser::apc::ApcScanState;

// Re-export TerminalCore from dedicated module
pub use terminal::TerminalCore;
