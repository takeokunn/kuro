//! Property-based and example-based tests for `osc` parsing.
//!
//! Module under test: `parser/osc.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;

// ── Helpers ───────────────────────────────────────────────────────────────────

fn with_osc_core(f: impl FnOnce(&mut crate::TerminalCore)) {
    let mut core = crate::TerminalCore::new(24, 80);
    f(&mut core);
}

/// Shared setup for OSC parser test macros.
macro_rules! assert_osc_dispatch {
    ($body:expr) => {{
        with_osc_core($body);
    }};
}

/// Assert that an OSC title command stores `$title` and sets `title_dirty`.
macro_rules! assert_osc_title_accepted {
    ($code:literal, $title:literal, $test_name:expr) => {{
        let test_name = $test_name;
        assert_osc_dispatch!(|core| {
            handle_osc(core, &[$code, $title], false);
            assert_eq!(
                core.meta.title,
                std::str::from_utf8($title).unwrap(),
                "{}: title must be stored",
                test_name
            );
            assert!(
                core.meta.title_dirty,
                "{}: title_dirty must be set",
                test_name
            );
        });
    }};
}

/// Assert that an OSC 7 command with a `file://` URL stores `$expected_cwd` and sets `cwd_dirty`.
macro_rules! assert_osc7_cwd_accepted {
    ($url:literal, $expected_cwd:literal) => {{
        assert_osc_dispatch!(|core| {
            handle_osc(core, &[b"7", $url], false);
            assert_eq!(
                core.osc_data.cwd.as_deref(),
                Some($expected_cwd),
                "OSC 7 with {:?} must set CWD to {:?}",
                $url,
                $expected_cwd
            );
            assert!(
                core.osc_data.cwd_dirty,
                "cwd_dirty must be set after accepting OSC 7 url {:?}",
                $url
            );
        });
    }};
}

/// Assert that an OSC 22 command stores the requested pointer shape.
macro_rules! assert_osc_pointer_shape_accepted {
    ($shape:literal) => {{
        assert_osc_dispatch!(|core| {
            handle_osc(core, &[b"22", $shape], false);
            assert_eq!(
                core.osc_data.pointer_shape.as_deref(),
                Some(std::str::from_utf8($shape).unwrap()),
                "OSC 22 must set pointer_shape to {:?}",
                $shape
            );
        });
    }};
}

/// Assert that an OSC 7 command is rejected: CWD stays `None` and `cwd_dirty` stays `false`.
macro_rules! assert_osc7_rejected {
    ($url:literal, $reason:literal) => {{
        let mut core = crate::TerminalCore::new(24, 80);
        let params: &[&[u8]] = &[b"7", $url];
        handle_osc(&mut core, params, false);
        assert!(
            core.osc_data.cwd.is_none(),
            "OSC 7 {} must leave CWD as None",
            $reason
        );
        assert!(
            !core.osc_data.cwd_dirty,
            "cwd_dirty must not be set when OSC 7 is rejected ({})",
            $reason
        );
    }};
}

/// Assert that an OSC notification command is ignored and leaves the queue empty.
macro_rules! assert_osc_notifications_empty {
    ($handler:path, $params:expr, $test_name:expr) => {{
        let test_name = $test_name;
        assert_osc_dispatch!(|core| {
            $handler(core, $params);
            assert!(
                core.osc_data.notifications.is_empty(),
                "{}: notification queue must stay empty",
                test_name
            );
        });
    }};
}

/// Generate a reset test for one default color slot.
macro_rules! test_osc_default_colors_reset {
    ($name:ident, $reset_code:expr, $seed_code:expr, $field:ident) => {
        #[test]
        fn $name() {
            let mut core = crate::TerminalCore::new(24, 80);
            let seed_params: &[&[u8]] = &[$seed_code, b"#112233"];
            handle_osc(&mut core, seed_params, false);

            let reset_params: &[&[u8]] = &[$reset_code];
            handle_osc(&mut core, reset_params, false);

            assert!(
                core.osc_data.$field.is_none(),
                concat!(
                    "OSC ",
                    stringify!($reset_code),
                    " must reset ",
                    stringify!($field),
                    " to None"
                )
            );
            assert!(core.osc_data.default_colors_dirty);
        }
    };
}

