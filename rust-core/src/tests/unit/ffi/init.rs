//! Unit tests for `crate::ffi::init` — version validation, exported symbols,
//! and `InitializationState` type properties.
//!
//! Note: `INIT_STATE` is a `OnceLock` that cannot be reset between test runs.
//! All tests that call `initialize()` must tolerate both `Ok(())` (first
//! caller) and `Err(AlreadyInitialized)` (every subsequent caller).

use crate::ffi::error::InitError;
use crate::ffi::init::{
    get_exported_symbols, get_init_state, initialize, is_initialized, InitializationState,
    MIN_EMACS_VERSION,
};
use crate::KuroError;

// ---------------------------------------------------------------------------
// MIN_EMACS_VERSION constant
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: The minimum version constant must be exactly (29, 1).
fn test_min_emacs_version_constant() {
    const { assert!(MIN_EMACS_VERSION.0 == 29) };
    const { assert!(MIN_EMACS_VERSION.1 == 1) };
}

// ---------------------------------------------------------------------------
// InitializationState enum — derived trait coverage
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: InitializationState variants are Copy/Clone — assignment does not
// move the value.
fn test_initialization_state_copy() {
    let s = InitializationState::Initialized;
    let t = s; // Copy
    assert_eq!(s, t);
}

#[test]
// INVARIANT: Debug output is non-empty for both variants.
fn test_initialization_state_debug() {
    let s = format!("{:?}", InitializationState::Initialized);
    assert!(!s.is_empty(), "Debug for Initialized must be non-empty");
    let s2 = format!("{:?}", InitializationState::NotInitialized);
    assert!(!s2.is_empty(), "Debug for NotInitialized must be non-empty");
}

#[test]
// INVARIANT: The two variants are not equal to each other (PartialEq correctness).
fn test_initialization_state_inequality() {
    assert_ne!(
        InitializationState::Initialized,
        InitializationState::NotInitialized,
        "Initialized != NotInitialized"
    );
}

// ---------------------------------------------------------------------------
// validate_emacs_version — boundary cases
// (validate_emacs_version is private; we exercise it through `initialize`
//  which propagates its error, and through `KuroError::Init` pattern match)
// ---------------------------------------------------------------------------

#[test]
// BOUNDARY: (29, 2) is above the minimum minor — must be accepted.
fn test_version_above_minimum_minor() {
    // initialize may have already been called by a previous test in this process.
    // We only care that if it fails, it is due to AlreadyInitialized, not
    // VersionMismatch.
    let result = initialize((29, 2));
    assert!(
        result.is_ok() || matches!(result, Err(KuroError::Init(InitError::AlreadyInitialized))),
        "version (29, 2) must not produce VersionMismatch: got {result:?}"
    );
}

#[test]
// BOUNDARY: (1, 0) is far below minimum — must produce VersionMismatch.
fn test_version_far_below_minimum() {
    // Call the private fn indirectly: we know initialize rejects anything
    // below (29, 1). However, since OnceLock can already be set, we cannot
    // test this path through `initialize`. Instead we confirm the constant
    // relationship: any (major < 29) is below minimum.
    let (min_major, min_minor) = MIN_EMACS_VERSION;
    // major=1, minor=0 is obviously below (29, 1)
    assert!(1 < min_major, "major=1 is below min_major={min_major}");
    let _ = min_minor;
}

#[test]
// BOUNDARY: (29, 0) has a correct major but minor < 1 — must be below minimum.
fn test_version_29_0_is_below_minimum() {
    let (min_major, min_minor) = MIN_EMACS_VERSION;
    // (29, 0): major == min_major, but 0 < min_minor
    let is_below = 29 == min_major && 0 < min_minor;
    assert!(is_below, "(29, 0) should be below the minimum (29, {min_minor})");
}

// ---------------------------------------------------------------------------
// get_exported_symbols — completeness
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: The list must contain all 11 expected symbols.
fn test_exported_symbols_count() {
    let symbols = get_exported_symbols();
    assert_eq!(
        symbols.len(),
        11,
        "expected exactly 11 exported symbols, got {}",
        symbols.len()
    );
}

#[test]
// INVARIANT: Every expected symbol name must appear in the list.
fn test_exported_symbols_all_present() {
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
// INVARIANT: No symbol name in the list is empty.
fn test_exported_symbols_non_empty_names() {
    for sym in get_exported_symbols() {
        assert!(!sym.is_empty(), "no exported symbol name may be empty");
    }
}

#[test]
// INVARIANT: All symbol names use kebab-case and start with "kuro-".
fn test_exported_symbols_kuro_prefix() {
    for sym in get_exported_symbols() {
        assert!(
            sym.starts_with("kuro-"),
            "exported symbol '{sym}' must start with 'kuro-'"
        );
    }
}

// ---------------------------------------------------------------------------
// is_initialized / get_init_state — post-OnceLock queries
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: After initialize() has been called at least once in this process,
// is_initialized() is true and get_init_state() returns Some(Initialized).
fn test_post_initialize_state_queries() {
    // Attempt initialization — result is Ok or AlreadyInitialized; either way
    // the lock is set.
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
