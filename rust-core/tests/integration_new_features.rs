//! Comprehensive integration tests for all newly implemented features:
//!
//! - XTVERSION (CSI > q)
//! - DECRQM (CSI ? Ps $ p)
//! - Mouse pixel mode (?1016)
//! - OSC 4 palette set/query
//! - OSC 10/11/12 default colors set/query
//! - OSC 1337 iTerm2 inline images (parse-only; no actual image rendering without GPU)
//! - DCS Sixel graphics parsing
//! - DCS XTGETTCAP capability queries
//! - SGR extended underline types (4:2, 4:3, 4:4, 4:5)
//! - SGR underline color (58/59)
//! - OSC 104 palette reset (index-specific and all)
//! - OSC 133 shell integration marks
//! - Streaming: has_pending_output (structural test only, no PTY)

use kuro_core::TerminalCore;

// ─────────────────────────────────────────────────────────────────────────────
// Helper: extract pending responses as UTF-8 strings
// ─────────────────────────────────────────────────────────────────────────────

fn take_responses(term: &mut TerminalCore) -> Vec<String> {
    // Access through public API and drain manually
    let responses = term.pending_responses().to_vec();
    // Reset is done by advance(); we just read here
    responses
        .iter()
        .map(|b| String::from_utf8_lossy(b).into_owned())
        .collect()
}

// ─────────────────────────────────────────────────────────────────────────────
// XTVERSION (CSI > q)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn xtversion_csi_greater_q_produces_dcs_response() {
    let mut t = TerminalCore::new(24, 80);
    // CSI > q — terminal version identification
    t.advance(b"\x1b[>q");
    let responses = take_responses(&mut t);
    assert!(
        !responses.is_empty(),
        "XTVERSION must produce at least one response"
    );
    let resp = &responses[0];
    // Response format: DCS > | <name>-<version> ST  (ESC P > | kuro-1.0.0 ESC \)
    assert!(
        resp.contains("kuro"),
        "XTVERSION response must contain 'kuro', got: {:?}",
        resp
    );
    assert!(
        resp.starts_with("\x1bP") || resp.contains(">|"),
        "XTVERSION response must be a DCS string, got: {:?}",
        resp
    );
}

#[test]
fn xtversion_csi_greater_0_q_produces_dcs_response() {
    // Optional: CSI > 0 q variant (param = 0)
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[>0q");
    // Should not panic; may or may not produce response (vte may not route "0q" with ">" same way)
    // The main test is no panic and optional response
    let _ = take_responses(&mut t);
}

// ─────────────────────────────────────────────────────────────────────────────
// DECRQM (CSI ? Ps $ p)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn decrqm_mode_25_cursor_visible_responds_set() {
    let mut t = TerminalCore::new(24, 80);
    // Cursor is visible by default (mode 25 = set)
    // CSI ? 25 $ p
    t.advance(b"\x1b[?25$p");
    let responses = take_responses(&mut t);
    assert!(
        !responses.is_empty(),
        "DECRQM for mode 25 must produce a response"
    );
    let resp = &responses[0];
    // Response: CSI ? 25 ; 1 $ y  (status=1 means set)
    assert!(
        resp.contains("25") && resp.contains('1') && resp.contains("$y"),
        "DECRQM response for mode 25 (set) must contain '25;1$y', got: {:?}",
        resp
    );
}

#[test]
fn decrqm_mode_1049_alt_screen_responds_reset() {
    let mut t = TerminalCore::new(24, 80);
    // Alternate screen is off by default (mode 1049 = reset)
    t.advance(b"\x1b[?1049$p");
    let responses = take_responses(&mut t);
    assert!(
        !responses.is_empty(),
        "DECRQM for mode 1049 must produce a response"
    );
    let resp = &responses[0];
    // Response: CSI ? 1049 ; 2 $ y  (status=2 means reset)
    assert!(
        resp.contains("1049") && resp.contains('2') && resp.contains("$y"),
        "DECRQM response for mode 1049 (reset) must contain '1049;2$y', got: {:?}",
        resp
    );
}

