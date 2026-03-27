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
}
