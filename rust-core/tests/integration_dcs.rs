//! DCS (Device Control String) integration tests.

mod common;

use kuro_core::TerminalCore;

// ─────────────────────────────────────────────────────────────────────────────
// DCS XTGETTCAP
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn xtgettcap_tn_responds_with_kuro() {
    let mut t = TerminalCore::new(24, 80);
    // DCS + q 544e ST  ("TN" in hex = 54 4e)
    t.advance(b"\x1bP+q544e\x1b\\");
    let responses = common::read_responses(&t);
    assert!(
        !responses.is_empty(),
        "XTGETTCAP for TN must produce a response"
    );
    let resp = &responses[0];
    assert!(
        resp.contains("1+r"),
        "Known capability must use DCS 1+r format, got: {resp:?}"
    );
    // Response contains hex-encoded "kuro"
    // "kuro" in hex = 6b 75 72 6f
    assert!(
        resp.contains("6b75726f") || resp.to_lowercase().contains("kuro"),
        "TN response must encode 'kuro', got: {resp:?}"
    );
}

#[test]
fn xtgettcap_rgb_responds_with_truecolor() {
    let mut t = TerminalCore::new(24, 80);
    // DCS + q 524742 ST  ("RGB" in hex = 52 47 42)
    t.advance(b"\x1bP+q524742\x1b\\");
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("1+r"),
        "RGB capability response must be DCS 1+r, got: {resp:?}"
    );
}

#[test]
fn xtgettcap_unknown_cap_responds_not_found() {
    let mut t = TerminalCore::new(24, 80);
    // DCS + q 786666 ST  ("xff" — not a valid capability)
    t.advance(b"\x1bP+q786666\x1b\\");
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("0+r"),
        "Unknown capability must use DCS 0+r format, got: {resp:?}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DCS Sixel — basic parse tests (no actual image rendering)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn sixel_dcs_does_not_panic_on_valid_input() {
    let mut t = TerminalCore::new(24, 80);
    // DCS 0;1;0 q " 1;1;10;6 #0;2;100;0;0 !10~ - ST
    // This is a simple 10x6 all-red sixel image
    t.advance(b"\x1bP0;1;0q\"1;1;10;6#0;2;100;0;0!10~\x1b\\");
    // Should not panic; cursor may advance
    assert!(t.cursor_row() < 24);
    assert!(t.cursor_col() < 80);
}

#[test]
fn sixel_empty_dcs_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1bPq\x1b\\"); // Empty sixel
    assert!(t.cursor_row() < 24);
}

#[test]
fn sixel_rle_sequence_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    // RLE: !100~ = repeat ~ 100 times
    t.advance(b"\x1bP0;1;0q\"1;1;100;6#0;2;100;0;0!100~\x1b\\");
    assert!(t.cursor_row() < 24);
}

#[test]
fn sixel_multiband_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    // Two bands separated by '-'
    t.advance(b"\x1bP0;1;0q\"1;1;4;12#0;2;100;0;0~~~~-~~~~\x1b\\");
    assert!(t.cursor_row() < 24);
}
