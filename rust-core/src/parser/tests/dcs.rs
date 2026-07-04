//! Property-based and example-based tests for `dcs` parsing.
//!
//! Module under test: `parser/dcs.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

#[path = "dcs/tests_support.rs"]
mod tests_support;

pub(crate) use tests_support::{
    assert_dcs_response_prefixes, assert_no_dcs_responses, assert_no_sixel_notifications,
    assert_single_dcs_response_contains, assert_single_sixel_notification,
    assert_sixel_notification_count, dcs_response_texts, run_dcs,
};

// -------------------------------------------------------------------------
// Macros for repetitive XTGETTCAP assertion patterns
// -------------------------------------------------------------------------

/// Assert that a single XTGETTCAP response starts with the success prefix
/// `ESC P 1 + r` and contains the hex-encoded capability name.
///
/// Usage: `assert_xtgettcap_success!(core, hex_name)`
macro_rules! assert_xtgettcap_success {
    ($core:expr, $hex:expr) => {{
        let responses = dcs_response_texts(&$core);
        assert_single_dcs_response_contains(&responses, "\x1bP1+r", &[$hex]);
    }};
}

/// Assert that a single XTGETTCAP response starts with the failure prefix
/// `ESC P 0 + r`.
///
/// Usage: `assert_xtgettcap_failure!(core)`
macro_rules! assert_xtgettcap_failure {
    ($core:expr) => {{
        let responses = dcs_response_texts(&$core);
        assert_single_dcs_response_contains(&responses, "\x1bP0+r", &[]);
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

    assert_no_dcs_responses(&core);
}

/// XTGETTCAP with two semicolon-separated capabilities must produce exactly
/// two responses - one per capability - each with the correct DCS prefix.
///
/// Capabilities used: "TN" (hex "544e", known) and "RGB" (hex "524742", known).
#[test]
fn test_xtgettcap_multiple_capabilities() {
    let mut core = crate::TerminalCore::new(24, 80);

    run_dcs(&mut core, b"+", 'q', b"544e;524742");

    let responses = dcs_response_texts(&core);
    assert_dcs_response_prefixes(&responses, &["\x1bP1+r", "\x1bP1+r"]);
}

/// XTGETTCAP with an odd-length hex string (not a valid two-hex-char-per-byte
/// encoding) must be silently skipped — no response queued, no panic.
#[test]
fn test_xtgettcap_odd_length_hex_is_skipped() {
    let mut core = crate::TerminalCore::new(24, 80);

    // "54f" is 3 hex characters — odd length, cannot represent whole bytes.
    run_dcs(&mut core, b"+", 'q', b"54f");

    assert_no_dcs_responses(&core);
}

// ── Single-capability XTGETTCAP: truecolor + colors ──────────────────────────
// `test_xtgettcap!(payload => success hex)`: ESC P 1 + r prefix + hex echo.

/// "Tc" (true-color flag) — hex "5463".
#[test]
fn test_xtgettcap_truecolor_flag_response() {
    test_xtgettcap!(b"5463"         => success "5463");
}
/// "colors" (256-colour count) — hex "636f6c6f7273".
#[test]
fn test_xtgettcap_colors_capability_response() {
    test_xtgettcap!(b"636f6c6f7273" => success "636f6c6f7273");
}

/// XTGETTCAP for "E3" (clear-scrollback) must report the `CSI 3 J` sequence so
/// tmux knows it can clear the host scrollback.
/// "E3" hex = "4533"; value "\x1b[3J" hex = "1b5b334a".
#[test]
fn test_xtgettcap_e3_clear_scrollback_response() {
    let mut core = crate::TerminalCore::new(24, 80);

    run_dcs(&mut core, b"+", 'q', b"4533");

    let responses = dcs_response_texts(&core);
    assert_single_dcs_response_contains(&responses, "\x1bP1+r", &["4533", "1b5b334a"]);
}

/// XTGETTCAP with three semicolon-separated capabilities (one unknown) must
/// produce one failure response and two success responses, in order.
#[test]
fn test_xtgettcap_mixed_known_unknown_capabilities() {
    let mut core = crate::TerminalCore::new(24, 80);

    run_dcs(&mut core, b"+", 'q', b"544e;5a5a5a5a;524742");

    let responses = dcs_response_texts(&core);
    assert_dcs_response_prefixes(&responses, &["\x1bP1+r", "\x1bP0+r", "\x1bP1+r"]);
}

/// XTGETTCAP with multiple unknown capabilities must produce one failure
/// response per unknown capability.
#[test]
fn test_xtgettcap_multiple_unknown_capabilities() {
    let mut core = crate::TerminalCore::new(24, 80);

    // "AA" = "4141", "BB" = "4242" — both unknown
    run_dcs(&mut core, b"+", 'q', b"4141;4242");

    let responses = dcs_response_texts(&core);
    assert_dcs_response_prefixes(&responses, &["\x1bP0+r", "\x1bP0+r"]);
}

// ── Single-capability XTGETTCAP: terminfo / key capabilities ─────────────────

/// `Ts` (strikethrough set) — hex "5473"; response echoes "5473=".
#[test]
fn test_xtgettcap_strikethrough_ts() {
    test_xtgettcap!(b"5473"           => success "5473=");
}
/// `Te` (strikethrough reset) — hex "5465".
#[test]
fn test_xtgettcap_strikethrough_te() {
    test_xtgettcap!(b"5465"           => success "5465");
}
/// `setrgbf` (truecolor fg terminfo) — hex "73657472676266".
#[test]
fn test_xtgettcap_setrgbf() {
    test_xtgettcap!(b"73657472676266" => success "73657472676266");
}
/// `setrgbb` (truecolor bg terminfo) — hex "73657472676262".
#[test]
fn test_xtgettcap_setrgbb() {
    test_xtgettcap!(b"73657472676262" => success "73657472676262");
}
/// `kbs` (backspace key) — hex "6B6273".
#[test]
fn test_xtgettcap_kbs() {
    test_xtgettcap!(b"6B6273"         => success "6B6273");
}
/// `Sync` (synchronized output) — hex "53796E63".
#[test]
fn test_xtgettcap_sync() {
    test_xtgettcap!(b"53796E63"       => success "53796E63");
}

// ── DECTABSR ─────────────────────────────────────────────────────────────────
// `DCS 2 $ t ST` → `DCS 2 ; 0 $ u col1/col2/.../colN ST`
// Columns are 1-indexed per the VT420 spec; default stops every 8 cols.

/// DECTABSR default tab stops: 80-col terminal has stops at 1-indexed columns
/// 9, 17, 25, 33, 41, 49, 57, 65, 73 (every 8 cols from col 9).
#[test]
fn test_dectabsr_reports_default_tab_stops() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1bP2$t\x1b\\");
    let responses = dcs_response_texts(&term);
    assert_eq!(
        responses.len(),
        1,
        "DECTABSR must produce exactly one response"
    );
    let resp = responses[0];
    assert!(
        resp.starts_with("\x1bP2;0$u"),
        "DECTABSR response must start with DCS 2;0$u, got: {resp:?}"
    );
    assert!(
        resp.ends_with("\x1b\\"),
        "DECTABSR response must end with ST (ESC \\), got: {resp:?}"
    );
    // Default 80-col stops: 9/17/25/33/41/49/57/65/73
    assert!(
        resp.contains("9/17/25/33/41/49/57/65/73"),
        "DECTABSR must report default tab stops, got: {resp:?}"
    );
}

/// DECTABSR with param 0 (not 2) must be silently ignored — no response.
#[test]
fn test_dectabsr_wrong_param_is_ignored() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1bP0$t\x1b\\"); // param 0, not 2
    assert_no_dcs_responses(&term);
}

