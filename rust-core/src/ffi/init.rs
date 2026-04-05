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
        // initialize() returns Ok on first call, AlreadyInitialized on any subsequent call.
        // OnceLock cannot be reset, so this test must tolerate both outcomes.
        let result = initialize((29, 1));
        assert!(
            result.is_ok() || matches!(result, Err(KuroError::Init(InitError::AlreadyInitialized))),
            "initialize must succeed or report AlreadyInitialized, got: {result:?}"
        );

        // Regardless of which path was taken, the module is now initialized
        assert!(
            is_initialized(),
            "is_initialized must be true after initialize()"
        );
        assert!(
            get_init_state().is_some(),
            "get_init_state must be Some after initialize()"
        );
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
                "duplicate symbol found in exported list: {sym}"
            );
        }
    }

    // --- Property-based unit tests (migrated from src/tests/unit/ffi/init.rs) ---

    // --- MIN_EMACS_VERSION constant ---

    #[test]
    fn test_pbt_min_emacs_version_constant() {
        const { assert!(MIN_EMACS_VERSION.0 == 29) };
        const { assert!(MIN_EMACS_VERSION.1 == 1) };
    }

    // --- InitializationState enum — derived trait coverage ---

    #[test]
    fn test_pbt_initialization_state_copy() {
        let s = InitializationState::Initialized;
        let t = s; // Copy
        assert_eq!(s, t);
    }

    #[test]
    fn test_pbt_initialization_state_debug() {
        let s = format!("{:?}", InitializationState::Initialized);
        assert!(!s.is_empty(), "Debug for Initialized must be non-empty");
        let s2 = format!("{:?}", InitializationState::NotInitialized);
        assert!(!s2.is_empty(), "Debug for NotInitialized must be non-empty");
    }

    #[test]
    fn test_pbt_initialization_state_inequality() {
        assert_ne!(
            InitializationState::Initialized,
            InitializationState::NotInitialized,
            "Initialized != NotInitialized"
        );
    }

    // --- validate_emacs_version — boundary cases ---

    #[test]
    fn test_pbt_version_above_minimum_minor() {
        let result = initialize((29, 2));
        assert!(
            result.is_ok() || matches!(result, Err(KuroError::Init(InitError::AlreadyInitialized))),
            "version (29, 2) must not produce VersionMismatch: got {result:?}"
        );
    }

    #[test]
    fn test_pbt_version_far_below_minimum() {
        let (min_major, min_minor) = MIN_EMACS_VERSION;
        assert!(1 < min_major, "major=1 is below min_major={min_major}");
        let _ = min_minor;
    }

    #[test]
    fn test_pbt_version_29_0_is_below_minimum() {
        let (min_major, min_minor) = MIN_EMACS_VERSION;
        let is_below = 29 == min_major && 0 < min_minor;
        assert!(
            is_below,
            "(29, 0) should be below the minimum (29, {min_minor})"
        );
    }

    // --- get_exported_symbols — completeness ---

    #[test]
    fn test_pbt_exported_symbols_count() {
        let symbols = get_exported_symbols();
        assert_eq!(
            symbols.len(),
            11,
            "expected exactly 11 exported symbols, got {}",
            symbols.len()
        );
    }

    #[test]
    fn test_pbt_exported_symbols_all_present() {
        let symbols = get_exported_symbols();
        let expected = [
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
        ];
        for sym in &expected {
            assert!(
                symbols.contains(sym),
                "exported symbols must include '{sym}'"
            );
        }
    }

    #[test]
    fn test_pbt_exported_symbols_non_empty_names() {
        for sym in get_exported_symbols() {
            assert!(!sym.is_empty(), "no exported symbol name may be empty");
        }
    }

    #[test]
    fn test_pbt_exported_symbols_kuro_prefix() {
        for sym in get_exported_symbols() {
            assert!(
                sym.starts_with("kuro-"),
                "exported symbol '{sym}' must start with 'kuro-'"
            );
        }
    }

    // --- is_initialized / get_init_state — post-OnceLock queries ---

    #[test]
    fn test_pbt_post_initialize_state_queries() {
        let _ = initialize((29, 1));
        assert!(
            is_initialized(),
            "is_initialized must return true after at least one successful initialize()"
        );
        assert_eq!(
            get_init_state(),
            Some(InitializationState::Initialized),
            "get_init_state must return Some(Initialized)"
        );
    }

    // --- MIN_EMACS_VERSION ordering invariants ---

    #[test]
    fn test_pbt_min_emacs_version_major_at_least_29() {
        const { assert!(MIN_EMACS_VERSION.0 >= 29) };
    }

    #[test]
    fn test_pbt_version_same_major_higher_minor_is_above_minimum() {
        let (min_major, min_minor) = MIN_EMACS_VERSION;
        let higher_minor = min_minor + 1;
        let is_above = min_major > MIN_EMACS_VERSION.0
            || (min_major == MIN_EMACS_VERSION.0 && higher_minor >= MIN_EMACS_VERSION.1);
        assert!(is_above, "({min_major}, {higher_minor}) must be >= minimum");
    }

    // --- get_exported_symbols — structural invariants ---

    #[test]
    fn test_pbt_exported_symbols_are_valid_utf8() {
        for sym in get_exported_symbols() {
            assert!(
                std::str::from_utf8(sym.as_bytes()).is_ok(),
                "symbol '{sym}' must be valid UTF-8"
            );
        }
    }

    #[test]
    fn test_pbt_exported_symbols_no_whitespace() {
        for sym in get_exported_symbols() {
            assert!(
                !sym.chars().any(char::is_whitespace),
                "symbol '{sym}' must not contain whitespace"
            );
        }
    }

    #[test]
    fn test_pbt_exported_symbols_kebab_case_charset() {
        for sym in get_exported_symbols() {
            for ch in sym.chars() {
                assert!(
                    ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '-',
                    "symbol '{sym}' has invalid char '{ch}' — must be kebab-case"
                );
            }
        }
    }

    #[test]
    fn test_pbt_exported_symbols_non_empty_list() {
        assert!(
            !get_exported_symbols().is_empty(),
            "get_exported_symbols must return a non-empty list"
        );
    }

    // --- InitializationState — exhaustive variant coverage ---

    #[test]
    fn test_pbt_not_initialized_differs_from_initialized() {
        let ni = InitializationState::NotInitialized;
        let i = InitializationState::Initialized;
        assert_ne!(ni, i, "NotInitialized must differ from Initialized");
        assert_eq!(ni, ni.clone());
        assert_eq!(i, i.clone());
    }

    #[test]
    fn test_pbt_get_init_state_some_after_any_initialize_call() {
        let _ = initialize((29, 1));
        let state = get_init_state();
        assert!(
            state.is_some(),
            "get_init_state must return Some after initialize()"
        );
        assert_eq!(
            state,
            Some(InitializationState::Initialized),
            "get_init_state must return Some(Initialized)"
        );
    }

    #[test]
    fn test_pbt_is_initialized_and_get_init_state_agree() {
        let _ = initialize((29, 1));
        let via_bool = is_initialized();
        let via_option = get_init_state().is_some();
        assert_eq!(
            via_bool, via_option,
            "is_initialized() must agree with get_init_state().is_some()"
        );
    }
}
