//! Integration tests for OSC (Operating System Command) sequences.

mod common;

use kuro_core::TerminalCore;

// ─────────────────────────────────────────────────────────────────────────────
// Macros
// ─────────────────────────────────────────────────────────────────────────────

/// Assert that a set-then-query sequence for OSC 10, 11, or 12 produces at
/// least one response containing the expected OSC number prefix.
///
/// Usage: `assert_osc_color_query!(set_seq, query_seq, "10;", "OSC 10 label")`
macro_rules! assert_osc_color_query {
    ($set_seq:expr, $query_seq:expr, $needle:literal, $label:literal) => {{
        let mut t = TerminalCore::new(24, 80);
        t.advance($set_seq);
        t.advance($query_seq);
        let responses = common::read_responses(&t);
        assert!(
            !responses.is_empty(),
            "{}: query must produce a response",
            $label
        );
        let resp = &responses[0];
        assert!(
            resp.contains($needle),
            "{}: response must contain {:?}, got: {resp:?}",
            $label,
            $needle
        );
    }};
}

/// Assert that an OSC 133 full shell-integration cycle (A→B→C→D) records the
/// correct number of prompt marks.
macro_rules! assert_osc133_cycle {
    ($seq:expr, $expected_count:expr, $label:literal) => {{
        let mut t = TerminalCore::new(24, 80);
        t.advance($seq);
        assert_eq!(
            t.osc_data().prompt_marks.len(),
            $expected_count,
            "{}: expected {} prompt marks, got {}",
            $label,
            $expected_count,
            t.osc_data().prompt_marks.len()
        );
    }};
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
    let responses = common::read_responses(&t);
    assert!(!responses.is_empty(), "OSC 4 query must produce a response");
    let resp = &responses[0];
    assert!(
        resp.contains("4;3"),
        "OSC 4 response must echo back index 3, got: {resp:?}"
    );
    // Response should contain some green channel info
    assert!(
        resp.contains("rgb:") || resp.contains("ff"),
        "OSC 4 response should contain the color spec, got: {resp:?}"
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
        t.osc_data()
            .palette
            .iter()
            .all(std::option::Option::is_none),
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
    assert_osc_color_query!(
        b"\x1b]10;rgb:aa/bb/cc\x07",
        b"\x1b]10;?\x07",
        "10;",
        "OSC 10 query"
    );
}

#[test]
fn osc11_query_produces_response() {
    assert_osc_color_query!(
        b"\x1b]11;rgb:22/33/44\x07",
        b"\x1b]11;?\x07",
        "11;",
        "OSC 11 query"
    );
}

#[test]
fn osc12_query_produces_response() {
    assert_osc_color_query!(
        b"\x1b]12;rgb:ff/a5/00\x07",
        b"\x1b]12;?\x07",
        "12;",
        "OSC 12 query"
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
// OSC 133 shell integration — prompt mark round-trip
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
// New tests
// ─────────────────────────────────────────────────────────────────────────────

/// OSC 9 (iTerm2 notification) is not handled by this emulator; it must be
/// silently discarded without panic and the cursor must remain in bounds.
#[test]
fn osc9_notification_does_not_panic() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]9;Test notification text\x07");
    assert!(
        t.cursor_row() < 24,
        "cursor row must remain in bounds after OSC 9"
    );
    assert!(
        t.cursor_col() < 80,
        "cursor col must remain in bounds after OSC 9"
    );
}

/// OSC 133 full shell-integration cycle (A → B → C → D) must record all 4
/// marks in the correct order.
#[test]
fn osc133_full_cycle_records_four_marks() {
    assert_osc133_cycle!(
        b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07\x1b]133;D\x07",
        4,
        "OSC 133 A→B→C→D"
    );
}

/// OSC 133 marks are position-stamped at the cursor location when they
/// arrive.  After moving the cursor to a known position the mark count must
/// reflect the OSC 133 sequences received.
#[test]
fn osc133_mark_round_trip_via_prompt_marks() {
    let mut t = TerminalCore::new(24, 80);
    // Move cursor to a non-zero position
    t.advance(b"\x1b[5;3H"); // row 4, col 2 (1-indexed)
    assert_eq!(t.cursor_row(), 4);
    assert_eq!(t.cursor_col(), 2);
    // Send PromptStart and PromptEnd
    t.advance(b"\x1b]133;A\x07");
    t.advance(b"\x1b]133;B\x07");
    let marks = &t.osc_data().prompt_marks;
    assert_eq!(marks.len(), 2, "Two OSC 133 marks must be recorded");
}

/// OSC 7 CWD round-trip: send a valid `file://` URL and verify the path is
/// extracted and stored in `osc_data().cwd`.
#[test]
fn osc7_cwd_round_trip() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]7;file://localhost/home/user/projects\x07");
    assert_eq!(
        t.osc_data().cwd.as_deref(),
        Some("/home/user/projects"),
        "OSC 7 must store the path component in osc_data().cwd"
    );
    assert!(t.osc_data().cwd_dirty, "cwd_dirty must be set after OSC 7");
}