/// DECTABSR with no param defaults to 0 and must also be ignored.
#[test]
fn test_dectabsr_no_param_is_ignored() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1bP$t\x1b\\"); // no param — VTE delivers 0 as default
    assert_no_dcs_responses(&term);
}

/// DECTABSR after TBC 3 must respond with default stops (Kuro restores defaults
/// on TBC 3 rather than clearing to empty — this is a deliberate implementation
/// choice matching many other terminals).
#[test]
fn test_dectabsr_after_tbc3_reports_defaults() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[3g"); // TBC 3: reset tab stops to defaults
    term.advance(b"\x1bP2$t\x1b\\");
    let responses = dcs_response_texts(&term);
    assert_eq!(responses.len(), 1);
    let resp = responses[0];
    // After TBC 3, Kuro restores default stops (every 8 cols from 9).
    assert!(
        resp.contains("9/17/25/33/41/49/57/65/73"),
        "DECTABSR after TBC 3 must report default stops, got: {resp:?}"
    );
}

/// DECTABSR after setting a custom tab stop via HTS (ESC H) must report it.
#[test]
fn test_dectabsr_custom_stop_via_hts() {
    let mut term = crate::TerminalCore::new(24, 80);
    // Clear all defaults, then set a stop at column 5 (0-indexed) = column 6 (1-indexed).
    term.advance(b"\x1b[3g"); // TBC 3: clear all
    term.advance(b"\x1b[1;5H"); // move cursor to row 1, col 5 (1-indexed = col 4 0-indexed)
    term.advance(b"\x1bH"); // HTS: set tab stop at current column (col 4 0-indexed = col 5 1-indexed)
    term.advance(b"\x1bP2$t\x1b\\");
    let responses = dcs_response_texts(&term);
    assert_eq!(responses.len(), 1);
    let resp = responses[0];
    assert!(
        resp.contains('5'),
        "DECTABSR must include the custom tab stop column 5, got: {resp:?}"
    );
}

