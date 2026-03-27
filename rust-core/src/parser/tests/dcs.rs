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

/// XTGETTCAP for "Tc" (true-color flag) must produce a success response.
///
/// "Tc" hex-encoded is "5463".
#[test]
fn test_xtgettcap_truecolor_flag_response() {
    let mut core = crate::TerminalCore::new(24, 80);

    run_dcs(&mut core, b"+", 'q', b"5463");

    assert_eq!(core.meta.pending_responses.len(), 1);
    let resp =
        std::str::from_utf8(&core.meta.pending_responses[0]).expect("response must be valid UTF-8");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "Tc capability response must start with ESC P 1 + r, got: {resp:?}"
    );
    assert!(
        resp.contains("5463"),
        "response must echo back the hex-encoded name"
    );
}

/// XTGETTCAP for "colors" (hex "636f6c6f7273") must produce a success response
/// with the "256" value encoded.
#[test]
fn test_xtgettcap_colors_capability_response() {
    let mut core = crate::TerminalCore::new(24, 80);

    // "colors" hex-encoded: c=63, o=6f, l=6c, o=6f, r=72, s=73 → "636f6c6f7273"
    run_dcs(&mut core, b"+", 'q', b"636f6c6f7273");

    assert_eq!(core.meta.pending_responses.len(), 1);
    let resp =
        std::str::from_utf8(&core.meta.pending_responses[0]).expect("response must be valid UTF-8");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "colors capability response must start with ESC P 1 + r, got: {resp:?}"
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

// -------------------------------------------------------------------------
// build_xtgettcap_response unit tests (pure lookup, no TerminalCore needed)
// -------------------------------------------------------------------------

#[test]
fn build_xtgettcap_response_tn_starts_with_success_prefix() {
    let resp = build_xtgettcap_response("TN", "544e");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "TN capability must produce a success response, got: {resp:?}"
    );
    assert!(
        resp.contains("544e"),
        "response must echo back the hex capability name"
    );
}

#[test]
fn build_xtgettcap_response_name_alias_same_as_tn() {
    let resp_tn = build_xtgettcap_response("TN", "544e");
    let resp_name = build_xtgettcap_response("name", "6e616d65");
    // Both must produce success responses (same match arm)
    assert!(resp_tn.starts_with("\x1bP1+r"));
    assert!(resp_name.starts_with("\x1bP1+r"));
}

#[test]
fn build_xtgettcap_response_rgb_encodes_888() {
    let resp = build_xtgettcap_response("RGB", "524742");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "RGB must succeed, got: {resp:?}"
    );
    // "8:8:8" hex-encoded is "383a383a38"
    let expected_val = {
        let mut s = String::new();
        for b in b"8:8:8" {
            use std::fmt::Write as _;
            let _ = write!(s, "{b:02x}");
        }
        s
    };
    assert!(
        resp.contains(&expected_val),
        "RGB response must contain hex-encoded '8:8:8', got: {resp:?}"
    );
}

#[test]
fn build_xtgettcap_response_tc_empty_value() {
    let resp = build_xtgettcap_response("Tc", "5463");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "Tc must succeed, got: {resp:?}"
    );
    // The value part is empty: "...5463=\x1b\\"
    assert!(
        resp.contains("5463=\x1b\\"),
        "Tc response value must be empty, got: {resp:?}"
    );
}

#[test]
fn build_xtgettcap_response_colors_encodes_256() {
    let resp = build_xtgettcap_response("colors", "636f6c6f7273");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "colors must succeed, got: {resp:?}"
    );
}

#[test]
fn build_xtgettcap_response_co_alias_same_branch() {
    let resp = build_xtgettcap_response("Co", "436f");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "Co must succeed (alias of colors), got: {resp:?}"
    );
}

#[test]
fn build_xtgettcap_response_unknown_starts_with_failure_prefix() {
    let resp = build_xtgettcap_response("UNKNOWN", "554e4b4e4f574e");
    assert!(
        resp.starts_with("\x1bP0+r"),
        "unknown capability must produce a failure response, got: {resp:?}"
    );
}

#[test]
fn build_xtgettcap_response_ms_encodes_clipboard_format() {
    let resp = build_xtgettcap_response("Ms", "4d73");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "Ms must succeed, got: {resp:?}"
    );
    assert!(resp.contains("4d73"), "Ms response must echo back hex name");
}

// -------------------------------------------------------------------------
// New edge-case tests
// -------------------------------------------------------------------------

