//! Property-based and example-based tests for `sixel` parsing.
//!
//! Module under test: `parser/sixel.rs`
//! Tier: T5 — `ProptestConfig::with_cases(64)`

use super::super::*;
use super::tests_support::*;

// ---------------------------------------------------------------------------
// Basic construction / empty decode
// ---------------------------------------------------------------------------

#[test]
fn test_empty_sixel() {
    let decoder = decode(b"");
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

#[test]
fn resolved_output_dimensions_prefers_declared_size_when_buffer_is_large_enough() {
    assert_resolved_output_dimensions!(
        8,
        6,
        4,
        3,
        8 * 6 * 4,
        expected Some([8, 6])
    );
}

#[test]
fn resolved_output_dimensions_falls_back_to_actual_size_when_declared_buffer_is_too_small() {
    assert_resolved_output_dimensions!(
        8,
        6,
        4,
        3,
        4 * 3 * 4,
        expected Some([4, 3])
    );
}

#[test]
fn resolved_output_dimensions_returns_none_when_no_size_is_usable() {
    assert_resolved_output_dimensions!(8, 6, 0, 0, 0, expected None);
}

// ---------------------------------------------------------------------------
// Single pixel / raster
// ---------------------------------------------------------------------------

#[test]
fn test_single_pixel_sixel() {
    let decoder = decode(b"\"1;1;1;6#0~");

    let (pixels, w, h) = finish_pixels(decoder);
    assert_eq!(w, 1);
    assert_eq!(h, 6);
    assert_eq!(pixels.len(), 24); // 1 * 6 * RGBA(4)
}

// ---------------------------------------------------------------------------
// Raster attributes (`"`)
// ---------------------------------------------------------------------------

#[test]
fn raster_sets_declared_dimensions() {
    assert_finish_dims!(seq b"\"1;1;40;20?", w 40, h 20);
}

#[test]
fn raster_fewer_than_four_params_ignored() {
    // "Pan;Pad;Ph — only 3 params, must not set declared dimensions
    let d = decode(b"\"1;1;40?"); // 3 params (0,0,40) — params[3] missing
    assert_declared_dims!(d, w 0, h 0);
}

#[test]
fn raster_zero_width_ignored() {
    // "1;1;0;20 — zero width must not set declared dimensions
    let d = decode(b"\"1;1;0;20?");
    assert_declared_dims!(d, w 0, h 0);
}

#[test]
fn raster_zero_height_ignored() {
    let d = decode(b"\"1;1;40;0?");
    assert_declared_dims!(d, w 0, h 0);
}

#[test]
fn raster_oversized_dimensions_ignored() {
    // 4097 * 4097 exceeds MAX_SIXEL_SIZE (4096*4096)
    let d = decode(b"\"1;1;4097;4097?");
    assert_declared_dims!(d, w 0, h 0);
}

#[test]
fn raster_finish_flushes_unterminated_command() {
    assert_finish_dims!(seq b"\"1;1;8;6", w 8, h 6);
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
fn color_definition_rejects_rgb_above_100() {
    let mut d = decode(b"");
    let original = d.color_map.get(&4).copied();
    feed(&mut d, b"#4;2;200;200;200$");

    assert_eq!(d.current_color, 4);
    assert_eq!(
        d.color_map.get(&4).copied(),
        original,
        "invalid RGB definition must keep the previous register value"
    );
}

#[test]
fn color_select_only_sets_current_color() {
    // #N with fewer than 5 params only selects current_color without redefining map entry
    let mut d = decode(b"");
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
    let d = decode(b"#~"); // finalize color command with empty params, then paint
                           // Must not panic; current_color stays 0
    assert_eq!(d.current_color, 0);
}

#[test]
fn color_index_above_max_register_is_ignored() {
    let d = decode(b"#65535;2;50;50;50$");
    assert_eq!(d.current_color, 0);
    assert!(
        !d.color_map.contains_key(&1023),
        "out-of-range register must not be redirected to register 1023"
    );
}

#[test]
fn color_index_above_u16_is_ignored() {
    let d = decode(b"#70000;2;50;50;50$");
    assert_eq!(d.current_color, 0);
    assert!(!d.color_map.contains_key(&1023));
}

#[test]
fn color_index_at_max_register_is_stored() {
    // Register 1023 is the last valid register; must be stored normally.
    let d = decode(b"#1023;2;50;50;50$");
    assert!(d.color_map.contains_key(&1023));
}

#[test]
fn color_index_just_below_max_is_stored() {
    // Register 1022 is within bounds.
    let d = decode(b"#1022;2;100;0;0$");
    assert!(d.color_map.contains_key(&1022));
}

#[test]
fn color_hls_definition() {
    // #1;1;0;50;100 → HLS(0°, 50%, 100%) → red
    let d = decode(b"#5;1;0;50;100$");
    let rgb = d.color_map.get(&5).copied().unwrap_or([0, 0, 0]);
    assert!(rgb[0] > 200, "hls red: r should be high, got {}", rgb[0]);
    assert!(rgb[1] < 50, "hls red: g should be low, got {}", rgb[1]);
    assert!(rgb[2] < 50, "hls red: b should be low, got {}", rgb[2]);
}

#[test]
fn color_hls_rejects_hue_above_360() {
    let mut d = decode(b"");
    let original = d.color_map.get(&5).copied();
    feed(&mut d, b"#5;1;361;50;100$");

    assert_eq!(d.current_color, 5);
    assert_eq!(d.color_map.get(&5).copied(), original);
}

#[test]
fn color_hls_rejects_lightness_or_saturation_above_100() {
    let mut d = decode(b"");
    let original = d.color_map.get(&5).copied();

    feed(&mut d, b"#5;1;0;101;100$");
    assert_eq!(d.color_map.get(&5).copied(), original);

    feed(&mut d, b"#5;1;0;50;101$");
    assert_eq!(d.color_map.get(&5).copied(), original);
}

#[test]
fn color_unknown_type_does_not_insert() {
    // Color type 3 is not defined (only 1=HLS, 2=RGB)
    let mut d = decode(b"");
    let before = d.color_map.contains_key(&9);
    feed(&mut d, b"#9;3;50;50;50$");
    // current_color is set to 9 but no new map entry should be added for type 3
    assert_eq!(d.color_map.contains_key(&9), before);
}

#[test]
fn color_finish_flushes_unterminated_color_command() {
    let _ = decode(b"\"1;1;4;6#1;2;100;0;0").finish();
}

// ---------------------------------------------------------------------------
// Repeat command (`!`)
// ---------------------------------------------------------------------------

#[test]
fn test_rle_repeat() {
    let decoder = decode(b"\"1;1;10;6!10~");
    assert_finish_dims!(decoder decoder, w 10, h 6);
}

#[test]
fn repeat_one_equivalent_to_single_paint() {
    let cursor_single = decode(b"\"1;1;2;6~").cursor_x;
    let cursor_repeat1 = decode(b"\"1;1;2;6!1~").cursor_x;

    assert_eq!(cursor_single, cursor_repeat1);
}

#[test]
fn repeat_zero_treated_as_one() {
    // !0~ — count.max(1) means 0 becomes 1
    let d = decode(b"\"1;1;4;6!0~");
    // cursor_x should advance by 1 (count clamped to 1)
    assert_eq!(d.cursor_x, 1);
}

#[test]
fn repeat_large_count_saturates_to_declared_width() {
    // Repeat count exceeding declared width stops at width boundary
    let d = decode(b"\"1;1;5;6!100~");
    // cursor_x advances by 100 but pixel painting stops at declared_width=5
    assert_eq!(d.cursor_x, 100); // cursor_x reflects repeat count
    assert_finish_dims!(decoder d, w 5, h 6);
}

#[test]
fn repeat_non_data_byte_resets_state() {
    // `!` followed by a non-digit non-data byte should reset to Normal and re-process
    let d = decode(b"\"1;1;4;6!$"); // `!$` — repeat with carriage return as terminator
                                    // After `$` re-processed as carriage-return, cursor_x resets to 0
    assert_eq!(d.cursor_x, 0);
    assert!(d.state == SixelParseState::Normal);
}

/// Regression: a flood of `;` separators in a parameterized command must not
/// grow `params` without bound. Before the cap, each `;` pushed one `u32`, so a
/// stream of separators (`#1;;;…`) allocated 4 bytes of heap per input byte —
/// an OOM DoS. The cap drops excess parameters while parsing continues, so a
/// following valid color command still resolves correctly.
#[test]
fn parameter_flood_is_capped_and_parsing_survives() {
    let mut d = make_decoder();
    // Color command `#1` followed by 10_000 empty parameters.
    let mut seq = b"#1".to_vec();
    seq.extend(std::iter::repeat_n(b';', 10_000));
    feed(&mut d, &seq);
    assert!(
        d.params.len() <= 16,
        "sixel params must be capped, got {}",
        d.params.len()
    );

    // A subsequent well-formed color definition still registers correctly,
    // proving the flood did not wedge the parser (`$` terminates the command).
    feed(&mut d, b"#2;2;100;0;0$");
    assert_eq!(d.color_map.get(&2), Some(&[255, 0, 0]));
}

#[path = "pixel_painting.rs"]
mod pixel_painting;
