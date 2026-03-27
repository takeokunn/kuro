//! Protocol-specific OSC handlers: OSC 52 (clipboard), OSC 104 (palette reset),
//! OSC 133 (prompt marks), OSC 10/11/12 (default colors), OSC 1337 (iTerm2 images).

use base64::Engine as _;

use crate::TerminalCore;

/// Decode a `params` slot as UTF-8, returning `""` on failure.
///
/// Usage: `osc_param_str!(params, 1)` expands to the UTF-8 string at index 1,
/// or `""` if the slot is absent or contains invalid UTF-8.
macro_rules! osc_param_str {
    ($params:expr, $idx:literal) => {
        $params
            .get($idx)
            .and_then(|b| std::str::from_utf8(b).ok())
            .unwrap_or("")
    };
}

/// Encode an RGB triple as `rgb:RRRR/GGGG/BBBB` for OSC query responses.
pub(super) fn encode_color_spec(rgb: [u8; 3]) -> String {
    format!(
        "rgb:{:04x}/{:04x}/{:04x}",
        u16::from(rgb[0]) << 8 | u16::from(rgb[0]),
        u16::from(rgb[1]) << 8 | u16::from(rgb[1]),
        u16::from(rgb[2]) << 8 | u16::from(rgb[2])
    )
}

/// Parse `rgb:RR/GG/BB` or `#RRGGBB` color strings into `[R,G,B]`.
///
/// Supports both xterm-style `rgb:RR/GG/BB` (16-bit per channel, upper 8 bits used)
/// and CSS-style `#RRGGBB` (8-bit per channel).
#[expect(
    clippy::cast_possible_truncation,
    reason = "2-digit hex colors are 0x00..=0xFF; the else branch is only reached when digits ≤ 2, so v fits in u8"
)]
pub(super) fn parse_color_spec(s: &str) -> Option<[u8; 3]> {
    let s = s.trim();
    if let Some(rest) = s.strip_prefix("rgb:") {
        // Format: rgb:RRRR/GGGG/BBBB (4 hex digits per channel) or rgb:RR/GG/BB (2 hex)
        let parts: Vec<&str> = rest.splitn(3, '/').collect();
        if parts.len() != 3 {
            return None;
        }
        let r = u16::from_str_radix(parts[0], 16).ok()?;
        let g = u16::from_str_radix(parts[1], 16).ok()?;
        let b = u16::from_str_radix(parts[2], 16).ok()?;
        // Normalize to 8-bit (take upper 8 bits if 4-digit, else direct if 2-digit)
        let normalize = |v: u16, digits: usize| -> u8 {
            if digits > 2 {
                (v >> 8) as u8
            } else {
                v as u8
            }
        };
        Some([
            normalize(r, parts[0].len()),
            normalize(g, parts[1].len()),
            normalize(b, parts[2].len()),
        ])
    } else if let Some(hex) = s.strip_prefix('#') {
        if hex.len() == 6 {
            let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
            let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
            let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
            Some([r, g, b])
        } else {
            None
        }
    } else {
        None
    }
}

/// Handle OSC 52 — Clipboard access.
pub(crate) fn handle_osc_52(core: &mut TerminalCore, params: &[&[u8]]) {
    if let Some(data_raw) = params.get(2) {
        if data_raw == b"?" {
            core.osc_data
                .clipboard_actions
                .push(crate::types::osc::ClipboardAction::Query);
        } else if data_raw.len() <= 1_048_576 {
            // 1MB cap
            if let Ok(decoded) = base64::engine::general_purpose::STANDARD.decode(data_raw) {
                if let Ok(text) = String::from_utf8(decoded) {
                    core.osc_data
                        .clipboard_actions
                        .push(crate::types::osc::ClipboardAction::Write(text));
                }
            }
        }
    }
}

/// Handle OSC 104 — Reset color palette.
pub(crate) fn handle_osc_104(core: &mut TerminalCore, params: &[&[u8]]) {
    if let Some(idx_raw) = params.get(1) {
        if idx_raw.is_empty() {
            // Reset all palette entries
            for entry in &mut core.osc_data.palette {
                *entry = None;
            }
        } else {
            let idx_str = osc_param_str!(params, 1);
            if let Ok(idx) = idx_str.parse::<usize>() {
                if idx < 256 {
                    core.osc_data.palette[idx] = None;
                }
            }
        }
    } else {
        // No argument: reset all
        for entry in &mut core.osc_data.palette {
            *entry = None;
        }
    }
    core.osc_data.palette_dirty = true;
}

/// Handle OSC 133 — Shell integration prompt marks.
pub(crate) fn handle_osc_133(core: &mut TerminalCore, params: &[&[u8]]) {
    if let Some(mark_raw) = params.get(1) {
        let mark = match mark_raw.first() {
            Some(b'A') => Some(crate::types::osc::PromptMark::PromptStart),
            Some(b'B') => Some(crate::types::osc::PromptMark::PromptEnd),
            Some(b'C') => Some(crate::types::osc::PromptMark::CommandStart),
            Some(b'D') => Some(crate::types::osc::PromptMark::CommandEnd),
            _ => None,
        };
        if let Some(m) = mark {
            let cursor = *core.screen.cursor();
            core.osc_data
                .prompt_marks
                .push(crate::types::osc::PromptMarkEvent {
                    mark: m,
                    row: cursor.row,
                    col: cursor.col,
                });
        }
    }
}

/// Handle OSC 10/11/12 — Set/query default fg/bg/cursor color.
pub(crate) fn handle_osc_default_colors(core: &mut TerminalCore, params: &[&[u8]]) {
    if let Some(spec_raw) = params.get(1) {
        let osc_num = params[0];
        if *spec_raw == b"?" {
            // Query: respond with current color
            let (color_opt, num_str) = match osc_num {
                b"10" => (&core.osc_data.default_fg, "10"),
                b"11" => (&core.osc_data.default_bg, "11"),
                b"12" => (&core.osc_data.cursor_color, "12"),
                _ => return,
            };
            let rgb = match color_opt {
                Some(crate::types::Color::Rgb(r, g, b)) => [*r, *g, *b],
                _ => [128, 128, 128], // default grey if unset
            };
            let resp = format!("\x1b]{};{}\x07", num_str, encode_color_spec(rgb));
            core.meta.pending_responses.push(resp.into_bytes());
        } else {
            let spec = osc_param_str!(params, 1);
            if let Some([r, g, b]) = parse_color_spec(spec) {
                let color = Some(crate::types::Color::Rgb(r, g, b));
                match osc_num {
                    b"10" => core.osc_data.default_fg = color,
                    b"11" => core.osc_data.default_bg = color,
                    b"12" => core.osc_data.cursor_color = color,
                    _ => {}
                }
                core.osc_data.default_colors_dirty = true;
            }
        }
    }
}

#[cfg(test)]
#[path = "tests/osc_protocol.rs"]
mod tests;

// ── iTerm2 OSC 1337 helpers ───────────────────────────────────────────────────

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
    use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
    let raw = BASE64_STANDARD.decode(b64_data.trim()).ok()?;

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
    let rest = osc_param_str!(params, 1);
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

    let data = ImageData {
        pixels,
        format: ImageFormat::Rgba,
        pixel_width: pw,
        pixel_height: ph,
    };
    let actual_id = core.screen.active_graphics_mut().store_image(None, data);
    let cursor = *core.screen.cursor();
    let placement = ImagePlacement {
        image_id: actual_id,
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