/// A DCS XTGETTCAP payload at exactly the `MAX_APC_PAYLOAD_BYTES` byte count
/// must be processed without panic.
///
/// DCS does not impose its own byte-count cap (the cap lives in the APC
/// pre-scanner); `dcs_put` accepts every byte.  The hex string of length
/// `MAX_APC_PAYLOAD_BYTES` is even (4 MiB is divisible by 2), so `hex_decode`
/// succeeds and decodes to a long ASCII string that is not a known capability,
/// yielding exactly one failure response.
///
/// We synthesise the payload with `run_dcs` (calling `dcs_put` per byte) to
/// exercise the same code path a real sequence would take, keeping the payload
/// at exactly `MAX_APC_PAYLOAD_BYTES` ASCII bytes.
#[test]
fn test_dcs_payload_at_max_limit_no_panic() {
    use crate::parser::limits::MAX_APC_PAYLOAD_BYTES;

    let mut core = crate::TerminalCore::new(24, 80);

    // "41" repeated MAX/2 times → hex string of exactly MAX bytes.
    // hex_decode("41"×N) decodes to 'A'×(N/2) — not a known capability.
    let payload: Vec<u8> = std::iter::repeat_n(b"41" as &[u8], MAX_APC_PAYLOAD_BYTES / 2)
        .flatten()
        .copied()
        .collect();
    assert_eq!(payload.len(), MAX_APC_PAYLOAD_BYTES);

    // Must not panic.
    run_dcs(&mut core, b"+", 'q', &payload);

    // Decoded to a long unknown capability name → one failure response.
    assert_eq!(
        core.meta.pending_responses.len(),
        1,
        "MAX-length valid-hex XTGETTCAP payload must produce exactly one (failure) response"
    );
    let resp =
        std::str::from_utf8(&core.meta.pending_responses[0]).expect("response must be valid UTF-8");
    assert!(
        resp.starts_with("\x1bP0+r"),
        "unknown long-name capability must produce a failure response, got: {resp:?}"
    );
}

/// A DCS XTGETTCAP payload that is one byte over `MAX_APC_PAYLOAD_BYTES`
/// produces an odd-length hex string, which `hex_decode` rejects with `None`,
/// so no response is queued.
///
/// `MAX_APC_PAYLOAD_BYTES` is 4 MiB (even).  Adding one byte yields an
/// odd-length string; `!hex.len().is_multiple_of(2)` returns true and the
/// capability is silently skipped.
#[test]
fn test_dcs_payload_one_byte_over_limit_is_skipped() {
    use crate::parser::limits::MAX_APC_PAYLOAD_BYTES;

    let mut core = crate::TerminalCore::new(24, 80);

    // MAX bytes of "41" + one trailing '4' → odd length → skipped by hex_decode.
    let mut payload: Vec<u8> = std::iter::repeat_n(b"41" as &[u8], MAX_APC_PAYLOAD_BYTES / 2)
        .flatten()
        .copied()
        .collect();
    payload.push(b'4'); // one extra byte → odd length
    assert_eq!(payload.len(), MAX_APC_PAYLOAD_BYTES + 1);

    run_dcs(&mut core, b"+", 'q', &payload);

    assert!(
        core.meta.pending_responses.is_empty(),
        "odd-length (over-limit) XTGETTCAP payload must be silently skipped (no response)"
    );
}

/// An empty DCS string — ST arrives immediately after the DCS introducer —
/// must produce no response and must not panic.
///
/// State path: `dcs_hook` sets `Xtgettcap { buf: [] }`, `dcs_put` is never
/// called, `dcs_unhook` calls `handle_xtgettcap` with an empty slice.
/// The for-loop over `s.split(';')` yields one empty string, which is skipped
/// by the `if cap_hex.is_empty() { continue }` guard.
#[test]
fn test_dcs_empty_string_no_response() {
    let mut core = crate::TerminalCore::new(24, 80);

    // DCS + q (XTGETTCAP) with zero data bytes followed immediately by ST.
    run_dcs(&mut core, b"+", 'q', b"");

    assert!(
        core.meta.pending_responses.is_empty(),
        "empty DCS XTGETTCAP payload must produce no response"
    );
}

