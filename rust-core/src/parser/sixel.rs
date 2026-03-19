//! Pure-Rust Sixel graphics decoder.
//!
//! Decodes `DCS P1;P2;P3 q <data> ST` sequences to RGBA pixel data.

use std::collections::HashMap;

const MAX_SIXEL_SIZE: usize = 4096 * 4096; // 4K x 4K pixel limit

/// In-progress sixel decoder state.
pub struct SixelDecoder {
    /// Color register map: index -> [R, G, B] (0-255 scale).
    color_map: HashMap<u16, [u8; 3]>,
    /// Current color register index.
    current_color: u16,
    /// Decoded pixel buffer (RGBA).
    pixels: Vec<u8>,
    /// Image width in pixels.
    width: u32,
    /// Image height in pixels.
    height: u32,
    /// Declared width from raster attributes (0 = unknown).
    declared_width: u32,
    /// Declared height from raster attributes (0 = unknown).
    declared_height: u32,
    /// Current X position in pixels.
    cursor_x: u32,
    /// Current band (each band = 6 pixel rows).
    band: u32,
    /// P2 parameter: 0/2 = transparent background, 1 = background filled.
    p2: u16,
    /// Parser state for multi-byte commands.
    state: SixelParseState,
    /// Accumulator for numeric arguments.
    num_buf: u32,
    /// Temporary parameter storage for commands.
    params: Vec<u32>,
}

#[derive(Default, PartialEq)]
enum SixelParseState {
    #[default]
    Normal,
    /// Reading `#` color command.
    Color,
    /// Reading `!` repeat count.
    Repeat,
    /// Reading `"` raster attributes.
    Raster,
}

