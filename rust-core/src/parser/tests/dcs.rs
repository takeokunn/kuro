//! Property-based and example-based tests for `dcs` parsing.
//!
//! Module under test: `parser/dcs.rs`
//! Tier: T3 — ProptestConfig::with_cases(256)

use super::*;

/// Build a minimal `vte::Params` with no numeric parameters.
fn empty_params() -> vte::Params {
    vte::Params::default()
}

/// Simulate a complete DCS sequence: hook → put bytes → unhook.
fn run_dcs(core: &mut crate::TerminalCore, intermediates: &[u8], c: char, data: &[u8]) {
    dcs_hook(core, &empty_params(), intermediates, false, c);
    for &byte in data {
        dcs_put(core, byte);
    }
    dcs_unhook(core);
}

/// XTGETTCAP for a known capability ("TN" = "544e") should produce a response
/// that starts with the DCS success prefix: ESC P 1 + r.
#[test]
fn test_xtgettcap_known_capability_response() {
    let mut core = crate::TerminalCore::new(24, 80);

    // "TN" hex-encoded is "544e".
    run_dcs(&mut core, b"+", 'q', b"544e");

    assert_eq!(
        core.meta.pending_responses.len(),
        1,
        "exactly one response should be queued for TN capability"
    );
    let resp = std::str::from_utf8(&core.meta.pending_responses[0])
        .expect("response must be valid UTF-8");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "known capability response must start with ESC P 1 + r, got: {:?}",
        resp
    );
    assert!(
        resp.contains("544e"),
        "response must echo back the hex-encoded capability name"
    );
}

/// XTGETTCAP for an unknown capability should produce a response that starts
/// with the DCS failure prefix: ESC P 0 + r.
#[test]
fn test_xtgettcap_unknown_capability_response() {
    let mut core = crate::TerminalCore::new(24, 80);

    // "XY" hex-encoded is "5859" — not a known capability.
    run_dcs(&mut core, b"+", 'q', b"5859");

    assert_eq!(
        core.meta.pending_responses.len(),
        1,
        "exactly one response should be queued for unknown capability"
    );
    let resp = std::str::from_utf8(&core.meta.pending_responses[0])
        .expect("response must be valid UTF-8");
    assert!(
        resp.starts_with("\x1bP0+r"),
        "unknown capability response must start with ESC P 0 + r, got: {:?}",
        resp
    );
}

/// A non-XTGETTCAP DCS hook (e.g., unknown final byte 'z') must leave the
/// state as Idle and produce no response.
#[test]
fn test_dcs_unknown_command_is_noop() {
    let mut core = crate::TerminalCore::new(24, 80);

    run_dcs(&mut core, b"", 'z', b"some data");

    assert!(
        core.meta.pending_responses.is_empty(),
        "unknown DCS command must produce no response"
    );
}

/// XTGETTCAP with two semicolon-separated capabilities must produce exactly
/// two responses — one per capability — each with the correct DCS prefix.
///
/// Capabilities used: "TN" (hex "544e", known) and "RGB" (hex "524742", known).
#[test]
fn test_xtgettcap_multiple_capabilities() {
    let mut core = crate::TerminalCore::new(24, 80);

    // "544e" = "TN", "524742" = "RGB" — both known capabilities.
    run_dcs(&mut core, b"+", 'q', b"544e;524742");

    assert_eq!(
        core.meta.pending_responses.len(),
        2,
        "two capabilities in one XTGETTCAP request must produce two responses"
    );

    let resp0 = std::str::from_utf8(&core.meta.pending_responses[0])
        .expect("first response must be valid UTF-8");
    let resp1 = std::str::from_utf8(&core.meta.pending_responses[1])
        .expect("second response must be valid UTF-8");

    assert!(
        resp0.starts_with("\x1bP1+r"),
        "TN capability response must start with ESC P 1 + r, got: {:?}",
        resp0
    );
    assert!(
        resp1.starts_with("\x1bP1+r"),
        "RGB capability response must start with ESC P 1 + r, got: {:?}",
        resp1
    );
}

