//! FFI-specific error types for Kuro Emacs module
//!
//! This module defines error types specific to the FFI layer, including
//! initialization errors, state errors, and runtime errors.

use crate::KuroError;
use std::fmt;

/// Errors that can occur during module initialization
#[derive(Debug, Clone, PartialEq)]
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
            InitError::VersionMismatch { required, found } => {
                write!(
                    f,
                    "Emacs version {}.{:?} is incompatible. Required: {}.{:?}",
                    found.0, found.1, required.0, required.1
                )
            }
            InitError::MissingFunction { function } => {
                write!(f, "Required Emacs function '{}' is not available", function)
            }
            InitError::AlreadyInitialized => {
                write!(f, "Kuro module is already initialized")
            }
            InitError::NotInitialized => {
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
#[derive(Debug, Clone, PartialEq)]
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
            StateError::NotInitialized => {
                write!(f, "Module not initialized. Call kuro-core-init first")
            }
            StateError::AlreadyInitialized => {
                write!(f, "Module already initialized")
            }
            StateError::NoTerminalSession => {
                write!(
                    f,
                    "No terminal session exists. Call kuro-core-init to create one"
                )
            }
            StateError::TerminalSessionExists => {
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
#[derive(Debug, Clone, PartialEq)]
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
            RuntimeError::PtySpawnFailed { command, message } => {
                write!(
                    f,
                    "Failed to spawn PTY for command '{}': {}",
                    command, message
                )
            }
            RuntimeError::PtyOperationFailed { operation, message } => {
                write!(f, "PTY operation '{}' failed: {}", operation, message)
            }
            RuntimeError::ParseError { message } => {
                write!(f, "VTE parse error: {}", message)
            }
            RuntimeError::InvalidParameter { param, message } => {
                write!(f, "Invalid parameter '{}': {}", param, message)
            }
            RuntimeError::AllocationFailed { message } => {
                write!(f, "Memory allocation failed: {}", message)
            }
            RuntimeError::FfiError { message } => {
                write!(f, "FFI error: {}", message)
            }
        }
    }
}

impl std::error::Error for RuntimeError {}

/// Convert FFI errors to KuroError
impl From<InitError> for KuroError {
    fn from(err: InitError) -> Self {
        KuroError::Init(err)
    }
}

impl From<StateError> for KuroError {
    fn from(err: StateError) -> Self {
        KuroError::State(err)
    }
}

impl From<RuntimeError> for KuroError {
    fn from(err: RuntimeError) -> Self {
        KuroError::Runtime(err)
    }
}

/// Helper function to create a PTY spawn error
pub fn pty_spawn_error(command: &str, message: &str) -> KuroError {
    RuntimeError::PtySpawnFailed {
        command: command.to_string(),
        message: message.to_string(),
    }
    .into()
}

/// Helper function to create a PTY operation error
pub fn pty_operation_error(operation: &str, message: &str) -> KuroError {
    RuntimeError::PtyOperationFailed {
        operation: operation.to_string(),
        message: message.to_string(),
    }
    .into()
}

/// Helper function to create a parse error
pub fn parse_error(message: &str) -> KuroError {
    RuntimeError::ParseError {
        message: message.to_string(),
    }
    .into()
}

/// Helper function to create an invalid parameter error
pub fn invalid_parameter_error(param: &str, message: &str) -> KuroError {
    RuntimeError::InvalidParameter {
        param: param.to_string(),
        message: message.to_string(),
    }
    .into()
}

/// Helper function to create an FFI error
pub fn ffi_error(message: &str) -> KuroError {
    RuntimeError::FfiError {
        message: message.to_string(),
    }
    .into()
}

#[cfg(test)]
#[path = "tests/error.rs"]
mod tests;
