use super::super::*;

pub(super) fn make_decoder() -> SixelDecoder {
    SixelDecoder::new(0)
}

pub(super) fn feed(decoder: &mut SixelDecoder, bytes: &[u8]) {
    for b in bytes {
        decoder.put(*b);
    }
}

pub(super) fn decode(bytes: &[u8]) -> SixelDecoder {
    let mut decoder = make_decoder();
    feed(&mut decoder, bytes);
    decoder
}

pub(super) fn finish_or_panic(decoder: SixelDecoder) -> (Vec<u8>, u32, u32) {
    decoder.finish().expect("finish() returned None")
}

pub(super) fn finish_pixels(decoder: SixelDecoder) -> (Vec<u8>, u32, u32) {
    finish_or_panic(decoder)
}

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

macro_rules! assert_finish_dims {
    (seq $seq:expr, w $w:expr, h $h:expr) => {{
        let mut _d = make_decoder();
        feed(&mut _d, $seq);
        let (_, _fw, _fh) = finish_or_panic(_d);
        assert_eq!(_fw, $w as u32, "width mismatch");
        assert_eq!(_fh, $h as u32, "height mismatch");
    }};
    (decoder $decoder:expr, w $w:expr, h $h:expr) => {{
        let (_, _fw, _fh) = finish_or_panic($decoder);
        assert_eq!(_fw, $w as u32, "width mismatch");
        assert_eq!(_fh, $h as u32, "height mismatch");
    }};
}

macro_rules! assert_resolved_output_dimensions {
    ($declared_width:expr, $declared_height:expr, $actual_width:expr, $actual_height:expr, $buffer_len:expr, expected Some([$expected_width:expr, $expected_height:expr])) => {{
        assert_eq!(
            sixel_resolved_output_dimensions(
                $declared_width,
                $declared_height,
                $actual_width,
                $actual_height,
                $buffer_len,
            ),
            Some(($expected_width, $expected_height))
        );
    }};
    ($declared_width:expr, $declared_height:expr, $actual_width:expr, $actual_height:expr, $buffer_len:expr, expected None) => {{
        assert_eq!(
            sixel_resolved_output_dimensions(
                $declared_width,
                $declared_height,
                $actual_width,
                $actual_height,
                $buffer_len,
            ),
            None
        );
    }};
}

macro_rules! assert_pixel_rgba {
    (pixels $pixels:expr, offset $offset:expr, rgba [$r:expr, $g:expr, $b:expr, $a:expr]) => {{
        let _offset = $offset;
        assert_eq!(
            $pixels[_offset], $r as u8,
            "R mismatch at offset {}",
            _offset
        );
        assert_eq!(
            $pixels[_offset + 1],
            $g as u8,
            "G mismatch at offset {}",
            _offset
        );
        assert_eq!(
            $pixels[_offset + 2],
            $b as u8,
            "B mismatch at offset {}",
            _offset
        );
        assert_eq!(
            $pixels[_offset + 3],
            $a as u8,
            "A mismatch at offset {}",
            _offset
        );
    }};
}

macro_rules! assert_pixel_alpha {
    (pixels $pixels:expr, offset $offset:expr, alpha $alpha:expr) => {{
        let _offset = $offset;
        assert_eq!(
            $pixels[_offset + 3],
            $alpha as u8,
            "A mismatch at offset {}",
            _offset
        );
    }};
}

macro_rules! assert_pixel_alpha_rows {
    (pixels $pixels:expr, rows $start:tt .. $end:tt, alpha $alpha:expr) => {{
        for row in $start..$end {
            assert_eq!(
                $pixels[row * 4 + 3],
                $alpha as u8,
                "row {} alpha mismatch",
                row
            );
        }
    }};
}

macro_rules! assert_declared_dims {
    (decoder $decoder:expr, w $w:expr, h $h:expr) => {{
        assert_eq!($decoder.declared_width, $w, "declared width mismatch");
        assert_eq!($decoder.declared_height, $h, "declared height mismatch");
    }};
    ($decoder:expr, w $w:expr, h $h:expr) => {{
        assert_eq!($decoder.declared_width, $w, "declared width mismatch");
        assert_eq!($decoder.declared_height, $h, "declared height mismatch");
    }};
}