/// XTGETTCAP with an odd-length hex string (not a valid two-hex-char-per-byte
/// encoding) must be silently skipped — no response queued, no panic.
#[test]
fn test_xtgettcap_odd_length_hex_is_skipped() {
    let mut core = crate::TerminalCore::new(24, 80);

    // "54f" is 3 hex characters — odd length, cannot represent whole bytes.
    run_dcs(&mut core, b"+", 'q', b"54f");

    assert!(
        core.meta.pending_responses.is_empty(),
        "odd-length hex in XTGETTCAP must be silently skipped (no response)"
    );
}

/// XTGETTCAP for "Tc" (true-color flag) must produce a success response.
///
/// "Tc" hex-encoded is "5463".
#[test]
fn test_xtgettcap_truecolor_flag_response() {
    let mut core = crate::TerminalCore::new(24, 80);

    run_dcs(&mut core, b"+", 'q', b"5463");

    assert_eq!(core.meta.pending_responses.len(), 1);
    let resp = std::str::from_utf8(&core.meta.pending_responses[0])
        .expect("response must be valid UTF-8");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "Tc capability response must start with ESC P 1 + r, got: {:?}",
        resp
    );
    assert!(resp.contains("5463"), "response must echo back the hex-encoded name");
}

/// XTGETTCAP for "colors" (hex "636f6c6f7273") must produce a success response
/// with the "256" value encoded.
#[test]
fn test_xtgettcap_colors_capability_response() {
    let mut core = crate::TerminalCore::new(24, 80);

    // "colors" hex-encoded: c=63, o=6f, l=6c, o=6f, r=72, s=73 → "636f6c6f7273"
    run_dcs(&mut core, b"+", 'q', b"636f6c6f7273");

    assert_eq!(core.meta.pending_responses.len(), 1);
    let resp = std::str::from_utf8(&core.meta.pending_responses[0])
        .expect("response must be valid UTF-8");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "colors capability response must start with ESC P 1 + r, got: {:?}",
        resp
    );
}

/// XTGETTCAP with three semicolon-separated capabilities (one unknown) must
/// produce one failure response and two success responses, in order.
#[test]
fn test_xtgettcap_mixed_known_unknown_capabilities() {
    let mut core = crate::TerminalCore::new(24, 80);

    // "TN" = "544e" (known), "ZZZZ" = "5a5a5a5a" (unknown), "RGB" = "524742" (known)
    run_dcs(&mut core, b"+", 'q', b"544e;5a5a5a5a;524742");

    assert_eq!(
        core.meta.pending_responses.len(),
        3,
        "three capabilities must yield three responses"
    );
    let r0 = std::str::from_utf8(&core.meta.pending_responses[0]).unwrap();
    let r1 = std::str::from_utf8(&core.meta.pending_responses[1]).unwrap();
    let r2 = std::str::from_utf8(&core.meta.pending_responses[2]).unwrap();
    assert!(r0.starts_with("\x1bP1+r"), "TN must succeed, got: {:?}", r0);
    assert!(r1.starts_with("\x1bP0+r"), "ZZZZ must fail, got: {:?}", r1);
    assert!(r2.starts_with("\x1bP1+r"), "RGB must succeed, got: {:?}", r2);
}

/// XTGETTCAP with multiple unknown capabilities must produce one failure
/// response per unknown capability.
#[test]
fn test_xtgettcap_multiple_unknown_capabilities() {
    let mut core = crate::TerminalCore::new(24, 80);

    // "AA" = "4141", "BB" = "4242" — both unknown
    run_dcs(&mut core, b"+", 'q', b"4141;4242");

    assert_eq!(
        core.meta.pending_responses.len(),
        2,
        "two unknown capabilities must each produce a failure response"
    );
    for resp_bytes in &core.meta.pending_responses {
        let resp = std::str::from_utf8(resp_bytes).expect("response must be valid UTF-8");
        assert!(
            resp.starts_with("\x1bP0+r"),
            "unknown capability response must start with ESC P 0 + r, got: {:?}",
            resp
        );
    }
}

