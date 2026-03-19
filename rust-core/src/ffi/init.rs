//! FFI initialization and Emacs environment validation
//!
//! This module handles initialization validation for the Emacs dynamic module,
//! including Emacs version compatibility checks and required function verification.

use super::error::InitError;
use crate::{KuroError, Result};
use std::sync::OnceLock;

/// Minimum supported Emacs version
pub const MIN_EMACS_VERSION: (u32, u32) = (29, 1);


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
/// Function availability cannot be checked here: `env.intern()` requires an
/// `emacs_env` pointer that is only valid during a module function call, not at
/// module-load time.  The dynamic linker ensures the emacs-module ABI symbols
/// (`make-user-ptr`, etc.) are present before `emacs_module_init` runs, so a
/// separate check would be redundant.
///
/// # Returns
/// * `Ok(())` always
fn verify_required_functions() -> Result<()> {
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
    #[ignore = "test_is_initialized depends on uninitialized global state; use --test-threads=1 and run in isolation"]
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

    /// Version (29, 1) is exactly the minimum — must be accepted.
    #[test]
    fn test_validate_emacs_version_minimum_29_1() {
        let result = validate_emacs_version((29, 1));
        assert!(
            result.is_ok(),
            "version (29, 1) should meet the minimum requirement"
        );
    }

    /// Version (28, 9) is below the minimum major version — must be rejected.
    #[test]
    fn test_validate_emacs_version_below_minimum_28_x() {
        let result = validate_emacs_version((28, 9));
        assert!(
            matches!(
                result,
                Err(KuroError::Init(InitError::VersionMismatch { .. }))
            ),
            "version (28, 9) should be rejected as below minimum"
        );
    }

    /// Version (29, 0) has the right major but minor is below the minimum — must be rejected.
    #[test]
    fn test_validate_emacs_version_below_minimum_29_0() {
        let result = validate_emacs_version((29, 0));
        assert!(
            matches!(
                result,
                Err(KuroError::Init(InitError::VersionMismatch { .. }))
            ),
            "version (29, 0) should be rejected because minor < 1"
        );
    }

    /// Version (30, 0) is above the minimum — must be accepted.
    #[test]
    fn test_validate_emacs_version_future_30_x() {
        let result = validate_emacs_version((30, 0));
        assert!(
            result.is_ok(),
            "version (30, 0) should be accepted as above minimum"
        );
    }

    /// The exported symbol list must contain "kuro-core-init".
    #[test]
    fn test_get_exported_symbols_contains_kuro_core_init() {
        let symbols = get_exported_symbols();
        assert!(
            symbols.contains(&"kuro-core-init"),
            "exported symbols should include 'kuro-core-init'"
        );
    }

    /// All exported symbols must be unique — no duplicates allowed.
    #[test]
    fn test_get_exported_symbols_no_duplicates() {
        let symbols = get_exported_symbols();
        let mut seen = std::collections::HashSet::new();
        for sym in &symbols {
            assert!(
                seen.insert(*sym),
                "duplicate symbol found in exported list: {}",
                sym
            );
        }
    }
}
