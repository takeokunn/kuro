//! Integration tests for OSC (Operating System Command) sequences.

mod common;

use kuro_core::TerminalCore;

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
    let responses = common::read_responses(&mut t);
    assert!(!responses.is_empty(), "OSC 4 query must produce a response");
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
    assert!(!t.palette_dirty());
    t.advance(b"\x1b]4;5;rgb:80/80/80\x07");
    assert!(
        t.palette_dirty(),
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
    assert!(
        osc.default_bg.is_some(),
        "default_bg should be set after OSC 11"
    );
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
    assert_eq!(
        osc.cursor_color,
        Some(kuro_core::Color::Rgb(0xff, 0xff, 0xff))
    );
}

#[test]
fn osc10_sets_default_colors_dirty_flag() {
    let mut t = TerminalCore::new(24, 80);
    assert!(!t.default_colors_dirty());
    t.advance(b"\x1b]10;rgb:11/22/33\x07");
    assert!(
        t.default_colors_dirty(),
        "default_colors_dirty must be set after OSC 10"
    );
}

#[test]
fn osc10_query_produces_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]10;rgb:aa/bb/cc\x07"); // set first
    t.advance(b"\x1b]10;?\x07"); // then query
    let responses = common::read_responses(&mut t);
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
    let responses = common::read_responses(&mut t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("11;"),
        "OSC 11 response must echo '11;', got: {:?}",
        resp
    );
}

#[test]
fn osc12_query_produces_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]12;rgb:ff/a5/00\x07");
    t.advance(b"\x1b]12;?\x07");
    let responses = common::read_responses(&mut t);
    assert!(!responses.is_empty());
    let resp = &responses[0];
    assert!(
        resp.contains("12;"),
        "OSC 12 response must echo '12;', got: {:?}",
        resp
    );
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
