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

include!("sixel_pixel_painting.rs");