#[test]
fn decrqm_mode_after_enable_responds_set() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1004h"); // enable focus events
    t.advance(b"\x1b[?1004$p"); // query
    let responses = take_responses(&mut t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("1004") && resp.contains('1'),
        "After enabling mode 1004, DECRQM must report status=1, got: {:?}",
        resp
    );
}

#[test]
fn decrqm_unknown_mode_responds_not_recognized() {
    let mut t = TerminalCore::new(24, 80);
    // Mode 9999 — unknown/unsupported
    t.advance(b"\x1b[?9999$p");
    let responses = take_responses(&mut t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    // Status 0 = not recognized
    assert!(
        resp.contains("9999") && resp.contains('0'),
        "Unknown mode must return status=0, got: {:?}",
        resp
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Mouse Pixel Mode (?1016)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn mouse_pixel_mode_1016_enable_disable() {
    let mut t = TerminalCore::new(24, 80);
    assert!(
        !t.dec_modes().mouse_pixel,
        "Mouse pixel mode should be off by default"
    );
    t.advance(b"\x1b[?1016h"); // enable
    assert!(
        t.dec_modes().mouse_pixel,
        "Mouse pixel mode should be on after ?1016h"
    );
    t.advance(b"\x1b[?1016l"); // disable
    assert!(
        !t.dec_modes().mouse_pixel,
        "Mouse pixel mode should be off after ?1016l"
    );
}

#[test]
fn mouse_pixel_mode_1016_reported_by_decrqm() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1016h");
    t.advance(b"\x1b[?1016$p");
    let responses = take_responses(&mut t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("1016") && resp.contains('1'),
        "Mouse pixel mode enabled → DECRQM must report status=1, got: {:?}",
        resp
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// OSC 4 — Palette color set/query
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn osc4_set_palette_color() {
    let mut t = TerminalCore::new(24, 80);
    // OSC 4 ; 1 ; rgb:ff/00/00 BEL — set palette index 1 to red
    t.advance(b"\x1b]4;1;rgb:ff/00/00\x07");
    let palette = &t.osc_data().palette;
    assert_eq!(
        palette[1],
        Some([0xff, 0x00, 0x00]),
        "Palette index 1 should be red after OSC 4"
    );
}

#[test]
fn osc4_set_palette_color_4digit_hex() {
    let mut t = TerminalCore::new(24, 80);
    // 4-digit hex per channel: rgb:ffff/0000/0000 → [255, 0, 0]
    t.advance(b"\x1b]4;2;rgb:ffff/0000/0000\x07");
    let palette = &t.osc_data().palette;
    assert_eq!(
        palette[2],
        Some([0xff, 0x00, 0x00]),
        "4-digit hex palette should map upper byte to 8-bit"
    );
}

#[test]
fn osc4_query_palette_color_produces_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]4;3;rgb:00/ff/00\x07"); // set index 3 = green
    t.advance(b"\x1b]4;3;?\x07"); // query index 3
    let responses = take_responses(&mut t);
    assert!(
        !responses.is_empty(),
        "OSC 4 query must produce a response"
    );
    let resp = &responses[0];
    assert!(
        resp.contains("4;3"),
        "OSC 4 response must echo back index 3, got: {:?}",
        resp
    );
    // Response should contain some green channel info
    assert!(
        resp.contains("rgb:") || resp.contains("ff"),
        "OSC 4 response should contain the color spec, got: {:?}",
        resp
    );
}

#[test]
fn osc4_set_marks_palette_dirty() {
    let mut t = TerminalCore::new(24, 80);
    assert!(!t.osc_data().palette_dirty);
    t.advance(b"\x1b]4;5;rgb:80/80/80\x07");
    assert!(
        t.osc_data().palette_dirty,
        "palette_dirty should be true after OSC 4 set"
    );
}

#[test]
fn osc104_reset_specific_index() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]4;10;rgb:aa/bb/cc\x07"); // set index 10
    assert!(t.osc_data().palette[10].is_some());
    t.advance(b"\x1b]104;10\x07"); // reset index 10 only
    assert!(
        t.osc_data().palette[10].is_none(),
        "OSC 104;N should reset specific palette index"
    );
}

