use std::collections::HashMap;

use super::color::hls_to_rgb;

pub(super) const SIXEL_DRAW_LIMIT: u32 = 4096;
const SIXEL_DRAW_LIMIT_USIZE: usize = 4096;
pub(super) const MAX_SIXEL_SIZE: usize = SIXEL_DRAW_LIMIT_USIZE * SIXEL_DRAW_LIMIT_USIZE;
pub(super) const MAX_COLOR_REGISTERS: u16 = 1024; // matches WezTerm / Ghostty / foot (VT340 = 16, xterm = 256)
const RGBA_CHANNELS: usize = 4;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct SixelColorRegister(u16);

impl SixelColorRegister {
    pub(super) fn parse(value: u32) -> Option<Self> {
        let register = u16::try_from(value).ok()?;
        (register < MAX_COLOR_REGISTERS).then_some(Self(register))
    }
}

impl From<SixelColorRegister> for u16 {
    fn from(value: SixelColorRegister) -> Self {
        value.0
    }
}

#[inline]
fn sixel_dimension_usize(value: u32) -> Option<usize> {
    usize::try_from(value).ok()
}

#[inline]
pub(super) fn sixel_pixel_area(width: u32, height: u32) -> Option<usize> {
    let width = sixel_dimension_usize(width)?;
    let height = sixel_dimension_usize(height)?;
    if width == 0 || height == 0 {
        return None;
    }

    let area = width.checked_mul(height)?;
    (area <= MAX_SIXEL_SIZE).then_some(area)
}

#[inline]
pub(super) fn sixel_pixel_bytes(width: u32, height: u32) -> Option<usize> {
    sixel_pixel_area(width, height)?.checked_mul(RGBA_CHANNELS)
}

#[inline]
pub(super) fn sixel_pixel_offset(x: u32, y: u32, width: u32) -> Option<usize> {
    let x = sixel_dimension_usize(x)?;
    let y = sixel_dimension_usize(y)?;
    let width = sixel_dimension_usize(width)?;

    y.checked_mul(width)?
        .checked_add(x)?
        .checked_mul(RGBA_CHANNELS)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct SixelPercent(u8);

impl SixelPercent {
    fn parse(value: u32) -> Option<Self> {
        let percent = u8::try_from(value).ok()?;
        (percent <= 100).then_some(Self(percent))
    }

    fn to_rgb_component(self) -> u8 {
        let scaled = u16::from(self.0) * 255 / 100;
        u8::try_from(scaled).expect("percentage scaled to 0..=255")
    }

    fn as_f32(self) -> f32 {
        f32::from(self.0)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct SixelRgb100 {
    red: SixelPercent,
    green: SixelPercent,
    blue: SixelPercent,
}

impl SixelRgb100 {
    fn parse(red: u32, green: u32, blue: u32) -> Option<Self> {
        Some(Self {
            red: SixelPercent::parse(red)?,
            green: SixelPercent::parse(green)?,
            blue: SixelPercent::parse(blue)?,
        })
    }

    fn to_rgb8(self) -> [u8; 3] {
        [
            self.red.to_rgb_component(),
            self.green.to_rgb_component(),
            self.blue.to_rgb_component(),
        ]
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct SixelHls {
    hue_degrees: u16,
    lightness: SixelPercent,
    saturation: SixelPercent,
}

impl SixelHls {
    fn parse(hue_degrees: u32, lightness: u32, saturation: u32) -> Option<Self> {
        let hue_degrees = u16::try_from(hue_degrees).ok()?;
        if hue_degrees > 360 {
            return None;
        }

        Some(Self {
            hue_degrees,
            lightness: SixelPercent::parse(lightness)?,
            saturation: SixelPercent::parse(saturation)?,
        })
    }

    fn to_rgb8(self) -> [u8; 3] {
        hls_to_rgb(
            f32::from(self.hue_degrees),
            self.lightness.as_f32(),
            self.saturation.as_f32(),
        )
    }
}

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
    SixelRgb100::parse(
        u32::from(rgb100[0]),
        u32::from(rgb100[1]),
        u32::from(rgb100[2]),
    )
    .expect("VT340 default palette uses percentage components")
    .to_rgb8()
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
            let Ok(idx) = u32::try_from(idx) else {
                continue;
            };
            let Some(reg) = SixelColorRegister::parse(idx) else {
                continue;
            };
            color_map.insert(u16::from(reg), *rgb);
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
        2 => Some(SixelRgb100::parse(a, b, c)?.to_rgb8()),
        1 => Some(SixelHls::parse(a, b, c)?.to_rgb8()),
        _ => None,
    }
}

pub(super) fn sixel_dimensions_are_usable(width: u32, height: u32) -> bool {
    sixel_pixel_area(width, height).is_some()
}

pub(crate) fn sixel_resolved_output_dimensions(
    declared_width: u32,
    declared_height: u32,
    width: u32,
    height: u32,
    pixels_len: usize,
) -> Option<(u32, u32)> {
    let declared_output_is_usable = sixel_pixel_bytes(declared_width, declared_height)
        .is_some_and(|byte_len| pixels_len >= byte_len);

    let (w, h) = if declared_output_is_usable {
        (declared_width, declared_height)
    } else {
        (width, height)
    };

    sixel_pixel_bytes(w, h)
        .is_some_and(|byte_len| pixels_len >= byte_len)
        .then_some((w, h))
}

pub(super) fn sixel_draw_limits(declared_width: u32, declared_height: u32) -> (u32, u32) {
    // Cap the paint region at SIXEL_DRAW_LIMIT even when the raster command
    // declares larger dimensions.  `paint_sixel` breaks its repeat loop on
    // `x >= max_w`, so an attacker-declared width up to MAX_SIXEL_SIZE would
    // otherwise let a tiny `!<count>` token drive millions of iterations and
    // freeze the synchronous module call.  The clamp keeps drawing bounded to
    // 4096x4096 regardless of the declared size.
    let max_w = if declared_width > 0 {
        declared_width.min(SIXEL_DRAW_LIMIT)
    } else {
        SIXEL_DRAW_LIMIT
    };
    let max_h = if declared_height > 0 {
        declared_height.min(SIXEL_DRAW_LIMIT)
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

    let new_pixel_len = sixel_pixel_bytes(new_w, new_h)?;
    let mut new_pixels = vec![0u8; new_pixel_len];

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
    let Some(src_row_len) =
        sixel_dimension_usize(width).and_then(|width| width.checked_mul(RGBA_CHANNELS))
    else {
        return;
    };
    let Some(dst_row_len) =
        sixel_dimension_usize(new_w).and_then(|width| width.checked_mul(RGBA_CHANNELS))
    else {
        return;
    };
    let Some(height) = sixel_dimension_usize(height) else {
        return;
    };

    for row in 0..height {
        let Some(src_start) = row.checked_mul(src_row_len) else {
            return;
        };
        let Some(src_end) = src_start.checked_add(src_row_len) else {
            return;
        };
        let Some(dst_start) = row.checked_mul(dst_row_len) else {
            return;
        };
        let Some(dst_end) = dst_start.checked_add(src_row_len) else {
            return;
        };
        if src_end <= pixels.len() && dst_end <= new_pixels.len() {
            new_pixels[dst_start..dst_end].copy_from_slice(&pixels[src_start..src_end]);
        }
    }
}
