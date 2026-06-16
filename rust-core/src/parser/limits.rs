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

/// Maximum byte length for a notification title or body (DoS prevention).
///
/// Desktop notifications are surfaced as UTF-8 strings. 4 KiB keeps the
/// memory footprint bounded while still allowing long but realistic titles
/// and bodies.
pub const NOTIFICATION_MAX_BYTES: usize = 4 * 1024;

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

/// Hard cap on `duration=` values in OSC 133 prompt marks.
///
/// One year in milliseconds is a generous upper bound for shell-provided
/// durations. Larger values are treated as absent rather than saturating into
/// a misleadingly huge number.
pub const MAX_PROMPT_DURATION_MS: u64 = 365 * 24 * 3600 * 1000;

#[cfg(test)]
mod tests;