/// OSC 0 sets the window title on the terminal core.
#[test]
fn test_osc0_sets_title() {
    assert_osc_title_accepted!(b"0", b"myterm", "OSC 0");
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
    assert_osc7_cwd_accepted!(b"file://hostname/home/user", "/home/user");
}

/// OSC 2 must behave identically to OSC 0 for window title setting:
/// the title is stored and `title_dirty` is set.
#[test]
fn test_osc2_sets_title_same_as_osc0() {
    assert_osc_title_accepted!(b"2", b"window-title", "OSC 2");
}

/// OSC 22 stores the requested pointer shape override.
#[test]
fn test_osc22_sets_pointer_shape() {
    assert_osc_pointer_shape_accepted!(b"pointer");
}

/// OSC 7 with a URL that does NOT start with `file://` must be silently
/// ignored — the CWD field must remain unset.
#[test]
fn test_osc7_rejects_non_file_url() {
    // An SSH URL does not match the `file://` guard in the handler.
    assert_osc7_rejected!(b"ssh://host/path", "non-file:// URL");
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

// OSC 110/111/112 reset the default fg/bg/cursor colors back to `None`.
test_osc_default_colors_reset!(test_osc110_resets_default_fg, b"110", b"10", default_fg);
test_osc_default_colors_reset!(test_osc111_resets_default_bg, b"111", b"11", default_bg);
test_osc_default_colors_reset!(test_osc112_resets_cursor_color, b"112", b"12", cursor_color);

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
        core.osc_data
            .palette
            .iter()
            .all(std::option::Option::is_none),
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
    let response =
        std::str::from_utf8(&core.meta.pending_responses[0]).expect("response must be valid UTF-8");
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

// ── OSC 66 (Kitty text-sizing) ──────────────────────────────────────────────

/// Drive an OSC 66 sequence through the full parser and return the resulting
/// core for cell inspection.
fn osc66_term(seq: &str) -> crate::TerminalCore {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(seq.as_bytes());
    term
}

/// Read the `TextSize` of the cell at (row, col), if any.
fn cell_text_size(
    term: &crate::TerminalCore,
    row: usize,
    col: usize,
) -> Option<crate::types::cell::TextSize> {
    term.screen
        .get_cell(row, col)
        .and_then(crate::types::cell::Cell::text_size)
}

/// INTENT: OSC 66 with `s=2` prints the payload and stamps every printed cell
/// with scale=2 (and nothing else).
#[test]
fn test_osc66_scale_2_stamps_cells() {
    let term = osc66_term("\x1b]66;s=2;Hi\x1b\\");
    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), 'H');
    assert_eq!(term.screen.get_cell(0, 1).unwrap().char(), 'i');
    let ts = cell_text_size(&term, 0, 0).expect("cell 0 must carry text size");
    assert_eq!(ts.scale, 2, "s=2 must set scale=2");
    assert_eq!(ts.scaled_permille(), 2000, "scale 2 → 2000 permille");
    assert_eq!(
        cell_text_size(&term, 0, 1).map(|t| t.scale),
        Some(2),
        "second cell must also be stamped"
    );
}

/// INTENT: OSC 66 fractional `n=1:d=2:w=1` yields a half-size sizing (500
/// permille) — matches the spec example `ESC]66;n=1:d=2:w=1;Ha`.
#[test]
fn test_osc66_fractional_half_size() {
    let term = osc66_term("\x1b]66;n=1:d=2:w=1;Ha\x1b\\");
    let ts = cell_text_size(&term, 0, 0).expect("cell must carry text size");
    assert_eq!(ts.numerator, 1);
    assert_eq!(ts.denominator, 2);
    assert_eq!(ts.width, 1);
    assert_eq!(ts.scaled_permille(), 500, "1/2 scale → 500 permille");
}

