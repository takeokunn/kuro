//! Error types for Kuro

use std::ffi::NulError;
use std::fmt;
use std::io;

// Re-export FFI-specific error types
pub use crate::ffi::error::{InitError, RuntimeError, StateError};

/// Main error type for Kuro operations
#[derive(Debug)]
#[non_exhaustive]
pub enum KuroError {
    /// IO-related errors
    Io(io::Error),

    /// Null pointer in FFI
    NullPointer,

    /// UTF-8 conversion error
    Utf8(std::string::FromUtf8Error),

    /// Nul error in string conversion
    NulError(NulError),

    /// Initialization errors
    Init(InitError),

    /// State errors
    State(StateError),

    /// Runtime errors
    Runtime(RuntimeError),
}

impl fmt::Display for KuroError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(e) => write!(f, "IO error: {e}"),
            Self::NullPointer => write!(f, "Null pointer"),
            Self::Utf8(e) => write!(f, "UTF-8 error: {e}"),
            Self::NulError(_) => write!(f, "Nul error in string"),
            Self::Init(e) => write!(f, "Initialization error: {e}"),
            Self::State(e) => write!(f, "State error: {e}"),
            Self::Runtime(e) => write!(f, "Runtime error: {e}"),
        }
    }
}

impl std::error::Error for KuroError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(e) => Some(e),
            Self::Utf8(e) => Some(e),
            Self::NulError(e) => Some(e),
            Self::Init(e) => Some(e),
            Self::State(e) => Some(e),
            Self::Runtime(e) => Some(e),
            Self::NullPointer => None,
        }
    }
}

impl From<io::Error> for KuroError {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}

impl From<std::string::FromUtf8Error> for KuroError {
    fn from(e: std::string::FromUtf8Error) -> Self {
        Self::Utf8(e)
    }
}

impl From<NulError> for KuroError {
    fn from(e: NulError) -> Self {
        Self::NulError(e)
    }
}

impl From<String> for KuroError {
    fn from(s: String) -> Self {
        crate::ffi::error::ffi_error(&s)
    }
}

impl From<&str> for KuroError {
    fn from(s: &str) -> Self {
        crate::ffi::error::ffi_error(s)
    }
}

impl From<crate::ffi::codec::BinaryFrameU32Overflow> for KuroError {
    fn from(error: crate::ffi::codec::BinaryFrameU32Overflow) -> Self {
        crate::ffi::error::ffi_error(&error.to_string())
    }
}

#[cfg(test)]
#[path = "error/tests.rs"]
mod tests;