/// OSC 7 with a path containing special characters must be stored verbatim
/// (no URL-decode occurs in the handler).
#[test]
fn osc7_cwd_with_spaces_percent_encoded() {
    let mut t = TerminalCore::new(24, 80);
    // Spaces are percent-encoded in the URL; the handler stores the raw path
    t.advance(b"\x1b]7;file://localhost/home/user/my%20project\x07");
    assert_eq!(
        t.osc_data().cwd.as_deref(),
        Some("/home/user/my%20project"),
        "OSC 7 must store percent-encoded path verbatim"
    );
}

/// OSC 7 with a non-file:// scheme must be silently rejected (not stored).
#[test]
fn osc7_non_file_scheme_is_rejected() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]7;https://example.com/\x07");
    assert!(
        t.osc_data().cwd.is_none(),
        "OSC 7 with non-file:// scheme must not be stored"
    );
}

/// OSC 52 clipboard write followed by OSC 52 clipboard query must leave the
/// terminal in a valid state without panic.  The `clipboard_actions` queue
/// is internal, but the terminal cursor must remain in bounds.
#[test]
fn osc52_write_and_query_no_panic() {
    let mut t = TerminalCore::new(24, 80);
    // Write "hello" (base64: aGVsbG8=) to the clipboard
    t.advance(b"\x1b]52;c;aGVsbG8=\x07");
    // Query clipboard
    t.advance(b"\x1b]52;c;?\x07");
    // Must not panic; cursor stays in bounds
    assert!(t.cursor_row() < 24);
    assert!(t.cursor_col() < 80);
}

/// OSC 52 with an invalid base64 payload must be silently ignored.
#[test]
fn osc52_invalid_base64_is_ignored() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]52;c;!!!not-base64!!!\x07");
    // Terminal must remain usable
    assert!(t.cursor_row() < 24);
}

// ─────────────────────────────────────────────────────────────────────────────
// OSC 7 — CWD edge cases
// ─────────────────────────────────────────────────────────────────────────────

// OSC 7 with a trailing slash must store the path with the trailing slash
// intact (no stripping occurs in the handler).
#[test]
fn osc7_cwd_trailing_slash_stored_verbatim() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]7;file://localhost/home/user/projects/\x07");
    assert_eq!(
        t.osc_data().cwd.as_deref(),
        Some("/home/user/projects/"),
        "OSC 7 must store trailing slash verbatim"
    );
}

// OSC 7 with an empty hostname (file:///path) must store the absolute path.
#[test]
fn osc7_cwd_empty_hostname_stores_path() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]7;file:///home/user\x07");
    assert_eq!(
        t.osc_data().cwd.as_deref(),
        Some("/home/user"),
        "OSC 7 with empty hostname must extract absolute path"
    );
    assert!(
        t.osc_data().cwd_dirty,
        "cwd_dirty must be set after OSC 7 with empty hostname"
    );
}

// OSC 7 with an ftp:// scheme must be rejected (not stored).
#[test]
fn osc7_ftp_scheme_is_rejected() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]7;ftp://host/path\x07");
    assert!(
        t.osc_data().cwd.is_none(),
        "OSC 7 with ftp:// scheme must not be stored"
    );
}

// OSC 7 with a completely bare string (no scheme) must be rejected.
#[test]
fn osc7_no_scheme_is_rejected() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]7;/home/user/noslash\x07");
    assert!(
        t.osc_data().cwd.is_none(),
        "OSC 7 with no file:// scheme must not be stored"
    );
}

// OSC 7 CWD must update cwd_dirty flag; a second OSC 7 with a different path
// must overwrite the previous value.
#[test]
fn osc7_cwd_can_be_overwritten() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]7;file://localhost/first\x07");
    assert_eq!(t.osc_data().cwd.as_deref(), Some("/first"));
    t.advance(b"\x1b]7;file://localhost/second\x07");
    assert_eq!(
        t.osc_data().cwd.as_deref(),
        Some("/second"),
        "Second OSC 7 must overwrite the previous CWD"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// OSC 8 — Hyperlink lifecycle
// ─────────────────────────────────────────────────────────────────────────────

// OSC 8 with a non-empty URI sets the hyperlink; OSC 8 with an empty URI clears it.
#[test]
fn osc8_hyperlink_open_then_close() {
    let mut t = TerminalCore::new(24, 80);
    // Open hyperlink: OSC 8 ; ; https://example.com ST
    t.advance(b"\x1b]8;;https://example.com\x07");
    assert_eq!(
        t.osc_data().hyperlink.uri.as_deref(),
        Some("https://example.com"),
        "hyperlink URI must be set after OSC 8 open"
    );
    // Close hyperlink: OSC 8 ; ; ST (empty URI)
    t.advance(b"\x1b]8;;\x07");
    assert!(
        t.osc_data().hyperlink.uri.is_none(),
        "hyperlink URI must be None after OSC 8 close"
    );
}

// A sequence of two different hyperlinks must update the URI to the latest one.
#[test]
fn osc8_hyperlink_sequential_links_update_uri() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]8;;https://first.example.com\x07");
    assert_eq!(
        t.osc_data().hyperlink.uri.as_deref(),
        Some("https://first.example.com"),
        "first hyperlink must be stored"
    );
    // Open a second link directly without closing the first
    t.advance(b"\x1b]8;;https://second.example.com\x07");
    assert_eq!(
        t.osc_data().hyperlink.uri.as_deref(),
        Some("https://second.example.com"),
        "second hyperlink must overwrite the first"
    );
}

