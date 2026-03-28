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
