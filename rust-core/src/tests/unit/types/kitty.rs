//! Example-based and structural tests for `types::kitty::KittyState`.
//!
//! Module under test: `src/types/kitty.rs`
//! Tier: T5 — ProptestConfig::with_cases(64)
//!
//! Field inventory (verified from source):
//!   apc_state: ApcScanState       (pub(crate))
//!   apc_buf: Vec<u8>              (pub(crate))
//!   kitty_chunk: Option<KittyChunkState>  (pub(crate))
//!   pending_image_notifications: Vec<ImageNotification>  (pub(crate))

use crate::parser::apc::ApcScanState;
use crate::types::kitty::KittyState;
use proptest::prelude::*;

// ---------------------------------------------------------------------------
// Default state invariants
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: KittyState::default() has ApcScanState::Idle
fn test_kitty_state_default_apc_is_idle() {
    let ks = KittyState::default();
    assert!(
        matches!(ks.apc_state, ApcScanState::Idle),
        "KittyState default must have apc_state == Idle"
    );
}

#[test]
// INVARIANT: KittyState::default() has no kitty_chunk
fn test_kitty_state_default_chunk_is_none() {
    let ks = KittyState::default();
    assert!(
        ks.kitty_chunk.is_none(),
        "KittyState default must have kitty_chunk == None"
    );
}

#[test]
// INVARIANT: KittyState::default() has empty pending notifications
fn test_kitty_state_default_notifications_empty() {
    let ks = KittyState::default();
    assert!(
        ks.pending_image_notifications.is_empty(),
        "KittyState default must have empty pending_image_notifications"
    );
}

#[test]
// INVARIANT: KittyState::default() has empty apc_buf
fn test_kitty_state_default_buf_empty() {
    let ks = KittyState::default();
    assert!(
        ks.apc_buf.is_empty(),
        "KittyState default must have empty apc_buf"
    );
}

#[test]
// INVARIANT: apc_state is not AfterEsc, InApc, or AfterApcEsc on default
fn test_kitty_state_default_apc_not_mid_sequence() {
    let ks = KittyState::default();
    assert!(
        !matches!(
            ks.apc_state,
            ApcScanState::AfterEsc | ApcScanState::InApc | ApcScanState::AfterApcEsc
        ),
        "KittyState default must not be in a mid-APC state"
    );
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    // INVARIANT: Multiple KittyState::default() calls all produce the same empty state
    fn prop_kitty_state_default_consistent(_seed in 0u64..=1000u64) {
        let ks = KittyState::default();
        prop_assert!(ks.kitty_chunk.is_none());
        prop_assert!(ks.apc_buf.is_empty());
        prop_assert!(ks.pending_image_notifications.is_empty());
        prop_assert!(matches!(ks.apc_state, ApcScanState::Idle));
    }
}