// ── Regression: untrusted-input hardening ────────────────────────────────────

/// Regression: an XTGETTCAP payload containing a multibyte UTF-8 scalar whose
/// byte boundary falls inside a 2-char hex slice must not panic. Before the
/// fix, `hex_decode` sliced `&hex[i..i + 2]` on a non-char-boundary, panicking
/// *inside* `parser.advance` — which left `core.parser` unrestored and killed
/// all further escape parsing for the session. This test proves both that the
/// crafted sequence is handled gracefully AND that a following CSI still works.
#[test]
fn test_xtgettcap_multibyte_payload_does_not_kill_parser() {
    let mut term = crate::TerminalCore::new(24, 80);
    // "a€" is 4 bytes (61 e2 82 ac): even length passes the multiple-of-2 check,
    // and `&hex[2..4]` would split the euro sign — the pre-fix panic trigger.
    term.advance("\x1bP+qa\u{20ac}\x1b\\".as_bytes());
    // Parser survived: a subsequent CSI cursor move is still honored.
    term.advance(b"\x1b[5;10H");
    let cur = term.screen.cursor();
    assert_eq!(
        (cur.row, cur.col),
        (4, 9),
        "escape parsing must remain alive after the malicious XTGETTCAP"
    );
}

/// Regression: the DCS passthrough buffer must be capped. vte streams `put`
/// bytes uncapped, so an unterminated XTGETTCAP would otherwise grow `buf`
/// without bound and exhaust host heap.
#[test]
fn test_xtgettcap_payload_accumulation_is_capped() {
    use crate::parser::dcs::DcsState;
    use crate::parser::limits::MAX_DCS_PAYLOAD_BYTES;

    let mut term = crate::TerminalCore::new(24, 80);
    // Open an XTGETTCAP request and stream far more payload than the cap,
    // without the terminating ST so it stays in the accumulating state.
    let mut seq = b"\x1bP+q".to_vec();
    seq.extend(std::iter::repeat_n(b'a', MAX_DCS_PAYLOAD_BYTES * 4));
    term.advance(&seq);
    match &term.meta.dcs_state {
        DcsState::Xtgettcap { buf } => assert!(
            buf.len() <= MAX_DCS_PAYLOAD_BYTES,
            "DCS payload buffer must be capped at {MAX_DCS_PAYLOAD_BYTES}, got {}",
            buf.len()
        ),
        _ => panic!("expected Xtgettcap accumulation state"),
    }
}

#[path = "dcs/sixel.rs"]
mod sixel;

#[path = "dcs/xtgettcap.rs"]
mod xtgettcap;

#[path = "dcs/decrqss.rs"]
mod decrqss;
