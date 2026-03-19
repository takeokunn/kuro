use super::*;

#[test]
fn test_empty_sixel() {
    let decoder = SixelDecoder::new(0);
    assert!(decoder.finish().is_none());
}

#[test]
fn test_single_pixel_sixel() {
    let mut decoder = SixelDecoder::new(0);
    for b in b"\"1;1;1;6#0~" {
        decoder.put(*b);
    }

    let result = decoder.finish();
    assert!(result.is_some());
    let (pixels, w, h) = result.expect("result should exist");
    assert_eq!(w, 1);
    assert_eq!(h, 6);
    assert_eq!(pixels.len(), 24); // 1 * 6 * RGBA(4)
}

#[test]
fn test_color_definition() {
    let mut decoder = SixelDecoder::new(0);
    for b in b"#1;2;100;0;0$" {
        decoder.put(*b);
    }
    assert_eq!(decoder.color_map.get(&1), Some(&[255u8, 0, 0]));
}

#[test]
fn test_rle_repeat() {
    let mut decoder = SixelDecoder::new(0);
    for b in b"\"1;1;10;6!10~" {
        decoder.put(*b);
    }
    let result = decoder.finish();
    assert!(result.is_some());
    let (_, w, h) = result.expect("result should exist");
    assert_eq!(w, 10);
    assert_eq!(h, 6);
}

#[test]
fn test_hls_to_rgb_red() {
    let [r, g, b] = hls_to_rgb(0.0, 50.0, 100.0);
    assert!(r > 200, "red should be high, got {r}");
    assert!(g < 50, "green should be low, got {g}");
    assert!(b < 50, "blue should be low, got {b}");
}
