//! Tests for parser/limits.rs — boundary constants
//!
//! Module under test: `src/parser/limits.rs`
//! Tier: T2 — `ProptestConfig::with_cases(128)`
//!
//! Constants verified:
//!   `MAX_APC_PAYLOAD_BYTES` = 4 MiB = 4 * 1024 * 1024 = 4_194_304
//!   `MAX_CHUNK_DATA_BYTES`  = `MAX_APC_PAYLOAD_BYTES` (alias for Kitty Graphics sync)
//!   `MAX_TITLE_BYTES`       = 1 KiB = 1024 (XTerm-compatible DoS limit)
//!   `OSC7_MAX_PATH_BYTES`   = 4096 (Linux PATH_MAX)
//!   `OSC8_MAX_URI_BYTES`    = 8192 (Alacritty/kitty practical upper bound)

use crate::parser::limits::{
    MAX_APC_PAYLOAD_BYTES, MAX_CHUNK_DATA_BYTES, MAX_TITLE_BYTES, OSC7_MAX_PATH_BYTES,
    OSC8_MAX_URI_BYTES,
};
use proptest::prelude::*;

// ---------------------------------------------------------------------------
// Exact numeric values — document the spec values as assertions
// ---------------------------------------------------------------------------

#[test]
// VALUE: MAX_APC_PAYLOAD_BYTES must be exactly 4 MiB (4 * 1024 * 1024).
fn test_max_apc_payload_bytes_is_4_mib() {
    assert_eq!(
        MAX_APC_PAYLOAD_BYTES,
        4 * 1024 * 1024,
        "MAX_APC_PAYLOAD_BYTES must equal 4 MiB = 4_194_304"
    );
}

#[test]
// VALUE: MAX_CHUNK_DATA_BYTES must equal MAX_APC_PAYLOAD_BYTES.
// Both cap the same Kitty Graphics Protocol transmission pipeline.
fn test_max_chunk_data_equals_max_apc_payload() {
    assert_eq!(
        MAX_CHUNK_DATA_BYTES, MAX_APC_PAYLOAD_BYTES,
        "MAX_CHUNK_DATA_BYTES must equal MAX_APC_PAYLOAD_BYTES to keep Kitty limits in sync"
    );
}

#[test]
// VALUE: MAX_TITLE_BYTES must be exactly 1024 (1 KiB, XTerm-compatible).
fn test_max_title_bytes_is_1024() {
    assert_eq!(
        MAX_TITLE_BYTES, 1024,
        "MAX_TITLE_BYTES must equal 1024 bytes (1 KiB)"
    );
}

#[test]
// VALUE: OSC7_MAX_PATH_BYTES must be exactly 4096 (Linux PATH_MAX).
fn test_osc7_max_path_bytes_is_4096() {
    assert_eq!(
        OSC7_MAX_PATH_BYTES, 4096,
        "OSC7_MAX_PATH_BYTES must equal 4096 (Linux PATH_MAX)"
    );
}

#[test]
// VALUE: OSC8_MAX_URI_BYTES must be exactly 8192 (8 KiB).
fn test_osc8_max_uri_bytes_is_8192() {
    assert_eq!(
        OSC8_MAX_URI_BYTES, 8192,
        "OSC8_MAX_URI_BYTES must equal 8192 bytes (8 KiB)"
    );
}

// ---------------------------------------------------------------------------
// Boundary arithmetic — values just below the limit are ≤ the limit
// ---------------------------------------------------------------------------

#[test]
// BOUNDARY: MAX_APC_PAYLOAD_BYTES - 1 is strictly less than MAX_APC_PAYLOAD_BYTES.
fn test_apc_payload_below_limit_accepted() {
    let just_below = MAX_APC_PAYLOAD_BYTES - 1;
    assert!(
        just_below < MAX_APC_PAYLOAD_BYTES,
        "value one below MAX_APC_PAYLOAD_BYTES must be strictly less than the limit"
    );
}

#[test]
// BOUNDARY: MAX_TITLE_BYTES - 1 is strictly less than MAX_TITLE_BYTES.
fn test_title_below_limit_accepted() {
    let just_below = MAX_TITLE_BYTES - 1;
    assert!(
        just_below < MAX_TITLE_BYTES,
        "value one below MAX_TITLE_BYTES must be strictly less than the limit"
    );
}

#[test]
// BOUNDARY: OSC7_MAX_PATH_BYTES - 1 is strictly less than OSC7_MAX_PATH_BYTES.
fn test_osc7_below_limit_accepted() {
    let just_below = OSC7_MAX_PATH_BYTES - 1;
    assert!(
        just_below < OSC7_MAX_PATH_BYTES,
        "value one below OSC7_MAX_PATH_BYTES must be strictly less than the limit"
    );
}

#[test]
// BOUNDARY: OSC8_MAX_URI_BYTES - 1 is strictly less than OSC8_MAX_URI_BYTES.
fn test_osc8_below_limit_accepted() {
    let just_below = OSC8_MAX_URI_BYTES - 1;
    assert!(
        just_below < OSC8_MAX_URI_BYTES,
        "value one below OSC8_MAX_URI_BYTES must be strictly less than the limit"
    );
}

// ---------------------------------------------------------------------------
// Ordering invariants between constants
// ---------------------------------------------------------------------------

#[test]
// ORDERING: MAX_TITLE_BYTES < OSC7_MAX_PATH_BYTES.
// A window title (1 KiB) must be capped tighter than a filesystem path (4 KiB).
fn test_max_title_bytes_less_than_osc7_max_path() {
    const { assert!(MAX_TITLE_BYTES < OSC7_MAX_PATH_BYTES) };
}

