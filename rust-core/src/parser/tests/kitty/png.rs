use super::support::encode_1x1_png_b64;
use crate::parser::kitty::{KittyCommand, KittyParams};

// ── PNG color-type expansion ───────────────────────────────────────────────────

test_png_pixel_round_trip!(
    test_kitty_png_grayscale_expands_to_rgb,
    color_type = png::ColorType::Grayscale,
    pixel = &[0x80],
    image_id = 32,
    fmt_var = Rgb,
    expected = vec![0x80u8, 0x80, 0x80],
    msg = "Grayscale PNG must expand to RGB bytes",
);

test_png_pixel_round_trip!(
    test_kitty_png_grayscale_alpha_expands_to_rgba,
    color_type = png::ColorType::GrayscaleAlpha,
    pixel = &[0x80, 0xC0],
    image_id = 33,
    fmt_var = Rgba,
    expected = vec![0x80u8, 0x80, 0x80, 0xC0],
    msg = "GrayscaleAlpha PNG must expand to RGBA bytes",
);

// ── KittyParams field coverage ─────────────────────────────────────────────────

test_kitty_payload_once_case!(
    test_kitty_params_empty_data_produces_none_action,
    payload = b"",
    check = |result: Option<KittyCommand>| assert!(
        result.is_none(),
        "empty APC payload must return None"
    ),
);

test_kitty_payload_once_case!(
    test_kitty_params_no_semicolon_no_data_chunk,
    payload = b"a=t,f=32,i=99",
    check = |result: Option<KittyCommand>| assert!(
        result.is_none(),
        "header with no ';' and no b64 data, zero dims must return None"
    ),
);

test_kitty_params_case!(
    test_kitty_params_duplicate_key_last_wins,
    params = b"f=24,f=32",
    check = |params: KittyParams| assert_eq!(
        params.format,
        Some(32),
        "duplicate key: last value (32) must win over first (24)"
    ),
);

test_kitty_params_case!(
    test_kitty_params_transmission_absent_defaults_to_direct,
    params = b"a=t,i=1",
    check = |params: KittyParams| assert!(
        params.transmission.is_none(),
        "transmission must be None when 't=' key is absent"
    ),
);

test_kitty_params_case!(
    test_kitty_params_quiet_one_parsed,
    params = b"q=1",
    check = |params: KittyParams| assert_eq!(params.quiet, 1, "q=1 must set quiet to 1"),
);

test_kitty_payload_once_case!(
    test_kitty_process_apc_empty_b64_after_semicolon_no_panic,
    payload = b"a=t,f=32,i=50;",
    check = |result: Option<KittyCommand>| assert!(
        result.is_none(),
        "empty b64 body with zero dims must return None without panicking"
    ),
);

// ── New coverage tests ─────────────────────────────────────────────────────────

// `KittyParams::parse` silently skips key-value pairs shorter than 3 bytes.
//
// The guard `if kv.len() < 3 || kv[1] != b'='` is designed to skip both
// zero-length entries and entries like "ab" (key without '=' at index 1).
// This test passes two short entries ("a" and "f=") and verifies that
// the trailing valid entry "i=5" is still parsed correctly.
test_kitty_params_case!(
    test_parse_params_short_kv_pairs_skipped,
    params = b"a,f=,i=5",
    check = |params: KittyParams| {
        assert_eq!(
            params.image_id,
            Some(5),
            "valid 'i=5' entry after short entries must be parsed"
        );
        assert!(
            params.action.is_none(),
            "short 'a' entry must be skipped (no action set)"
        );
        assert!(
            params.format.is_none(),
            "short 'f=' entry must be skipped (no format set)"
        );
    },
);

// `KittyParams::parse` skips entries where index 1 is not `=`.
//
// Exercises the `kv[1] != b'='` branch of the guard condition.
test_kitty_params_case!(
    test_parse_params_no_equals_at_index1_skipped,
    params = b"abc,i=3",
    check = |params: KittyParams| {
        assert_eq!(params.image_id, Some(3));
        // 'a' of "abc" was not parsed as an action because the whole entry was skipped
        assert!(
            params.action.is_none(),
            "'abc' must be skipped — no action extracted"
        );
    },
);

// `t=t` (temp-file) with an EMPTY payload (no base64 path) must be rejected:
// file/temp/shm transmission requires a path reference; an absent one yields
// None. (Successful t=t reads are covered in tests/kitty_media.rs.)
test_unsupported_transmission!(
    test_unsupported_transmission_temp_file_returns_none,
    payload = b"a=t,t=t,i=1;",
    label = "temp-file (t=t) with no path",
);

// `t=s` (shared-memory) with an EMPTY payload (no shm name) must be rejected.
// (Successful t=s reads are covered in tests/kitty_media.rs.)
test_unsupported_transmission!(
    test_unsupported_transmission_shared_mem_returns_none,
    payload = b"a=t,t=s,i=2;",
    label = "shared-memory (t=s) with no name",
);

// When no `a=` key is present, `build_command` defaults the action to `'T'`
// (TransmitAndDisplay), not `'t'`.
//
// This exercises the `params.action.unwrap_or('T')` path in `build_command`.
test_kitty_payload_once_case!(
    test_default_action_is_transmit_and_display,
    payload = b"f=32,i=1,s=1,v=1;AAAAAA==",
    check = |result: Option<KittyCommand>| assert!(
        matches!(result, Some(KittyCommand::TransmitAndDisplay { .. })),
        "absent a= key must default to TransmitAndDisplay"
    ),
);

// `parse_u32` (via `KittyParams::parse`) must return `None` for a value that
// overflows `u32` (i.e., any value > 4,294,967,295).
//
// `"4294967296"` is `u32::MAX + 1`; `str::parse::<u32>()` returns `Err`.
test_kitty_params_case!(
    test_parse_params_u32_overflow_returns_none,
    params = b"i=4294967296",
    check = |params: KittyParams| assert!(
        params.image_id.is_none(),
        "u32::MAX+1 must parse to None (overflow)"
    ),
);

// `decode_png` Indexed color type branch: an Indexed-color PNG must not panic
// and must produce an `ImageFormat::Rgba` result with the raw palette-expanded
// bytes from the `png` crate.
//
// This exercises the `png::ColorType::Indexed => (buf, ImageFormat::Rgba)` arm,
// which is the one remaining uncovered branch in `decode_png`.
// The `png` crate requires a PLTE chunk for Indexed-color PNGs.
// Build a 1×1 Indexed PNG with a single-entry palette at runtime.
test_kitty_png_transmit_case!(
    test_kitty_png_indexed_color_type_produces_rgba_format,
    payload = {
        let mut png_bytes: Vec<u8> = Vec::new();
        {
            let mut enc = png::Encoder::new(&mut png_bytes, 1, 1);
            enc.set_color(png::ColorType::Indexed);
            enc.set_depth(png::BitDepth::Eight);
            // Set a 1-entry palette: index 0 → (0xAB, 0xCD, 0xEF)
            enc.set_palette(vec![0xAB, 0xCD, 0xEF]);
            let mut writer = enc.write_header().expect("PNG header write");
            // Image data: one pixel at palette index 0.
            writer.write_image_data(&[0u8]).expect("PNG pixel write");
        }
        format!(
            "a=t,f=100,i=40,s=1,v=1;{}",
            crate::util::base64::encode(&png_bytes)
        )
    },
    fmt_var = Rgba,
    expected_len = 1,
    pixels = pixels => {},
    expected = "Transmit",
);
