//! Pure-Rust Sixel graphics decoder.
//!
//! Decodes `DCS P1;P2;P3 q <data> ST` sequences to RGBA pixel data.

use std::collections::HashMap;

use support::{
    resized_sixel_canvas, seed_default_palette, seed_osc4_palette_overrides, sixel_color_rgb,
    sixel_dimensions_are_usable, sixel_draw_limits, sixel_painted_rows, MAX_COLOR_REGISTERS,
};

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

/// Accumulate a decimal digit byte into a saturating `u32` buffer.
///
/// Used by all three numeric-argument handlers (`Color`, `Repeat`, `Raster`).
/// The digit arm is structurally identical across all three state handlers;
/// this macro eliminates the duplication while preserving the inline expansion.
macro_rules! accumulate_digit {
    ($self:expr, $byte:expr) => {{
        $self.num_buf = $self
            .num_buf
            .saturating_mul(10)
            .saturating_add(u32::from($byte - b'0'));
    }};
}

#[path = "sixel_support.rs"]
mod support;

impl SixelDecoder {
    fn sixel_color_register(params: &[u32]) -> Option<u16> {
        params
            .first()
            .copied()
            .map(|reg| (reg as u16).min(MAX_COLOR_REGISTERS - 1))
    }

    fn sixel_color_definition_rgb(params: &[u32]) -> Option<[u8; 3]> {
        if params.len() < 5 {
            return None;
        }

        sixel_color_rgb(params[1], params[2], params[3], params[4])
    }

    fn sixel_raster_declared_dimensions(params: &[u32]) -> Option<(u32, u32)> {
        if params.len() < 4 {
            return None;
        }

        let declared_width = params[2];
        let declared_height = params[3];

        sixel_dimensions_are_usable(declared_width, declared_height)
            .then_some((declared_width, declared_height))
    }

