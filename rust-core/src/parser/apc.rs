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

pub(crate) fn advance_with_apc(core: &mut TerminalCore, bytes: &[u8]) {
    // --- Hybrid APC pre-scanner for Kitty Graphics ---
    // Only run the byte-by-byte scanner if:
    // 1. There's an ESC byte in the buffer (detected via bytes.contains()), OR
    // 2. We're already in the middle of an APC sequence
    //
    // This optimization provides 2-4x throughput improvement for plain text
    // (no escape sequences) which is common in typical terminal output.
    if should_scan_apc_bytes(core, bytes) {
        scan_apc_bytes(core, bytes);
    }

    // --- ASCII fast-path + vte parser ---
    // When the VTE parser is known to be in Ground state, scan for contiguous
    // runs of printable ASCII bytes (0x20-0x7E) and handle them directly via
    // Screen::print_ascii_run(), bypassing VTE's per-byte state machine dispatch.
    // Only non-ASCII or escape-containing segments are forwarded to VTE.
    let pos = advance_ascii_fast_path(core, bytes);

    // Feed remaining bytes (if any) to VTE
    advance_vte_parser(core, bytes, pos);
    // If pos == bytes.len(), entire buffer was ASCII — parser_in_ground stays true
}

fn should_scan_apc_bytes(core: &TerminalCore, bytes: &[u8]) -> bool {
    let has_esc = bytes.contains(&0x1B);
    let in_apc_sequence = core.kitty.apc_state != ApcScanState::Idle;

    in_apc_sequence || (has_esc && bytes.contains(&b'_'))
}

fn scan_apc_bytes(core: &mut TerminalCore, bytes: &[u8]) {
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
                // APC complete — dispatch if it starts with 'G' (Kitty Graphics).
                // Take the buffer out to avoid copying potentially-large image payloads;
                // core.kitty.apc_buf becomes an empty Vec (retains capacity on return).
                let mut buf = std::mem::take(&mut core.kitty.apc_buf);
                if buf.first() == Some(&b'G') {
                    dispatch_kitty_apc(core, &buf[1..]);
                }
                buf.clear();
                core.kitty.apc_buf = buf; // return capacity to the pool
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

fn advance_ascii_fast_path(core: &mut TerminalCore, bytes: &[u8]) -> usize {
    if core.parser_in_ground
        && core.active_charset() == crate::types::charset::CharsetType::Ascii
        && !core.dec_modes.insert_mode
    {
        let mut pos = 0;
        while pos < bytes.len() && bytes[pos] >= 0x20 && bytes[pos] <= 0x7E {
            pos += 1;
        }
        if pos > 0 {
            // Track last char for REP (CSI Ps b) — fast-path bypasses VTE print().
            core.last_printed_char = bytes[..pos].last().map(|&b| b as char);
            core.screen.print_ascii_run(
                &bytes[..pos],
                core.current_attrs,
                core.dec_modes.auto_wrap,
            );
            // Stamp hyperlink on the cells just written (if active)
            if core.osc_data.hyperlink.uri.is_some() {
                core.stamp_hyperlink_on_last_n_cells(pos);
            }
        }
        pos
    } else {
        0
    }
}

fn advance_vte_parser(core: &mut TerminalCore, bytes: &[u8], pos: usize) {
    if pos >= bytes.len() {
        return;
    }

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
fn build_kitty_image_data(
    pixels: Vec<u8>,
    format: crate::parser::kitty::ImageFormat,
    pixel_width: u32,
    pixel_height: u32,
) -> crate::grid::screen::ImageData {
    crate::grid::screen::ImageData::new(pixels, format, pixel_width, pixel_height)
}

#[expect(
    clippy::too_many_arguments,
    reason = "mirrors the kitty placement key set (geometry + z + pixel offsets); a struct adds indirection without clarity"
)]
fn build_kitty_image_placement(
    cursor: crate::types::cursor::Cursor,
    image_id: u32,
    placement_id: Option<u32>,
    columns: Option<u32>,
    rows: Option<u32>,
    z_index: i32,
    pixel_x_offset: u32,
    pixel_y_offset: u32,
) -> crate::grid::screen::ImagePlacement {
    crate::grid::screen::ImagePlacement {
        image_id,
        placement_id,
        row: cursor.row,
        col: cursor.col,
        display_cols: columns.unwrap_or(1),
        display_rows: rows.unwrap_or(1),
        z_index,
        pixel_x_offset,
        pixel_y_offset,
    }
}

fn store_kitty_image(
    core: &mut TerminalCore,
    image_id: Option<u32>,
    pixels: Vec<u8>,
    format: crate::parser::kitty::ImageFormat,
    pixel_width: u32,
    pixel_height: u32,
) -> u32 {
    let data = build_kitty_image_data(pixels, format, pixel_width, pixel_height);
    core.screen
        .active_graphics_mut()
        .store_image(image_id, data)
}

