use super::super::*;

pub(super) fn make_decoder() -> SixelDecoder {
    SixelDecoder::new(0)
}

pub(super) fn feed(decoder: &mut SixelDecoder, bytes: &[u8]) {
    for b in bytes {
        decoder.put(*b);
    }
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
        let _result = _d.finish();
        assert!(_result.is_some(), "finish() returned None");
        let (_, _fw, _fh) = _result.unwrap();
        assert_eq!(_fw, $w as u32, "width mismatch");
        assert_eq!(_fh, $h as u32, "height mismatch");
    }};
}
