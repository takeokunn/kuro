//! Error types for Kuro

use std::ffi::NulError;
use std::io;
use thiserror::Error;

// Re-export FFI-specific error types
pub use crate::ffi::error::{InitError, RuntimeError, StateError};

/// Main error type for Kuro operations
#[derive(Error, Debug)]
#[non_exhaustive]
pub enum KuroError {
    /// IO-related errors
    #[error("IO error: {0}")]
    Io(#[from] io::Error),

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
        crate::ffi::error::ffi_error(&s)
    }
}

impl From<&str> for KuroError {
    fn from(s: &str) -> Self {
        crate::ffi::error::ffi_error(s)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- Variant construction and Display formatting ---

    #[test]
    fn test_io_variant_display() {
        let io_err = io::Error::new(io::ErrorKind::NotFound, "file not found");
        let err: KuroError = io_err.into();
        assert!(matches!(err, KuroError::Io(_)));
        let s = err.to_string();
        assert!(!s.is_empty(), "Display for Io variant must be non-empty");
        assert!(s.contains("IO error"), "Display must contain 'IO error'");
    }

    #[test]
    fn test_pty_variant_display() {
        let err = crate::ffi::error::pty_spawn_error("bash", "pty failed");
        let s = err.to_string();
        assert!(!s.is_empty());
        assert!(s.contains("PTY"));
        assert!(s.contains("pty failed"));
    }

    #[test]
    fn test_ffi_variant_display() {
        let err = crate::ffi::error::ffi_error("ffi blew up");
        let s = err.to_string();
        assert!(!s.is_empty());
        assert!(s.contains("FFI error"));
        assert!(s.contains("ffi blew up"));
    }

    #[test]
    fn test_parser_variant_display() {
        let err = crate::ffi::error::parse_error("unexpected byte");
        let s = err.to_string();
        assert!(!s.is_empty());
        assert!(s.contains("parse error") || s.contains("VTE parse error"));
        assert!(s.contains("unexpected byte"));
    }

    #[test]
    fn test_invalid_param_variant_display() {
        let err = crate::ffi::error::invalid_parameter_error("rows", "rows must be > 0");
        let s = err.to_string();
        assert!(!s.is_empty());
        assert!(s.contains("Invalid parameter") || s.contains("parameter"));
        assert!(s.contains("rows must be > 0"));
    }

    #[test]
    fn test_null_pointer_variant_display() {
        let err = KuroError::NullPointer;
        let s = err.to_string();
        assert!(!s.is_empty());
        assert!(s.contains("Null pointer"));
    }

    #[test]
    fn test_utf8_variant_display() {
        // Construct a FromUtf8Error by trying to convert invalid bytes.
        let bad_bytes = vec![0xFF, 0xFE];
        let utf8_err = String::from_utf8(bad_bytes).unwrap_err();
        let err: KuroError = utf8_err.into();
        assert!(matches!(err, KuroError::Utf8(_)));
        let s = err.to_string();
        assert!(!s.is_empty());
        assert!(s.contains("UTF-8 error"));
    }

    #[test]
    fn test_nul_error_variant_display() {
        // Construct a NulError by embedding a nul byte in a CString.
        let nul_err = std::ffi::CString::new("hel\0lo").unwrap_err();
        let err: KuroError = nul_err.into();
        assert!(matches!(err, KuroError::NulError(_)));
        let s = err.to_string();
        assert!(!s.is_empty());
        assert!(s.contains("Nul error"));
    }

    // --- From conversions ---

    #[test]
    fn test_from_io_error() {
        let io_err = io::Error::new(io::ErrorKind::PermissionDenied, "denied");
        let err = KuroError::from(io_err);
        assert!(matches!(err, KuroError::Io(_)));
    }

    #[test]
    fn test_from_utf8_error() {
        let bad_bytes = vec![0x80, 0x81];
        let utf8_err = String::from_utf8(bad_bytes).unwrap_err();
        let err = KuroError::from(utf8_err);
        assert!(matches!(err, KuroError::Utf8(_)));
    }

    #[test]
    fn test_from_nul_error() {
        let nul_err = std::ffi::CString::new("a\0b").unwrap_err();
        let err = KuroError::from(nul_err);
        assert!(matches!(err, KuroError::NulError(_)));
    }

    #[test]
    fn test_from_string() {
        let err = KuroError::from("some error".to_owned());
        assert!(matches!(err, KuroError::Runtime(_)));
    }

    #[test]
    fn test_from_str() {
        let err = KuroError::from("some error");
        assert!(matches!(err, KuroError::Runtime(_)));
    }

    // --- Debug formatting (non-empty for all variants) ---

    #[test]
    fn test_debug_format_non_empty() {
        let variants: Vec<Box<dyn std::fmt::Debug>> = vec![
            Box::new(crate::ffi::error::pty_spawn_error("bash", "x")),
            Box::new(crate::ffi::error::ffi_error("x")),
            Box::new(crate::ffi::error::parse_error("x")),
            Box::new(crate::ffi::error::invalid_parameter_error("p", "x")),
            Box::new(KuroError::NullPointer),
        ];
        for v in &variants {
            let s = format!("{v:?}");
            assert!(!s.is_empty(), "Debug format must be non-empty");
        }
    }
}
