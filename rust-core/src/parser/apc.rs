//! APC (Application Program Command) pre-scanner for Kitty Graphics Protocol

use crate::TerminalCore;
use memchr::memchr;

/// State machine for raw APC byte-stream pre-scanning.
///
/// vte 0.15.0 routes ESC _ to SosPmApcString which silently discards bytes,
/// so we scan the raw byte stream ourselves.
/// The payload buffer is stored separately in `TerminalCore::apc_buf` to avoid
/// per-byte heap moves through the state machine.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum ApcScanState {
    /// Not in an APC sequence
    Idle,
    /// Saw ESC, waiting to see if next byte is '_' (APC start)
    AfterEsc,
    /// Inside an APC payload (ESC _ received); accumulating bytes in apc_buf
    InApc,
    /// Inside APC, saw ESC — waiting to see if next byte is '\\' (ST = String Terminator)
    AfterApcEsc,
}

/// Run the APC pre-scanner and advance the VTE parser.
///
/// This uses a hybrid approach for APC (Kitty Graphics) handling:
/// 1. Fast path: If no ESC byte (0x1B) is present AND we're not in an APC sequence,
///    skip the APC pre-scanner entirely (memchr check is ~10-20x faster than byte-by-byte)
/// 2. Slow path: Run the APC state machine only when ESC is detected or we're mid-sequence
/// 3. Always run the vte parser for all other terminal sequences
pub(crate) fn advance_with_apc(core: &mut TerminalCore, bytes: &[u8]) {
    /// Maximum bytes accumulated in a single APC payload (4 MiB).
    /// Bytes beyond this limit are silently dropped; the sequence is still
    /// dispatched with the truncated payload.
    const MAX_APC_PAYLOAD_BYTES: usize = 4 * 1024 * 1024;

    // --- Hybrid APC pre-scanner for Kitty Graphics ---
    // Only run the byte-by-byte scanner if:
    // 1. There's an ESC byte in the buffer (detected via memchr), OR
    // 2. We're already in the middle of an APC sequence
    //
    // This optimization provides 2-4x throughput improvement for plain text
    // (no escape sequences) which is common in typical terminal output.
    let has_esc = memchr(0x1B, bytes).is_some();
    let in_apc_sequence = core.apc_state != ApcScanState::Idle;

    if has_esc || in_apc_sequence {
        for &byte in bytes {
            match (core.apc_state, byte) {
                // Idle: watch for ESC
                (ApcScanState::Idle, 0x1B) => {
                    core.apc_state = ApcScanState::AfterEsc;
                }
                (ApcScanState::Idle, _) => {}
                // AfterEsc: ESC + '_' starts APC; anything else resets
                (ApcScanState::AfterEsc, b'_') => {
                    core.apc_buf.clear();
                    core.apc_state = ApcScanState::InApc;
                }
                (ApcScanState::AfterEsc, _) => {
                    core.apc_state = ApcScanState::Idle;
                }
                // InApc: accumulate bytes (with size cap); ESC may be start of ST
                (ApcScanState::InApc, 0x1B) => {
                    core.apc_state = ApcScanState::AfterApcEsc;
                }
                (ApcScanState::InApc, b) => {
                    if core.apc_buf.len() < MAX_APC_PAYLOAD_BYTES {
                        core.apc_buf.push(b);
                    }
                    // If over limit, keep state but drop byte (truncate silently)
                }
                // AfterApcEsc: '\\' completes the APC (ESC \\ = ST); else keep accumulating
                (ApcScanState::AfterApcEsc, b'\\') => {
                    // APC complete — dispatch if it starts with 'G' (Kitty Graphics)
                    if core.apc_buf.first() == Some(&b'G') {
                        let payload = core.apc_buf[1..].to_vec();
                        dispatch_kitty_apc(core, &payload);
                    }
                    core.apc_buf.clear();
                    core.apc_state = ApcScanState::Idle;
                }
                (ApcScanState::AfterApcEsc, b) => {
                    // False ESC — add ESC + this byte back and stay in InApc
                    if core.apc_buf.len() + 2 <= MAX_APC_PAYLOAD_BYTES {
                        core.apc_buf.push(0x1B);
                        core.apc_buf.push(b);
                    }
                    core.apc_state = ApcScanState::InApc;
                }
            }
        }
    }

    // --- vte parser for all other sequences ---
    let mut parser = std::mem::replace(&mut core.parser, vte::Parser::new());
    parser.advance(core, bytes);
    core.parser = parser;
}

/// Dispatch a fully assembled Kitty Graphics APC payload.
///
/// `payload` is everything after the leading 'G' byte (i.e., the key=value header
/// and optional base64 data, separated by ';').
pub(crate) fn dispatch_kitty_apc(core: &mut TerminalCore, payload: &[u8]) {
    use crate::grid::screen::{ImageData, ImagePlacement};
    use crate::parser::kitty::{process_apc_payload, KittyCommand};

    let cmd = match process_apc_payload(payload, &mut core.kitty_chunk) {
        Some(cmd) => cmd,
        None => return, // more chunks incoming, or malformed
    };

    match cmd {
        KittyCommand::Transmit {
            image_id,
            pixels,
            format,
            pixel_width,
            pixel_height,
            ..
        } => {
            let data = ImageData {
                pixels,
                format,
                pixel_width,
                pixel_height,
            };
            core.screen
                .active_graphics_mut()
                .store_image(image_id, data);
        }

        KittyCommand::TransmitAndDisplay {
            image_id,
            pixels,
            format,
            pixel_width,
            pixel_height,
            columns,
            rows,
            ..
        } => {
            let data = ImageData {
                pixels,
                format,
                pixel_width,
                pixel_height,
            };
            let actual_id = core
                .screen
                .active_graphics_mut()
                .store_image(image_id, data);
            let cursor = *core.screen.cursor();
            let placement = ImagePlacement {
                image_id: actual_id,
                row: cursor.row,
                col: cursor.col,
                display_cols: columns.unwrap_or(1),
                display_rows: rows.unwrap_or(1),
            };
            if let Some(notif) = core.screen.active_graphics_mut().add_placement(placement) {
                core.pending_image_notifications.push(notif);
            }
        }

        KittyCommand::Place {
            image_id,
            columns,
            rows,
            ..
        } => {
            let cursor = *core.screen.cursor();
            let placement = ImagePlacement {
                image_id,
                row: cursor.row,
                col: cursor.col,
                display_cols: columns.unwrap_or(1),
                display_rows: rows.unwrap_or(1),
            };
            if let Some(notif) = core.screen.active_graphics_mut().add_placement(placement) {
                core.pending_image_notifications.push(notif);
            }
        }

        KittyCommand::Delete {
            delete_sub,
            image_id,
            ..
        } => {
            match delete_sub {
                'a' => core.screen.active_graphics_mut().clear_all_placements(),
                'I' | 'i' => {
                    if let Some(id) = image_id {
                        core.screen.active_graphics_mut().delete_by_id(id);
                    }
                }
                _ => {} // other delete sub-commands not supported in Phase 15
            }
        }

        KittyCommand::Query { image_id } => {
            // Respond with "OK" status using existing pending_responses mechanism
            let id_part = image_id.map(|id| format!(",i={}", id)).unwrap_or_default();
            let response = format!("\x1b_Ga=q{};OK\x1b\\", id_part);
            core.pending_responses.push(response.into_bytes());
        }
    }
}