fn add_kitty_placement(core: &mut TerminalCore, placement: crate::grid::screen::ImagePlacement) {
    if let Some(notif) = core.screen.active_graphics_mut().add_placement(placement) {
        core.kitty.pending_image_notifications.push(notif);
    }
}

#[expect(
    clippy::too_many_arguments,
    reason = "mirrors the kitty placement key set (geometry + z + pixel offsets)"
)]
fn add_kitty_image_placement(
    core: &mut TerminalCore,
    image_id: u32,
    placement_id: Option<u32>,
    columns: Option<u32>,
    rows: Option<u32>,
    z_index: i32,
    pixel_x_offset: u32,
    pixel_y_offset: u32,
) {
    let cursor = *core.screen.cursor();
    let placement = build_kitty_image_placement(
        cursor,
        image_id,
        placement_id,
        columns,
        rows,
        z_index,
        pixel_x_offset,
        pixel_y_offset,
    );
    add_kitty_placement(core, placement);
}

fn handle_kitty_transmit(
    core: &mut TerminalCore,
    image_id: Option<u32>,
    pixels: Vec<u8>,
    format: crate::parser::kitty::ImageFormat,
    pixel_width: u32,
    pixel_height: u32,
) {
    let _ = store_kitty_image(core, image_id, pixels, format, pixel_width, pixel_height);
}

#[expect(
    clippy::too_many_arguments,
    reason = "forwards the kitty a=T key set (image data + placement geometry + z + pixel offsets)"
)]
fn handle_kitty_transmit_and_display(
    core: &mut TerminalCore,
    image_id: Option<u32>,
    pixels: Vec<u8>,
    format: crate::parser::kitty::ImageFormat,
    pixel_width: u32,
    pixel_height: u32,
    columns: Option<u32>,
    rows: Option<u32>,
    placement_id: Option<u32>,
    z_index: i32,
    pixel_x_offset: u32,
    pixel_y_offset: u32,
) {
    let actual_id = store_kitty_image(core, image_id, pixels, format, pixel_width, pixel_height);
    add_kitty_image_placement(
        core,
        actual_id,
        placement_id,
        columns,
        rows,
        z_index,
        pixel_x_offset,
        pixel_y_offset,
    );
}

#[expect(
    clippy::too_many_arguments,
    reason = "forwards the kitty a=p key set (image + placement geometry + z + pixel offsets)"
)]
fn handle_kitty_place(
    core: &mut TerminalCore,
    image_id: u32,
    placement_id: Option<u32>,
    columns: Option<u32>,
    rows: Option<u32>,
    z_index: i32,
    pixel_x_offset: u32,
    pixel_y_offset: u32,
) {
    add_kitty_image_placement(
        core,
        image_id,
        placement_id,
        columns,
        rows,
        z_index,
        pixel_x_offset,
        pixel_y_offset,
    );
}

#[expect(
    clippy::too_many_arguments,
    reason = "mirrors the full kitty a=d key set; threading a struct adds indirection"
)]
fn handle_kitty_delete(
    core: &mut TerminalCore,
    delete_sub: char,
    image_id: Option<u32>,
    placement_id: Option<u32>,
    image_number: Option<u32>,
    cell_col: u32,
    cell_row: u32,
    z_index: i32,
) {
    let cursor = *core.screen.cursor();
    let graphics = core.screen.active_graphics_mut();

    // Uppercase delete targets ALSO free the backing image data, not just the
    // placement(s). Lowercase drops placements only.
    let free_data = delete_sub.is_ascii_uppercase();

    match delete_sub.to_ascii_lowercase() {
        // a: all visible placements.
        'a' => graphics.delete_all(free_data),
        // i: by image id (i=).
        'i' => {
            if let Some(id) = image_id {
                graphics.delete_id(id, free_data);
            }
        }
        // n: newest by image number (I=); no number → most recently stored.
        'n' => graphics.delete_newest(image_number, free_data),
        // c: at cursor cell.
        'c' => graphics.delete_at_cursor(cursor.row, cursor.col, free_data),
        // p: at cell (x=,y=). With both id and placement id present this also
        // covers the targeted-placement case (a=d,p=).
        'p' => {
            if let (Some(id), Some(pid)) = (image_id, placement_id) {
                graphics.delete_by_placement(id, pid);
            } else {
                graphics.delete_at_cell(cell_row as usize, cell_col as usize, free_data);
            }
        }
        // q: at cell with z (x=,y=,z=).
        'q' => {
            graphics.delete_at_cell_with_z(
                cell_row as usize,
                cell_col as usize,
                z_index,
                free_data,
            );
        }
        // x: intersecting column (x=).
        'x' => graphics.delete_intersecting_col(cell_col as usize, free_data),
        // y: intersecting row (y=).
        'y' => graphics.delete_intersecting_row(cell_row as usize, free_data),
        // z: by z-index (z=).
        'z' => graphics.delete_by_z(z_index, free_data),
        // r: id range (x=min, y=max).
        'r' => graphics.delete_id_range(cell_col, cell_row, free_data),
        _ => {}
    }
}

