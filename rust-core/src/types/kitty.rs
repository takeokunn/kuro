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