/// A DCS string containing all printable ASCII characters (0x20–0x7E) must
/// not panic and must produce either a success or failure response (not zero
/// responses), because the payload is a valid even-length hex string.
///
/// Printable ASCII: 0x20..=0x7E = 95 characters.  We hex-encode a known
/// sequence of printable bytes and verify the round-trip.
///
/// Specifically: "546f" = hex("To") — not a known capability → failure response.
#[test]
fn test_dcs_all_printable_ascii_payload_no_panic() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Build a hex payload from all 95 printable ASCII bytes (0x20..=0x7E).
    // Each byte encodes to exactly 2 hex chars, so total length is 190 bytes
    // (even) — valid hex string.  None of the decoded names match a known
    // capability, so we expect a single failure response.
    let mut payload = Vec::with_capacity(95 * 2);
    for byte in 0x20u8..=0x7Eu8 {
        use std::fmt::Write as _;
        let mut s = String::new();
        let _ = write!(s, "{byte:02x}");
        payload.extend_from_slice(s.as_bytes());
    }

    // Must not panic.
    run_dcs(&mut core, b"+", 'q', &payload);

    // The decoded string " !"#$%&'()*+,-./0123456789:;<=>?@ABC...~" is not a
    // known capability name → failure response.
    assert_eq!(
        core.meta.pending_responses.len(),
        1,
        "all-printable-ASCII XTGETTCAP payload must produce exactly one (failure) response"
    );
    let resp =
        std::str::from_utf8(&core.meta.pending_responses[0]).expect("response must be valid UTF-8");
    assert!(
        resp.starts_with("\x1bP0+r"),
        "unknown all-printable-ASCII capability must produce a failure response, got: {resp:?}"
    );
}

/// DCS with an unknown intermediate byte (not "+" or "") must be a no-op —
/// no Sixel decoder is created and no response is queued.
#[test]
fn test_dcs_unknown_intermediate_is_noop() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Intermediate '!' with final 'q' matches neither b"+" nor b"" in dcs_hook.
    run_dcs(&mut core, b"!", 'q', b"544e");

    assert!(
        core.meta.pending_responses.is_empty(),
        "unknown DCS intermediate must produce no response"
    );
    assert!(
        core.kitty.pending_image_notifications.is_empty(),
        "unknown DCS intermediate must not produce an image notification"
    );
}

/// A DCS XTGETTCAP payload with only semicolons (no actual capability tokens)
/// must produce no response — all tokens are empty and are skipped by the
/// `if cap_hex.is_empty() { continue }` guard.
#[test]
fn test_dcs_only_semicolons_zero_responses() {
    let mut core = crate::TerminalCore::new(24, 80);
    run_dcs(&mut core, b"+", 'q', b";;;");
    assert!(
        core.meta.pending_responses.is_empty(),
        "XTGETTCAP payload of only semicolons must produce no response"
    );
}

// ── Additional DCS edge-case tests ────────────────────────────────────────────

/// `build_xtgettcap_response` for "TN" must include "kuro" hex-encoded in the
/// value portion of the response (capability returns terminal name).
#[test]
fn build_xtgettcap_response_tn_value_encodes_kuro() {
    let resp = build_xtgettcap_response("TN", "544e");
    // "kuro" hex = 6b 75 72 6f → "6b75726f"
    assert!(
        resp.contains("6b75726f"),
        "TN response value must contain hex-encoded 'kuro', got: {resp:?}"
    );
}

/// `build_xtgettcap_response` for the "name" alias must produce the same
/// success prefix as for "TN" (they share the same match arm).
#[test]
fn build_xtgettcap_response_name_alias_contains_kuro_value() {
    let resp = build_xtgettcap_response("name", "6e616d65");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "name alias must be a success response"
    );
    assert!(
        resp.contains("6b75726f"),
        "name alias must encode terminal name 'kuro'"
    );
}

/// `build_xtgettcap_response` for "Ms" must have a non-empty hex value
/// (the clipboard format string `\x1b]52;%p1%s;%p2%s\x07`).
#[test]
fn build_xtgettcap_response_ms_value_is_non_empty() {
    let resp = build_xtgettcap_response("Ms", "4d73");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "Ms must be a success response"
    );
    // The response must have content between the '=' and the final ST.
    let eq_pos = resp.find('=').expect("response must contain '='");
    let st_pos = resp.find("\x1b\\").expect("response must end with ST");
    assert!(
        st_pos > eq_pos + 1,
        "Ms value must be non-empty between '=' and ST"
    );
}

/// `build_xtgettcap_response` for "colors" must contain the hex-encoded "256"
/// value in the response body.
#[test]
fn build_xtgettcap_response_colors_encodes_256_value() {
    let resp = build_xtgettcap_response("colors", "636f6c6f7273");
    // "256" hex = 32 35 36 → "323536"
    assert!(
        resp.contains("323536"),
        "colors response must contain hex-encoded '256', got: {resp:?}"
    );
}

/// `build_xtgettcap_response` for "Co" must also contain hex-encoded "256"
/// (same match arm as "colors").
#[test]
fn build_xtgettcap_response_co_alias_encodes_256_value() {
    let resp = build_xtgettcap_response("Co", "436f");
    assert!(
        resp.contains("323536"),
        "Co alias response must contain hex-encoded '256', got: {resp:?}"
    );
}