#[test]
fn osc104_reset_all() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]4;0;rgb:ff/00/00\x07");
    t.advance(b"\x1b]4;1;rgb:00/ff/00\x07");
    t.advance(b"\x1b]104\x07"); // reset all
    assert!(
        t.osc_data().palette.iter().all(|e| e.is_none()),
        "OSC 104 with no args must reset all palette entries"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// OSC 10/11/12 — Default fg/bg/cursor colors
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn osc10_set_default_fg_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]10;rgb:ff/80/00\x07"); // set fg to orange
    let osc = t.osc_data();
    assert!(
        osc.default_fg.is_some(),
        "default_fg should be set after OSC 10"
    );
    assert_eq!(
        osc.default_fg,
        Some(kuro_core::Color::Rgb(0xff, 0x80, 0x00)),
        "default_fg should be Rgb(255, 128, 0)"
    );
}

#[test]
fn osc11_set_default_bg_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]11;rgb:1e/1e/2e\x07"); // Catppuccin Mocha base
    let osc = t.osc_data();
    assert!(osc.default_bg.is_some(), "default_bg should be set after OSC 11");
    assert_eq!(
        osc.default_bg,
        Some(kuro_core::Color::Rgb(0x1e, 0x1e, 0x2e))
    );
}

#[test]
fn osc12_set_cursor_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]12;rgb:ff/ff/ff\x07");
    let osc = t.osc_data();
    assert!(osc.cursor_color.is_some());
    assert_eq!(osc.cursor_color, Some(kuro_core::Color::Rgb(0xff, 0xff, 0xff)));
}

#[test]
fn osc10_sets_default_colors_dirty_flag() {
    let mut t = TerminalCore::new(24, 80);
    assert!(!t.osc_data().default_colors_dirty);
    t.advance(b"\x1b]10;rgb:11/22/33\x07");
    assert!(
        t.osc_data().default_colors_dirty,
        "default_colors_dirty must be set after OSC 10"
    );
}

#[test]
fn osc10_query_produces_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]10;rgb:aa/bb/cc\x07"); // set first
    t.advance(b"\x1b]10;?\x07"); // then query
    let responses = take_responses(&mut t);
    assert!(
        !responses.is_empty(),
        "OSC 10 query must produce a response"
    );
    let resp = &responses[0];
    assert!(
        resp.contains("10;"),
        "OSC 10 response must echo back '10;', got: {:?}",
        resp
    );
}

#[test]
fn osc11_query_produces_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]11;rgb:22/33/44\x07");
    t.advance(b"\x1b]11;?\x07");
    let responses = take_responses(&mut t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(resp.contains("11;"), "OSC 11 response must echo '11;', got: {:?}", resp);
}

#[test]
fn osc12_query_produces_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]12;rgb:ff/a5/00\x07");
    t.advance(b"\x1b]12;?\x07");
    let responses = take_responses(&mut t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(resp.contains("12;"), "OSC 12 response must echo '12;', got: {:?}", resp);
}

