//! APC (Application Program Command) pre-scanner for Kitty Graphics Protocol

use crate::parser::limits::MAX_APC_PAYLOAD_BYTES;
use crate::TerminalCore;

/// State machine for raw APC byte-stream pre-scanning.
///
/// vte 0.15.0 routes ESC _ to `SosPmApcString` which silently discards bytes,
/// so we scan the raw byte stream ourselves.
/// The payload buffer is stored separately in `TerminalCore::apc_buf` to avoid
/// per-byte heap moves through the state machine.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum ApcScanState {
    /// Not in an APC sequence
    Idle,
    /// Saw ESC, waiting to see if next byte is '_' (APC start)
    AfterEsc,
    /// Inside an APC payload (ESC _ received); accumulating bytes in `apc_buf`
    InApc,
    /// Inside APC, saw ESC — waiting to see if next byte is '\\' (ST = String Terminator)
    AfterApcEsc,
}

/// Run the APC pre-scanner and advance the VTE parser.
///
/// This uses a hybrid approach for APC (Kitty Graphics) handling:
/// 1. Fast path: If no ESC byte (0x1B) is present AND we're not in an APC sequence,
///    skip the APC pre-scanner entirely (contains-based fast-path check)
/// 2. Slow path: Run the APC state machine only when ESC is detected or we're mid-sequence
/// 3. Always run the vte parser for all other terminal sequences
pub(crate) fn advance_with_apc(core: &mut TerminalCore, bytes: &[u8]) {
    // --- Hybrid APC pre-scanner for Kitty Graphics ---
    // Only run the byte-by-byte scanner if:
    // 1. There's an ESC byte in the buffer (detected via bytes.contains()), OR
    // 2. We're already in the middle of an APC sequence
    //
    // This optimization provides 2-4x throughput improvement for plain text
    // (no escape sequences) which is common in typical terminal output.
    let has_esc = bytes.contains(&0x1B);
    let in_apc_sequence = core.kitty.apc_state != ApcScanState::Idle;

    // Quick bail-out: when starting Idle and the buffer contains no '_' byte,
    // no APC start sequence (ESC _) can exist, so skip the byte-by-byte
    // scanner entirely.  This is the common case for CSI/OSC-heavy TUI output
    // where ESC bytes are frequent but APC sequences are absent.
    if in_apc_sequence || (has_esc && bytes.contains(&b'_')) {
        for &byte in bytes {
            match (core.kitty.apc_state, byte) {
                // Idle: watch for ESC
                (ApcScanState::Idle, 0x1B) => {
                    core.kitty.apc_state = ApcScanState::AfterEsc;
                }
                (ApcScanState::Idle, _) => {}
                // AfterEsc: ESC + '_' starts APC; anything else resets
                (ApcScanState::AfterEsc, b'_') => {
                    core.kitty.apc_buf.clear();
                    core.kitty.apc_state = ApcScanState::InApc;
                }
                (ApcScanState::AfterEsc, _) => {
                    core.kitty.apc_state = ApcScanState::Idle;
                }
                // InApc: accumulate bytes (with size cap); ESC may be start of ST
                (ApcScanState::InApc, 0x1B) => {
                    core.kitty.apc_state = ApcScanState::AfterApcEsc;
                }
                (ApcScanState::InApc, b) => {
                    if core.kitty.apc_buf.len() < MAX_APC_PAYLOAD_BYTES {
                        core.kitty.apc_buf.push(b);
                    }
                    // If over limit, keep state but drop byte (truncate silently)
                }
                // AfterApcEsc: '\\' completes the APC (ESC \\ = ST); else keep accumulating
                (ApcScanState::AfterApcEsc, b'\\') => {
                    // APC complete — dispatch if it starts with 'G' (Kitty Graphics)
                    if core.kitty.apc_buf.first() == Some(&b'G') {
                        let payload = core.kitty.apc_buf[1..].to_vec();
                        dispatch_kitty_apc(core, &payload);
                    }
                    core.kitty.apc_buf.clear();
                    core.kitty.apc_state = ApcScanState::Idle;
                }
                (ApcScanState::AfterApcEsc, b) => {
                    // False ESC — add ESC + this byte back and stay in InApc
                    if core.kitty.apc_buf.len() + 2 <= MAX_APC_PAYLOAD_BYTES {
                        core.kitty.apc_buf.push(0x1B);
                        core.kitty.apc_buf.push(b);
                    }
                    core.kitty.apc_state = ApcScanState::InApc;
                }
            }
        }
    }

    // --- ASCII fast-path + vte parser ---
    // When the VTE parser is known to be in Ground state, scan for contiguous
    // runs of printable ASCII bytes (0x20-0x7E) and handle them directly via
    // Screen::print_ascii_run(), bypassing VTE's per-byte state machine dispatch.
    // Only non-ASCII or escape-containing segments are forwarded to VTE.
    let mut pos = 0;

    // ASCII fast-path: scan for printable ASCII run at start of buffer
    if core.parser_in_ground {
        while pos < bytes.len() && bytes[pos] >= 0x20 && bytes[pos] <= 0x7E {
            pos += 1;
        }
        if pos > 0 {
            core.screen.print_ascii_run(
                &bytes[..pos],
                core.current_attrs,
                core.dec_modes.auto_wrap,
            );
            // After printing ASCII, parser is still in Ground (we didn't touch VTE)
        }
    }

    // Feed remaining bytes (if any) to VTE
    if pos < bytes.len() {
        core.vte_callback_count = 0;
        core.vte_last_ground = false;

        let mut parser = core.parser.take().expect("parser must be present");
        parser.advance(core, &bytes[pos..]);
        core.parser = Some(parser);

        // Flush any remaining buffered ASCII from VTE print() callbacks
        core.flush_print_buf();

        // Update Ground-state tracking based on VTE callback observations
        if core.vte_callback_count == 0 {
            // VTE processed bytes without dispatching — mid-sequence
            core.parser_in_ground = false;
        } else {
            core.parser_in_ground = core.vte_last_ground;
        }
    }
    // If pos == bytes.len(), entire buffer was ASCII — parser_in_ground stays true
}

#[cfg(test)]
#[path = "tests/apc.rs"]
mod tests;

/// Dispatch a fully assembled Kitty Graphics APC payload.
///
/// `payload` is everything after the leading 'G' byte (i.e., the key=value header
/// and optional base64 data, separated by ';').
pub(crate) fn dispatch_kitty_apc(core: &mut TerminalCore, payload: &[u8]) {
    use crate::grid::screen::{ImageData, ImagePlacement};
    use crate::parser::kitty::{process_apc_payload, KittyCommand};

    let Some(cmd) = process_apc_payload(payload, &mut core.kitty.kitty_chunk) else {
        return; // more chunks incoming, or malformed
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
                core.kitty.pending_image_notifications.push(notif);
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
                core.kitty.pending_image_notifications.push(notif);
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
            let id_part = image_id.map(|id| format!(",i={id}")).unwrap_or_default();
            let response = format!("\x1b_Ga=q{id_part};OK\x1b\\");
            core.meta.pending_responses.push(response.into_bytes());
        }
    }
}