    #[must_use]
    #[expect(
        clippy::cast_possible_truncation,
        reason = "register index is bounds-checked against MAX_COLOR_REGISTERS before the u16 cast"
    )]
    /// Create a new sixel decoder, optionally seeding the palette from terminal OSC 4 overrides.
    ///
    /// `osc4_palette` is the terminal's 256-entry OSC 4 palette; entries with `Some([r,g,b])`
    /// override the VT340 defaults. This ensures `#N` references in sixel data that reference
    /// unredefined registers use the terminal's current color assignments.
    pub fn new_with_palette(p2: u16, osc4_palette: &[Option<[u8; 3]>]) -> Self {
        let mut decoder = Self::new(p2);
        // Override VT340 defaults with any OSC 4 terminal palette entries.
        seed_osc4_palette_overrides(&mut decoder.color_map, osc4_palette);
        decoder
    }

    /// Create a Sixel decoder seeded with the VT340 default 16-color palette.
    ///
    /// `p2` is the DCS P2 parameter selecting background fill behaviour
    /// (0/2 = pixels default to background color, 1 = leave untouched).
    pub fn new(p2: u16) -> Self {
        let mut color_map = HashMap::new();
        seed_default_palette(&mut color_map);

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

    fn current_rgb(&self) -> [u8; 3] {
        self.color_map
            .get(&self.current_color)
            .copied()
            .unwrap_or([255, 255, 255])
    }

    fn push_current_param(&mut self) {
        self.params.push(self.num_buf);
        self.num_buf = 0;
    }

    fn reset_parameterized_command(&mut self) {
        self.params.clear();
        self.num_buf = 0;
        self.state = SixelParseState::Normal;
    }

    fn begin_parameterized_command(&mut self, state: SixelParseState) {
        self.state = state;
        self.num_buf = 0;
        self.params.clear();
    }

    fn begin_repeat_command(&mut self) {
        self.state = SixelParseState::Repeat;
        self.num_buf = 0;
    }

    fn write_sixel_pixel(&mut self, x: u32, y: u32, rgb: [u8; 3]) {
        self.ensure_size(x + 1, y + 1);

        let pixel_offset = ((y as usize) * (self.width as usize) + x as usize) * 4;
        if pixel_offset + 3 >= self.pixels.len() {
            return;
        }

        self.pixels[pixel_offset] = rgb[0];
        self.pixels[pixel_offset + 1] = rgb[1];
        self.pixels[pixel_offset + 2] = rgb[2];
        self.pixels[pixel_offset + 3] = 255;
    }

    fn advance_logical_width(&mut self, max_w: u32) {
        // Preserve logical width advancement even for blank sixel columns.
        let logical_w = self.cursor_x.min(max_w);
        if logical_w > self.width {
            self.ensure_size(logical_w, self.height.max(1));
        }
    }

    fn handle_normal(&mut self, byte: u8) {
        match byte {
            b'#' => {
                self.begin_parameterized_command(SixelParseState::Color);
            }
            b'!' => {
                self.begin_repeat_command();
            }
            b'"' => {
                self.begin_parameterized_command(SixelParseState::Raster);
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

    fn handle_parameterized_command(&mut self, byte: u8, apply: fn(&mut Self)) {
        match byte {
            b'0'..=b'9' => accumulate_digit!(self, byte),
            b';' => {
                self.push_current_param();
            }
            _ => {
                self.finish_parameterized_command(byte, apply);
            }
        }
    }

    fn handle_color(&mut self, byte: u8) {
        self.handle_parameterized_command(byte, Self::apply_color_command);
    }

    fn handle_repeat(&mut self, byte: u8) {
        match byte {
            b'0'..=b'9' => accumulate_digit!(self, byte),
            0x3F..=0x7E => self.finish_repeat_command(byte),
            _ => {
                self.num_buf = 0;
                self.state = SixelParseState::Normal;
                self.handle_normal(byte);
            }
        }
    }

    fn finish_repeat_command(&mut self, byte: u8) {
        let count = self.num_buf.max(1);
        self.paint_sixel(byte - 0x3F, count);
        self.num_buf = 0;
        self.state = SixelParseState::Normal;
    }

    fn handle_raster(&mut self, byte: u8) {
        self.handle_parameterized_command(byte, Self::apply_raster_command);
    }

    fn finish_parameterized_command(&mut self, byte: u8, apply: fn(&mut Self)) {
        self.push_current_param();
        apply(self);
        self.reset_parameterized_command();
        // Re-process the current byte after returning to the normal state.
        self.handle_normal(byte);
    }

    #[expect(
        clippy::cast_possible_truncation,
        reason = "register index: DCS params are u32 but we cap at MAX_COLOR_REGISTERS (1024); RGB percentages are clamped to 0-100 before × 255 / 100 → always ≤ 255"
    )]
    #[expect(
        clippy::cast_precision_loss,
        reason = "converting integer percentage (0-100) to f32 for HLS math; precision loss is negligible for color computation"
    )]
    fn apply_color_command(&mut self) {
        let Some(reg) = Self::sixel_color_register(&self.params) else {
            return;
        };
        self.current_color = reg;

        let Some(rgb) = Self::sixel_color_definition_rgb(&self.params) else {
            return;
        };

        self.color_map.insert(reg, rgb);
    }

    fn apply_raster_command(&mut self) {
        let Some((declared_width, declared_height)) =
            Self::sixel_raster_declared_dimensions(&self.params)
        else {
            self.declared_width = 0;
            self.declared_height = 0;
            return;
        };

        self.declared_width = declared_width;
        self.declared_height = declared_height;
        self.ensure_size(self.declared_width, self.declared_height);
    }

    /// Paint one repeated sixel column at `x`.
    fn paint_sixel_column(&mut self, x: u32, bits: u8, y_base: u32, max_h: u32, rgb: [u8; 3]) {
        for y in sixel_painted_rows(bits, y_base, max_h) {
            self.write_sixel_pixel(x, y, rgb);
        }
    }

    /// Paint a sixel column at the current position, repeated `count` times.
    fn paint_sixel(&mut self, bits: u8, count: u32) {
        if count == 0 {
            return;
        }

        let rgb = self.current_rgb();
        let y_base = self.band.saturating_mul(6);
        let (max_w, max_h) = sixel_draw_limits(self.declared_width, self.declared_height);

        for dx in 0..count {
            let x = self.cursor_x.saturating_add(dx);
            if x >= max_w {
                break;
            }

            self.paint_sixel_column(x, bits, y_base, max_h, rgb);
        }

        self.cursor_x = self.cursor_x.saturating_add(count);
        self.advance_logical_width(max_w);
    }

    fn ensure_size(&mut self, min_w: u32, min_h: u32) {
        if let Some((new_w, new_h, new_pixels)) = resized_sixel_canvas(
            self.width,
            self.height,
            min_w,
            min_h,
            self.p2,
            &self.color_map,
            &self.pixels,
        ) {
            self.pixels = new_pixels;
            self.width = new_w;
            self.height = new_h;
        }
    }

    fn flush_pending_parameterized_command_at_end(&mut self) {
        // End-of-sequence flush for unterminated COLOR / RASTER commands.
        match self.state {
            SixelParseState::Color => {
                self.push_current_param();
                self.apply_color_command();
            }
            SixelParseState::Raster => {
                self.push_current_param();
                self.apply_raster_command();
            }
            SixelParseState::Repeat | SixelParseState::Normal => {}
        }

        self.reset_parameterized_command();
    }

    fn resolve_output_dimensions(&self) -> Option<(u32, u32)> {
        sixel_resolved_output_dimensions(
            self.declared_width,
            self.declared_height,
            self.width,
            self.height,
            self.pixels.len(),
        )
    }

    /// Finalize decoding.
    ///
    /// Returns `(pixels_rgba, width, height)` or `None` when nothing was decoded.
    #[must_use]
    pub fn finish(mut self) -> Option<(Vec<u8>, u32, u32)> {
        self.flush_pending_parameterized_command_at_end();
        let (w, h) = self.resolve_output_dimensions()?;
        Some((self.pixels, w, h))
    }
}

#[path = "sixel_color.rs"]
mod color;

#[cfg(test)]
use color::{hls_to_rgb, hue_to_rgb};

pub(crate) use support::sixel_resolved_output_dimensions;

#[cfg(test)]
#[path = "tests/sixel.rs"]
mod tests;