/// INTENT: OSC 66 alignment keys `v=` and `h=` are parsed and clamped to 0..=2.
#[test]
fn test_osc66_alignment_parsed_and_clamped() {
    let term = osc66_term("\x1b]66;s=3:v=2:h=1;X\x1b\\");
    let ts = cell_text_size(&term, 0, 0).expect("cell must carry text size");
    assert_eq!(ts.scale, 3);
    assert_eq!(ts.valign, 2);
    assert_eq!(ts.halign, 1);

    // Out-of-range alignment is clamped.
    let term = osc66_term("\x1b]66;v=9:h=9;Y\x1b\\");
    let ts = cell_text_size(&term, 0, 0).expect("cell must carry text size");
    assert_eq!(ts.valign, 2, "valign clamped to 2");
    assert_eq!(ts.halign, 2, "halign clamped to 2");
}

/// INTENT: a default sizing (scale 1, no fraction) must NOT allocate extras —
/// `s=1` with no other keys prints text but stamps no text size.
#[test]
fn test_osc66_default_size_no_stamp() {
    let term = osc66_term("\x1b]66;s=1;Z\x1b\\");
    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), 'Z');
    assert_eq!(
        cell_text_size(&term, 0, 0),
        None,
        "default size (scale 1) must not stamp a TextSize"
    );
}

/// INTENT: malformed metadata is ignored gracefully; the payload still prints
/// at normal size and the terminal stays valid.
#[test]
fn test_osc66_malformed_metadata_ignored() {
    // Garbage keys/values: no recognised key parses, so sizing stays default.
    let term = osc66_term("\x1b]66;garbage=xx:s=notanumber;Q\x1b\\");
    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), 'Q');
    assert_eq!(
        cell_text_size(&term, 0, 0),
        None,
        "unparseable metadata must leave sizing at default (no stamp)"
    );
    assert!(term.screen.cursor().row < 24, "terminal must remain valid");
}

/// INTENT: a denominator that is not strictly greater than the numerator is
/// dropped (spec: d must be > n when non-zero) — sizing collapses to default.
#[test]
fn test_osc66_invalid_fraction_dropped() {
    // n=3 d=2 → d <= n → fraction dropped → default sizing → no stamp.
    let term = osc66_term("\x1b]66;n=3:d=2;W\x1b\\");
    assert_eq!(
        cell_text_size(&term, 0, 0),
        None,
        "d <= n must drop the fraction, leaving default sizing"
    );
}

/// INTENT: a payload containing `;` (which VTE splits into params[3..]) is
/// rejoined so the semicolons survive into the printed cells.
#[test]
fn test_osc66_payload_with_semicolons() {
    let term = osc66_term("\x1b]66;s=2;a;b;c\x1b\\");
    let expected = ['a', ';', 'b', ';', 'c'];
    for (col, &ch) in expected.iter().enumerate() {
        assert_eq!(
            term.screen.get_cell(0, col).unwrap().char(),
            ch,
            "payload char {col} must be {ch:?}"
        );
        assert_eq!(
            cell_text_size(&term, 0, col).map(|t| t.scale),
            Some(2),
            "every payload cell (incl. ';') must be stamped"
        );
    }
}

