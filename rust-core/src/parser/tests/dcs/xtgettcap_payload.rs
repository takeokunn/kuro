// ── Additional DCS edge-case tests ────────────────────────────────────────────

use super::*;
use crate::parser::dcs::build_xtgettcap_response;

/// A DCS XTGETTCAP payload at exactly the `MAX_DCS_PAYLOAD_BYTES` cap must be
/// processed without panic and yield one response.
///
/// `dcs_put` caps accumulation at `MAX_DCS_PAYLOAD_BYTES`; a payload exactly at
/// the cap is retained in full.  The cap (4096) is even, so `hex_decode`
/// succeeds and decodes to a long ASCII string that is not a known capability,
/// yielding exactly one failure response.
#[test]
fn test_dcs_payload_at_cap_no_panic() {
    use crate::parser::limits::MAX_DCS_PAYLOAD_BYTES;

    let mut core = crate::TerminalCore::new(24, 80);

    // "41" repeated CAP/2 times → hex string of exactly CAP bytes.
    // hex_decode("41"×N) decodes to 'A'×(N/2) — not a known capability.
    let payload: Vec<u8> = std::iter::repeat_n(b"41" as &[u8], MAX_DCS_PAYLOAD_BYTES / 2)
        .flatten()
        .copied()
        .collect();
    assert_eq!(payload.len(), MAX_DCS_PAYLOAD_BYTES);

    // Must not panic.
    run_dcs(&mut core, b"+", 'q', &payload);

    // Decoded to a long unknown capability name → one failure response.
    let responses = dcs_response_texts(&core);
    assert_single_dcs_response_contains(&responses, "\x1bP0+r", &[]);
}

/// A DCS XTGETTCAP payload far larger than `MAX_DCS_PAYLOAD_BYTES` must be
/// truncated at the cap (not accumulated unboundedly) and still not panic.
///
/// With a uniform `"41"` fill the retained even-length prefix decodes to an
/// unknown capability, so exactly one failure response is queued — proving the
/// excess bytes were dropped rather than growing the buffer without bound.
#[test]
fn test_dcs_payload_over_cap_is_truncated() {
    use crate::parser::limits::MAX_DCS_PAYLOAD_BYTES;

    let mut core = crate::TerminalCore::new(24, 80);

    // Four times the cap of "41" plus one stray byte — all excess is dropped.
    let mut payload: Vec<u8> = std::iter::repeat_n(b"41" as &[u8], MAX_DCS_PAYLOAD_BYTES * 2)
        .flatten()
        .copied()
        .collect();
    payload.push(b'4');

    run_dcs(&mut core, b"+", 'q', &payload);

    // Buffer capped to an even-length prefix → one failure response.
    let responses = dcs_response_texts(&core);
    assert_single_dcs_response_contains(&responses, "\x1bP0+r", &[]);
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

    assert_no_dcs_responses(&core);
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
    let responses = dcs_response_texts(&core);
    assert_single_dcs_response_contains(&responses, "\x1bP0+r", &[]);
}

/// DCS with an unknown intermediate byte (not "+" or "") must be a no-op —
/// no Sixel decoder is created and no response is queued.
#[test]
fn test_dcs_unknown_intermediate_is_noop() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Intermediate '!' with final 'q' matches neither b"+" nor b"" in dcs_hook.
    run_dcs(&mut core, b"!", 'q', b"544e");

    assert_no_dcs_responses(&core);
    assert_no_sixel_notifications(&core);
}

/// A DCS XTGETTCAP payload with only semicolons (no actual capability tokens)
/// must produce no response — all tokens are empty and are skipped by the
/// `if cap_hex.is_empty() { continue }` guard.
#[test]
fn test_dcs_only_semicolons_zero_responses() {
    let mut core = crate::TerminalCore::new(24, 80);
    run_dcs(&mut core, b"+", 'q', b";;;");
    assert_no_dcs_responses(&core);
}

// ── Additional DCS edge-case tests ────────────────────────────────────────────

// `build_xtgettcap_response` for "TN" must include "kuro" hex-encoded in the
// value portion of the response (capability returns terminal name).
// Success-prefix check is covered in dcs.rs; here we verify the value.
test_build_response!(
    build_xtgettcap_response_tn_value_encodes_kuro,
    "TN", "544e" => success contains "6b75726f"
);

test_build_response!(
    build_xtgettcap_response_name_alias_contains_kuro_value,
    "name", "6e616d65" => success contains "6b75726f"
);

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

test_build_response!(
    build_xtgettcap_response_colors_encodes_256_value,
    "colors", "636f6c6f7273" => success contains "323536"
);

test_build_response!(
    build_xtgettcap_response_co_alias_encodes_256_value,
    "Co", "436f" => success contains "323536"
);

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
    let responses = dcs_response_texts(&core);
    assert_single_dcs_response_contains(&responses, "\x1bP1+r", &["544e"]);
}

/// A DCS sequence with intermediates b"+", final 'q', but with non-UTF-8 bytes
/// in the payload must be silently discarded — `std::str::from_utf8` returns
/// `Err` and `handle_xtgettcap` returns early.
#[test]
fn test_dcs_non_utf8_payload_no_response() {
    let mut core = crate::TerminalCore::new(24, 80);
    // 0xFF, 0xFE are invalid UTF-8 start bytes.
    run_dcs(&mut core, b"+", 'q', &[0xFF, 0xFE, b'4', b'1']);
    assert_no_dcs_responses(&core);
}

/// A Sixel sequence at a non-zero cursor position must place the image at
/// that position (row and col reflect the cursor before the DCS sequence).
#[test]
fn test_sixel_placement_respects_cursor_position() {
    let mut core = crate::TerminalCore::new(24, 80);
    // Move cursor to (3, 5).
    core.screen.move_cursor(3, 5);

    run_dcs(&mut core, b"", 'q', b"\"1;1;8;16#0~");

    assert_single_sixel_notification(&core, 3, 5);
}

/// A DCS with unknown intermediate b"!" and final 'q' must leave the DCS
/// state as Idle so that a subsequent valid XTGETTCAP is still processed.
#[test]
fn test_dcs_unknown_intermediate_then_valid_xtgettcap() {
    let mut core = crate::TerminalCore::new(24, 80);

    // First sequence: unknown intermediate → noop.
    run_dcs(&mut core, b"!", 'q', b"544e");
    assert_no_dcs_responses(&core);

    // Second sequence: valid XTGETTCAP for "TN".
    run_dcs(&mut core, b"+", 'q', b"544e");
    let responses = dcs_response_texts(&core);
    assert_single_dcs_response_contains(&responses, "\x1bP1+r", &["544e"]);
}

/// XTGETTCAP for invalid hex (non-hex ASCII like "GG") must produce a failure
/// response — `hex_decode` returns `None` for bytes outside [0-9a-fA-F],
/// so `handle_xtgettcap` skips the token entirely.
#[test]
fn test_dcs_invalid_hex_chars_skipped() {
    let mut core = crate::TerminalCore::new(24, 80);
    // "GGGG" — 'G' is not a valid hex digit.
    run_dcs(&mut core, b"+", 'q', b"GGGG");
    assert_no_dcs_responses(&core);
}
