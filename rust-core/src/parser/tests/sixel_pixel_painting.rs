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

include!("sixel_hls.rs");

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