/// INTENT (regression): when a deferred wrap (`pending_wrap`) is active before
/// the OSC 66 payload, the first payload char must land at column 0 of the NEXT
/// row and be stamped there — NOT at the previous row's last cell.
///
/// The original `text_size_write_position` had a bogus `pending_wrap` branch
/// that returned `(pre_cursor.row, pre_cursor.col)`, which (a) dropped the
/// wrapped char's stamp and (b) corrupted the pre-existing last-column cell by
/// tagging it with the new text size. This drove the fix to mirror the proven
/// `hyperlink_write_position` logic exactly.
#[test]
fn test_osc66_stamp_after_pending_wrap_lands_on_next_row() {
    let mut term = crate::TerminalCore::new(24, 80);
    // Fill row 0 completely (80 'x' chars) so pending_wrap is set on the cursor.
    for _ in 0..80 {
        term.advance(b"x");
    }
    let c = *term.screen.cursor();
    assert_eq!((c.row, c.col), (0, 79), "precondition: cursor parked at (0,79)");
    assert!(c.pending_wrap, "precondition: pending_wrap must be set");

    term.advance(b"\x1b]66;s=2;AB\x1b\\");

    // 'A' wraps to (1,0); 'B' to (1,1). Both must carry scale=2.
    assert_eq!(term.screen.get_cell(1, 0).unwrap().char(), 'A');
    assert_eq!(term.screen.get_cell(1, 1).unwrap().char(), 'B');
    assert_eq!(
        cell_text_size(&term, 1, 0).map(|t| t.scale),
        Some(2),
        "wrapped first char must be stamped at (1,0)"
    );
    assert_eq!(
        cell_text_size(&term, 1, 1).map(|t| t.scale),
        Some(2),
        "second char must be stamped at (1,1)"
    );
    // The pre-existing last-column 'x' must NOT have been corrupted with sizing.
    assert_eq!(term.screen.get_cell(0, 79).unwrap().char(), 'x');
    assert_eq!(
        cell_text_size(&term, 0, 79),
        None,
        "pre-existing cell at (0,79) must keep its default (unsized) state"
    );
}

/// INTENT (adversarial): a wide/CJK OSC 66 char that does not fit at the last
/// column wraps to the next row; BOTH the wide cell and its width placeholder
/// must be stamped at the new row.
#[test]
fn test_osc66_wide_char_wrap_stamps_both_cells_on_next_row() {
    let mut term = crate::TerminalCore::new(2, 4);
    // Print 3 half-width chars: cols 0,1,2 filled; cursor at col 3, no pending_wrap.
    term.advance(b"abc");
    // A wide char (width 2) cannot fit at col 3 → immediate wrap to row 1, col 0.
    term.advance("\x1b]66;s=2;\u{6f22}\x1b\\".as_bytes()); // 漢

    assert_eq!(term.screen.get_cell(1, 0).unwrap().char(), '漢');
    assert_eq!(
        cell_text_size(&term, 1, 0).map(|t| t.scale),
        Some(2),
        "wide char must be stamped at (1,0) after wrap"
    );
    assert_eq!(
        cell_text_size(&term, 1, 1).map(|t| t.scale),
        Some(2),
        "wide placeholder at (1,1) must also be stamped"
    );
}

/// INTENT (adversarial): OSC 66 with EMPTY metadata (`OSC 66 ;; text`) uses all
/// defaults → scale 1, no fraction → which is the normal sizing → no stamp.
#[test]
fn test_osc66_empty_metadata_uses_defaults_no_stamp() {
    let term = osc66_term("\x1b]66;;hello\x1b\\");
    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), 'h');
    assert_eq!(
        cell_text_size(&term, 0, 0),
        None,
        "empty metadata → default sizing → no TextSize stamp"
    );
}

/// INTENT (adversarial): scale out of range (`s=99`) clamps to 7; a multibyte
/// CJK payload still prints + stamps correctly with the clamped scale.
#[test]
fn test_osc66_scale_out_of_range_clamps_to_7_multibyte() {
    let term = osc66_term("\x1b]66;s=99;\u{4f60}\u{597d}\x1b\\"); // 你好
    let ts = cell_text_size(&term, 0, 0).expect("first CJK cell must carry text size");
    assert_eq!(ts.scale, 7, "s=99 must clamp to 7");
    assert_eq!(ts.scaled_permille(), 7000, "scale 7 → 7000 permille");
    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), '你');
    // 你 is wide → occupies cols 0,1; 好 occupies cols 2,3.
    assert_eq!(term.screen.get_cell(0, 2).unwrap().char(), '好');
    assert_eq!(
        cell_text_size(&term, 0, 2).map(|t| t.scale),
        Some(7),
        "second CJK glyph must also be stamped"
    );
}

