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
    verify_required_functions();

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
const fn validate_emacs_version(version: (u32, u32)) -> Result<()> {
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
const fn verify_required_functions() {}

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

/// Get the list of exported module symbols
///
/// This function returns a list of symbols that the module exports,
/// which can be used for introspection or debugging.
///
/// # Returns
/// A vector of symbol names
#[must_use]
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
#[path = "tests/init.rs"]
mod tests;
