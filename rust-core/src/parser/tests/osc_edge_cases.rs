// ── New edge-case tests ───────────────────────────────────────────────────────

/// OSC 7 with `file:///` (empty hostname, root path) must store `"/"` as CWD.
///
/// The handler strips `file://` to get `"/"`, then `find('/')` returns `Some(0)`,
/// so `path = &after_scheme[0..]` == `"/"`.
#[test]
fn test_osc7_root_path_accepted() {
    assert_osc7_cwd_accepted!(b"file:///", "/");
}

/// OSC 7 with a bare empty string (no `file://` prefix) must be silently rejected.
///
/// The handler requires a `file://` prefix; an empty string has none, so CWD
/// must remain `None` and `cwd_dirty` must stay `false`.
#[test]
fn test_osc7_empty_string_rejected() {
    assert_osc7_rejected!(b"", "empty string");
}

/// OSC 0 with an empty title byte slice must be silently rejected.
///
/// The handler has an explicit `if raw.is_empty() { return; }` guard before
/// storing the title.  The title must remain `""` (default) and `title_dirty`
/// must remain `false`.
#[test]
fn test_osc0_empty_title_rejected() {
    let mut core = crate::TerminalCore::new(24, 80);

    let params: &[&[u8]] = &[b"0", b""];
    handle_osc(&mut core, params, false);

    assert!(
        core.meta.title.is_empty(),
        "OSC 0 with empty title must not change the stored title"
    );
    assert!(
        !core.meta.title_dirty,
        "title_dirty must not be set when OSC 0 title is rejected (empty)"
    );
}

/// OSC 8 with a non-empty URI followed by a close (empty URI) must clear
/// the hyperlink — `hyperlink.uri` must be `None` after the close sequence.
#[test]
fn test_osc8_empty_uri_clears_hyperlink() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Open a hyperlink.
    let open_params: &[&[u8]] = &[b"8", b"", b"https://example.com"];
    handle_osc(&mut core, open_params, false);

    assert!(
        core.osc_data.hyperlink.uri.is_some(),
        "precondition: hyperlink must be open before testing close"
    );

    // Close with an empty URI (the `id=` params field is also empty here).
    let close_params: &[&[u8]] = &[b"8", b"", b""];
    handle_osc(&mut core, close_params, false);

    assert!(
        core.osc_data.hyperlink.uri.is_none(),
        "hyperlink must be cleared after OSC 8 with empty URI"
    );
}

/// OSC 4 with a multi-entry string in one command only sets the first entry.
///
/// The handler parses exactly `params[1]` (index) and `params[2]` (spec); any
/// further params slots are silently ignored.  When VTE splits
/// `4;0;#ff0000;1;#00ff00` by `;` the resulting params are
/// `["4","0","#ff0000","1","#00ff00"]`, so only palette[0] gets set.
#[test]
fn test_osc4_set_multiple_entries_only_first_applied() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Simulate what VTE produces when the raw OSC string is
    // "4;0;#ff0000;1;#00ff00" — each `;`-separated token becomes one param slot.
    let params: &[&[u8]] = &[b"4", b"0", b"#ff0000", b"1", b"#00ff00"];
    handle_osc(&mut core, params, false);

    assert_eq!(
        core.osc_data.palette[0],
        Some([255, 0, 0]),
        "palette[0] must be set to red from the first entry"
    );
    assert!(
        core.osc_data.palette[1].is_none(),
        "palette[1] must remain None — handler only processes the first index/spec pair"
    );
    assert!(
        core.osc_data.palette_dirty,
        "palette_dirty must be true after a successful OSC 4 set"
    );
}

/// OSC 4 with X11 `rgb:RR/GG/BB` syntax (2-digit hex per channel) must parse
/// correctly into `[R, G, B]` and store at the requested palette index.
#[test]
fn test_osc4_set_entry_with_rgb_keyword() {
    let mut core = crate::TerminalCore::new(24, 80);

    // "rgb:ff/00/00" — 2-digit channels; `parse_color_spec` treats each as
    // a direct 8-bit value (the ≤2 digit branch).
    let params: &[&[u8]] = &[b"4", b"0", b"rgb:ff/00/00"];
    handle_osc(&mut core, params, false);

    assert_eq!(
        core.osc_data.palette[0],
        Some([255, 0, 0]),
        "OSC 4 with rgb:ff/00/00 must store [255, 0, 0] at palette index 0"
    );
    assert!(
        core.osc_data.palette_dirty,
        "palette_dirty must be true after OSC 4 set via rgb: keyword"
    );
}

/// OSC 2 with a title containing spaces and special ASCII characters must be
/// stored verbatim — the handler does not sanitise title content.
#[test]
fn test_osc2_title_with_special_chars() {
    assert_osc_title_accepted!(b"2", b"Hello World!", "OSC 2 special chars");
}

/// OSC 8 URI of exactly `OSC8_MAX_URI_BYTES` bytes must be accepted.
///
/// This is a focused boundary test: the URI lands on the inclusive upper limit
/// (`uri.len() <= OSC8_MAX_URI_BYTES`), so it must be stored without truncation.
#[test]
fn test_osc8_uri_at_exactly_limit() {
    use crate::parser::limits::OSC8_MAX_URI_BYTES;

    let mut core = crate::TerminalCore::new(24, 80);

    let uri_at_limit = "x".repeat(OSC8_MAX_URI_BYTES);
    let params: &[&[u8]] = &[b"8", b"", uri_at_limit.as_bytes()];
    handle_osc(&mut core, params, false);

    assert!(
        core.osc_data.hyperlink.uri.is_some(),
        "URI of exactly OSC8_MAX_URI_BYTES must be accepted"
    );
    assert_eq!(
        core.osc_data.hyperlink.uri.as_deref().unwrap().len(),
        OSC8_MAX_URI_BYTES,
        "URI of exactly OSC8_MAX_URI_BYTES must be stored intact without truncation"
    );
}
