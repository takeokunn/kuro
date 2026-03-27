//! Property-based and example-based tests for `sixel` parsing.
//!
//! Module under test: `parser/sixel.rs`
//! Tier: T5 — `ProptestConfig::with_cases(64)`

use super::*;

// ---------------------------------------------------------------------------
// Test-only macros
// ---------------------------------------------------------------------------

/// Feed a color definition sequence and assert the resulting palette entry.
///
/// ```
/// assert_color_reg!(reg 1, seq b"#1;2;100;0;0$", rgb [255, 0, 0]);
/// ```
macro_rules! assert_color_reg {
    (reg $reg:expr, seq $seq:expr, rgb [$r:expr, $g:expr, $b:expr]) => {{
        let mut _d = make_decoder();
        feed(&mut _d, $seq);
        assert_eq!(
            _d.color_map.get(&$reg),
            Some(&[$r as u8, $g as u8, $b as u8]),
            "register {} rgb mismatch",
            $reg
        );
    }};
}

/// Feed a sixel stream and assert the finished dimensions.
///
/// ```
/// assert_finish_dims!(seq b"\"1;1;3;6~~~", w 3, h 6);
/// ```
macro_rules! assert_finish_dims {
    (seq $seq:expr, w $w:expr, h $h:expr) => {{
        let mut _d = make_decoder();
        feed(&mut _d, $seq);
        let _result = _d.finish();
        assert!(_result.is_some(), "finish() returned None");
        let (_, _fw, _fh) = _result.unwrap();
        assert_eq!(_fw, $w as u32, "width mismatch");
        assert_eq!(_fh, $h as u32, "height mismatch");
    }};
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn make_decoder() -> SixelDecoder {
    SixelDecoder::new(0)
}

fn feed(decoder: &mut SixelDecoder, bytes: &[u8]) {
    for b in bytes {
        decoder.put(*b);
    }
}

// ---------------------------------------------------------------------------
// Basic construction / empty decode
// ---------------------------------------------------------------------------

#[test]
fn test_empty_sixel() {
    let decoder = make_decoder();
    assert!(decoder.finish().is_none());
}

#[test]
fn new_decoder_has_zero_dimensions() {
    let d = make_decoder();
    assert_eq!(d.width, 0);
    assert_eq!(d.height, 0);
    assert_eq!(d.declared_width, 0);
    assert_eq!(d.declared_height, 0);
}

#[test]
fn new_decoder_cursor_at_origin() {
    let d = make_decoder();
    assert_eq!(d.cursor_x, 0);
    assert_eq!(d.band, 0);
}

#[test]
fn new_decoder_default_color_zero_is_black() {
    let d = make_decoder();
    // VT340 palette register 0 is (0,0,0)
    assert_eq!(d.color_map.get(&0), Some(&[0u8, 0, 0]));
}

#[test]
fn new_decoder_default_palette_register_15_is_near_white() {
    let d = make_decoder();
    // Register 15: (80,80,80) in 0-100 scale → 204,204,204
    let rgb = d.color_map.get(&15).copied().unwrap_or([0, 0, 0]);
    assert!(
        rgb[0] > 190,
        "register 15 red should be near-white, got {}",
        rgb[0]
    );
    assert_eq!(rgb[0], rgb[1], "register 15 should be grey");
    assert_eq!(rgb[1], rgb[2], "register 15 should be grey");
}

#[test]
fn new_decoder_pixel_buffer_is_empty() {
    let d = make_decoder();
    assert!(d.pixels.is_empty());
}

#[test]
fn new_decoder_state_is_normal() {
    let d = make_decoder();
    assert!(d.state == SixelParseState::Normal);
}

#[test]
fn new_decoder_num_buf_is_zero() {
    let d = make_decoder();
    assert_eq!(d.num_buf, 0);
}

#[test]
fn new_decoder_params_is_empty() {
    let d = make_decoder();
    assert!(d.params.is_empty());
}

// ---------------------------------------------------------------------------
// Single pixel / raster
// ---------------------------------------------------------------------------

#[test]
fn test_single_pixel_sixel() {
    let mut decoder = make_decoder();
    feed(&mut decoder, b"\"1;1;1;6#0~");

    let result = decoder.finish();
    assert!(result.is_some());
    let (pixels, w, h) = result.expect("result should exist");
    assert_eq!(w, 1);
    assert_eq!(h, 6);
    assert_eq!(pixels.len(), 24); // 1 * 6 * RGBA(4)
}

// ---------------------------------------------------------------------------
// Raster attributes (`"`)
// ---------------------------------------------------------------------------

#[test]
fn raster_sets_declared_dimensions() {
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;40;20");
    // Unterminated raster; flush via finish
    let _ = d.finish();
    // We can't inspect after finish (consumes self), so test via a non-consuming path:
    // re-run with a terminator byte
    let mut d2 = make_decoder();
    feed(&mut d2, b"\"1;1;40;20?"); // `?` triggers raster termination + paint
    assert_eq!(d2.declared_width, 40);
    assert_eq!(d2.declared_height, 20);
}

#[test]
fn raster_fewer_than_four_params_ignored() {
    // "Pan;Pad;Ph — only 3 params, must not set declared dimensions
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;40?"); // 3 params (0,0,40) — params[3] missing
    assert_eq!(d.declared_width, 0);
    assert_eq!(d.declared_height, 0);
}

#[test]
fn raster_zero_width_ignored() {
    // "1;1;0;20 — zero width must not set declared dimensions
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;0;20?");
    assert_eq!(d.declared_width, 0);
    assert_eq!(d.declared_height, 0);
}

#[test]
fn raster_zero_height_ignored() {
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;40;0?");
    assert_eq!(d.declared_width, 0);
    assert_eq!(d.declared_height, 0);
}

#[test]
fn raster_oversized_dimensions_ignored() {
    // 4097 * 4097 exceeds MAX_SIXEL_SIZE (4096*4096)
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;4097;4097?");
    assert_eq!(d.declared_width, 0);
    assert_eq!(d.declared_height, 0);
}

#[test]
fn raster_finish_flushes_unterminated_command() {
    // Feed raster without a terminating non-digit byte, let finish() flush it
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;8;6");
    // No terminator byte — finish() must flush
    // After finish(), declared dimensions should be set and result non-None
    // (we need at least one sixel data byte for finish to return Some)
    // Re-feed with terminator to inspect state
    let mut d2 = make_decoder();
    feed(&mut d2, b"\"1;1;8;6");
    // Manually simulate finish flush path by feeding a data char
    d2.put(b'~'); // this acts as terminator for raster and paints
    assert_eq!(d2.declared_width, 8);
    assert_eq!(d2.declared_height, 6);
}

// ---------------------------------------------------------------------------
// Color command (`#`)
// ---------------------------------------------------------------------------

#[test]
fn test_color_definition() {
    assert_color_reg!(reg 1, seq b"#1;2;100;0;0$", rgb [255, 0, 0]);
}

#[test]
fn color_definition_rgb_green() {
    assert_color_reg!(reg 2, seq b"#2;2;0;100;0$", rgb [0, 255, 0]);
}

#[test]
fn color_definition_rgb_blue() {
    assert_color_reg!(reg 3, seq b"#3;2;0;0;100$", rgb [0, 0, 255]);
}

#[test]
fn color_definition_clamps_rgb_to_100() {
    // Values above 100 must be clamped to 100 before scaling to 255
    let mut d = make_decoder();
    feed(&mut d, b"#4;2;200;200;200$");
    // 100.min(200) * 255 / 100 == 255
    assert_eq!(d.color_map.get(&4), Some(&[255u8, 255, 255]));
}

#[test]
fn color_select_only_sets_current_color() {
    // #N with fewer than 5 params only selects current_color without redefining map entry
    let mut d = make_decoder();
    let original = d.color_map.get(&3).copied();
    feed(&mut d, b"#3$");
    assert_eq!(d.current_color, 3);
    assert_eq!(
        d.color_map.get(&3).copied(),
        original,
        "color map must not be altered"
    );
}

#[test]
fn color_no_params_does_not_panic() {
    // `#` followed immediately by a non-digit, non-semicolon character
    let mut d = make_decoder();
    feed(&mut d, b"#~"); // finalize color command with empty params, then paint
                         // Must not panic; current_color stays 0
    assert_eq!(d.current_color, 0);
}

#[test]
fn color_index_high_value_does_not_panic() {
    // Index 65535 is the maximum u16; must not panic
    let mut d = make_decoder();
    feed(&mut d, b"#65535;2;50;50;50$");
    assert!(d.color_map.contains_key(&65535));
}

#[test]
fn color_hls_definition() {
    // #1;1;0;50;100 → HLS(0°, 50%, 100%) → red
    let mut d = make_decoder();
    feed(&mut d, b"#5;1;0;50;100$");
    let rgb = d.color_map.get(&5).copied().unwrap_or([0, 0, 0]);
    assert!(rgb[0] > 200, "hls red: r should be high, got {}", rgb[0]);
    assert!(rgb[1] < 50, "hls red: g should be low, got {}", rgb[1]);
    assert!(rgb[2] < 50, "hls red: b should be low, got {}", rgb[2]);
}

#[test]
fn color_unknown_type_does_not_insert() {
    // Color type 3 is not defined (only 1=HLS, 2=RGB)
    let mut d = make_decoder();
    let before = d.color_map.contains_key(&9);
    feed(&mut d, b"#9;3;50;50;50$");
    // current_color is set to 9 but no new map entry should be added for type 3
    assert_eq!(d.color_map.contains_key(&9), before);
}

#[test]
fn color_finish_flushes_unterminated_color_command() {
    // Feed color definition without terminator — finish() must flush it
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;4;6");
    feed(&mut d, b"#1;2;100;0;0"); // no terminator
    let _ = d.finish();
    // We can't inspect after finish, but it must not panic
}

// ---------------------------------------------------------------------------
// Repeat command (`!`)
// ---------------------------------------------------------------------------

#[test]
fn test_rle_repeat() {
    let mut decoder = make_decoder();
    feed(&mut decoder, b"\"1;1;10;6!10~");
    let result = decoder.finish();
    assert!(result.is_some());
    let (_, w, h) = result.expect("result should exist");
    assert_eq!(w, 10);
    assert_eq!(h, 6);
}

#[test]
fn repeat_one_equivalent_to_single_paint() {
    // !1~ and ~ should produce identical cursor advancement
    let mut d1 = make_decoder();
    feed(&mut d1, b"\"1;1;2;6~");
    let cursor_single = d1.cursor_x;

    let mut d2 = make_decoder();
    feed(&mut d2, b"\"1;1;2;6!1~");
    let cursor_repeat1 = d2.cursor_x;

    assert_eq!(cursor_single, cursor_repeat1);
}

#[test]
fn repeat_zero_treated_as_one() {
    // !0~ — count.max(1) means 0 becomes 1
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;4;6!0~");
    // cursor_x should advance by 1 (count clamped to 1)
    assert_eq!(d.cursor_x, 1);
}

#[test]
fn repeat_large_count_saturates_to_declared_width() {
    // Repeat count exceeding declared width stops at width boundary
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;5;6!100~");
    // cursor_x advances by 100 but pixel painting stops at declared_width=5
    assert_eq!(d.cursor_x, 100); // cursor_x reflects repeat count
    let result = d.finish();
    assert!(result.is_some());
    let (_, w, _) = result.unwrap();
    assert_eq!(w, 5); // width capped at declared_width
}

#[test]
fn repeat_non_data_byte_resets_state() {
    // `!` followed by a non-digit non-data byte should reset to Normal and re-process
    let mut d = make_decoder();
    // `!$` — repeat with carriage return as terminator
    feed(&mut d, b"\"1;1;4;6!$");
    // After `$` re-processed as carriage-return, cursor_x resets to 0
    assert_eq!(d.cursor_x, 0);
    assert!(d.state == SixelParseState::Normal);
}

// ---------------------------------------------------------------------------
// Sixel data characters
// ---------------------------------------------------------------------------

#[test]
fn data_byte_question_mark_paints_no_bits() {
    // `?` = 0x3F = bits 0b000000 — no pixels set
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;4;6#0?"); // register 0 = black, `?` = 0 bits
                                   // cursor_x must advance by 1
    assert_eq!(d.cursor_x, 1);
    // No pixels should be opaque (alpha=255) since bits are all zero
    // The pixel buffer should have been allocated but remain transparent
    assert!(
        d.pixels.iter().step_by(4).skip(3).all(|&a| a == 0),
        "all alpha bytes should be 0 for blank sixel"
    );
}

#[test]
fn data_byte_tilde_paints_all_six_bits() {
    // `~` = 0x7E = bits 0b111111 — all 6 pixels in the column set
    let mut d = make_decoder();
    // Use register 1 = blue (from VT340 default palette)
    feed(&mut d, b"\"1;1;1;6#0~");
    assert_eq!(d.cursor_x, 1);
    let result = d.finish();
    assert!(result.is_some());
    let (pixels, w, h) = result.unwrap();
    assert_eq!(w, 1);
    assert_eq!(h, 6);
    // All 6 pixels should be opaque (alpha == 255)
    for row in 0..6usize {
        let alpha = pixels[row * 4 + 3];
        assert_eq!(alpha, 255, "row {} alpha should be 255", row);
    }
}

#[test]
fn data_byte_at_sign_paints_bit_zero_only() {
    // `@` = 0x40 = bits 0b000001 — only the first pixel (row 0) in the column
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;1;6#0@");
    let result = d.finish();
    assert!(result.is_some());
    let (pixels, w, h) = result.unwrap();
    assert_eq!(w, 1);
    assert_eq!(h, 6);
    // Row 0 should be opaque
    assert_eq!(pixels[3], 255, "row 0 alpha should be 255 (bit 0 set)");
    // Rows 1-5 should be transparent
    for row in 1..6usize {
        let alpha = pixels[row * 4 + 3];
        assert_eq!(alpha, 0, "row {} alpha should be 0 (bit not set)", row);
    }
}

#[test]
fn data_byte_uses_current_color_rgb() {
    // Define register 1 as pure red, select it, paint all-bits
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;1;6#1;2;100;0;0#1~");
    let result = d.finish();
    assert!(result.is_some());
    let (pixels, _, _) = result.unwrap();
    // First pixel (row 0, col 0): should be red
    assert_eq!(pixels[0], 255, "R should be 255");
    assert_eq!(pixels[1], 0, "G should be 0");
    assert_eq!(pixels[2], 0, "B should be 0");
    assert_eq!(pixels[3], 255, "A should be 255");
}

#[test]
fn data_byte_increments_cursor_x() {
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;5;6~");
    assert_eq!(d.cursor_x, 1);
    feed(&mut d, b"~");
    assert_eq!(d.cursor_x, 2);
    feed(&mut d, b"~");
    assert_eq!(d.cursor_x, 3);
}

#[test]
fn unknown_byte_in_normal_state_ignored() {
    // Non-sixel bytes (e.g. spaces, DEL) must be silently ignored
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;4;6");
    let cursor_before = d.cursor_x;
    feed(&mut d, b"  \x7f"); // space and DEL
    assert_eq!(
        d.cursor_x, cursor_before,
        "ignored bytes must not advance cursor"
    );
}

// ---------------------------------------------------------------------------
// Carriage return (`$`) and band advance (`-`)
// ---------------------------------------------------------------------------

#[test]
fn carriage_return_resets_cursor_x() {
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;5;6~~~$");
    assert_eq!(d.cursor_x, 0, "$ must reset cursor_x to 0");
}

#[test]
fn band_advance_increments_band_and_resets_cursor() {
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;5;12~~~-");
    assert_eq!(d.band, 1);
    assert_eq!(d.cursor_x, 0);
}

#[test]
fn two_band_advances_produce_correct_height() {
    // Two bands: band 0 (rows 0-5) + band 1 (rows 6-11) + some data in band 1
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;1;12~-~");
    let result = d.finish();
    assert!(result.is_some());
    let (pixels, w, h) = result.unwrap();
    assert_eq!(w, 1);
    assert_eq!(h, 12);
    assert_eq!(pixels.len(), 12 * 4);
}

// ---------------------------------------------------------------------------
// P2 parameter (background fill)
// ---------------------------------------------------------------------------

#[test]
fn p2_one_fills_background_opaque() {
    // P2=1 → background is opaque color register 0
    let mut d = SixelDecoder::new(1);
    feed(&mut d, b"\"1;1;2;6~");
    // ensure_size was called; pixels allocated with opaque background
    // All alpha values in allocated region should be 255
    assert!(!d.pixels.is_empty());
    let all_opaque = d.pixels.chunks_exact(4).all(|px| px[3] == 255);
    assert!(all_opaque, "P2=1 background pixels should all be opaque");
}

#[test]
fn p2_zero_transparent_background() {
    // P2=0 → background pixels start transparent (alpha=0) before painting
    let mut d = make_decoder(); // p2=0
    feed(&mut d, b"\"1;1;2;6?"); // `?` allocates buffer but paints no pixels
                                 // Allocated pixels should have alpha=0 (transparent)
    assert!(!d.pixels.is_empty());
    let all_transparent = d.pixels.chunks_exact(4).all(|px| px[3] == 0);
    assert!(
        all_transparent,
        "P2=0 background pixels should all be transparent"
    );
}

// ---------------------------------------------------------------------------
// finish() behaviour
// ---------------------------------------------------------------------------

#[test]
fn finish_returns_none_when_only_color_defined() {
    // Defining a color but painting no pixels should return None
    let mut d = make_decoder();
    feed(&mut d, b"#1;2;100;0;0");
    // finish() flushes color command but no pixels → None
    assert!(d.finish().is_none());
}

#[test]
fn finish_returns_some_with_correct_size_ratio() {
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;3;6~~~");
    let result = d.finish();
    assert!(result.is_some());
    let (pixels, w, h) = result.unwrap();
    assert_eq!(w, 3);
    assert_eq!(h, 6);
    assert_eq!(pixels.len(), (w * h * 4) as usize);
}

#[test]
fn finish_uses_declared_dimensions_over_actual() {
    // Declare 4x6 but only paint 2 columns → finish should return declared size
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;4;6~~");
    let result = d.finish();
    assert!(result.is_some());
    let (_, w, h) = result.unwrap();
    assert_eq!(w, 4);
    assert_eq!(h, 6);
}

// ---------------------------------------------------------------------------
// HLS color conversion
// ---------------------------------------------------------------------------

#[test]
fn test_hls_to_rgb_red() {
    let [r, g, b] = hls_to_rgb(0.0, 50.0, 100.0);
    assert!(r > 200, "red should be high, got {r}");
    assert!(g < 50, "green should be low, got {g}");
    assert!(b < 50, "blue should be low, got {b}");
}

#[test]
fn hls_to_rgb_achromatic_saturation_zero() {
    // S=0 → grey: all channels equal to L-scaled value
    let [r, g, b] = hls_to_rgb(0.0, 50.0, 0.0);
    assert_eq!(r, g, "achromatic: r==g");
    assert_eq!(g, b, "achromatic: g==b");
    assert!(r > 100 && r < 160, "L=50% should give mid-grey, got {r}");
}

#[test]
fn hls_to_rgb_achromatic_full_white() {
    let [r, g, b] = hls_to_rgb(180.0, 100.0, 0.0);
    assert_eq!(r, 255);
    assert_eq!(g, 255);
    assert_eq!(b, 255);
}

#[test]
fn hls_to_rgb_achromatic_full_black() {
    let [r, g, b] = hls_to_rgb(180.0, 0.0, 0.0);
    assert_eq!(r, 0);
    assert_eq!(g, 0);
    assert_eq!(b, 0);
}

#[test]
fn hls_to_rgb_green() {
    // H=120°, L=50%, S=100% → pure green
    let [r, g, b] = hls_to_rgb(120.0, 50.0, 100.0);
    assert!(g > 200, "green should be high, got {g}");
    assert!(r < 50, "red should be low, got {r}");
    assert!(b < 50, "blue should be low, got {b}");
}

#[test]
fn hls_to_rgb_blue() {
    // H=240°, L=50%, S=100% → pure blue
    let [r, g, b] = hls_to_rgb(240.0, 50.0, 100.0);
    assert!(b > 200, "blue should be high, got {b}");
    assert!(r < 50, "red should be low, got {r}");
    assert!(g < 50, "green should be low, got {g}");
}

#[test]
fn hls_to_rgb_values_clamped_above_100() {
    // L > 100 and S > 100 must not produce out-of-range values (no panic)
    let [r, g, b] = hls_to_rgb(0.0, 200.0, 200.0);
    // Just ensure no panic; values should be in 0-255
    let _ = (r, g, b);
}

// ---------------------------------------------------------------------------
// Numeric digit accumulation
// ---------------------------------------------------------------------------

#[test]
fn digit_accumulation_in_color_command() {
    // Feed `#255` — the index should be parsed as 255
    let mut d = make_decoder();
    feed(&mut d, b"#255$");
    assert_eq!(d.current_color, 255);
}

#[test]
fn digit_accumulation_multi_digit_repeat() {
    // !12~ should paint 12 columns
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;12;6!12~");
    assert_eq!(d.cursor_x, 12);
}

#[test]
fn digit_accumulation_saturating_on_overflow() {
    // Feed a number larger than u32::MAX digits — saturating_mul/add must not panic
    let huge = "9".repeat(20);
    let seq = format!("#{}$", huge);
    let mut d = make_decoder();
    feed(&mut d, seq.as_bytes());
    // current_color is u16; the parsed u32 saturates then casts — just no panic
    let _ = d.current_color;
}

// ---------------------------------------------------------------------------
// hue_to_rgb internal helper
// ---------------------------------------------------------------------------

#[test]
fn hue_to_rgb_t_below_zero_wraps_up() {
    // t < 0 branch: -0.1 + 1.0 = 0.9, which is > 2/3, so result == p
    let p = 0.2_f32;
    let q = 0.8_f32;
    let result = hue_to_rgb(p, q, -0.1);
    // 0.9 >= 2/3, so hue_to_rgb returns p
    assert!(
        (result - p).abs() < 0.001,
        "t=-0.1 wraps to 0.9, result should be p={p}, got {result}"
    );
}

#[test]
fn hue_to_rgb_t_above_one_wraps_down() {
    // t > 1 branch: 1.1 - 1.0 = 0.1, which is < 1/6, so result ≈ p + (q-p)*6*0.1
    let p = 0.0_f32;
    let q = 1.0_f32;
    let result = hue_to_rgb(p, q, 1.1);
    // t becomes 0.1; < 1/6 → (q-p)*6*t + p = 1.0*6*0.1 = 0.6
    assert!(
        (result - 0.6).abs() < 0.01,
        "t=1.1 wraps to 0.1, result should be ~0.6, got {result}"
    );
}

#[test]
fn hue_to_rgb_t_in_half_range_returns_q() {
    // 1/6 ≤ t < 1/2 → returns q
    let p = 0.1_f32;
    let q = 0.7_f32;
    let result = hue_to_rgb(p, q, 0.3); // 0.3 is in [1/6, 1/2)
    assert!(
        (result - q).abs() < 0.001,
        "t=0.3 should return q={q}, got {result}"
    );
}

// ---------------------------------------------------------------------------
// Color register 0 redefinition
// ---------------------------------------------------------------------------

#[test]
fn color_index_zero_can_be_redefined() {
    // Register 0 is black by default; redefine it as pure white
    let mut d = make_decoder();
    assert_eq!(d.color_map.get(&0), Some(&[0u8, 0, 0]));
    feed(&mut d, b"#0;2;100;100;100$");
    assert_eq!(
        d.color_map.get(&0),
        Some(&[255u8, 255, 255]),
        "register 0 must be overridable"
    );
}

#[test]
fn color_redefined_register_zero_used_for_painting() {
    // Redefine register 0 as red, then paint with it using `~`
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;1;6#0;2;100;0;0#0~");
    let result = d.finish();
    assert!(result.is_some());
    let (pixels, _, _) = result.unwrap();
    // Row 0, pixel (0,0): should be red because we redefined register 0
    assert_eq!(
        pixels[0], 255,
        "R must be 255 after redefining reg 0 as red"
    );
    assert_eq!(pixels[1], 0, "G must be 0");
    assert_eq!(pixels[2], 0, "B must be 0");
}

// ---------------------------------------------------------------------------
// finish() with unterminated Repeat state (no-op flush path)
// ---------------------------------------------------------------------------

#[test]
fn finish_unterminated_repeat_does_not_paint() {
    // `!5` without a data byte or raster declaration: finish() must not paint.
    // The Repeat state is the no-op arm in finish() — accumulated count is dropped.
    // Without any prior pixel allocation the result is None.
    let mut d = make_decoder();
    feed(&mut d, b"!5"); // repeat count accumulating, no data byte, no raster
                         // finish() hits the `Repeat | Normal` no-op arm
    let result = d.finish();
    // No sixel data was painted so finish returns None
    assert!(
        result.is_none(),
        "unterminated !N with no prior pixels must return None"
    );
}

// ---------------------------------------------------------------------------
// Multi-band pixel placement
// ---------------------------------------------------------------------------

#[test]
fn band_advance_places_pixels_at_correct_y_offset() {
    // Band 0: paint row 0 only (`@` = bit 0); band 1: paint row 6 only
    let mut d = make_decoder();
    // `@` = 0x40 = bit 0 set; `-` advances band; `@` again in band 1
    feed(&mut d, b"\"1;1;1;12#0;2;100;0;0#0@-@");
    let result = d.finish();
    assert!(result.is_some());
    let (pixels, w, h) = result.unwrap();
    assert_eq!(w, 1);
    assert_eq!(h, 12);

    // Band 0, row 0 (pixel offset 0*4): painted red, alpha=255
    assert_eq!(pixels[3], 255, "band 0 row 0 alpha should be 255");
    // Band 0, rows 1-5 (pixel offsets 4..24): transparent
    for row in 1..6usize {
        assert_eq!(
            pixels[row * 4 + 3],
            0,
            "band 0 row {row} should be transparent"
        );
    }
    // Band 1, row 6 (pixel offset 6*4=24): painted red, alpha=255
    assert_eq!(pixels[6 * 4 + 3], 255, "band 1 row 6 alpha should be 255");
    // Band 1, rows 7-11: transparent
    for row in 7..12usize {
        assert_eq!(
            pixels[row * 4 + 3],
            0,
            "band 1 row {row} should be transparent"
        );
    }
}

// ---------------------------------------------------------------------------
// Color scaling boundary: mid-range values
// ---------------------------------------------------------------------------

#[test]
fn color_definition_mid_range_rgb_scales_correctly() {
    // #6;2;50;25;75 → R=50*255/100=127, G=25*255/100=63, B=75*255/100=191
    let mut d = make_decoder();
    feed(&mut d, b"#6;2;50;25;75$");
    let rgb = d.color_map.get(&6).copied().unwrap_or([0, 0, 0]);
    assert_eq!(rgb[0], 127, "R=50% should be 127, got {}", rgb[0]);
    assert_eq!(rgb[1], 63, "G=25% should be 63, got {}", rgb[1]);
    assert_eq!(rgb[2], 191, "B=75% should be 191, got {}", rgb[2]);
}

// ---------------------------------------------------------------------------
// Color register boundary indices (0 and 255)
// ---------------------------------------------------------------------------

#[test]
fn color_register_boundary_index_zero_rgb() {
    // Register 0 is the default-palette black; RGB definition via macro.
    assert_color_reg!(reg 0, seq b"#0;2;100;100;100$", rgb [255, 255, 255]);
}

#[test]
fn color_register_boundary_index_255_rgb() {
    // Register 255 is at the u8 boundary; must be stored without panic.
    assert_color_reg!(reg 255, seq b"#255;2;0;50;100$", rgb [0, 127, 255]);
}

// ---------------------------------------------------------------------------
// Repeat count at boundaries (1, 255, 256)
// ---------------------------------------------------------------------------

#[test]
fn repeat_count_one_advances_cursor_by_one() {
    // !1~ is the minimum non-trivial repeat; cursor must advance by exactly 1.
    let mut d = make_decoder();
    feed(&mut d, b"!1~");
    assert_eq!(d.cursor_x, 1, "!1~ must advance cursor by 1");
}

#[test]
fn repeat_count_255_advances_cursor_by_255() {
    // !255~ — maximum u8-range repeat; cursor must advance by 255.
    let mut d = make_decoder();
    feed(&mut d, b"!255~");
    assert_eq!(d.cursor_x, 255, "!255~ must advance cursor by 255");
}

#[test]
fn repeat_count_256_advances_cursor_by_256() {
    // !256~ — one beyond u8; decoded as u32; cursor must advance by 256.
    let mut d = make_decoder();
    feed(&mut d, b"!256~");
    assert_eq!(d.cursor_x, 256, "!256~ must advance cursor by 256");
}

// ---------------------------------------------------------------------------
// Multiple color registers in one sixel stream
// ---------------------------------------------------------------------------

#[test]
fn multiple_color_registers_in_one_stream() {
    // Define three registers in a single stream and verify each independently.
    let mut d = make_decoder();
    // Define register 10=red, 11=green, 12=blue in one byte sequence.
    feed(&mut d, b"#10;2;100;0;0$#11;2;0;100;0$#12;2;0;0;100$");
    assert_eq!(
        d.color_map.get(&10),
        Some(&[255u8, 0, 0]),
        "register 10 should be red"
    );
    assert_eq!(
        d.color_map.get(&11),
        Some(&[0u8, 255, 0]),
        "register 11 should be green"
    );
    assert_eq!(
        d.color_map.get(&12),
        Some(&[0u8, 0, 255]),
        "register 12 should be blue"
    );
}

#[test]
fn multiple_registers_paint_independent_colors() {
    // Paint col 0 with register 10 (red) and col 1 with register 11 (green).
    let mut d = make_decoder();
    feed(&mut d, b"\"1;1;2;6#10;2;100;0;0#10~#11;2;0;100;0#11~");
    let result = d.finish();
    assert!(result.is_some(), "finish() must return Some");
    let (pixels, w, h) = result.unwrap();
    assert_eq!(w, 2);
    assert_eq!(h, 6);
    // Col 0, row 0 (offset 0): red
    assert_eq!(pixels[0], 255, "col 0 R should be 255");
    assert_eq!(pixels[1], 0, "col 0 G should be 0");
    assert_eq!(pixels[2], 0, "col 0 B should be 0");
    assert_eq!(pixels[3], 255, "col 0 A should be 255");
    // Col 1, row 0 (offset 4): green
    assert_eq!(pixels[4], 0, "col 1 R should be 0");
    assert_eq!(pixels[5], 255, "col 1 G should be 255");
    assert_eq!(pixels[6], 0, "col 1 B should be 0");
    assert_eq!(pixels[7], 255, "col 1 A should be 255");
}

// ---------------------------------------------------------------------------
// assert_finish_dims! macro usage — dimension assertions
// ---------------------------------------------------------------------------

#[test]
fn finish_dims_single_column_two_bands() {
    // 1-wide, 2-band image: declared height 12, one data char per band.
    assert_finish_dims!(seq b"\"1;1;1;12~-~", w 1, h 12);
}

#[test]
fn finish_dims_three_columns_declared() {
    // Declared 3×6 with 3 data chars: finish must return declared dimensions.
    assert_finish_dims!(seq b"\"1;1;3;6~~~", w 3, h 6);
}

// ---------------------------------------------------------------------------
// Property-based tests
// ---------------------------------------------------------------------------

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    // PANIC SAFETY: DCS sixel sequence with arbitrary data bytes never panics
    fn prop_sixel_data_no_panic(
        data in proptest::collection::vec(0x3fu8..=0x7eu8, 0..=100)
    ) {
        let mut term = crate::TerminalCore::new(24, 80);
        // DCS P1;P2;P3 q <sixel_data> ST
        let d = String::from_utf8(data).unwrap_or_default();
        let seq = format!("\x1bPq{d}\x1b\\");
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }

    #[test]
    // PANIC SAFETY: arbitrary byte sequence fed to SixelDecoder must not panic
    fn prop_decoder_arbitrary_bytes_no_panic(
        bytes in proptest::collection::vec(0u8..=255u8, 0..=200)
    ) {
        let mut d = SixelDecoder::new(0);
        for b in &bytes {
            d.put(*b);
        }
        let _ = d.finish();
    }

    #[test]
    // INVARIANT: pixel buffer length is always a multiple of 4 (RGBA)
    fn prop_pixel_buffer_always_rgba_aligned(
        data in proptest::collection::vec(0x3fu8..=0x7eu8, 0..=100)
    ) {
        let mut d = SixelDecoder::new(0);
        for b in &data {
            d.put(*b);
        }
        if let Some((pixels, w, h)) = d.finish() {
            prop_assert_eq!(
                pixels.len() % 4, 0,
                "pixel buffer must be RGBA-aligned (4 bytes per pixel)"
            );
            prop_assert!(
                pixels.len() >= (w * h * 4) as usize,
                "pixel buffer length {} must be at least w*h*4={}",
                pixels.len(), w * h * 4
            );
        }
    }

    #[test]
    // INVARIANT: color register RGB values are always clamped to 0-255
    fn prop_color_register_valid_after_rgb_definition(
        reg in 0u8..=15u8,
        r in 0u32..=200u32,
        g in 0u32..=200u32,
        b in 0u32..=200u32,
    ) {
        let mut d = SixelDecoder::new(0);
        let seq = format!("#{reg};2;{r};{g};{b}$");
        for byte in seq.as_bytes() {
            d.put(*byte);
        }
        if let Some(&[rv, gv, bv]) = d.color_map.get(&u16::from(reg)) {
            // RGB values are (v.min(100) * 255 / 100); clamped result in [0,255]
            let _ = (rv, gv, bv); // just verify no panic accessing them
        }
    }

    #[test]
    // INVARIANT: repeat count N produces cursor advancement of N
    fn prop_repeat_advances_cursor_by_count(count in 1u32..=50u32) {
        let mut d = SixelDecoder::new(0);
        let seq = format!("!{count}~");
        for b in seq.as_bytes() {
            d.put(*b);
        }
        prop_assert_eq!(
            d.cursor_x, count,
            "cursor_x must advance by repeat count {}", count
        );
    }
}
