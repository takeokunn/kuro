/// HLS to RGB conversion (H: 0-360, L: 0-100, S: 0-100).
#[expect(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    reason = "L/S are clamped to [0,1] and hue_to_rgb returns [0,1]; multiplied by 255 gives [0,255] — always fits in u8"
)]
#[expect(
    clippy::many_single_char_names,
    reason = "h/l/s/p/q/r/g/b are standard HLS and RGB color component abbreviations"
)]
fn hls_to_rgb(h: f32, l: f32, s: f32) -> [u8; 3] {
    let l = (l / 100.0).clamp(0.0, 1.0);
    let s = (s / 100.0).clamp(0.0, 1.0);

    if s == 0.0 {
        let v = (l * 255.0) as u8;
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

    [(r * 255.0) as u8, (g * 255.0) as u8, (b * 255.0) as u8]
}

fn hue_to_rgb(p: f32, q: f32, mut t: f32) -> f32 {
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
