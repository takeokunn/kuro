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
        let drained_count = m.pending_responses.drain(..).count();
        assert_eq!(drained_count, 2);
        assert!(m.pending_responses.is_empty());
    }

    #[test]
    // MUTATION: DcsState::default() is DcsState::Idle.
    fn terminal_meta_dcs_state_default_is_idle() {
        let m = TerminalMeta::default();
        assert!(matches!(m.dcs_state, DcsState::Idle));
    }

    // -------------------------------------------------------------------------
    // Merged from tests/unit/types/meta.rs
    // -------------------------------------------------------------------------

    #[test]
    // INVARIANT: TerminalMeta::default() has empty title
    fn test_terminal_meta_default_title_empty() {
        let m = TerminalMeta::default();
        assert!(
            m.title.is_empty(),
            "TerminalMeta default must have empty title"
        );
    }

    #[test]
    // INVARIANT: TerminalMeta::default() has title_dirty == false
    fn test_terminal_meta_default_title_not_dirty() {
        let m = TerminalMeta::default();
        assert!(
            !m.title_dirty,
            "TerminalMeta default must have title_dirty == false"
        );
    }

    #[test]
    // INVARIANT: TerminalMeta::default() has bell_pending == false
    fn test_terminal_meta_default_no_bell() {
        let m = TerminalMeta::default();
        assert!(
            !m.bell_pending,
            "TerminalMeta default must have bell_pending == false"
        );
    }

    #[test]
    // INVARIANT: TerminalMeta::default() has empty pending_responses
    fn test_terminal_meta_default_pending_empty() {
        let m = TerminalMeta::default();
        assert!(
            m.pending_responses.is_empty(),
            "TerminalMeta default must have empty pending_responses"
        );
    }

    #[test]
    // MUTATION: Setting bell_pending to true persists
    fn test_terminal_meta_bell_set_persists() {
        let m = TerminalMeta {
            bell_pending: true,
            ..Default::default()
        };
        assert!(
            m.bell_pending,
            "bell_pending must persist after being set to true"
        );
    }

    #[test]
    // MUTATION: Clearing bell_pending back to false persists
    fn test_terminal_meta_bell_clear_persists() {
        let mut m = TerminalMeta {
            bell_pending: true,
            ..Default::default()
        };
        m.bell_pending = false;
        assert!(
            !m.bell_pending,
            "bell_pending must persist after being cleared"
        );
    }

    #[test]
    // MUTATION: Setting title and title_dirty persists
    fn test_terminal_meta_title_set_persists() {
        let m = TerminalMeta {
            title: "my terminal".to_owned(),
            title_dirty: true,
            ..Default::default()
        };
        assert_eq!(m.title, "my terminal");
        assert!(m.title_dirty);
    }

    #[test]
    // MUTATION: Clearing title_dirty after reading persists
    fn test_terminal_meta_title_dirty_clear() {
        let mut m = TerminalMeta {
            title: "test".to_owned(),
            title_dirty: true,
            ..Default::default()
        };
        m.title_dirty = false;
        assert!(
            !m.title_dirty,
            "title_dirty must persist as false after clear"
        );
    }

    #[test]
    // MUTATION: pushing to pending_responses persists
    fn test_terminal_meta_push_response_persists() {
        let mut m = TerminalMeta::default();
        m.pending_responses.push(b"reply".to_vec());
        assert_eq!(m.pending_responses.len(), 1);
        assert_eq!(m.pending_responses[0], b"reply");
    }

    #[test]
    // MUTATION: draining pending_responses empties the vec
    fn test_terminal_meta_drain_responses() {
        let mut m = TerminalMeta::default();
        m.pending_responses.push(b"a".to_vec());
        m.pending_responses.push(b"b".to_vec());
        let count = m.pending_responses.drain(..).count();
        assert_eq!(count, 2);
        assert!(m.pending_responses.is_empty());
    }

    mod pbt {
        use super::*;
        use proptest::prelude::*;

        proptest! {
            #![proptest_config(ProptestConfig::with_cases(64))]

            #[test]
            // INVARIANT: Multiple TerminalMeta::default() calls all produce the same empty state
            fn prop_terminal_meta_default_consistent(_seed in 0u64..=1000u64) {
                let m = TerminalMeta::default();
                prop_assert!(m.title.is_empty());
                prop_assert!(!m.title_dirty);
                prop_assert!(!m.bell_pending);
                prop_assert!(m.pending_responses.is_empty());
            }

            #[test]
            // INVARIANT: Any string assigned to title is preserved exactly
            fn prop_terminal_meta_title_roundtrip(s in "[\\x20-\\x7e]{0,128}") {
                let m = TerminalMeta { title: s.clone(), ..Default::default() };
                prop_assert_eq!(&m.title, &s);
            }

            #[test]
            // INVARIANT: pending_responses length matches number of pushes
            fn prop_terminal_meta_response_count(count in 0usize..=16usize) {
                let mut m = TerminalMeta::default();
                for i in 0..count {
                    #[expect(clippy::cast_possible_truncation, reason = "i is 0..=16; always fits in u8")]
                    m.pending_responses.push(vec![i as u8]);
                }
                prop_assert_eq!(m.pending_responses.len(), count);
            }
        }
    }
}
