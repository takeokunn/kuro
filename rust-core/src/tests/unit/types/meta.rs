//! Example-based and structural tests for `types::meta::TerminalMeta`.
//!
//! Module under test: `src/types/meta.rs`
//! Tier: T5 — ProptestConfig::with_cases(64)
//!
//! Field inventory (verified from source):
//!   title: String                (pub(crate))
//!   title_dirty: bool            (pub(crate))
//!   bell_pending: bool           (pub(crate))
//!   pending_responses: Vec<Vec<u8>>  (pub(crate))
//!   dcs_state: DcsState          (pub(crate)) — Default yields DcsState::Idle

use crate::types::meta::TerminalMeta;
use proptest::prelude::*;

// ---------------------------------------------------------------------------
// Default state invariants
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: TerminalMeta::default() has empty title
fn test_terminal_meta_default_title_empty() {
    let m = TerminalMeta::default();
    assert!(m.title.is_empty(), "TerminalMeta default must have empty title");
}

#[test]
// INVARIANT: TerminalMeta::default() has title_dirty == false
fn test_terminal_meta_default_title_not_dirty() {
    let m = TerminalMeta::default();
    assert!(!m.title_dirty, "TerminalMeta default must have title_dirty == false");
}

#[test]
// INVARIANT: TerminalMeta::default() has bell_pending == false
fn test_terminal_meta_default_no_bell() {
    let m = TerminalMeta::default();
    assert!(!m.bell_pending, "TerminalMeta default must have bell_pending == false");
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

// ---------------------------------------------------------------------------
// Mutation invariants
// ---------------------------------------------------------------------------

#[test]
// MUTATION: Setting bell_pending to true persists
fn test_terminal_meta_bell_set_persists() {
    let mut m = TerminalMeta::default();
    m.bell_pending = true;
    assert!(m.bell_pending, "bell_pending must persist after being set to true");
}

#[test]
// MUTATION: Clearing bell_pending back to false persists
fn test_terminal_meta_bell_clear_persists() {
    let mut m = TerminalMeta::default();
    m.bell_pending = true;
    m.bell_pending = false;
    assert!(!m.bell_pending, "bell_pending must persist after being cleared");
}

#[test]
// MUTATION: Setting title and title_dirty persists
fn test_terminal_meta_title_set_persists() {
    let mut m = TerminalMeta::default();
    m.title = "my terminal".to_string();
    m.title_dirty = true;
    assert_eq!(m.title, "my terminal");
    assert!(m.title_dirty);
}

#[test]
// MUTATION: Clearing title_dirty after reading persists
fn test_terminal_meta_title_dirty_clear() {
    let mut m = TerminalMeta::default();
    m.title = "test".to_string();
    m.title_dirty = true;
    m.title_dirty = false;
    assert!(!m.title_dirty, "title_dirty must persist as false after clear");
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
    let drained: Vec<Vec<u8>> = m.pending_responses.drain(..).collect();
    assert_eq!(drained.len(), 2);
    assert!(m.pending_responses.is_empty());
}

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
        let mut m = TerminalMeta::default();
        m.title = s.clone();
        prop_assert_eq!(&m.title, &s);
    }

    #[test]
    // INVARIANT: pending_responses length matches number of pushes
    fn prop_terminal_meta_response_count(count in 0usize..=16usize) {
        let mut m = TerminalMeta::default();
        for i in 0..count {
            m.pending_responses.push(vec![i as u8]);
        }
        prop_assert_eq!(m.pending_responses.len(), count);
    }
}
