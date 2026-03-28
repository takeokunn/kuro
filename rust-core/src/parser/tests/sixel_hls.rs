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