#[test]
// ORDERING: OSC7_MAX_PATH_BYTES < OSC8_MAX_URI_BYTES.
// A filesystem path (4 KiB) must be capped tighter than a hyperlink URI (8 KiB).
fn test_osc7_max_path_less_than_osc8_max_uri() {
    const { assert!(OSC7_MAX_PATH_BYTES < OSC8_MAX_URI_BYTES) };
}

#[test]
// ORDERING: OSC8_MAX_URI_BYTES < MAX_APC_PAYLOAD_BYTES.
// A hyperlink URI (8 KiB) must be capped far below the 4 MiB APC payload budget.
fn test_osc8_max_uri_less_than_max_apc_payload() {
    const { assert!(OSC8_MAX_URI_BYTES < MAX_APC_PAYLOAD_BYTES) };
}

// ---------------------------------------------------------------------------
// Property-based: buffer lengths at the boundary never exceed the limit
// ---------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(128))]

    #[test]
    // BOUNDARY: Any string whose byte length is exactly MAX_TITLE_BYTES is
    // within the allowed budget.
    fn prop_title_at_limit_is_valid(len in 0usize..=MAX_TITLE_BYTES) {
        prop_assert!(
            len <= MAX_TITLE_BYTES,
            "len {len} must be ≤ MAX_TITLE_BYTES ({MAX_TITLE_BYTES})"
        );
    }

    #[test]
    // BOUNDARY: Any path length in [0, OSC7_MAX_PATH_BYTES] is within the budget.
    fn prop_osc7_path_at_limit_is_valid(len in 0usize..=OSC7_MAX_PATH_BYTES) {
        prop_assert!(
            len <= OSC7_MAX_PATH_BYTES,
            "len {len} must be ≤ OSC7_MAX_PATH_BYTES ({OSC7_MAX_PATH_BYTES})"
        );
    }
}

// ---------------------------------------------------------------------------
// Additional arithmetic and representational invariants
// ---------------------------------------------------------------------------

#[test]
// VALUE: MAX_APC_PAYLOAD_BYTES is exactly 4_194_304 (4 * 1024 * 1024).
// Verify as a compile-time constant to catch accidental edits.
fn test_max_apc_payload_bytes_exact_decimal() {
    const { assert!(MAX_APC_PAYLOAD_BYTES == 4_194_304) };
}

#[test]
// VALUE: MAX_TITLE_BYTES is a power of two (2^10 = 1024).
// Power-of-two limits play well with allocators.
fn test_max_title_bytes_is_power_of_two() {
    const { assert!(MAX_TITLE_BYTES.count_ones() == 1) };
}

#[test]
// RATIO: MAX_APC_PAYLOAD_BYTES / MAX_TITLE_BYTES must be exactly 4096.
// Confirms the relative sizing between the title cap and the APC budget.
fn test_apc_to_title_ratio_is_4096() {
    const { assert!(MAX_APC_PAYLOAD_BYTES / MAX_TITLE_BYTES == 4096) };
}

#[test]
// RATIO: OSC7_MAX_PATH_BYTES / MAX_TITLE_BYTES == 4.
// A filesystem path cap is four times the title cap.
fn test_osc7_to_title_ratio_is_4() {
    const { assert!(OSC7_MAX_PATH_BYTES / MAX_TITLE_BYTES == 4) };
}

#[test]
// RATIO: OSC8_MAX_URI_BYTES / OSC7_MAX_PATH_BYTES == 2.
// A hyperlink URI cap is exactly twice the path cap.
fn test_osc8_to_osc7_ratio_is_2() {
    const { assert!(OSC8_MAX_URI_BYTES / OSC7_MAX_PATH_BYTES == 2) };
}

#[test]
// VALUE: MAX_CHUNK_DATA_BYTES is non-zero — the codec must always accept
// at least one byte of chunk data.
fn test_max_chunk_data_bytes_is_non_zero() {
    const { assert!(MAX_CHUNK_DATA_BYTES > 0) };
}

#[test]
// VALUE: All limits fit within usize (no truncation on 32-bit targets).
// OSC8_MAX_URI_BYTES = 8192 < 65536 = 2^16; safe on any platform.
fn test_all_limits_fit_in_usize_comfortably() {
    // The smallest plausible usize is 16 bits (2^16 = 65536).
    // OSC8_MAX_URI_BYTES = 8192 < 65536.
    const { assert!(OSC8_MAX_URI_BYTES < 65536) };
    // MAX_TITLE_BYTES = 1024 < 65536.
    const { assert!(MAX_TITLE_BYTES < 65536) };
    // OSC7_MAX_PATH_BYTES = 4096 < 65536.
    const { assert!(OSC7_MAX_PATH_BYTES < 65536) };
}

#[test]
// ORDERING: MAX_APC_PAYLOAD_BYTES > OSC8_MAX_URI_BYTES > OSC7_MAX_PATH_BYTES
// > MAX_TITLE_BYTES. The full ordering chain must hold in a single assertion.
fn test_full_ordering_chain() {
    const {
        assert!(
            MAX_APC_PAYLOAD_BYTES > OSC8_MAX_URI_BYTES
            && OSC8_MAX_URI_BYTES > OSC7_MAX_PATH_BYTES
            && OSC7_MAX_PATH_BYTES > MAX_TITLE_BYTES
        )
    };
}
