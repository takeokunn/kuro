use std::collections::HashMap;

use super::color::hls_to_rgb;

pub(super) const SIXEL_DRAW_LIMIT: u32 = 4096;
pub(super) const MAX_SIXEL_SIZE: usize = SIXEL_DRAW_LIMIT as usize * SIXEL_DRAW_LIMIT as usize; // 4K x 4K pixel limit
pub(super) const MAX_COLOR_REGISTERS: u16 = 1024; // matches WezTerm / Ghostty / foot (VT340 = 16, xterm = 256)

pub(super) const VT340_DEFAULT_PALETTE: &[(u16, [u8; 3])] = &[
    (0, [0, 0, 0]),
    (1, [20, 20, 80]),
    (2, [80, 13, 13]),
    (3, [20, 80, 20]),
    (4, [80, 20, 80]),
    (5, [20, 80, 80]),
    (6, [80, 80, 20]),
    (7, [53, 53, 53]),
    (8, [26, 26, 26]),
    (9, [33, 33, 60]),
    (10, [60, 26, 26]),
    (11, [33, 60, 33]),
    (12, [60, 33, 60]),
    (13, [33, 60, 60]),
    (14, [60, 60, 33]),
    (15, [80, 80, 80]),
];

pub(super) fn scale_rgb100(rgb100: [u8; 3]) -> [u8; 3] {
    [
        (rgb100[0] as u32 * 255 / 100) as u8,
        (rgb100[1] as u32 * 255 / 100) as u8,
        (rgb100[2] as u32 * 255 / 100) as u8,
    ]
}

pub(super) fn seed_default_palette(color_map: &mut HashMap<u16, [u8; 3]>) {
    for &(idx, rgb100) in VT340_DEFAULT_PALETTE {
        color_map.insert(idx, scale_rgb100(rgb100));
    }
}

pub(super) fn seed_osc4_palette_overrides(
    color_map: &mut HashMap<u16, [u8; 3]>,
    osc4_palette: &[Option<[u8; 3]>],
) {
    for (idx, entry) in osc4_palette.iter().enumerate() {
        if let Some(rgb) = entry {
            let reg = idx as u16;
            if reg < MAX_COLOR_REGISTERS {
                color_map.insert(reg, *rgb);
            }
        }
    }
}

pub(super) fn sixel_painted_rows(bits: u8, y_base: u32, max_h: u32) -> impl Iterator<Item = u32> {
    (0..6u32).filter_map(move |bit_idx| {
        if (bits >> bit_idx) & 1 == 0 {
            return None;
        }

        let y = y_base.saturating_add(bit_idx);
        if y < max_h {
            Some(y)
        } else {
            None
        }
    })
}

pub(super) fn sixel_color_rgb(color_type: u32, a: u32, b: u32, c: u32) -> Option<[u8; 3]> {
    match color_type {
        2 => Some([
            (a.min(100) * 255 / 100) as u8,
            (b.min(100) * 255 / 100) as u8,
            (c.min(100) * 255 / 100) as u8,
        ]),
        1 => Some(hls_to_rgb(a as f32, b as f32, c as f32)),
        _ => None,
    }
}

pub(super) fn sixel_dimensions_are_usable(width: u32, height: u32) -> bool {
    width > 0 && height > 0 && (width as usize).saturating_mul(height as usize) <= MAX_SIXEL_SIZE
}

pub(crate) fn sixel_resolved_output_dimensions(
    declared_width: u32,
    declared_height: u32,
    width: u32,
    height: u32,
    pixels_len: usize,
) -> Option<(u32, u32)> {
    let declared_output_is_usable = sixel_dimensions_are_usable(declared_width, declared_height)
        && pixels_len
            >= (declared_width as usize)
                .saturating_mul(declared_height as usize)
                .saturating_mul(4);

    let (w, h) = if declared_output_is_usable {
        (declared_width, declared_height)
    } else {
        (width, height)
    };

    if w == 0 || h == 0 || pixels_len == 0 {
        None
    } else {
        Some((w, h))
    }
}

pub(super) fn sixel_draw_limits(declared_width: u32, declared_height: u32) -> (u32, u32) {
    let max_w = if declared_width > 0 {
        declared_width
    } else {
        SIXEL_DRAW_LIMIT
    };
    let max_h = if declared_height > 0 {
        declared_height
    } else {
        SIXEL_DRAW_LIMIT
    };
    (max_w, max_h)
}

pub(super) fn resized_sixel_canvas(
    width: u32,
    height: u32,
    min_w: u32,
    min_h: u32,
    p2: u16,
    color_map: &HashMap<u16, [u8; 3]>,
    pixels: &[u8],
) -> Option<(u32, u32, Vec<u8>)> {
    let new_w = width.max(min_w);
    let new_h = height.max(min_h);

    if new_w == width && new_h == height {
        return None;
    }

    if (new_w as usize).saturating_mul(new_h as usize) > MAX_SIXEL_SIZE {
        return None;
    }

    let mut new_pixels = vec![0u8; new_w as usize * new_h as usize * 4];

    init_sixel_background(&mut new_pixels, p2, color_map);
    copy_sixel_rows(width, height, new_w, pixels, &mut new_pixels);

    Some((new_w, new_h, new_pixels))
}

pub(super) fn init_sixel_background(pixels: &mut [u8], p2: u16, color_map: &HashMap<u16, [u8; 3]>) {
    if p2 != 1 {
        return;
    }

    let bg = color_map.get(&0).copied().unwrap_or([0, 0, 0]);
    for px in pixels.chunks_exact_mut(4) {
        px[0] = bg[0];
        px[1] = bg[1];
        px[2] = bg[2];
        px[3] = 255;
    }
}

pub(super) fn copy_sixel_rows(
    width: u32,
    height: u32,
    new_w: u32,
    pixels: &[u8],
    new_pixels: &mut [u8],
) {
    let src_row_len = width as usize * 4;
    let dst_row_len = new_w as usize * 4;

    for row in 0..height as usize {
        let src_start = row * src_row_len;
        let src_end = src_start + src_row_len;
        let dst_start = row * dst_row_len;
        if src_end <= pixels.len() {
            new_pixels[dst_start..dst_start + src_row_len]
                .copy_from_slice(&pixels[src_start..src_end]);
        }
    }
}
