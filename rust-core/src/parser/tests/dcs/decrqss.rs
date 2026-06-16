// DECRQSS (DCS $ q <setting> ST) — Request Status String.
//
// `handle_decrqss` has 4 branches; none were previously covered:
//   1. b" q"  → DECSCUSR cursor style
//   2. b"r"   → DECSTBM scroll margins
//   3. b"m"   → current SGR rendition
//   4. unknown → failure prefix DCS 0 $ r ST

use super::*;

/// Query the cursor style when it is at the default (BlinkingBlock → PS 0).
#[test]
fn test_decrqss_cursor_style_default() {
    let mut core = crate::TerminalCore::new(24, 80);
    run_dcs(&mut core, b"$", 'q', b" q");
    assert_eq!(core.meta.pending_responses.len(), 1);
    let resp = std::str::from_utf8(&core.meta.pending_responses[0]).unwrap();
    assert!(
        resp.starts_with("\x1bP1$r"),
        "DECRQSS cursor style must start with DCS 1 $ r, got: {resp:?}"
    );
    assert!(
        resp.ends_with(" q\x1b\\"),
        "DECRQSS cursor style must end with ' q ST', got: {resp:?}"
    );
    // Default BlinkingBlock serialises to PS 0.
    assert!(
        resp.contains("0 q"),
        "default BlinkingBlock must report PS 0, got: {resp:?}"
    );
}

/// Query cursor style after switching to SteadyBar (DECSCUSR 6).
#[test]
fn test_decrqss_cursor_style_after_decscusr() {
    let mut core = crate::TerminalCore::new(24, 80);
    core.advance(b"\x1b[6 q"); // set SteadyBar
    run_dcs(&mut core, b"$", 'q', b" q");
    let resp = std::str::from_utf8(&core.meta.pending_responses[0]).unwrap();
    assert!(
        resp.contains("6 q"),
        "SteadyBar (DECSCUSR 6) must be reported as PS 6, got: {resp:?}"
    );
}

/// Query scroll margins at default: a 24-row terminal reports `1;24r`.
#[test]
fn test_decrqss_scroll_margins_default() {
    let mut core = crate::TerminalCore::new(24, 80);
    run_dcs(&mut core, b"$", 'q', b"r");
    assert_eq!(core.meta.pending_responses.len(), 1);
    let resp = std::str::from_utf8(&core.meta.pending_responses[0]).unwrap();
    assert!(
        resp.starts_with("\x1bP1$r"),
        "DECRQSS DECSTBM must start with DCS 1 $ r, got: {resp:?}"
    );
    assert!(
        resp.contains("1;24r"),
        "default scroll region on a 24-row terminal must report 1;24r, got: {resp:?}"
    );
}

/// Query scroll margins after setting DECSTBM to rows 5–20.
#[test]
fn test_decrqss_scroll_margins_after_decstbm() {
    let mut core = crate::TerminalCore::new(24, 80);
    core.advance(b"\x1b[5;20r"); // DECSTBM 5–20
    run_dcs(&mut core, b"$", 'q', b"r");
    let resp = std::str::from_utf8(&core.meta.pending_responses[0]).unwrap();
    assert!(
        resp.contains("5;20r"),
        "DECSTBM 5–20 must be reported as 5;20r, got: {resp:?}"
    );
}

/// Query SGR with default attributes: response must begin with `DCS 1 $ r 0m`.
#[test]
fn test_decrqss_sgr_default_attrs() {
    let mut core = crate::TerminalCore::new(24, 80);
    run_dcs(&mut core, b"$", 'q', b"m");
    assert_eq!(core.meta.pending_responses.len(), 1);
    let resp = std::str::from_utf8(&core.meta.pending_responses[0]).unwrap();
    assert!(
        resp.starts_with("\x1bP1$r0m"),
        "default SGR query must respond with DCS 1 $ r 0m ST, got: {resp:?}"
    );
}

/// Query SGR after setting bold: response must contain `;1` in the parameter string.
#[test]
fn test_decrqss_sgr_bold_attr() {
    let mut core = crate::TerminalCore::new(24, 80);
    core.advance(b"\x1b[1m"); // set bold
    run_dcs(&mut core, b"$", 'q', b"m");
    let resp = std::str::from_utf8(&core.meta.pending_responses[0]).unwrap();
    assert!(
        resp.contains(";1m") || resp.contains(";1;"),
        "bold must appear as ';1' in the SGR serialisation, got: {resp:?}"
    );
}

/// An unrecognised DECRQSS target must return the failure prefix `DCS 0 $ r ST`.
#[test]
fn test_decrqss_unknown_target_returns_failure() {
    let mut core = crate::TerminalCore::new(24, 80);
    run_dcs(&mut core, b"$", 'q', b"UNKNOWN");
    assert_eq!(core.meta.pending_responses.len(), 1);
    let resp = std::str::from_utf8(&core.meta.pending_responses[0]).unwrap();
    assert!(
        resp.starts_with("\x1bP0$r"),
        "unknown DECRQSS target must return DCS 0 $ r ST, got: {resp:?}"
    );
}
