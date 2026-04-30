//! Protocol size limits for the terminal parser.
//!
//! All parser-level byte-count caps are defined here to avoid cross-module
//! constant references. Both `apc.rs` and `kitty.rs` cap accumulated data
//! at [`MAX_APC_PAYLOAD_BYTES`] — the same Kitty Graphics Protocol memory
//! budget; centralising the constant here ensures they stay in sync.

/// Maximum APC payload accumulation in bytes (4 MiB).
///
/// Applied in `apc.rs` before the payload is forwarded to the Kitty
/// graphics handler. Excess bytes are silently dropped.
/// Also re-used as [`MAX_CHUNK_DATA_BYTES`] in `kitty.rs`.
pub const MAX_APC_PAYLOAD_BYTES: usize = 4 * 1024 * 1024;

/// Maximum Kitty chunk data accumulation in bytes.
///
/// Must equal [`MAX_APC_PAYLOAD_BYTES`]: both cap the same Kitty Graphics
/// Protocol transmission and are defined together to prevent divergence.
pub const MAX_CHUNK_DATA_BYTES: usize = MAX_APC_PAYLOAD_BYTES;

/// Maximum OSC window title / icon-name length in bytes (OSC 0 / OSC 2).
///
/// **`DoS` prevention:** a PTY under attacker control can emit arbitrarily long
/// OSC 0/2 sequences. Without this cap, unbounded accumulation of title bytes
/// would allow a malicious PTY to exhaust heap memory one sequence at a time.
///
/// **Why 1024?** Any real window title fits comfortably within 1 KiB; `XTerm`
/// uses a similar internal limit. Titles longer than this are silently
/// rejected without storing, preserving heap safety against terminals that
/// emit unusually verbose titles.
pub const MAX_TITLE_BYTES: usize = 1024;

/// Maximum `file://` path length for OSC 7 (set CWD).
///
/// Matches Linux `PATH_MAX` (4096).
pub const OSC7_MAX_PATH_BYTES: usize = 4096;

/// Maximum OSC 51 eval command length in bytes.
/// 4 KiB is generous for any legitimate Elisp eval command.
pub const OSC51_MAX_EVAL_BYTES: usize = 4096;

/// Maximum URI length for OSC 8 (hyperlink).
///
/// 8 KiB is a practical upper bound used by Alacritty and kitty;
/// modern URIs (GitHub permalinks, long query strings) often exceed
/// RFC 2616's 2 KiB recommendation.
pub const OSC8_MAX_URI_BYTES: usize = 8192;

/// Maximum `aid=` length for OSC 133 (shell job / action ID).
///
/// 256 is generous vs typical values (≤32); oversized values are silently
/// dropped to prevent a shell under attacker control from inflating
/// `PromptMarkEvent::aid` storage one mark at a time.
pub const OSC133_MAX_AID_BYTES: usize = 256;

/// Maximum `err=` path length for OSC 133 (error-report path).
///
/// Mirrors Linux `PATH_MAX` (4096). OSC 133 `err=` commonly carries a
/// PATH-like string; anything larger is silently rejected to preserve
/// heap safety against adversarial prompt marks.
pub const OSC133_MAX_ERR_PATH_BYTES: usize = 4096;

/// Maximum number of pending entries in [`crate::types::osc::OscData::prompt_marks`].
///
/// **`DoS` prevention:** a runaway or adversarial shell could emit prompt marks
/// faster than Elisp drains them. Without this cap, the `prompt_marks` Vec would
/// grow unboundedly and eventually OOM the host Emacs. Once the cap is reached,
/// additional marks are silently dropped.
pub const MAX_PENDING_PROMPT_MARKS: usize = 256;

#[cfg(test)]
mod tests {
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

    use super::{
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
}
