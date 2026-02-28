//! FFI initialization and Emacs environment validation
//!
//! This module handles initialization validation for the Emacs dynamic module,
//! including Emacs version compatibility checks and required function verification.

use super::error::InitError;
use crate::{KuroError, Result};
use std::sync::OnceLock;

/// Minimum supported Emacs version
pub const MIN_EMACS_VERSION: (u32, u32) = (29, 1);

/// Required Emacs module functions that must be available
#[allow(dead_code)]
const REQUIRED_FUNCTIONS: &[&str] = &[
    "emacs-module-init",
    "module-load",
    "make-user-ptr",
    "set-user-ptr-data",
    "get-user-ptr-data",
];

/// Global initialization state
static INIT_STATE: OnceLock<InitializationState> = OnceLock::new();

/// Initialization state tracking
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InitializationState {
    /// Not initialized
    NotInitialized,
    /// Successfully initialized
    Initialized,
}

/// Initialize the Kuro module
///
/// This function validates the Emacs environment and initializes the module.
/// It must be called once during module loading.
///
/// # Arguments
/// * `emacs_version` - Tuple of (major, minor) Emacs version
///
/// # Returns
/// * `Ok(())` if initialization succeeds
/// * `Err(InitError)` if validation fails
///
/// # Errors
/// * `InitError::VersionMismatch` - Emacs version is too old
/// * `InitError::AlreadyInitialized` - Module was already initialized
pub fn initialize(emacs_version: (u32, u32)) -> Result<()> {
    // Check if already initialized
    if INIT_STATE.get().is_some() {
        return Err(KuroError::Init(InitError::AlreadyInitialized));
    }

    // Validate Emacs version
    validate_emacs_version(emacs_version)?;

    // Verify required functions are available
    verify_required_functions()?;

    // Mark as initialized
    INIT_STATE
        .set(InitializationState::Initialized)
        .map_err(|_| KuroError::Init(InitError::AlreadyInitialized))?;

    Ok(())
}

/// Validate Emacs version compatibility
///
/// # Arguments
/// * `version` - Tuple of (major, minor) Emacs version
///
/// # Returns
/// * `Ok(())` if version is compatible
/// * `Err(InitError::VersionMismatch)` if version is too old
fn validate_emacs_version(version: (u32, u32)) -> Result<()> {
    let (major, minor) = version;
    let (min_major, min_minor) = MIN_EMACS_VERSION;

    if major < min_major || (major == min_major && minor < min_minor) {
        Err(KuroError::Init(InitError::VersionMismatch {
            required: MIN_EMACS_VERSION,
            found: version,
        }))
    } else {
        Ok(())
    }
}

/// Verify that required Emacs functions are available
///
/// This is a placeholder implementation. In the actual module,
/// this would check the Emacs environment for function availability.
///
/// # Returns
/// * `Ok(())` if all required functions are available
/// * `Err(InitError::MissingFunction)` if a function is missing
fn verify_required_functions() -> Result<()> {
    // In the actual implementation, this would query the Emacs environment
    // For now, we assume all functions are available if initialization is called
    // This is because we can't query Emacs from Rust without the environment pointer
    Ok(())
}

/// Check if the module has been initialized
///
/// # Returns
/// * `true` if initialized, `false` otherwise
pub fn is_initialized() -> bool {
    INIT_STATE.get().is_some()
}

/// Get the current initialization state
///
/// # Returns
/// * `Some(state)` if module has been initialized
/// * `None` if not initialized
pub fn get_init_state() -> Option<InitializationState> {
    INIT_STATE.get().copied()
}

/// Reset the initialization state (for testing only)
///
/// # Safety
/// This function should only be used in test code to reset the
/// initialization state between tests.
#[cfg(test)]
pub fn reset_init_state() {
    // Note: OnceLock doesn't provide a reset method,
    // so in tests we would need to use a different mechanism.
    // For now, this is a placeholder.
}

/// Get the list of exported module symbols
///
/// This function returns a list of symbols that the module exports,
/// which can be used for introspection or debugging.
///
/// # Returns
/// A vector of symbol names
pub fn get_exported_symbols() -> Vec<&'static str> {
    vec![
        "kuro-core-init",
        "kuro-core-send-key",
        "kuro-core-poll-updates",
        "kuro-core-resize",
        "kuro-core-shutdown",
        "kuro-core-get-cursor",
        "kuro-core-get-scrollback",
        "kuro-core-clear-scrollback",
        "kuro-core-set-scrollback-max-lines",
        "kuro-core-get-scrollback-count",
        "kuro-core-poll-updates-with-faces",
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_emacs_version() {
        // Test compatible version
        assert!(validate_emacs_version((29, 1)).is_ok());
        assert!(validate_emacs_version((30, 0)).is_ok());
        assert!(validate_emacs_version((31, 1)).is_ok());

        // Test incompatible version
        let result = validate_emacs_version((28, 1));
        assert!(matches!(
            result,
            Err(KuroError::Init(InitError::VersionMismatch { .. }))
        ));
    }

    #[test]
    fn test_is_initialized() {
        // Initially not initialized
        assert!(!is_initialized());

        // After initialization
        let result = initialize((29, 1));
        assert!(
            result.is_ok() || matches!(result, Err(KuroError::Init(InitError::AlreadyInitialized)))
        );

        // Check state
        let state = get_init_state();
        assert!(state.is_some());
    }

    #[test]
    fn test_get_exported_symbols() {
        let symbols = get_exported_symbols();
        assert!(!symbols.is_empty());
        assert!(symbols.contains(&"kuro-core-init"));
        assert!(symbols.contains(&"kuro-core-poll-updates"));
    }

    #[test]
    fn test_already_initialized() {
        // First initialization should succeed
        let result1 = initialize((29, 1));
        assert!(
            result1.is_ok()
                || matches!(result1, Err(KuroError::Init(InitError::AlreadyInitialized)))
        );

        // Second initialization should fail
        let result2 = initialize((29, 1));
        assert!(matches!(
            result2,
            Err(KuroError::Init(InitError::AlreadyInitialized))
        ));
    }
}
