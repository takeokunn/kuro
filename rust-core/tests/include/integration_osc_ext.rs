use super::*;

// ─────────────────────────────────────────────────────────────────────────────
// OSC 133 shell integration — prompt mark round-trip
// ─────────────────────────────────────────────────────────────────────────────

#[test]
fn osc133_prompt_marks_are_recorded() {
    let mut t = common::new_terminal();
    t.advance(b"\x1b]133;A\x07"); // PromptStart
    t.advance(b"\x1b]133;B\x07"); // PromptEnd
    let marks = t.osc_data().prompt_marks();
    assert_eq!(marks.len(), 2, "OSC 133 A and B must both be recorded");
}

// ─────────────────────────────────────────────────────────────────────────────
// New tests
// ─────────────────────────────────────────────────────────────────────────────

/// OSC 9 (iTerm2 notification) is not handled by this emulator; it must be
/// silently discarded without panic and the cursor must remain in bounds.
#[test]
fn osc9_notification_does_not_panic() {
    let mut t = common::new_terminal();
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
    let mut t = common::new_terminal();
    // Move cursor to a non-zero position
    t.advance(b"\x1b[5;3H"); // row 4, col 2 (1-indexed)
    assert_eq!(t.cursor_row(), 4);
    assert_eq!(t.cursor_col(), 2);
    // Send PromptStart and PromptEnd
    t.advance(b"\x1b]133;A\x07");
    t.advance(b"\x1b]133;B\x07");
    let marks = t.osc_data().prompt_marks();
    assert_eq!(marks.len(), 2, "Two OSC 133 marks must be recorded");
}

/// OSC 7 CWD round-trip: send a valid `file://` URL and verify the path is
/// extracted and stored in `osc_data().cwd`.
#[test]
fn osc7_cwd_round_trip() {
    let mut t = common::new_terminal();
    t.advance(b"\x1b]7;file://localhost/home/user/projects\x07");
    assert_eq!(
        t.osc_data().cwd(),
        Some("/home/user/projects"),
        "OSC 7 must store the path component in osc_data().cwd"
    );
    assert!(
        t.osc_data().cwd_dirty(),
        "cwd_dirty must be set after OSC 7"
    );
}

/// OSC 7 with a path containing special characters must be stored verbatim
/// (no URL-decode occurs in the handler).
#[test]
fn osc7_cwd_with_spaces_percent_encoded() {
    let mut t = common::new_terminal();
    // Spaces are percent-encoded in the URL; the handler stores the raw path
    t.advance(b"\x1b]7;file://localhost/home/user/my%20project\x07");
    assert_eq!(
        t.osc_data().cwd(),
        Some("/home/user/my%20project"),
        "OSC 7 must store percent-encoded path verbatim"
    );
}

/// OSC 7 with a non-file:// scheme must be silently rejected (not stored).
#[test]
fn osc7_non_file_scheme_is_rejected() {
    let mut t = common::new_terminal();
    t.advance(b"\x1b]7;https://example.com/\x07");
    assert!(
        t.osc_data().cwd().is_none(),
        "OSC 7 with non-file:// scheme must not be stored"
    );
}

/// OSC 52 clipboard write followed by OSC 52 clipboard query must leave the
/// terminal in a valid state without panic.  The `clipboard_actions` queue
/// is internal, but the terminal cursor must remain in bounds.
#[test]
fn osc52_write_and_query_no_panic() {
    let mut t = common::new_terminal();
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
    let mut t = common::new_terminal();
    t.advance(b"\x1b]52;c;!!!not-base64!!!\x07");
    // Terminal must remain usable
    assert!(t.cursor_row() < 24);
}

// ─────────────────────────────────────────────────────────────────────────────
// OSC 110 / 111 / 112 — reset default fg / bg / cursor color
// ─────────────────────────────────────────────────────────────────────────────

/// OSC 110 resets the default foreground color to None (terminal default).
#[test]
fn osc110_resets_default_fg_to_none() {
    let mut t = common::new_terminal();
    // Set fg to a color first (OSC 10 ; rgb:ff/00/00)
    t.advance(b"\x1b]10;rgb:ff/00/00\x07");
    assert!(
        t.osc_data().default_fg().is_some(),
        "default_fg must be Some after OSC 10"
    );
    // Now reset via OSC 110
    t.advance(b"\x1b]110\x07");
    assert!(
        t.osc_data().default_fg().is_none(),
        "default_fg must be None after OSC 110"
    );
}

/// OSC 111 resets the default background color to None.
#[test]
fn osc111_resets_default_bg_to_none() {
    let mut t = common::new_terminal();
    t.advance(b"\x1b]11;rgb:00/ff/00\x07");
    assert!(
        t.osc_data().default_bg().is_some(),
        "default_bg must be Some after OSC 11"
    );
    t.advance(b"\x1b]111\x07");
    assert!(
        t.osc_data().default_bg().is_none(),
        "default_bg must be None after OSC 111"
    );
}

/// OSC 112 resets the cursor color to None.
#[test]
fn osc112_resets_cursor_color_to_none() {
    let mut t = common::new_terminal();
    t.advance(b"\x1b]12;rgb:00/00/ff\x07");
    assert!(
        t.osc_data().cursor_color().is_some(),
        "cursor_color must be Some after OSC 12"
    );
    t.advance(b"\x1b]112\x07");
    assert!(
        t.osc_data().cursor_color().is_none(),
        "cursor_color must be None after OSC 112"
    );
}

/// OSC 110 on an already-unset fg is a no-op (must not panic).
#[test]
fn osc110_on_already_none_fg_is_noop() {
    let mut t = common::new_terminal();
    assert!(t.osc_data().default_fg().is_none());
    t.advance(b"\x1b]110\x07");
    assert!(t.osc_data().default_fg().is_none());
}