impl SixelDecoder {
    /// Create a decoder using Sixel P2 behavior.
    pub fn new(p2: u16) -> Self {
        let mut color_map = HashMap::new();
        // VT340-like default palette (first 16 entries, 0-100 mapped to 0-255).
        let defaults = [
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

        for (idx, rgb100) in defaults {
            color_map.insert(
                idx,
                [
                    (rgb100[0] as u32 * 255 / 100) as u8,
                    (rgb100[1] as u32 * 255 / 100) as u8,
                    (rgb100[2] as u32 * 255 / 100) as u8,
                ],
            );
        }

        Self {
            color_map,
            current_color: 0,
            pixels: Vec::new(),
            width: 0,
            height: 0,
            declared_width: 0,
            declared_height: 0,
            cursor_x: 0,
            band: 0,
            p2,
            state: SixelParseState::Normal,
            num_buf: 0,
            params: Vec::new(),
        }
    }

    /// Process one byte of sixel data.
    pub fn put(&mut self, byte: u8) {
        match self.state {
            SixelParseState::Normal => self.handle_normal(byte),
            SixelParseState::Color => self.handle_color(byte),
            SixelParseState::Repeat => self.handle_repeat(byte),
            SixelParseState::Raster => self.handle_raster(byte),
        }
    }

    fn handle_normal(&mut self, byte: u8) {
        match byte {
            b'#' => {
                self.state = SixelParseState::Color;
                self.num_buf = 0;
                self.params.clear();
            }
            b'!' => {
                self.state = SixelParseState::Repeat;
                self.num_buf = 0;
            }
            b'"' => {
                self.state = SixelParseState::Raster;
                self.num_buf = 0;
                self.params.clear();
            }
            b'-' => {
                // Next band: advance 6 rows and reset x.
                self.band = self.band.saturating_add(1);
                self.cursor_x = 0;
            }
            b'$' => {
                // Carriage return within current band.
                self.cursor_x = 0;
            }
            0x3F..=0x7E => {
                // Sixel data character.
                self.paint_sixel(byte - 0x3F, 1);
            }
            _ => {
                // Ignore spaces and other non-sixel bytes.
            }
        }
    }

    fn handle_color(&mut self, byte: u8) {
        match byte {
            b'0'..=b'9' => {
                self.num_buf = self
                    .num_buf
                    .saturating_mul(10)
                    .saturating_add((byte - b'0') as u32);
            }
            b';' => {
                self.params.push(self.num_buf);
                self.num_buf = 0;
            }
            _ => {
                self.params.push(self.num_buf);
                self.apply_color_command();
                self.params.clear();
                self.num_buf = 0;
                self.state = SixelParseState::Normal;
                // Re-process current byte in normal state.
                self.handle_normal(byte);
            }
        }
    }

    fn handle_repeat(&mut self, byte: u8) {
        match byte {
            b'0'..=b'9' => {
                self.num_buf = self
                    .num_buf
                    .saturating_mul(10)
                    .saturating_add((byte - b'0') as u32);
            }
            0x3F..=0x7E => {
                let count = self.num_buf.max(1);
                self.paint_sixel(byte - 0x3F, count);
                self.num_buf = 0;
                self.state = SixelParseState::Normal;
            }
            _ => {
                self.num_buf = 0;
                self.state = SixelParseState::Normal;
                self.handle_normal(byte);
            }
        }
    }

    fn handle_raster(&mut self, byte: u8) {
        match byte {
            b'0'..=b'9' => {
                self.num_buf = self
                    .num_buf
                    .saturating_mul(10)
                    .saturating_add((byte - b'0') as u32);
            }
            b';' => {
                self.params.push(self.num_buf);
                self.num_buf = 0;
            }
            _ => {
                self.params.push(self.num_buf);
                self.apply_raster_command();
                self.params.clear();
                self.num_buf = 0;
                self.state = SixelParseState::Normal;
                self.handle_normal(byte);
            }
        }
    }

    fn apply_color_command(&mut self) {
        if self.params.is_empty() {
            return;
        }

        let reg = self.params[0] as u16;
        self.current_color = reg;

        // #N;2;R;G;B (0-100 each) or #N;1;H;L;S.
        if self.params.len() < 5 {
            return;
        }

        let color_type = self.params[1];
        let a = self.params[2];
        let b = self.params[3];
        let c = self.params[4];

        let rgb = match color_type {
            2 => [
                (a.min(100) * 255 / 100) as u8,
                (b.min(100) * 255 / 100) as u8,
                (c.min(100) * 255 / 100) as u8,
            ],
            1 => hls_to_rgb(a as f32, b as f32, c as f32),
            _ => return,
        };

        self.color_map.insert(reg, rgb);
    }

    fn apply_raster_command(&mut self) {
        // "Pan;Pad;Ph;Pv where Ph=width, Pv=height.
        if self.params.len() < 4 {
            return;
        }

        let declared_width = self.params[2];
        let declared_height = self.params[3];

        if declared_width > 0
            && declared_height > 0
            && (declared_width as usize).saturating_mul(declared_height as usize) <= MAX_SIXEL_SIZE
        {
            self.declared_width = declared_width;
            self.declared_height = declared_height;
            self.ensure_size(self.declared_width, self.declared_height);
        } else {
            self.declared_width = 0;
            self.declared_height = 0;
        }
    }

    /// Paint a sixel column at the current position, repeated `count` times.
    fn paint_sixel(&mut self, bits: u8, count: u32) {
        if count == 0 {
            return;
        }

        let rgb = self
            .color_map
            .get(&self.current_color)
            .copied()
            .unwrap_or([255, 255, 255]);

        let y_base = self.band * 6;
        let max_w = if self.declared_width > 0 {
            self.declared_width
        } else {
            4096
        };
        let max_h = if self.declared_height > 0 {
            self.declared_height
        } else {
            4096
        };

        for dx in 0..count {
            let x = self.cursor_x.saturating_add(dx);
            if x >= max_w {
                break;
            }

            for bit_idx in 0..6u32 {
                if (bits >> bit_idx) & 1 == 0 {
                    continue;
                }

                let y = y_base.saturating_add(bit_idx);
                if y >= max_h {
                    continue;
                }

                self.ensure_size(x + 1, y + 1);
                let pixel_offset = ((y as usize) * (self.width as usize) + x as usize) * 4;
                if pixel_offset + 3 >= self.pixels.len() {
                    continue;
                }

                self.pixels[pixel_offset] = rgb[0];
                self.pixels[pixel_offset + 1] = rgb[1];
                self.pixels[pixel_offset + 2] = rgb[2];
                self.pixels[pixel_offset + 3] = 255;
            }
        }

        self.cursor_x = self.cursor_x.saturating_add(count);

        // Preserve logical width advancement even for blank sixel columns.
        let logical_w = self.cursor_x.min(max_w);
        if logical_w > self.width {
            self.ensure_size(logical_w, self.height.max(1));
        }
    }

    fn ensure_size(&mut self, min_w: u32, min_h: u32) {
        let new_w = self.width.max(min_w);
        let new_h = self.height.max(min_h);

        if new_w == self.width && new_h == self.height {
            return;
        }

        if (new_w as usize).saturating_mul(new_h as usize) > MAX_SIXEL_SIZE {
            return;
        }

        let mut new_pixels = vec![0u8; new_w as usize * new_h as usize * 4];

        // P2=1 means background should be initialized as opaque color register 0.
        if self.p2 == 1 {
            let bg = self.color_map.get(&0).copied().unwrap_or([0, 0, 0]);
            for px in new_pixels.chunks_exact_mut(4) {
                px[0] = bg[0];
                px[1] = bg[1];
                px[2] = bg[2];
                px[3] = 255;
            }
        }

        // Copy old rows into resized backing store.
        for row in 0..self.height as usize {
            let src_start = row * self.width as usize * 4;
            let src_end = src_start + self.width as usize * 4;
            let dst_start = row * new_w as usize * 4;
            if src_end <= self.pixels.len() {
                new_pixels[dst_start..dst_start + self.width as usize * 4]
                    .copy_from_slice(&self.pixels[src_start..src_end]);
            }
        }

        self.pixels = new_pixels;
        self.width = new_w;
        self.height = new_h;
    }

    /// Finalize decoding.
    ///
    /// Returns `(pixels_rgba, width, height)` or `None` when nothing was decoded.
    pub fn finish(mut self) -> Option<(Vec<u8>, u32, u32)> {
        // Flush an unterminated command at sequence end.
        match self.state {
            SixelParseState::Color => {
                self.params.push(self.num_buf);
                self.apply_color_command();
            }
            SixelParseState::Raster => {
                self.params.push(self.num_buf);
                self.apply_raster_command();
            }
            SixelParseState::Repeat | SixelParseState::Normal => {}
        }

        self.state = SixelParseState::Normal;
        self.params.clear();
        self.num_buf = 0;

        let declared_pixels =
            (self.declared_width as usize).saturating_mul(self.declared_height as usize);
        let declared_usable = self.declared_width > 0
            && self.declared_height > 0
            && declared_pixels <= MAX_SIXEL_SIZE
            && self.pixels.len() >= declared_pixels.saturating_mul(4);

        let (w, h) = if declared_usable {
            (self.declared_width, self.declared_height)
        } else {
            (self.width, self.height)
        };

        if w == 0 || h == 0 || self.pixels.is_empty() {
            return None;
        }

        Some((self.pixels, w, h))
    }
}

/// HLS to RGB conversion (H: 0-360, L: 0-100, S: 0-100).
fn hls_to_rgb(h: f32, l: f32, s: f32) -> [u8; 3] {
    let l = (l / 100.0).clamp(0.0, 1.0);
    let s = (s / 100.0).clamp(0.0, 1.0);

    if s == 0.0 {
        let v = (l * 255.0) as u8;
        return [v, v, v];
    }

    let q = if l < 0.5 {
        l * (1.0 + s)
    } else {
        l + s - l * s
    };
    let p = 2.0 * l - q;
    let h = h / 360.0;

    let r = hue_to_rgb(p, q, h + 1.0 / 3.0);
    let g = hue_to_rgb(p, q, h);
    let b = hue_to_rgb(p, q, h - 1.0 / 3.0);

    [(r * 255.0) as u8, (g * 255.0) as u8, (b * 255.0) as u8]
}

fn hue_to_rgb(p: f32, q: f32, mut t: f32) -> f32 {
    if t < 0.0 {
        t += 1.0;
    }
    if t > 1.0 {
        t -= 1.0;
    }
    if t < 1.0 / 6.0 {
        return p + (q - p) * 6.0 * t;
    }
    if t < 1.0 / 2.0 {
        return q;
    }
    if t < 2.0 / 3.0 {
        return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    }
    p
}

#[cfg(test)]
#[path = "tests/sixel.rs"]
mod tests;
