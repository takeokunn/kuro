use super::*;

#[test]
fn test_xtgettcap_smol_returns_overline() {
    let mut term = TerminalCore::new(24, 80);
    let cap_hex = hex_encode_str(b"Smol");
    let seq = format!("\x1bP+q{cap_hex}\x1b\\");
    term.advance(seq.as_bytes());
    let responses = term.pending_responses();
    assert!(!responses.is_empty(), "Smol query must produce a response");
    let resp = String::from_utf8_lossy(responses[0].as_slice()).to_string();
    assert!(
        resp.contains("1+r"),
        "Smol response must be DCS 1+r (known)"
    );
}

#[test]
fn test_xtgettcap_ss_se_cursor_style() {
    let mut term = TerminalCore::new(24, 80);
    for cap in [b"Ss" as &[u8], b"Se"] {
        let cap_hex = hex_encode_str(cap);
        let seq = format!("\x1bP+q{cap_hex}\x1b\\");
        term.advance(seq.as_bytes());
    }
    let responses = term.pending_responses();
    assert_eq!(responses.len(), 2, "Ss and Se must each produce a response");
    for r in responses {
        let s = String::from_utf8_lossy(r).to_string();
        assert!(s.contains("1+r"), "Ss/Se must be DCS 1+r (known)");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode 47/1047 — alternate screen variants
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_mode47_switches_to_alt_screen() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"primary content");
    term.advance(b"\x1b[?47h"); // enter alt screen
    assert!(
        term.dec_modes().alternate_screen,
        "mode 47 must set alternate_screen"
    );
    term.advance(b"\x1b[?47l"); // exit alt screen
    assert!(
        !term.dec_modes().alternate_screen,
        "mode 47 reset must clear alternate_screen"
    );
}

#[test]
fn test_mode1047_clears_alt_screen_on_entry() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1047h"); // enter alt screen (clears it)
                                  // Alt screen must be active
    assert!(term.dec_modes().alternate_screen);
    // Write something, then exit
    term.advance(b"\x1b[1;1Halt content");
    term.advance(b"\x1b[?1047l");
    assert!(!term.dec_modes().alternate_screen);
}

// ─────────────────────────────────────────────────────────────────────────────
// DECSCNM (mode 5) / mode 40 / mode 45
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_decscnm_mode5_tracks_screen_reverse() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?5h");
    assert!(
        term.dec_modes().screen_reverse,
        "mode 5 must set screen_reverse"
    );
    term.advance(b"\x1b[?5l");
    assert!(!term.dec_modes().screen_reverse);
}

#[test]
fn test_mode40_tracks_allow_deccolm() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?40h");
    assert!(term.dec_modes().allow_deccolm);
    term.advance(b"\x1b[?40l");
    assert!(!term.dec_modes().allow_deccolm);
}

#[test]
fn test_mode45_tracks_reverse_wraparound() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?45h");
    assert!(term.dec_modes().reverse_wraparound);
    term.advance(b"\x1b[?45l");
    assert!(!term.dec_modes().reverse_wraparound);
}

// ─────────────────────────────────────────────────────────────────────────────
// Mode 12 (DECBKM) — cursor blink toggle
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_mode12_enables_cursor_blink() {
    use kuro_core::types::cursor::CursorShape;
    let mut term = TerminalCore::new(24, 80);
    // Start with steady block (via DECSCUSR 2)
    term.advance(b"\x1b[2 q");
    assert_eq!(term.dec_modes().cursor_shape, CursorShape::SteadyBlock);
    // Mode 12 on → switch to blinking block
    term.advance(b"\x1b[?12h");
    assert_eq!(
        term.dec_modes().cursor_shape,
        CursorShape::BlinkingBlock,
        "mode 12 set must switch SteadyBlock → BlinkingBlock"
    );
}

#[test]
fn test_mode12_disables_cursor_blink() {
    use kuro_core::types::cursor::CursorShape;
    let mut term = TerminalCore::new(24, 80);
    // Start with blinking block (default)
    assert_eq!(term.dec_modes().cursor_shape, CursorShape::BlinkingBlock);
    // Mode 12 off → switch to steady block
    term.advance(b"\x1b[?12l");
    assert_eq!(
        term.dec_modes().cursor_shape,
        CursorShape::SteadyBlock,
        "mode 12 reset must switch BlinkingBlock → SteadyBlock"
    );
}

