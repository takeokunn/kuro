//! Property-based and example-based tests for `osc` parsing.
//!
//! Module under test: `parser/osc.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;

/// OSC 0 sets the window title on the terminal core.
#[test]
fn test_osc0_sets_title() {
    let mut core = crate::TerminalCore::new(24, 80);

    let params: &[&[u8]] = &[b"0", b"myterm"];
    handle_osc(&mut core, params, false);

    assert_eq!(core.meta.title, "myterm", "OSC 0 must set the window title");
    assert!(core.meta.title_dirty, "title_dirty must be set after OSC 0");
}

/// OSC 0 with a title longer than 1024 bytes must be silently rejected
/// (`DoS` prevention guard in the handler).
#[test]
fn test_osc0_oversized_title_is_rejected() {
    let mut core = crate::TerminalCore::new(24, 80);

    let long_title = vec![b'A'; 1025];
    let params: &[&[u8]] = &[b"0", &long_title];
    handle_osc(&mut core, params, false);

    assert!(
        core.meta.title.is_empty(),
        "oversized title must be rejected; title should remain empty"
    );
    assert!(
        !core.meta.title_dirty,
        "title_dirty must not be set when title is rejected"
    );
}

/// OSC 7 (`file://hostname/path`) must extract the path component and store
/// it in `osc_data.cwd`.
#[test]
fn test_osc7_extracts_path() {
    let mut core = crate::TerminalCore::new(24, 80);

    let params: &[&[u8]] = &[b"7", b"file://hostname/home/user"];
    handle_osc(&mut core, params, false);

    assert_eq!(
        core.osc_data.cwd.as_deref(),
        Some("/home/user"),
        "OSC 7 must extract the path component from the file:// URL"
    );
    assert!(
        core.osc_data.cwd_dirty,
        "cwd_dirty must be set after OSC 7"
    );
}

/// OSC 2 must behave identically to OSC 0 for window title setting:
/// the title is stored and `title_dirty` is set.
#[test]
fn test_osc2_sets_title_same_as_osc0() {
    let mut core = crate::TerminalCore::new(24, 80);

    let params: &[&[u8]] = &[b"2", b"window-title"];
    handle_osc(&mut core, params, false);

    assert_eq!(
        core.meta.title, "window-title",
        "OSC 2 must set the window title identically to OSC 0"
    );
    assert!(
        core.meta.title_dirty,
        "title_dirty must be set after OSC 2"
    );
}

/// OSC 7 with a URL that does NOT start with `file://` must be silently
/// ignored — the CWD field must remain unset.
#[test]
fn test_osc7_rejects_non_file_url() {
    let mut core = crate::TerminalCore::new(24, 80);

    // An SSH URL does not match the `file://` guard in the handler.
    let params: &[&[u8]] = &[b"7", b"ssh://host/path"];
    handle_osc(&mut core, params, false);

    assert!(
        core.osc_data.cwd.is_none(),
        "non-file:// URL in OSC 7 must leave CWD unset"
    );
    assert!(
        !core.osc_data.cwd_dirty,
        "cwd_dirty must not be set when OSC 7 URL is rejected"
    );
}

/// OSC 8 lifecycle: opening a hyperlink sets uri; closing it (empty
/// URI) resets the hyperlink state back to the default (None).
#[test]
fn test_osc8_hyperlink_lifecycle() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Open hyperlink: OSC 8 ; id=abc ; https://example.com ST
    let open_params: &[&[u8]] = &[b"8", b"id=abc", b"https://example.com"];
    handle_osc(&mut core, open_params, false);

    assert_eq!(
        core.osc_data.hyperlink.uri.as_deref(),
        Some("https://example.com"),
        "hyperlink URI must be set after OSC 8 open"
    );

    // Close hyperlink: OSC 8 ; ; ST (empty URI)
    let close_params: &[&[u8]] = &[b"8", b"", b""];
    handle_osc(&mut core, close_params, false);

    assert!(
        core.osc_data.hyperlink.uri.is_none(),
        "hyperlink URI must be cleared after OSC 8 close"
    );
}

/// OSC 0 title of exactly `MAX_TITLE_BYTES` must be accepted and stored intact.
#[test]
fn test_osc_title_exactly_at_limit_is_accepted() {
    use crate::parser::limits::MAX_TITLE_BYTES;

    let mut core = crate::TerminalCore::new(24, 80);

    // Construct a title of exactly the limit.
    let exact_title = "a".repeat(MAX_TITLE_BYTES);
    let params: &[&[u8]] = &[b"0", exact_title.as_bytes()];
    handle_osc(&mut core, params, false);

    assert_eq!(
        core.meta.title.len(),
        MAX_TITLE_BYTES,
        "title of exactly MAX_TITLE_BYTES must be stored intact"
    );
    assert!(
        core.meta.title_dirty,
        "title_dirty must be set when title is accepted"
    );
}

