//! Unit and property tests for `TerminalCore`.
//!
//! This module is declared via `#[cfg(test)] mod tests;` in `lib.rs` and
//! therefore has access to all private items in the parent module through
//! `use super::*;`.

mod apc;
mod osc;
mod regression;
mod sgr;
mod terminal;

/// Create a standard 24×80 TerminalCore for testing.
pub(crate) fn make_term() -> crate::TerminalCore {
    crate::TerminalCore::new(24, 80)
}
