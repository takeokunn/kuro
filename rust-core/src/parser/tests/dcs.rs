//! Property-based and example-based tests for `dcs` parsing.
//!
//! Module under test: `parser/dcs.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

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

// -------------------------------------------------------------------------
// Macros for repetitive XTGETTCAP assertion patterns
// -------------------------------------------------------------------------

/// Assert that a single XTGETTCAP response starts with the success prefix
/// `ESC P 1 + r` and contains the hex-encoded capability name.
///
/// Usage: `assert_xtgettcap_success!(core, hex_name)`
macro_rules! assert_xtgettcap_success {
    ($core:expr, $hex:expr) => {{
        assert_eq!(
            $core.meta.pending_responses.len(),
            1,
            "exactly one response should be queued"
        );
        let resp = std::str::from_utf8(&$core.meta.pending_responses[0])
            .expect("response must be valid UTF-8");
        assert!(
            resp.starts_with("\x1bP1+r"),
            "known capability response must start with ESC P 1 + r, got: {resp:?}"
        );
        assert!(
            resp.contains($hex),
            "response must echo back the hex-encoded capability name"
        );
    }};
}

/// Assert that a single XTGETTCAP response starts with the failure prefix
/// `ESC P 0 + r`.
///
/// Usage: `assert_xtgettcap_failure!(core)`
macro_rules! assert_xtgettcap_failure {
    ($core:expr) => {{
        assert_eq!(
            $core.meta.pending_responses.len(),
            1,
            "exactly one response should be queued for unknown capability"
        );
        let resp = std::str::from_utf8(&$core.meta.pending_responses[0])
            .expect("response must be valid UTF-8");
        assert!(
            resp.starts_with("\x1bP0+r"),
            "unknown capability response must start with ESC P 0 + r, got: {resp:?}"
        );
    }};
}

/// Run a single XTGETTCAP DCS sequence and assert the result via
/// `assert_xtgettcap_success!` or `assert_xtgettcap_failure!`.
///
/// Usage: `test_xtgettcap!(hex_payload => success "expected_hex")`
///         `test_xtgettcap!(hex_payload => failure)`
macro_rules! test_xtgettcap {
    ($payload:expr => success $hex:expr) => {{
        let mut core = crate::TerminalCore::new(24, 80);
        run_dcs(&mut core, b"+", 'q', $payload);
        assert_xtgettcap_success!(core, $hex);
    }};
    ($payload:expr => failure) => {{
        let mut core = crate::TerminalCore::new(24, 80);
        run_dcs(&mut core, b"+", 'q', $payload);
        assert_xtgettcap_failure!(core);
    }};
}

/// XTGETTCAP for a known capability ("TN" = "544e") should produce a response
/// that starts with the DCS success prefix: ESC P 1 + r.
#[test]
fn test_xtgettcap_known_capability_response() {
    test_xtgettcap!(b"544e" => success "544e");
}

/// XTGETTCAP for an unknown capability should produce a response that starts
/// with the DCS failure prefix: ESC P 0 + r.
#[test]
fn test_xtgettcap_unknown_capability_response() {
    test_xtgettcap!(b"5859" => failure);
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
        "TN capability response must start with ESC P 1 + r, got: {resp0:?}"
    );
    assert!(
        resp1.starts_with("\x1bP1+r"),
        "RGB capability response must start with ESC P 1 + r, got: {resp1:?}"
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

// ── Single-capability XTGETTCAP: truecolor + colors ──────────────────────────
// `test_xtgettcap!(payload => success hex)`: ESC P 1 + r prefix + hex echo.

/// "Tc" (true-color flag) — hex "5463".
#[test] fn test_xtgettcap_truecolor_flag_response()    { test_xtgettcap!(b"5463"         => success "5463"); }
/// "colors" (256-colour count) — hex "636f6c6f7273".
#[test] fn test_xtgettcap_colors_capability_response() { test_xtgettcap!(b"636f6c6f7273" => success "636f6c6f7273"); }

/// XTGETTCAP for "E3" (clear-scrollback) must report the `CSI 3 J` sequence so
/// tmux knows it can clear the host scrollback.
/// "E3" hex = "4533"; value "\x1b[3J" hex = "1b5b334a".
#[test]
fn test_xtgettcap_e3_clear_scrollback_response() {
    let mut core = crate::TerminalCore::new(24, 80);

    run_dcs(&mut core, b"+", 'q', b"4533");

    assert_eq!(core.meta.pending_responses.len(), 1);
    let resp =
        std::str::from_utf8(&core.meta.pending_responses[0]).expect("response must be valid UTF-8");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "E3 must be a known capability (ESC P 1 + r), got: {resp:?}"
    );
    assert!(resp.contains("4533"), "response must echo the E3 name hex");
    assert!(
        resp.contains("1b5b334a"),
        "E3 value must be the hex of ESC [ 3 J, got: {resp:?}"
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
    assert!(r0.starts_with("\x1bP1+r"), "TN must succeed, got: {r0:?}");
    assert!(r1.starts_with("\x1bP0+r"), "ZZZZ must fail, got: {r1:?}");
    assert!(r2.starts_with("\x1bP1+r"), "RGB must succeed, got: {r2:?}");
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
            "unknown capability response must start with ESC P 0 + r, got: {resp:?}"
        );
    }
}

// ── Single-capability XTGETTCAP: terminfo / key capabilities ─────────────────

/// `Ts` (strikethrough set) — hex "5473"; response echoes "5473=".
#[test] fn test_xtgettcap_strikethrough_ts() { test_xtgettcap!(b"5473"           => success "5473="); }
/// `Te` (strikethrough reset) — hex "5465".
#[test] fn test_xtgettcap_strikethrough_te() { test_xtgettcap!(b"5465"           => success "5465"); }
/// `setrgbf` (truecolor fg terminfo) — hex "73657472676266".
#[test] fn test_xtgettcap_setrgbf()          { test_xtgettcap!(b"73657472676266" => success "73657472676266"); }
/// `setrgbb` (truecolor bg terminfo) — hex "73657472676262".
#[test] fn test_xtgettcap_setrgbb()          { test_xtgettcap!(b"73657472676262" => success "73657472676262"); }
/// `kbs` (backspace key) — hex "6B6273".
#[test] fn test_xtgettcap_kbs()              { test_xtgettcap!(b"6B6273"         => success "6B6273"); }
/// `Sync` (synchronized output) — hex "53796E63".
#[test] fn test_xtgettcap_sync()             { test_xtgettcap!(b"53796E63"       => success "53796E63"); }

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
    assert_eq!(
        cursor.col, 0,
        "sixel rendering must reset cursor column to 0"
    );
}

/// A Sixel DCS sequence with empty data (no pixel commands) must not add any
/// image notification (`decoder.finish()` returns None for an empty sequence).
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


include!("dcs_xtgettcap.rs");