/// OSC 8 URI exactly at the limit must be accepted; one byte over the limit
/// must be silently rejected (hyperlink URI stays None).
#[test]
fn test_osc8_uri_truncated_at_limit() {
    use crate::parser::limits::OSC8_MAX_URI_BYTES;

    let mut core = crate::TerminalCore::new(24, 80);

    // Exactly at the limit — must be accepted.
    let uri_at_limit = "a".repeat(OSC8_MAX_URI_BYTES);
    let open_params: &[&[u8]] = &[b"8", b"", uri_at_limit.as_bytes()];
    handle_osc(&mut core, open_params, false);

    assert!(
        core.osc_data.hyperlink.uri.is_some(),
        "URI of exactly OSC8_MAX_URI_BYTES must be accepted"
    );
    assert_eq!(
        core.osc_data.hyperlink.uri.as_deref().unwrap().len(),
        OSC8_MAX_URI_BYTES,
        "URI of exactly OSC8_MAX_URI_BYTES must be stored intact"
    );

    // Reset state.
    core.osc_data.hyperlink = crate::types::osc::HyperlinkState::default();

    // One byte over the limit — must be rejected.
    let uri_over_limit = "a".repeat(OSC8_MAX_URI_BYTES + 1);
    let over_params: &[&[u8]] = &[b"8", b"", uri_over_limit.as_bytes()];
    handle_osc(&mut core, over_params, false);

    assert!(
        core.osc_data.hyperlink.uri.is_none(),
        "URI of OSC8_MAX_URI_BYTES + 1 must be rejected; hyperlink URI must remain None"
    );
}

/// OSC 4 set palette: `OSC 4 ; 1 ; rgb:ff/00/00 ST` must store
/// `[255, 0, 0]` at palette index 1 and set `palette_dirty`.
#[test]
fn test_osc4_set_palette_entry() {
    let mut core = crate::TerminalCore::new(24, 80);

    // params[0]="4", params[1]="1" (index), params[2]="rgb:ff/00/00" (color spec)
    let params: &[&[u8]] = &[b"4", b"1", b"rgb:ff/00/00"];
    handle_osc(&mut core, params, false);

    assert_eq!(
        core.osc_data.palette[1],
        Some([255, 0, 0]),
        "OSC 4 set must store [255,0,0] at palette index 1"
    );
    assert!(
        core.osc_data.palette_dirty,
        "palette_dirty must be true after OSC 4 set"
    );
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: OSC 0 with arbitrary ASCII title never panics
    fn prop_osc0_title_no_panic(
        title in proptest::collection::vec(b'!'..=b'~', 0..=100)
    ) {
        let mut term = crate::TerminalCore::new(24, 80);
        let title_str = String::from_utf8(title).unwrap_or_default();
        let seq = format!("\x1b]0;{title_str}\x07");
        term.advance(seq.as_bytes());
        // Terminal must remain in a valid state
        prop_assert!(term.screen.cursor().row < 24);
    }

    #[test]
    // PANIC SAFETY: OSC 4 with any palette index never panics
    fn prop_osc4_no_panic(idx in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        let seq = format!("\x1b]4;{idx};rgb:ff/00/00\x07");
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }

    #[test]
    // PANIC SAFETY: OSC 2 (icon name) with arbitrary title never panics
    fn prop_osc2_no_panic(
        title in proptest::collection::vec(b'!'..=b'~', 0..=50)
    ) {
        let mut term = crate::TerminalCore::new(24, 80);
        let title_str = String::from_utf8(title).unwrap_or_default();
        let seq = format!("\x1b]2;{title_str}\x07");
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }
}

/// OSC 4 with index 256 (out of range) must be silently ignored:
/// the palette must remain all-None and `palette_dirty` must stay false.
#[test]
fn test_osc4_set_index_out_of_bounds() {
    // Index 256 is out of range (palette has 256 entries, indices 0-255)
    // The handler should silently ignore it
    let mut core = crate::TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"4", b"256", b"rgb:ff/00/00"];
    handle_osc(&mut core, params, false);
    // palette should be unchanged (all None)
    assert!(
        core.osc_data.palette.iter().all(std::option::Option::is_none),
        "palette should be unchanged for out-of-range index 256"
    );
    assert!(
        !core.osc_data.palette_dirty,
        "palette_dirty should remain false for out-of-range index"
    );
}

/// OSC 4 query: `OSC 4 ; 1 ; ? ST` must push a response of the form
/// `\x1b]4;1;rgb:RRRR/GGGG/BBBB\x07` into `meta.pending_responses`.
#[test]
fn test_osc4_query_palette_entry() {
    let mut core = crate::TerminalCore::new(24, 80);

    // First set palette index 1 to red so the query has a known value to return
    let set_params: &[&[u8]] = &[b"4", b"1", b"rgb:ff/00/00"];
    handle_osc(&mut core, set_params, false);
    // Clear responses from any potential set side-effect (there are none, but be explicit)
    core.meta.pending_responses.clear();

    // Now query palette index 1
    let query_params: &[&[u8]] = &[b"4", b"1", b"?"];
    handle_osc(&mut core, query_params, false);

    assert!(
        !core.meta.pending_responses.is_empty(),
        "OSC 4 query must push a response into meta.pending_responses"
    );

    // The response must be OSC 4 ; 1 ; rgb:ffff/0000/0000 BEL
    let response = std::str::from_utf8(&core.meta.pending_responses[0])
        .expect("response must be valid UTF-8");
    assert!(
        response.starts_with("\x1b]4;1;rgb:"),
        "OSC 4 query response must start with ESC]4;1;rgb: — got: {response:?}"
    );
    assert!(
        response.ends_with('\x07'),
        "OSC 4 query response must be BEL-terminated — got: {response:?}"
    );
    // Verify the red channel is ffff (encode_color_spec scales 0xff → 0xffff)
    assert!(
        response.contains("ffff"),
        "OSC 4 query response for red must contain 'ffff' — got: {response:?}"
    );
}