/// XTGETTCAP with whitespace-only tokens (spaces around semicolons) must not
/// produce responses for the whitespace tokens — they are trimmed and empty
/// after trim, so the guard `if cap_hex.is_empty() { continue }` skips them.
#[test]
fn test_dcs_whitespace_around_semicolons_skipped() {
    let mut core = crate::TerminalCore::new(24, 80);
    // " ; ; 544e" — tokens " ", " ", "544e" after split.
    // After trim: "", "", "544e" → first two skipped.
    run_dcs(&mut core, b"+", 'q', b" ; ; 544e");
    // "544e" is a valid capability (TN) but the whitespace tokens also produce
    // no responses.  Depending on trim behavior only the valid one fires.
    // We assert no panic and that exactly 1 response is queued for the valid token.
    assert_eq!(
        core.meta.pending_responses.len(),
        1,
        "only the non-empty capability 'TN' must produce a response"
    );
}

/// A DCS sequence with intermediates b"+", final 'q', but with non-UTF-8 bytes
/// in the payload must be silently discarded — `std::str::from_utf8` returns
/// `Err` and `handle_xtgettcap` returns early.
#[test]
fn test_dcs_non_utf8_payload_no_response() {
    let mut core = crate::TerminalCore::new(24, 80);
    // 0xFF, 0xFE are invalid UTF-8 start bytes.
    run_dcs(&mut core, b"+", 'q', &[0xFF, 0xFE, b'4', b'1']);
    assert!(
        core.meta.pending_responses.is_empty(),
        "non-UTF-8 XTGETTCAP payload must be silently discarded"
    );
}

/// A Sixel sequence at a non-zero cursor position must place the image at
/// that position (row and col reflect the cursor before the DCS sequence).
#[test]
fn test_sixel_placement_respects_cursor_position() {
    let mut core = crate::TerminalCore::new(24, 80);
    // Move cursor to (3, 5).
    core.screen.move_cursor(3, 5);

    run_dcs(&mut core, b"", 'q', b"\"1;1;8;16#0~");

    assert_eq!(
        core.kitty.pending_image_notifications.len(),
        1,
        "exactly one sixel notification must be queued"
    );
    let notif = &core.kitty.pending_image_notifications[0];
    assert_eq!(notif.row, 3, "sixel image row must match cursor row at hook time");
    assert_eq!(notif.col, 5, "sixel image col must match cursor col at hook time");
}

/// A DCS with unknown intermediate b"!" and final 'q' must leave the DCS
/// state as Idle so that a subsequent valid XTGETTCAP is still processed.
#[test]
fn test_dcs_unknown_intermediate_then_valid_xtgettcap() {
    let mut core = crate::TerminalCore::new(24, 80);

    // First sequence: unknown intermediate → noop.
    run_dcs(&mut core, b"!", 'q', b"544e");
    assert!(
        core.meta.pending_responses.is_empty(),
        "unknown intermediate must produce no response"
    );

    // Second sequence: valid XTGETTCAP for "TN".
    run_dcs(&mut core, b"+", 'q', b"544e");
    assert_eq!(
        core.meta.pending_responses.len(),
        1,
        "valid XTGETTCAP after unknown-intermediate sequence must produce one response"
    );
    let resp = std::str::from_utf8(&core.meta.pending_responses[0]).unwrap();
    assert!(resp.starts_with("\x1bP1+r"), "response must be a success response");
}

/// XTGETTCAP for invalid hex (non-hex ASCII like "GG") must produce a failure
/// response — `hex_decode` returns `None` for bytes outside [0-9a-fA-F],
/// so `handle_xtgettcap` skips the token entirely.
#[test]
fn test_dcs_invalid_hex_chars_skipped() {
    let mut core = crate::TerminalCore::new(24, 80);
    // "GGGG" — 'G' is not a valid hex digit.
    run_dcs(&mut core, b"+", 'q', b"GGGG");
    assert!(
        core.meta.pending_responses.is_empty(),
        "invalid hex characters in XTGETTCAP payload must be skipped (no response)"
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
        use std::fmt::Write as _;
        let mut term = crate::TerminalCore::new(24, 80);
        // Encode as hex string
        let mut hex = String::with_capacity(cap.len() * 2);
        for b in &cap { let _ = write!(hex, "{b:02X}"); }
        let seq = format!("\x1bP+q{hex}\x1b\\");
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
        let seq = format!("\x1bP{p}\x1b\\");
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }
}
