// ── iTerm2 OSC 1337 helpers ───────────────────────────────────────────────────

use crate::TerminalCore;

/// Parsed key=value parameters from an iTerm2 `File=…` header.
pub(crate) struct Iterm2Params {
    /// `inline=1` — render image inline in the terminal.
    pub(crate) inline: bool,
    /// Requested display width in terminal columns (`width=N`); `None` means auto.
    pub(crate) display_cols: Option<u32>,
    /// Requested display height in terminal rows (`height=N`); `None` means auto.
    pub(crate) display_rows: Option<u32>,
}

/// Parse the semicolon-separated `key=value` string that precedes the `:` separator
/// in an iTerm2 `File=…` payload.
///
/// Unknown keys are silently ignored. Width/height suffixes (`px`, `%`) are stripped
/// before numeric parsing; `0` or unparseable values leave the field as `None`.
pub(crate) fn parse_iterm2_params(param_str: &str) -> Iterm2Params {
    let mut inline = false;
    let mut display_cols: Option<u32> = None;
    let mut display_rows: Option<u32> = None;

    for kv in param_str.split(';') {
        if let Some(v) = kv.strip_prefix("inline=") {
            inline = v == "1";
        } else if let Some(v) = kv.strip_prefix("width=") {
            let n: u32 = v
                .trim_end_matches("px")
                .trim_end_matches('%')
                .parse()
                .unwrap_or(0);
            if n > 0 {
                display_cols = Some(n);
            }
        } else if let Some(v) = kv.strip_prefix("height=") {
            let n: u32 = v
                .trim_end_matches("px")
                .trim_end_matches('%')
                .parse()
                .unwrap_or(0);
            if n > 0 {
                display_rows = Some(n);
            }
        }
    }

    Iterm2Params {
        inline,
        display_cols,
        display_rows,
    }
}

/// Decode base64-encoded image data and return `(rgba_pixels, width, height)`.
///
/// Attempts PNG decoding first; on success converts RGB frames to RGBA.
/// Returns `None` if `b64_data` is empty, base64-invalid, or not a valid PNG.
pub(crate) fn decode_iterm2_image(b64_data: &str) -> Option<(Vec<u8>, u32, u32)> {
    if b64_data.is_empty() {
        return None;
    }
    let raw = crate::util::base64::decode(b64_data.trim().as_bytes()).ok()?;

    use crate::parser::kitty::ImageFormat;
    let decoder = png::Decoder::new(std::io::Cursor::new(&raw));
    decoder.read_info().ok().and_then(|mut reader| {
        let mut buf = vec![0u8; reader.output_buffer_size()];
        reader.next_frame(&mut buf).ok().map(|info| {
            buf.truncate(info.buffer_size());
            let fmt = match info.color_type {
                png::ColorType::Rgba => ImageFormat::Rgba,
                _ => ImageFormat::Rgb,
            };
            let w = info.width;
            let h = info.height;
            // Convert RGB → RGBA
            let pixels = if fmt == ImageFormat::Rgb {
                buf.chunks(3)
                    .flat_map(|p| [p[0], p[1], p[2], 255])
                    .collect()
            } else {
                buf
            };
            (pixels, w, h)
        })
    })
}

/// Handle OSC 1337 — iTerm2 inline images.
pub(crate) fn handle_osc_1337(core: &mut TerminalCore, params: &[&[u8]]) {
    let rest = params
        .get(1)
        .and_then(|raw| std::str::from_utf8(raw).ok())
        .unwrap_or("");
    let Some(stripped) = rest.strip_prefix("File=") else {
        return;
    };
    let Some(colon_pos) = stripped.find(':') else {
        return;
    };
    let param_str = &stripped[..colon_pos];
    let b64_data = &stripped[colon_pos + 1..];

    let p = parse_iterm2_params(param_str);
    if !p.inline {
        return;
    }

    let Some((pixels, pw, ph)) = decode_iterm2_image(b64_data) else {
        return;
    };

    use crate::grid::screen::{ImageData, ImagePlacement};
    use crate::parser::kitty::ImageFormat;

    let cols = p.display_cols.unwrap_or_else(|| pw.div_ceil(8)).max(1);
    let rows = p.display_rows.unwrap_or_else(|| ph.div_ceil(16)).max(1);

    let data = ImageData::new(pixels, ImageFormat::Rgba, pw, ph);
    let actual_id = core.screen.active_graphics_mut().store_image(None, data);
    let cursor = *core.screen.cursor();
    let placement = ImagePlacement {
        image_id: actual_id,
        placement_id: None,
        row: cursor.row,
        col: cursor.col,
        display_cols: cols,
        display_rows: rows,
    };
    if let Some(notif) = core.screen.active_graphics_mut().add_placement(placement) {
        core.kitty.pending_image_notifications.push(notif);
    }
    // Advance cursor past the image
    let max_row = (core.screen.rows() as usize).saturating_sub(1);
    let new_row = cursor.row.saturating_add(rows as usize).min(max_row);
    core.screen.move_cursor(new_row, 0);
}