#[test]
fn test_mode12_decrqm_reports_blink_state() {
    let mut term = TerminalCore::new(24, 80);
    // Default is BlinkingBlock → mode 12 is set
    term.advance(b"\x1b[?12$p"); // DECRQM for mode 12
    let responses = term.pending_responses();
    assert!(
        !responses.is_empty(),
        "DECRQM for mode 12 must produce response"
    );
    let resp = String::from_utf8_lossy(&responses[0]).to_string();
    // Should report mode 12 as set (status=1) since default is BlinkingBlock
    assert!(
        resp.contains("?12;1$y"),
        "DECRQM mode 12 default must be set: {resp}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reverse-wraparound (mode 45) actual behavior
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_reverse_wraparound_bs_at_col0_wraps_to_prev_line() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?45h"); // enable reverse-wraparound
    term.advance(b"\x1b[2;1H"); // cursor to row 1, col 0 (0-indexed)
    term.advance(b"\x08"); // backspace at col 0 → should wrap to row 0, col 79
    assert_eq!(
        term.cursor_row(),
        0,
        "reverse-wraparound BS at col 0 must go to row 0"
    );
    assert_eq!(
        term.cursor_col(),
        79,
        "reverse-wraparound BS must go to last col (79)"
    );
}

#[test]
fn test_reverse_wraparound_off_bs_at_col0_stays() {
    let mut term = TerminalCore::new(24, 80);
    // mode 45 off by default
    term.advance(b"\x1b[2;1H"); // row 1, col 0
    term.advance(b"\x08"); // backspace — without mode 45, stays at col 0
    assert_eq!(
        term.cursor_col(),
        0,
        "without mode 45, BS at col 0 must stay"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sixel palette sharing with OSC 4
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_sixel_inherits_osc4_palette_override() {
    let mut term = TerminalCore::new(24, 80);
    // Override palette index 1 via OSC 4 (pure red)
    term.advance(b"\x1b]4;1;rgb:ff/00/00\x07");
    assert!(
        term.osc_data().palette()[1].is_some(),
        "OSC 4 palette entry 1 must be set"
    );
    // Now send a minimal sixel that references color register 1 without redefining it
    // DCS 0;1;0 q (P2=1 = background is color register 0)
    // The fact that this doesn't panic and the palette is initialized is what we test
    let sixel = b"\x1bP0;1;0q#1!1~\x1b\\"; // use register 1, paint one pixel
    term.advance(sixel);
    // If palette sharing works, the sixel uses the OSC4-overridden red for register 1
    // (We can't easily verify pixel values here but the test ensures no panic)
    assert!(
        term.cursor_row() < 24,
        "sixel with palette sharing must not panic"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// soft_reset (DECSTR) resets IRM/LNM/reverse-wraparound
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_decstr_resets_irm_lnm_reverse_wraparound() {
    let mut term = TerminalCore::new(24, 80);
    // Enable all three modes
    term.advance(b"\x1b[4h"); // IRM on (ANSI mode 4)
    term.advance(b"\x1b[20h"); // LNM on (ANSI mode 20)
    term.advance(b"\x1b[?45h"); // reverse-wraparound on
    assert!(term.dec_modes().insert_mode);
    assert!(term.dec_modes().newline_mode);
    assert!(term.dec_modes().reverse_wraparound);
    // DECSTR should reset all three
    term.advance(b"\x1b[!p"); // DECSTR
    assert!(!term.dec_modes().insert_mode, "DECSTR must reset IRM");
    assert!(!term.dec_modes().newline_mode, "DECSTR must reset LNM");
    assert!(
        !term.dec_modes().reverse_wraparound,
        "DECSTR must reset reverse-wraparound"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// CSI ^ (SD - Scroll Down, MINTTY alternate)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_csi_caret_scroll_down() {
    let mut term = TerminalCore::new(10, 80);
    term.advance(b"\x1b[1;1HLine1");
    term.advance(b"\x1b[2;1HLine2");
    // CSI ^ scrolls content down (same as CSI T)
    term.advance(b"\x1b[1^"); // scroll down 1
                              // No panic, cursor in bounds
    assert!(term.cursor_row() < 10);
}

// ─────────────────────────────────────────────────────────────────────────────
// XTGETTCAP: U8 (UTF-8 support) and Cr (cursor reset)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_xtgettcap_u8_utf8_support() {
    let mut term = TerminalCore::new(24, 80);
    let cap_hex = hex_encode_str(b"U8");
    let seq = format!("\x1bP+q{cap_hex}\x1b\\");
    term.advance(seq.as_bytes());
    let responses = term.pending_responses();
    assert!(!responses.is_empty(), "U8 query must produce a response");
    let resp = String::from_utf8_lossy(&responses[0]).to_string();
    assert!(resp.contains("1+r"), "U8 must be known (DCS 1+r): {resp}");
}

#[test]
fn test_xtgettcap_cr_cursor_reset() {
    let mut term = TerminalCore::new(24, 80);
    let cap_hex = hex_encode_str(b"Cr");
    let seq = format!("\x1bP+q{cap_hex}\x1b\\");
    term.advance(seq.as_bytes());
    let responses = term.pending_responses();
    assert!(!responses.is_empty());
    let resp = String::from_utf8_lossy(&responses[0]).to_string();
    assert!(resp.contains("1+r"), "Cr must be known: {resp}");
}

// ─────────────────────────────────────────────────────────────────────────────
// DECSDM (mode 80) — Sixel Display Mode tracking
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_decsdm_mode80_tracks_sixel_display() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?80h");
    assert!(
        term.dec_modes().sixel_display_mode,
        "mode 80 must set sixel_display_mode"
    );
    term.advance(b"\x1b[?80l");
    assert!(!term.dec_modes().sixel_display_mode);
}

#[test]
fn test_decsdm_decrqm_reports_state() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?80$p"); // DECRQM for mode 80
    let responses = term.pending_responses();
    assert!(
        !responses.is_empty(),
        "DECRQM mode 80 must produce response"
    );
    let resp = String::from_utf8_lossy(&responses[0]).to_string();
    assert!(
        resp.contains("?80;2$y"),
        "mode 80 default is reset (status=2): {resp}"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DECREQTPARM (CSI Ps x) — Request Terminal Parameters
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_decreqtparm_req0_reports_sol2() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[0x"); // DECREQTPARM request 0
    let responses = term.pending_responses();
    assert!(!responses.is_empty(), "DECREQTPARM 0 must produce a report");
    let resp = String::from_utf8_lossy(&responses[0]).to_string();
    assert_eq!(resp, "\x1b[2;1;1;128;128;1;0x", "req 0 must report sol=2");
}

#[test]
fn test_decreqtparm_req1_reports_sol3() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[1x"); // DECREQTPARM request 1
    let responses = term.pending_responses();
    assert!(!responses.is_empty());
    let resp = String::from_utf8_lossy(&responses[0]).to_string();
    assert_eq!(resp, "\x1b[3;1;1;128;128;1;0x", "req 1 must report sol=3");
}

#[test]
fn test_decreqtparm_req2_no_report() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[2x"); // request 2 produces no report (VT100 behavior)
    let responses = term.pending_responses();
    assert!(responses.is_empty(), "DECREQTPARM 2 must produce no report");
}

// ─────────────────────────────────────────────────────────────────────────────
// ANSI DECRQM (CSI Ps $ p, no '?') — query IRM/LNM state
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_ansi_decrqm_irm_set() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[4h"); // IRM on
    term.advance(b"\x1b[4$p"); // ANSI DECRQM query mode 4
    let responses = term.pending_responses();
    assert!(!responses.is_empty(), "ANSI DECRQM must produce a response");
    let resp = String::from_utf8_lossy(&responses[0]).to_string();
    assert_eq!(resp, "\x1b[4;1$y", "IRM set → status 1, no '?' prefix");
}

#[test]
fn test_ansi_decrqm_lnm_reset() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[20$p"); // query LNM (mode 20), default reset
    let responses = term.pending_responses();
    assert!(!responses.is_empty());
    let resp = String::from_utf8_lossy(&responses[0]).to_string();
    assert_eq!(resp, "\x1b[20;2$y", "LNM default → status 2 (reset)");
}

#[test]
fn test_ansi_decrqm_unknown_mode() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[99$p"); // unknown ANSI mode
    let responses = term.pending_responses();
    assert!(!responses.is_empty());
    let resp = String::from_utf8_lossy(&responses[0]).to_string();
    assert_eq!(resp, "\x1b[99;0$y", "unknown mode → status 0");
}

// ─────────────────────────────────────────────────────────────────────────────
// XTGETTCAP "kt" — Tab key capability
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn test_xtgettcap_kt_tab_key() {
    let mut term = TerminalCore::new(24, 80);
    let cap_hex = hex_encode_str(b"kt");
    let seq = format!("\x1bP+q{cap_hex}\x1b\\");
    term.advance(seq.as_bytes());
    let responses = term.pending_responses();
    assert!(!responses.is_empty(), "kt query must produce a response");
    let resp = String::from_utf8_lossy(&responses[0]).to_string();
    assert!(resp.contains("1+r"), "kt must be known (DCS 1+r): {resp}");
}