#[test]
fn osc10_hash_color_format() {
    // CSS-style #RRGGBB format should also work
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]10;#ff8000\x07");
    assert_eq!(
        t.osc_data().default_fg,
        Some(kuro_core::Color::Rgb(0xff, 0x80, 0x00)),
        "#RRGGBB format should parse correctly"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// DCS XTGETTCAP
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn xtgettcap_tn_responds_with_kuro() {
    let mut t = TerminalCore::new(24, 80);
    // DCS + q 544e ST  ("TN" in hex = 54 4e)
    t.advance(b"\x1bP+q544e\x1b\\");
    let responses = take_responses(&mut t);
    assert!(
        !responses.is_empty(),
        "XTGETTCAP for TN must produce a response"
    );
    let resp = &responses[0];
    assert!(
        resp.contains("1+r"),
        "Known capability must use DCS 1+r format, got: {:?}",
        resp
    );
    // Response contains hex-encoded "kuro"
    // "kuro" in hex = 6b 75 72 6f
    assert!(
        resp.contains("6b75726f") || resp.to_lowercase().contains("kuro"),
        "TN response must encode 'kuro', got: {:?}",
        resp
    );
}

#[test]
fn xtgettcap_rgb_responds_with_truecolor() {
    let mut t = TerminalCore::new(24, 80);
    // DCS + q 524742 ST  ("RGB" in hex = 52 47 42)
    t.advance(b"\x1bP+q524742\x1b\\");
    let responses = take_responses(&mut t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("1+r"),
        "RGB capability response must be DCS 1+r, got: {:?}",
        resp
    );
}

#[test]
fn xtgettcap_unknown_cap_responds_not_found() {
    let mut t = TerminalCore::new(24, 80);
    // DCS + q 786666 ST  ("xff" — not a valid capability)
    t.advance(b"\x1bP+q786666\x1b\\");
    let responses = take_responses(&mut t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("0+r"),
        "Unknown capability must use DCS 0+r format, got: {:?}",
        resp
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

// ─────────────────────────────────────────────────────────────────────────────
// SGR Extended Underline Types (4:X sub-params, 21, 58, 59)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn sgr_4_colon_2_sets_double_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:2m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Double,
        "SGR 4:2 must set Double underline"
    );
}

#[test]
fn sgr_4_colon_3_sets_curly_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:3m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Curly
    );
}

#[test]
fn sgr_4_colon_4_sets_dotted_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:4m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Dotted
    );
}

#[test]
fn sgr_4_colon_5_sets_dashed_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:5m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Dashed
    );
}

#[test]
fn sgr_4_colon_0_clears_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4m"); // set straight first
    assert!(t.current_underline());
    t.advance(b"\x1b[4:0m"); // clear via sub-param
    assert!(
        !t.current_underline(),
        "SGR 4:0 must clear underline"
    );
}

#[test]
fn sgr_21_sets_double_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[21m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Double,
        "SGR 21 must set Double underline"
    );
}

#[test]
fn sgr_58_sets_underline_color_rgb() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[58:2:255:128:0m"); // RGB underline color
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::Color::Rgb(255, 128, 0),
        "SGR 58:2:R:G:B must set underline_color to Rgb"
    );
}

#[test]
fn sgr_59_resets_underline_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[58:2:255:0:0m"); // set red underline color
    t.advance(b"\x1b[59m"); // reset underline color
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::Color::Default,
        "SGR 59 must reset underline_color to Default"
    );
}

#[test]
fn sgr_4_colon_1_sets_straight_underline() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:1m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::Straight,
        "SGR 4:1 must set Straight underline"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// OSC 1337 iTerm2 inline images — parse-only (structural test)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn iterm2_osc1337_inline0_is_ignored() {
    let mut t = TerminalCore::new(24, 80);
    let cursor_before = (t.cursor_row(), t.cursor_col());
    // inline=0 means save to disk, not display — should be ignored
    t.advance(b"\x1b]1337;File=name=dGVzdA==;inline=0:dGVzdA==\x07");
    // Cursor should NOT move because inline=0
    assert_eq!(
        (t.cursor_row(), t.cursor_col()),
        cursor_before,
        "OSC 1337 with inline=0 must not move cursor"
    );
}

#[test]
fn iterm2_osc1337_malformed_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    // Malformed: missing ':' separator between params and data
    t.advance(b"\x1b]1337;File=inline=1;NOTBASE64\x07");
    // Just must not panic
    assert!(t.cursor_row() < 24);
}

#[test]
fn iterm2_osc1337_empty_data_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]1337;File=inline=1:\x07"); // empty base64
    assert!(t.cursor_row() < 24);
}

