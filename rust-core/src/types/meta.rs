//! Terminal metadata state

use crate::parser::dcs::DcsState;

/// Grouped terminal metadata and pending-response state.
#[derive(Default)]
pub(crate) struct TerminalMeta {
    /// Window title set via OSC 0 or OSC 2
    pub(crate) title: String,
    /// Whether the title has been updated and not yet read
    pub(crate) title_dirty: bool,
    /// Whether a BEL character has been received and not yet cleared
    pub(crate) bell_pending: bool,
    /// Queued responses to write back to the PTY (e.g. DA1/DA2 replies)
    pub(crate) pending_responses: Vec<Vec<u8>>,
    /// DCS (Device Control String) sequence state
    pub(crate) dcs_state: DcsState,
}
