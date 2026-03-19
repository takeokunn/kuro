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
pub(crate) const MAX_APC_PAYLOAD_BYTES: usize = 4 * 1024 * 1024;

/// Maximum Kitty chunk data accumulation in bytes.
///
/// Must equal [`MAX_APC_PAYLOAD_BYTES`]: both cap the same Kitty Graphics
/// Protocol transmission and are defined together to prevent divergence.
pub(crate) const MAX_CHUNK_DATA_BYTES: usize = MAX_APC_PAYLOAD_BYTES;

/// Maximum OSC window title / icon-name length in bytes (OSC 0 / OSC 2).
///
/// **DoS prevention:** a PTY under attacker control can emit arbitrarily long
/// OSC 0/2 sequences. Without this cap, unbounded accumulation of title bytes
/// would allow a malicious PTY to exhaust heap memory one sequence at a time.
///
/// **Why 1024?** Any real window title fits comfortably within 1 KiB; XTerm
/// uses a similar internal limit. Titles longer than this are silently
/// rejected without storing, preserving heap safety against terminals that
/// emit unusually verbose titles.
pub(crate) const MAX_TITLE_BYTES: usize = 1024;

/// Maximum `file://` path length for OSC 7 (set CWD).
///
/// Matches Linux `PATH_MAX` (4096).
pub(crate) const OSC7_MAX_PATH_BYTES: usize = 4096;

/// Maximum URI length for OSC 8 (hyperlink).
///
/// 8 KiB is a practical upper bound used by Alacritty and kitty;
/// modern URIs (GitHub permalinks, long query strings) often exceed
/// RFC 2616's 2 KiB recommendation.
pub(crate) const OSC8_MAX_URI_BYTES: usize = 8192;