// OSC 8 with id= parameter must still store the URI correctly.
#[test]
fn osc8_hyperlink_with_id_param_stores_uri() {
    let mut t = TerminalCore::new(24, 80);
    // OSC 8 ; id=mylink ; https://docs.rs ST
    t.advance(b"\x1b]8;id=mylink;https://docs.rs\x07");
    assert_eq!(
        t.osc_data().hyperlink.uri.as_deref(),
        Some("https://docs.rs"),
        "OSC 8 with id= parameter must store the URI"
    );
}

// Open a hyperlink, write some text, then close. Cursor must remain in bounds.
#[test]
fn osc8_hyperlink_text_between_open_and_close() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]8;;https://example.com\x07");
    t.advance(b"click here");
    t.advance(b"\x1b]8;;\x07");
    assert!(
        t.osc_data().hyperlink.uri.is_none(),
        "hyperlink must be closed after final OSC 8 empty-URI"
    );
    assert!(t.cursor_row() < 24);
    assert!(t.cursor_col() < 80);
}

// ─────────────────────────────────────────────────────────────────────────────
// OSC 10/11/12 — default color set/query additional coverage
// ─────────────────────────────────────────────────────────────────────────────

// OSC 11 hash color format (#RRGGBB) must be accepted.
#[test]
fn osc11_hash_color_format() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]11;#1e1e2e\x07");
    assert_eq!(
        t.osc_data().default_bg,
        Some(kuro_core::Color::Rgb(0x1e, 0x1e, 0x2e)),
        "#RRGGBB format must be accepted for OSC 11"
    );
}

// OSC 12 hash color format (#RRGGBB) must be accepted.
#[test]
fn osc12_hash_color_format() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]12;#cdd6f4\x07");
    assert_eq!(
        t.osc_data().cursor_color,
        Some(kuro_core::Color::Rgb(0xcd, 0xd6, 0xf4)),
        "#RRGGBB format must be accepted for OSC 12"
    );
}

// OSC 11 must set the default_colors_dirty flag.
#[test]
fn osc11_sets_default_colors_dirty_flag() {
    let mut t = TerminalCore::new(24, 80);
    assert!(!t.default_colors_dirty());
    t.advance(b"\x1b]11;rgb:00/00/00\x07");
    assert!(
        t.default_colors_dirty(),
        "default_colors_dirty must be set after OSC 11"
    );
}

// OSC 12 must set the default_colors_dirty flag.
#[test]
fn osc12_sets_default_colors_dirty_flag() {
    let mut t = TerminalCore::new(24, 80);
    assert!(!t.default_colors_dirty());
    t.advance(b"\x1b]12;rgb:ff/ff/ff\x07");
    assert!(
        t.default_colors_dirty(),
        "default_colors_dirty must be set after OSC 12"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// OSC 104 — palette reset additional coverage
// ─────────────────────────────────────────────────────────────────────────────

// OSC 104 must leave unrelated palette indices untouched when resetting one.
#[test]
fn osc104_reset_specific_leaves_others_intact() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]4;1;rgb:ff/00/00\x07"); // set index 1 to red
    t.advance(b"\x1b]4;2;rgb:00/ff/00\x07"); // set index 2 to green
    t.advance(b"\x1b]104;1\x07"); // reset only index 1
    assert!(
        t.osc_data().palette[1].is_none(),
        "index 1 must be reset by OSC 104;1"
    );
    assert_eq!(
        t.osc_data().palette[2],
        Some([0x00, 0xff, 0x00]),
        "index 2 must remain untouched after OSC 104;1"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// OSC 133 — shell integration additional coverage
// ─────────────────────────────────────────────────────────────────────────────

// OSC 133;A (PromptStart) alone records exactly one mark.
#[test]
fn osc133_single_prompt_start_records_one_mark() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]133;A\x07");
    assert_eq!(
        t.osc_data().prompt_marks.len(),
        1,
        "One OSC 133;A must produce exactly one prompt mark"
    );
}

// Repeated OSC 133 sequences accumulate marks correctly.
#[test]
fn osc133_repeated_sequences_accumulate_marks() {
    assert_osc133_cycle!(
        b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07\x1b]133;D\x07\
          \x1b]133;A\x07\x1b]133;B\x07",
        6,
        "OSC 133 A→B→C→D→A→B must accumulate 6 marks"
    );
}

// OSC 133 with an unknown letter must not panic and must not add a mark.
#[test]
fn osc133_unknown_letter_is_ignored() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]133;Z\x07");
    assert_eq!(
        t.osc_data().prompt_marks.len(),
        0,
        "Unknown OSC 133 letter must not add a prompt mark"
    );
    assert!(t.cursor_row() < 24);
}
