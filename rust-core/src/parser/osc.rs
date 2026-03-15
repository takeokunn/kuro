//! OSC (Operating System Command) sequence handler

use base64::Engine as _;

use crate::TerminalCore;

/// Parse `rgb:RR/GG/BB` or `#RRGGBB` color strings into `[R,G,B]`.
///
/// Supports both xterm-style `rgb:RR/GG/BB` (16-bit per channel, upper 8 bits used)
/// and CSS-style `#RRGGBB` (8-bit per channel).
fn parse_color_spec(s: &str) -> Option<[u8; 3]> {
    let s = s.trim();
    if let Some(rest) = s.strip_prefix("rgb:") {
        // Format: rgb:RRRR/GGGG/BBBB (4 hex digits per channel) or rgb:RR/GG/BB (2 hex)
        let parts: Vec<&str> = rest.splitn(3, '/').collect();
        if parts.len() != 3 { return None; }
        let r = u16::from_str_radix(parts[0], 16).ok()?;
        let g = u16::from_str_radix(parts[1], 16).ok()?;
        let b = u16::from_str_radix(parts[2], 16).ok()?;
        // Normalize to 8-bit (take upper 8 bits if 4-digit, else direct if 2-digit)
        let normalize = |v: u16, digits: usize| -> u8 {
            if digits > 2 { (v >> 8) as u8 } else { v as u8 }
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

/// Encode an RGB triple as `rgb:RRRR/GGGG/BBBB` for OSC query responses.
fn encode_color_spec(rgb: [u8; 3]) -> String {
    format!("rgb:{:04x}/{:04x}/{:04x}",
        (rgb[0] as u16) << 8 | rgb[0] as u16,
        (rgb[1] as u16) << 8 | rgb[1] as u16,
        (rgb[2] as u16) << 8 | rgb[2] as u16)
}

/// Handle OSC sequences dispatched from the VTE parser.
/// Called from `TerminalCore::osc_dispatch`.
///
/// Handles:
/// - OSC 0 / OSC 2: set window title.
/// - OSC 4: Set/query individual palette color entries.
/// - OSC 7: Current Working Directory notification (`file://host/path`).
/// - OSC 8: Hyperlinks (`ESC]8;params;uri ST`).
/// - OSC 10/11/12: Set/query default foreground/background/cursor colors.
/// - OSC 52: Clipboard access.
/// - OSC 104: Reset color palette.
/// - OSC 133: Shell integration prompt marks.
/// - OSC 1337: iTerm2 inline images.
/// - All other OSC numbers are silently discarded.
pub(crate) fn handle_osc(core: &mut TerminalCore, params: &[&[u8]], _bell_terminated: bool) {
    if params.is_empty() {
        return;
    }
    match params[0] {
        b"0" | b"2" => {
            if let Some(raw) = params.get(1) {
                if raw.is_empty() {
                    return; // ignore empty titles
                }
                const MAX_TITLE_BYTES: usize = 1024;
                if raw.len() > MAX_TITLE_BYTES {
                    return; // ignore oversized titles (DoS prevention)
                }
                let title = String::from_utf8_lossy(raw).into_owned();
                core.title = title;
                core.title_dirty = true;
            }
        }
        b"7" => {
            // OSC 7 - Current Working Directory: file://host/path
            if let Some(raw) = params.get(1) {
                let url = String::from_utf8_lossy(raw);
                // Strip file://hostname prefix to get just the path
                if let Some(after_scheme) = url.strip_prefix("file://") {
                    // Skip hostname part (up to next /)
                    let path = after_scheme
                        .find('/')
                        .map(|i| &after_scheme[i..])
                        .unwrap_or(after_scheme);
                    if path.len() <= 4096 {
                        core.osc_data.cwd = Some(path.to_string());
                        core.osc_data.cwd_dirty = true;
                    }
                }
            }
        }
        b"8" => {
            // OSC 8 - Hyperlinks: ESC]8;params;uri ST
            if let Some(params_raw) = params.get(1) {
                let params_str = String::from_utf8_lossy(params_raw);
                if let Some(uri_raw) = params.get(2) {
                    let uri = String::from_utf8_lossy(uri_raw);
                    if uri.is_empty() {
                        // Close hyperlink
                        core.osc_data.hyperlink = crate::types::osc::HyperlinkState::default();
                    } else if uri.len() <= 8192 {
                        // Extract id from params if present
                        let id = params_str
                            .split(';')
                            .find_map(|p| p.strip_prefix("id="))
                            .map(String::from);
                        core.osc_data.hyperlink = crate::types::osc::HyperlinkState {
                            uri: Some(uri.into_owned()),
                            id,
                        };
                    }
                }
            }
        }
        b"52" => {
            // OSC 52 - Clipboard: ESC]52;selection;base64data ST
            if let Some(data_raw) = params.get(2) {
                if data_raw == b"?" {
                    core.osc_data
                        .clipboard_actions
                        .push(crate::types::osc::ClipboardAction::Query);
                } else if data_raw.len() <= 1_048_576 {
                    // 1MB cap
                    if let Ok(decoded) = base64::engine::general_purpose::STANDARD.decode(data_raw)
                    {
                        if let Ok(text) = String::from_utf8(decoded) {
                            core.osc_data
                                .clipboard_actions
                                .push(crate::types::osc::ClipboardAction::Write(text));
                        }
                    }
                }
            }
        }
        b"133" => {
            // OSC 133 - Shell integration prompt marks
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
        b"4" => {
            // OSC 4 - Set/query palette color: OSC 4 ; N ; spec ST
            // params[1] = index, params[2] = "?" or "rgb:..." spec
            if let (Some(idx_raw), Some(spec_raw)) = (params.get(1), params.get(2)) {
                let idx_str = std::str::from_utf8(idx_raw).unwrap_or("");
                if let Ok(idx) = idx_str.parse::<usize>() {
                    if idx < 256 {
                        if *spec_raw == b"?" {
                            // Query: respond with current color
                            let rgb = core.osc_data.palette[idx].unwrap_or([0, 0, 0]);
                            let resp = format!("\x1b]4;{};{}\x07", idx, encode_color_spec(rgb));
                            core.pending_responses.push(resp.into_bytes());
                        } else {
                            let spec = std::str::from_utf8(spec_raw).unwrap_or("");
                            if let Some(rgb) = parse_color_spec(spec) {
                                core.osc_data.palette[idx] = Some(rgb);
                                core.osc_data.palette_dirty = true;
                            }
                        }
                    }
                }
            }
        }
        b"10" | b"11" | b"12" => {
            // OSC 10/11/12 - Set/query default fg/bg/cursor color
            // OSC 10 ; ? ST → query fg color
            // OSC 10 ; rgb:... ST → set fg color
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
                    core.pending_responses.push(resp.into_bytes());
                } else {
                    let spec = std::str::from_utf8(spec_raw).unwrap_or("");
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
        b"104" => {
            // OSC 104 - Reset color palette (reset all if no arg, else reset specific index)
            if let Some(idx_raw) = params.get(1) {
                if !idx_raw.is_empty() {
                    let idx_str = std::str::from_utf8(idx_raw).unwrap_or("");
                    if let Ok(idx) = idx_str.parse::<usize>() {
                        if idx < 256 {
                            core.osc_data.palette[idx] = None;
                        }
                    }
                } else {
                    // Reset all palette entries
                    for entry in &mut core.osc_data.palette {
                        *entry = None;
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
        b"1337" => {
            // OSC 1337 - iTerm2 inline images: OSC 1337 ; File=params:base64data BEL/ST
            if let Some(rest_raw) = params.get(1) {
                let rest = std::str::from_utf8(rest_raw).unwrap_or("");
                if let Some(stripped) = rest.strip_prefix("File=") {
                    // Split at ':' to separate params from base64 data
                    if let Some(colon_pos) = stripped.find(':') {
                        let param_str = &stripped[..colon_pos];
                        let b64_data = &stripped[colon_pos + 1..];

                        // Parse parameters
                        let mut inline = false;
                        let mut display_cols: u32 = 0;
                        let mut display_rows: u32 = 0;
                        for kv in param_str.split(';') {
                            if let Some(v) = kv.strip_prefix("inline=") {
                                inline = v == "1";
                            } else if let Some(v) = kv.strip_prefix("width=") {
                                // Width: N (cells), Npx, N%, auto
                                display_cols = v.trim_end_matches("px")
                                    .trim_end_matches('%')
                                    .parse().unwrap_or(0);
                            } else if let Some(v) = kv.strip_prefix("height=") {
                                display_rows = v.trim_end_matches("px")
                                    .trim_end_matches('%')
                                    .parse().unwrap_or(0);
                            }
                        }

                        if inline && !b64_data.is_empty() {
                            use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
                            if let Ok(raw) = BASE64_STANDARD.decode(b64_data.trim()) {
                                // Try to decode as PNG first, then treat as raw RGBA
                                use crate::grid::screen::{ImageData, ImagePlacement};
                                use crate::parser::kitty::ImageFormat;

                                let result = {
                                    let decoder = png::Decoder::new(std::io::Cursor::new(&raw));
                                    match decoder.read_info() {
                                        Ok(mut reader) => {
                                            let mut buf = vec![0u8; reader.output_buffer_size()];
                                            match reader.next_frame(&mut buf) {
                                                Ok(info) => {
                                                    buf.truncate(info.buffer_size());
                                                    let fmt = match info.color_type {
                                                        png::ColorType::Rgba => ImageFormat::Rgba,
                                                        _ => ImageFormat::Rgb,
                                                    };
                                                    let w = info.width;
                                                    let h = info.height;
                                                    // Convert to RGBA if RGB
                                                    let pixels = if fmt == ImageFormat::Rgb {
                                                        buf.chunks(3).flat_map(|p| {
                                                            [p[0], p[1], p[2], 255]
                                                        }).collect()
                                                    } else {
                                                        buf
                                                    };
                                                    Some((pixels, ImageFormat::Rgba, w, h))
                                                }
                                                Err(_) => None,
                                            }
                                        }
                                        Err(_) => None,
                                    }
                                };

                                if let Some((pixels, format, pw, ph)) = result {
                                    let cols = if display_cols > 0 { display_cols } else { pw.div_ceil(8) };
                                    let rows = if display_rows > 0 { display_rows } else { ph.div_ceil(16) };

                                    let data = ImageData {
                                        pixels,
                                        format,
                                        pixel_width: pw,
                                        pixel_height: ph,
                                    };
                                    let actual_id = core.screen.active_graphics_mut().store_image(None, data);
                                    let cursor = *core.screen.cursor();
                                    let placement = ImagePlacement {
                                        image_id: actual_id,
                                        row: cursor.row,
                                        col: cursor.col,
                                        display_cols: cols.max(1),
                                        display_rows: rows.max(1),
                                    };
                                    if let Some(notif) = core.screen.active_graphics_mut().add_placement(placement) {
                                        core.pending_image_notifications.push(notif);
                                    }
                                    // Advance cursor
                                    let max_row = (core.screen.rows() as usize).saturating_sub(1);
                                    let new_row = cursor.row.saturating_add(rows as usize).min(max_row);
                                    core.screen.move_cursor(new_row, 0);
                                }
                            }
                        }
                    }
                }
            }
        }
        _ => {} // all other OSC numbers: silently ignore
    }
}
