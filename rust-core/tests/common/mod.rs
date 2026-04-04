//! Shared helpers for Kuro integration tests.

use kuro_core::TerminalCore;

/// Return a standard-size test terminal used by the integration suites.
#[allow(dead_code)]
pub fn new_terminal() -> TerminalCore {
    TerminalCore::new(24, 80)
}

/// Read (not drain) pending responses from a `TerminalCore` and decode to UTF-8 strings.
///
/// Accumulates across calls — each subsequent call returns all responses since
/// the session was created (or since `TerminalCore::reset()` was last called).
/// Use the length delta between two calls to check for new responses.
#[allow(dead_code)]
pub fn read_responses(term: &TerminalCore) -> Vec<String> {
    let responses = term.pending_responses().to_vec();
    responses
        .iter()
        .map(|b| String::from_utf8_lossy(b).into_owned())
        .collect()
}
