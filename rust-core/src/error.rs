//! Error types for Kuro

use std::ffi::NulError;
use std::io;
use thiserror::Error;

// Re-export FFI-specific error types
pub use crate::ffi::error::{InitError, RuntimeError, StateError};

/// Main error type for Kuro operations
#[derive(Error, Debug)]
pub enum KuroError {
    /// IO-related errors
    #[error("IO error: {0}")]
    Io(#[from] io::Error),

    /// PTY-related errors
    #[error("PTY error: {0}")]
    Pty(String),

    /// FFI-related errors
    #[error("FFI error: {0}")]
    Ffi(String),

    /// Parser errors
    #[error("Parser error: {0}")]
    Parser(String),

    /// Invalid parameter
    #[error("Invalid parameter: {0}")]
    InvalidParam(String),

    /// Null pointer in FFI
    #[error("Null pointer")]
    NullPointer,

    /// UTF-8 conversion error
    #[error("UTF-8 error: {0}")]
    Utf8(#[from] std::string::FromUtf8Error),

    /// Nul error in string conversion
    #[error("Nul error in string")]
    NulError(#[from] NulError),

    /// Initialization errors
    #[error("Initialization error: {0}")]
    Init(InitError),

    /// State errors
    #[error("State error: {0}")]
    State(StateError),

    /// Runtime errors
    #[error("Runtime error: {0}")]
    Runtime(RuntimeError),
}

impl From<String> for KuroError {
    fn from(s: String) -> Self {
        KuroError::Ffi(s)
    }
}

impl From<&str> for KuroError {
    fn from(s: &str) -> Self {
        KuroError::Ffi(s.to_string())
    }
}
