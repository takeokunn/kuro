/// HLS to RGB conversion (H: 0-360, L: 0-100, S: 0-100).
#[expect(
    clippy::many_single_char_names,
    reason = "h/l/s/p/q/r/g/b are standard HLS and RGB color component abbreviations"
)]
pub(super) fn hls_to_rgb(h: f32, l: f32, s: f32) -> [u8; 3] {
    let l = (l / 100.0).clamp(0.0, 1.0);
    let s = (s / 100.0).clamp(0.0, 1.0);

    if s == 0.0 {
        let v = unit_interval_to_byte(l);
        return [v, v, v];
    }

    let q = if l < 0.5 {
        l * (1.0 + s)
    } else {
        l + s - l * s
    };
    let p = 2.0f32.mul_add(l, -q);
    let h = h / 360.0;

    let r = hue_to_rgb(p, q, h + 1.0 / 3.0);
    let g = hue_to_rgb(p, q, h);
    let b = hue_to_rgb(p, q, h - 1.0 / 3.0);

    [
        unit_interval_to_byte(r),
        unit_interval_to_byte(g),
        unit_interval_to_byte(b),
    ]
}

fn unit_interval_to_byte(value: f32) -> u8 {
    let scaled = value.clamp(0.0, 1.0) * 255.0;
    let mut byte = 0u8;
    while byte < u8::MAX && f32::from(byte.saturating_add(1)) <= scaled {
        byte = byte.saturating_add(1);
    }
    byte
}

pub(super) fn hue_to_rgb(p: f32, q: f32, mut t: f32) -> f32 {
    if t < 0.0 {
        t += 1.0;
    }
    if t > 1.0 {
        t -= 1.0;
    }
    if t < 1.0 / 6.0 {
        return ((q - p) * 6.0).mul_add(t, p);
    }
    if t < 1.0 / 2.0 {
        return q;
    }
    if t < 2.0 / 3.0 {
        return ((q - p) * (2.0 / 3.0 - t)).mul_add(6.0, p);
    }
    p
}