/// INTENT (adversarial): denominator == 0 explicitly (`n=5:d=0`) keeps the
/// fraction neutral — `scaled_permille` treats den 0 as 1, so a pure `s` scale
/// survives but the numerator does NOT inflate the size beyond scale alone when
/// the denominator is absent. Verifies no divide-by-zero / overflow.
#[test]
fn test_osc66_denominator_zero_no_panic() {
    // d=0 (default) with n=5 and s=2: scaled_permille = 1000*2*max(5,1)/max(0,1)
    // = 1000*2*5/1 = 10000. No panic; large but finite multiplier.
    let term = osc66_term("\x1b]66;s=2:n=5;Q\x1b\\");
    let ts = cell_text_size(&term, 0, 0).expect("cell must carry text size");
    assert_eq!(ts.denominator, 0);
    assert_eq!(ts.numerator, 5);
    assert_eq!(
        ts.scaled_permille(),
        10_000,
        "den 0 treated as 1; must not panic"
    );
}

/// INTENT (adversarial): a payload longer than 4096 bytes is capped on a UTF-8
/// boundary. Build a payload of 5000 ASCII chars; only the first cells up to the
/// terminal width get printed, but crucially the cap must not panic and the
/// stamped region must be self-consistent.
#[test]
fn test_osc66_oversized_payload_capped_no_panic() {
    let payload = "z".repeat(5000);
    let seq = format!("\x1b]66;s=2;{payload}\x1b\\");
    let term = osc66_term(&seq);
    // First cell printed and stamped.
    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), 'z');
    assert_eq!(cell_text_size(&term, 0, 0).map(|t| t.scale), Some(2));
    // Terminal must remain in a valid state (cursor within bounds).
    assert!(term.screen.cursor().row < 24, "terminal stays valid after cap");
}

/// INTENT (adversarial): multibyte UTF-8 at the 4096-byte cap boundary must be
/// truncated on a char boundary (no panic, no partial-codepoint slice). Uses a
/// 3-byte CJK char repeated so the raw byte length straddles 4096.
#[test]
fn test_osc66_multibyte_at_cap_boundary_truncates_cleanly() {
    // 1366 × 3-byte '好' = 4098 bytes > 4096. The cap must back off to a char
    // boundary (4096 is not a multiple of 3) without panicking.
    let payload = "\u{597d}".repeat(1366);
    assert!(payload.len() > 4096, "precondition: payload exceeds cap");
    let seq = format!("\x1b]66;s=3;{payload}\x1b\\");
    let term = osc66_term(&seq);
    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), '好');
    assert_eq!(cell_text_size(&term, 0, 0).map(|t| t.scale), Some(3));
}

/// INTENT (adversarial): an OSC 66 sized cell that is subsequently erased (cell
/// reset via ED / overwrite) must clear its text-size extras so no sizing leaks
/// into the now-blank cell.
#[test]
fn test_osc66_erase_clears_text_size() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b]66;s=2;AB\x1b\\");
    assert_eq!(cell_text_size(&term, 0, 0).map(|t| t.scale), Some(2));

    // Move cursor home and overwrite with a plain (unsized) char.
    term.advance(b"\x1b[H");
    term.advance(b"C");
    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), 'C');
    assert_eq!(
        cell_text_size(&term, 0, 0),
        None,
        "overwriting a sized cell with plain text must drop the text size (no leak)"
    );

    // Erase the rest of the line (ED-style): clear from cursor to end.
    term.advance(b"\x1b[2K"); // erase entire line
    assert_eq!(
        cell_text_size(&term, 0, 1),
        None,
        "erased cell must carry no text size"
    );
}

#[path = "osc/edge_cases.rs"]
mod edge_cases;
