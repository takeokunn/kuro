//! FFI-specific error types for Kuro Emacs module
//!
//! This module defines error types specific to the FFI layer, including
//! initialization errors, state errors, and runtime errors.

use crate::KuroError;
use std::fmt;

/// Errors that can occur during module initialization
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InitError {
    /// Emacs version is too old
    VersionMismatch {
        /// Required version (major, minor)
        required: (u32, u32),
        /// Found version (major, minor)
        found: (u32, u32),
    },
    /// Required Emacs function is not available
    MissingFunction {
        /// Name of the missing function
        function: String,
    },
    /// Module was already initialized
    AlreadyInitialized,
    /// Module has not been initialized yet
    NotInitialized,
}

impl fmt::Display for InitError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::VersionMismatch { required, found } => {
                write!(
                    f,
                    "Emacs version {}.{:?} is incompatible. Required: {}.{:?}",
                    found.0, found.1, required.0, required.1
                )
            }
            Self::MissingFunction { function } => {
                write!(f, "Required Emacs function '{function}' is not available")
            }
            Self::AlreadyInitialized => {
                write!(f, "Kuro module is already initialized")
            }
            Self::NotInitialized => {
                write!(
                    f,
                    "Kuro module has not been initialized. Call kuro-core-init first"
                )
            }
        }
    }
}

impl std::error::Error for InitError {}

/// Errors related to module state
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StateError {
    /// Module has not been initialized
    NotInitialized,
    /// Module is already initialized
    AlreadyInitialized,
    /// Terminal session does not exist
    NoTerminalSession,
    /// Terminal session already exists
    TerminalSessionExists,
}

impl fmt::Display for StateError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotInitialized => {
                write!(f, "Module not initialized. Call kuro-core-init first")
            }
            Self::AlreadyInitialized => {
                write!(f, "Module already initialized")
            }
            Self::NoTerminalSession => {
                write!(
                    f,
                    "No terminal session exists. Call kuro-core-init to create one"
                )
            }
            Self::TerminalSessionExists => {
                write!(
                    f,
                    "Terminal session already exists. Call kuro-core-shutdown first"
                )
            }
        }
    }
}

impl std::error::Error for StateError {}

/// Runtime errors that can occur during terminal operation
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuntimeError {
    /// PTY spawn failed
    PtySpawnFailed {
        /// Command that failed
        command: String,
        /// Error message
        message: String,
    },
    /// PTY operation failed
    PtyOperationFailed {
        /// Operation that failed
        operation: String,
        /// Error message
        message: String,
    },
    /// VTE parse error
    ParseError {
        /// Description of the parse error
        message: String,
    },
    /// Invalid parameter provided
    InvalidParameter {
        /// Parameter name
        param: String,
        /// Error message
        message: String,
    },
    /// Memory allocation failed
    AllocationFailed {
        /// Description
        message: String,
    },
    /// FFI operation error
    FfiError {
        /// Error message
        message: String,
    },
}

impl fmt::Display for RuntimeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::PtySpawnFailed { command, message } => {
                write!(f, "Failed to spawn PTY for command '{command}': {message}")
            }
            Self::PtyOperationFailed { operation, message } => {
                write!(f, "PTY operation '{operation}' failed: {message}")
            }
            Self::ParseError { message } => {
                write!(f, "VTE parse error: {message}")
            }
            Self::InvalidParameter { param, message } => {
                write!(f, "Invalid parameter '{param}': {message}")
            }
            Self::AllocationFailed { message } => {
                write!(f, "Memory allocation failed: {message}")
            }
            Self::FfiError { message } => {
                write!(f, "FFI error: {message}")
            }
        }
    }
}

impl std::error::Error for RuntimeError {}

/// Convert FFI errors to `KuroError`
impl From<InitError> for KuroError {
    fn from(err: InitError) -> Self {
        Self::Init(err)
    }
}

impl From<StateError> for KuroError {
    fn from(err: StateError) -> Self {
        Self::State(err)
    }
}

impl From<RuntimeError> for KuroError {
    fn from(err: RuntimeError) -> Self {
        Self::Runtime(err)
    }
}

/// Helper function to create a PTY spawn error
#[must_use]
pub fn pty_spawn_error(command: &str, message: &str) -> KuroError {
    RuntimeError::PtySpawnFailed {
        command: command.to_owned(),
        message: message.to_owned(),
    }
    .into()
}

/// Helper function to create a PTY operation error
#[must_use]
pub fn pty_operation_error(operation: &str, message: &str) -> KuroError {
    RuntimeError::PtyOperationFailed {
        operation: operation.to_owned(),
        message: message.to_owned(),
    }
    .into()
}

/// Helper function to create a parse error
#[must_use]
pub fn parse_error(message: &str) -> KuroError {
    RuntimeError::ParseError {
        message: message.to_owned(),
    }
    .into()
}

/// Helper function to create an invalid parameter error
#[must_use]
pub fn invalid_parameter_error(param: &str, message: &str) -> KuroError {
    RuntimeError::InvalidParameter {
        param: param.to_owned(),
        message: message.to_owned(),
    }
    .into()
}

/// Helper function to create an FFI error
#[must_use]
pub fn ffi_error(message: &str) -> KuroError {
    RuntimeError::FfiError {
        message: message.to_owned(),
    }
    .into()
}

#[cfg(test)]
#[path = "tests/error.rs"]
mod tests;
