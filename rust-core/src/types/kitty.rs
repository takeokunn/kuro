//! Kitty Graphics Protocol state

use crate::grid::screen::ImageNotification;
use crate::parser::apc::ApcScanState;
use crate::parser::kitty::KittyChunkState;

/// Grouped state for Kitty Graphics Protocol handling.
pub(crate) struct KittyState {
    /// APC byte-stream state machine for Kitty Graphics pre-scanning
    pub(crate) apc_state: ApcScanState,
    /// Accumulation buffer for the current APC payload (cleared on each new APC)
    pub(crate) apc_buf: Vec<u8>,
    /// Accumulated chunk state for multi-chunk Kitty image transfers (m=1)
    pub(crate) kitty_chunk: Option<KittyChunkState>,
    /// Image placement notifications waiting to be sent to Elisp
    pub(crate) pending_image_notifications: Vec<ImageNotification>,
}

impl Default for KittyState {
    fn default() -> Self {
        Self {
            apc_state: ApcScanState::Idle,
            apc_buf: Vec::new(),
            kitty_chunk: None,
            pending_image_notifications: Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // -------------------------------------------------------------------------
    // Default-state invariants
    // -------------------------------------------------------------------------

    #[test]
    // CONSTRUCTION: KittyState::default() must start in ApcScanState::Idle.
    fn kitty_state_default_apc_is_idle() {
        assert!(matches!(
            KittyState::default().apc_state,
            ApcScanState::Idle
        ));
    }

    #[test]
    // CONSTRUCTION: KittyState::default() must have an empty apc_buf.
    fn kitty_state_default_apc_buf_empty() {
        assert!(KittyState::default().apc_buf.is_empty());
    }

    #[test]
    // CONSTRUCTION: KittyState::default() must have kitty_chunk == None.
    fn kitty_state_default_kitty_chunk_none() {
        assert!(KittyState::default().kitty_chunk.is_none());
    }

    #[test]
    // CONSTRUCTION: KittyState::default() must have no pending notifications.
    fn kitty_state_default_pending_notifications_empty() {
        assert!(KittyState::default().pending_image_notifications.is_empty());
    }

    // -------------------------------------------------------------------------
    // Mutation invariants
    // -------------------------------------------------------------------------

    #[test]
    // MUTATION: pushing bytes into apc_buf stores them in order.
    fn kitty_state_apc_buf_push_stores_bytes() {
        let mut ks = KittyState::default();
        ks.apc_buf.extend_from_slice(b"hello");
        assert_eq!(ks.apc_buf, b"hello");
    }

    #[test]
    // MUTATION: clearing apc_buf after push restores empty state.
    fn kitty_state_apc_buf_clear_restores_empty() {
        let mut ks = KittyState::default();
        ks.apc_buf.extend_from_slice(b"data");
        ks.apc_buf.clear();
        assert!(ks.apc_buf.is_empty());
    }

    #[test]
    // STATE TRANSITION: transitioning apc_state from Idle to AfterEsc persists.
    fn kitty_state_apc_state_transition_idle_to_after_esc() {
        let ks = KittyState {
            apc_state: ApcScanState::AfterEsc,
            ..Default::default()
        };
        assert!(matches!(ks.apc_state, ApcScanState::AfterEsc));
    }

    #[test]
    // STATE TRANSITION: transitioning apc_state back to Idle from InApc persists.
    fn kitty_state_apc_state_transition_in_apc_to_idle() {
        let mut ks = KittyState {
            apc_state: ApcScanState::InApc,
            ..Default::default()
        };
        ks.apc_state = ApcScanState::Idle;
        assert!(matches!(ks.apc_state, ApcScanState::Idle));
    }

    // -------------------------------------------------------------------------
    // Merged from tests/unit/types/kitty.rs
    // -------------------------------------------------------------------------

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

    mod pbt {
        use super::*;
        use proptest::prelude::*;

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
    }
}
