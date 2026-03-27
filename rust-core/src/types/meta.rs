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

#[cfg(test)]
mod tests {
    use super::*;

    // -------------------------------------------------------------------------
    // Default-state invariants
    // -------------------------------------------------------------------------

    #[test]
    // CONSTRUCTION: TerminalMeta::default() must have an empty title.
    fn terminal_meta_default_title_empty() {
        assert!(TerminalMeta::default().title.is_empty());
    }

    #[test]
    // CONSTRUCTION: TerminalMeta::default() must have title_dirty == false.
    fn terminal_meta_default_title_dirty_false() {
        assert!(!TerminalMeta::default().title_dirty);
    }

    #[test]
    // CONSTRUCTION: TerminalMeta::default() must have bell_pending == false.
    fn terminal_meta_default_bell_pending_false() {
        assert!(!TerminalMeta::default().bell_pending);
    }

    #[test]
    // CONSTRUCTION: TerminalMeta::default() must have empty pending_responses.
    fn terminal_meta_default_pending_responses_empty() {
        assert!(TerminalMeta::default().pending_responses.is_empty());
    }

    // -------------------------------------------------------------------------
    // Mutation invariants
    // -------------------------------------------------------------------------

    #[test]
    // MUTATION: Setting title stores the string and sets title_dirty.
    fn terminal_meta_set_title_and_dirty() {
        let m = TerminalMeta {
            title: "xterm-kitty".to_owned(),
            title_dirty: true,
            ..Default::default()
        };
        assert_eq!(m.title, "xterm-kitty");
        assert!(m.title_dirty);
    }

    #[test]
    // MUTATION: Setting bell_pending to true persists through a round-trip.
    fn terminal_meta_bell_pending_set_round_trip() {
        let mut m = TerminalMeta {
            bell_pending: true,
            ..Default::default()
        };
        assert!(m.bell_pending);
        m.bell_pending = false;
        assert!(!m.bell_pending);
    }

    #[test]
    // MUTATION: Pushing multiple responses preserves count and content.
    fn terminal_meta_push_multiple_responses_count_and_content() {
        let mut m = TerminalMeta::default();
        m.pending_responses.push(b"\x1b[?1;0c".to_vec()); // DA1 reply
        m.pending_responses.push(b"\x1b[>0;10;1c".to_vec()); // DA2 reply
        assert_eq!(m.pending_responses.len(), 2);
        assert_eq!(m.pending_responses[0], b"\x1b[?1;0c");
        assert_eq!(m.pending_responses[1], b"\x1b[>0;10;1c");
    }

    #[test]
    // MUTATION: Draining pending_responses empties the vec.
    fn terminal_meta_drain_responses_empties_vec() {
        let mut m = TerminalMeta::default();
        m.pending_responses.push(b"r1".to_vec());
        m.pending_responses.push(b"r2".to_vec());
        let drained: Vec<_> = m.pending_responses.drain(..).collect();
        assert_eq!(drained.len(), 2);
        assert!(m.pending_responses.is_empty());
    }

    #[test]
    // MUTATION: DcsState::default() is DcsState::Idle.
    fn terminal_meta_dcs_state_default_is_idle() {
        let m = TerminalMeta::default();
        assert!(matches!(m.dcs_state, DcsState::Idle));
    }
}
