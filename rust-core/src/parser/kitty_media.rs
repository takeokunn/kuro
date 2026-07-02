//! Kitty Graphics Protocol file / temp / shared-memory media transmission.
//!
//! Direct or chunked inline Kitty graphics payloads are decoded in
//! `parser/kitty.rs`. Every host-object transmission (`t=f`, `t=t`, `t=s`) is
//! rejected here.
//!
//! The PTY controls the encoded reference. Treating that reference as a host
//! path or shared-memory name would create a file-disclosure primitive, and
//! `t=t` would additionally create a PTY-triggered deletion primitive. The
//! ideal boundary is therefore simple: do not decode the reference, do not open
//! anything, do not delete anything.

use crate::parser::kitty::KittyParams;

/// Resolve a non-direct transmission (`t=f`, `t=t`, or `t=s`) into raw image
/// bytes.
///
/// This intentionally never succeeds. Inline `t=d` / omitted-transmission
/// payloads remain supported by the caller; host-object references do not.
pub(super) fn resolve_media_payload(
    _transmission: char,
    _b64_data: &[u8],
    _params: &KittyParams,
) -> Option<Vec<u8>> {
    None
}

#[cfg(test)]
#[path = "tests/kitty_media.rs"]
mod tests;