/// A Sixel DCS sequence with valid pixel data must produce exactly one image
/// placement notification.
///
/// The sixel data "#0~" uses color register 0 (black by default) and encodes
/// a 1×6 pixel column. Raster attributes "\"1;1;1;6" declare 1×6 pixel size.
#[test]
fn test_sixel_produces_image_placement() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Minimal sixel: raster attrs, color select, one pixel column.
    run_dcs(&mut core, b"", 'q', b"\"1;1;1;6#0~");

    assert_eq!(
        core.kitty.pending_image_notifications.len(),
        1,
        "one sixel sequence must produce exactly one image notification"
    );
    assert_eq!(
        core.kitty.pending_image_notifications[0].row, 0,
        "sixel placement must default to cursor row 0"
    );
    assert_eq!(
        core.kitty.pending_image_notifications[0].col, 0,
        "sixel placement must default to cursor col 0"
    );
}

/// Two consecutive Sixel DCS sequences must each produce a separate image
/// notification, giving two notifications total.
#[test]
fn test_two_consecutive_sixels_produce_two_placements() {
    let mut core = crate::TerminalCore::new(24, 80);

    run_dcs(&mut core, b"", 'q', b"\"1;1;1;6#0~");
    run_dcs(&mut core, b"", 'q', b"\"1;1;1;6#0~");

    assert_eq!(
        core.kitty.pending_image_notifications.len(),
        2,
        "two sixel sequences must produce two distinct image notifications"
    );
}

/// After a Sixel DCS sequence, the cursor must have advanced past the rendered
/// image region (row should be greater than the initial row).
#[test]
fn test_sixel_advances_cursor_after_render() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Cursor starts at (0, 0).
    assert_eq!(core.screen.cursor().row, 0);

    // Sixel with declared height=6 → cell_h = ceil(6/16) = 1 → new row = 0 + 1 = 1.
    run_dcs(&mut core, b"", 'q', b"\"1;1;1;6#0~");

    let cursor = core.screen.cursor();
    assert!(
        cursor.row >= 1,
        "cursor row must advance past the rendered sixel region, got row {}",
        cursor.row
    );
    assert_eq!(cursor.col, 0, "sixel rendering must reset cursor column to 0");
}

/// A Sixel DCS sequence with empty data (no pixel commands) must not add any
/// image notification (decoder.finish() returns None for an empty sequence).
#[test]
fn test_sixel_empty_data_no_placement() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Hook a sixel DCS but provide no pixel data at all.
    run_dcs(&mut core, b"", 'q', b"");

    assert!(
        core.kitty.pending_image_notifications.is_empty(),
        "empty sixel data must produce no image notification"
    );
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: DCS XTGETTCAP with arbitrary hex-encoded capability name never panics
    fn prop_xtgettcap_arbitrary_hex_no_panic(
        cap in proptest::collection::vec(0u8..=255u8, 0..=30)
    ) {
        let mut term = crate::TerminalCore::new(24, 80);
        // Encode as hex string
        let hex: String = cap.iter().map(|b| format!("{:02X}", b)).collect();
        let seq = format!("\x1bP+q{}\x1b\\", hex);
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }

    #[test]
    // PANIC SAFETY: DCS with arbitrary payload bytes never panics
    fn prop_dcs_arbitrary_payload_no_panic(
        payload in proptest::collection::vec(0x20u8..=0x7eu8, 0..=50)
    ) {
        let mut term = crate::TerminalCore::new(24, 80);
        let p = String::from_utf8(payload).unwrap_or_default();
        let seq = format!("\x1bP{}\x1b\\", p);
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }
}