fn notify_image_redisplay(core: &mut TerminalCore, image_id: u32) {
    let notifs = core
        .screen
        .active_graphics()
        .notifications_for_image(image_id);
    core.kitty.pending_image_notifications.extend(notifs);
}

#[expect(
    clippy::too_many_arguments,
    reason = "forwards the kitty a=f key set to GraphicsStore::add_frame"
)]
fn handle_kitty_frame(
    core: &mut TerminalCore,
    image_id: Option<u32>,
    pixels: Vec<u8>,
    format: crate::parser::kitty::ImageFormat,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    base_frame: Option<u32>,
    edit_frame: Option<u32>,
    bg_color: u32,
    replace: bool,
    gap: Option<i32>,
) {
    // a=f requires a target image id; ignore frames with no addressable image.
    let Some(id) = image_id else {
        return;
    };
    // z=0 and negative gaps mean "no/gapless delay" per the kitty spec → clamp to 0.
    let gap_ms = gap.filter(|&g| g > 0).map_or(0, |g| g.unsigned_abs());
    let applied = core.screen.active_graphics_mut().add_frame(
        id, &pixels, format, x, y, width, height, base_frame, edit_frame, bg_color, replace, gap_ms,
    );
    if applied.is_some() {
        notify_image_redisplay(core, id);
    }
}

fn handle_kitty_animation_control(
    core: &mut TerminalCore,
    image_id: Option<u32>,
    state: Option<u32>,
    loop_count: Option<u32>,
    current_frame: Option<u32>,
) {
    let Some(id) = image_id else {
        return;
    };
    if core
        .screen
        .active_graphics_mut()
        .set_animation(id, state, loop_count, current_frame)
    {
        // current_frame change repaints; emit a redisplay so Emacs picks it up.
        if current_frame.is_some() {
            notify_image_redisplay(core, id);
        }
    }
}

fn handle_kitty_query(core: &mut TerminalCore, image_id: Option<u32>) {
    let id_part = image_id.map(|id| format!(",i={id}")).unwrap_or_default();
    let response = format!("\x1b_Ga=q{id_part};OK\x1b\\");
    core.meta.pending_responses.push(response.into_bytes());
}

#[cfg(test)]
#[path = "tests/apc.rs"]
mod tests;

pub(crate) fn dispatch_kitty_apc(core: &mut TerminalCore, payload: &[u8]) {
    use crate::parser::kitty::{process_apc_payload, KittyCommand};

    let Some(cmd) = process_apc_payload(payload, &mut core.kitty.kitty_chunk) else {
        return;
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
            handle_kitty_transmit(core, image_id, pixels, format, pixel_width, pixel_height);
        }
        KittyCommand::TransmitAndDisplay {
            image_id,
            pixels,
            format,
            pixel_width,
            pixel_height,
            columns,
            rows,
            placement_id,
            z_index,
            pixel_x_offset,
            pixel_y_offset,
        } => {
            handle_kitty_transmit_and_display(
                core,
                image_id,
                pixels,
                format,
                pixel_width,
                pixel_height,
                columns,
                rows,
                placement_id,
                z_index,
                pixel_x_offset,
                pixel_y_offset,
            );
        }
        KittyCommand::Place {
            image_id,
            placement_id,
            columns,
            rows,
            z_index,
            pixel_x_offset,
            pixel_y_offset,
        } => {
            handle_kitty_place(
                core,
                image_id,
                placement_id,
                columns,
                rows,
                z_index,
                pixel_x_offset,
                pixel_y_offset,
            );
        }
        KittyCommand::Delete {
            delete_sub,
            image_id,
            placement_id,
            image_number,
            cell_col,
            cell_row,
            z_index,
        } => {
            handle_kitty_delete(
                core,
                delete_sub,
                image_id,
                placement_id,
                image_number,
                cell_col,
                cell_row,
                z_index,
            );
        }
        KittyCommand::Query { image_id } => {
            handle_kitty_query(core, image_id);
        }
        KittyCommand::Frame {
            image_id,
            pixels,
            format,
            x,
            y,
            width,
            height,
            base_frame,
            edit_frame,
            bg_color,
            replace,
            gap,
        } => {
            handle_kitty_frame(
                core, image_id, pixels, format, x, y, width, height, base_frame, edit_frame,
                bg_color, replace, gap,
            );
        }
        KittyCommand::AnimationControl {
            image_id,
            state,
            loop_count,
            current_frame,
        } => {
            handle_kitty_animation_control(core, image_id, state, loop_count, current_frame);
        }
    }
}