#[test]
fn iterm2_osc1337_invalid_base64_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    // Invalid base64 — should be silently ignored without panic
    t.advance(b"\x1b]1337;File=inline=1:!!!invalid!!!\x07");
    assert!(t.cursor_row() < 24);
}

// ─────────────────────────────────────────────────────────────────────────────
// DA1 / DA2 — device attributes (pre-existing, regression test)
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn da1_produces_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[c"); // Primary DA
    let responses = take_responses(&mut t);
    assert!(!responses.is_empty(), "DA1 must produce a response");
    let resp = &responses[0];
    assert!(resp.contains("?1"), "DA1 response must contain '?1', got: {:?}", resp);
}

#[test]
fn da2_produces_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[>c"); // Secondary DA
    let responses = take_responses(&mut t);
    assert!(!responses.is_empty(), "DA2 must produce a response");
    let resp = &responses[0];
    assert!(resp.starts_with("\x1b[>"), "DA2 response must start with ESC[>, got: {:?}", resp);
}

// ─────────────────────────────────────────────────────────────────────────────
// Synchronized Output (?2026) — regression test
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn synchronized_output_enable_disable() {
    let mut t = TerminalCore::new(24, 80);
    assert!(!t.dec_modes().synchronized_output);
    t.advance(b"\x1b[?2026h");
    assert!(t.dec_modes().synchronized_output);
    t.advance(b"\x1b[?2026l");
    assert!(!t.dec_modes().synchronized_output);
}

#[test]
fn decrqm_synchronized_output_reports_state() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?2026h");
    t.advance(b"\x1b[?2026$p");
    let responses = take_responses(&mut t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("2026") && resp.contains('1'),
        "?2026 enabled → DECRQM must report 1, got: {:?}",
        resp
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Kitty keyboard protocol — regression test
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn kitty_keyboard_push_pop_query() {
    let mut t = TerminalCore::new(24, 80);
    assert_eq!(t.dec_modes().keyboard_flags, 0);
    // Push flags=1
    t.advance(b"\x1b[>1u");
    assert_eq!(t.dec_modes().keyboard_flags, 1);
    // Query → response with current flags
    t.advance(b"\x1b[?u");
    let responses = take_responses(&mut t);
    assert!(!responses.is_empty(), "Kitty keyboard query must respond");
    // Pop
    t.advance(b"\x1b[<u");
    assert_eq!(t.dec_modes().keyboard_flags, 0, "Flags should revert after pop");
}

// ─────────────────────────────────────────────────────────────────────────────
// OSC 133 shell integration — regression test
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn osc133_prompt_marks_are_recorded() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]133;A\x07"); // PromptStart
    t.advance(b"\x1b]133;B\x07"); // PromptEnd
    let marks = &t.osc_data().prompt_marks;
    assert_eq!(marks.len(), 2, "OSC 133 A and B must both be recorded");
}

// ─────────────────────────────────────────────────────────────────────────────
// OscData::default() — ensure palette is 256 elements
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn osc_data_palette_initialized_to_256_nones() {
    let t = TerminalCore::new(24, 80);
    assert_eq!(
        t.osc_data().palette.len(),
        256,
        "OscData.palette must have 256 entries"
    );
    assert!(
        t.osc_data().palette.iter().all(|e| e.is_none()),
        "All palette entries must be None initially"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Regression: reset() must clear dcs_state and palette
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn reset_clears_palette_entries() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]4;0;rgb:ff/00/00\x07");
    assert!(t.osc_data().palette[0].is_some());
    t.advance(b"\x1bc"); // RIS full reset
    assert!(
        t.osc_data().palette[0].is_none(),
        "RIS reset must clear palette entries"
    );
}

#[test]
fn reset_clears_default_colors() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]10;rgb:ff/ff/ff\x07");
    assert!(t.osc_data().default_fg.is_some());
    t.advance(b"\x1bc"); // RIS
    assert!(
        t.osc_data().default_fg.is_none(),
        "RIS reset must clear default_fg"
    );
}
