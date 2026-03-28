// ── New tests: OSC 7, OSC 8, SM/RM, SS2/SS3, DECSCUSR, DCS data ──────────

// OSC 7 with a valid `file://` URL must update `osc_data.cwd` and set `cwd_dirty`.
#[test]
fn test_osc_dispatch_osc7_sets_cwd() {
    let term = term_with!(b"\x1b]7;file://localhost/home/user/project\x07");
    assert_eq!(
        term.osc_data.cwd.as_deref(),
        Some("/home/user/project"),
        "OSC 7 must extract and store the path from a file:// URL"
    );
    assert!(
        term.osc_data.cwd_dirty,
        "cwd_dirty must be set after a valid OSC 7"
    );
}

// OSC 8 with a non-empty URI must open a hyperlink (store the URI).
#[test]
fn test_osc_dispatch_osc8_open_hyperlink() {
    let term = term_with!(b"\x1b]8;;https://example.com\x07");
    assert_eq!(
        term.osc_data.hyperlink.uri.as_deref(),
        Some("https://example.com"),
        "OSC 8 with non-empty URI must set the active hyperlink"
    );
}

// OSC 8 with an empty URI must close the active hyperlink.
#[test]
fn test_osc_dispatch_osc8_close_hyperlink() {
    let mut term = term_with!(b"\x1b]8;;https://example.com\x07");
    assert!(
        term.osc_data.hyperlink.uri.is_some(),
        "hyperlink must be open before the close sequence"
    );
    term.advance(b"\x1b]8;;\x07"); // empty URI closes hyperlink
    assert!(
        term.osc_data.hyperlink.uri.is_none(),
        "OSC 8 with empty URI must clear the active hyperlink"
    );
}

// SM 4 (CSI 4 h — IRM insert mode) without the `?` intermediate falls to
// the unknown handler and must be silently ignored.
#[test]
fn test_csi_sm4_irm_noop() {
    let term = term_with!(b"\x1b[4h");
    assert!(
        term.meta.pending_responses.is_empty(),
        "SM 4 (IRM, no ? prefix) must not queue a response"
    );
}

// RM 4 (CSI 4 l — reset IRM) is likewise unimplemented and must be silently ignored.
#[test]
fn test_csi_rm4_irm_noop() {
    let term = term_with!(b"\x1b[4l");
    assert!(
        term.meta.pending_responses.is_empty(),
        "RM 4 (no ? prefix) must not queue a response"
    );
}

// SS2 (ESC N) — Single Shift 2 — is not implemented.
// Must be silently ignored without panicking or queueing a response.
#[test]
fn test_esc_ss2_no_panic_no_response() {
    let term = term_with!(b"\x1bN");
    assert!(
        term.meta.pending_responses.is_empty(),
        "SS2 (ESC N) must not queue any response"
    );
    // Terminal must still be usable after an unknown ESC sequence.
    let term2 = {
        let mut t = crate::TerminalCore::new(24, 80);
        t.advance(b"\x1bN");
        t.advance(b"X");
        t
    };
    assert!(
        term2.screen.cursor().col > 0,
        "printing must work normally after SS2"
    );
}

// SS3 (ESC O) — Single Shift 3 — is not implemented.
// Must be silently ignored without panicking or queueing a response.
#[test]
fn test_esc_ss3_no_panic_no_response() {
    let term = term_with!(b"\x1bO");
    assert!(
        term.meta.pending_responses.is_empty(),
        "SS3 (ESC O) must not queue any response"
    );
}

// DECSCUSR style 2 (CSI 2 SP q) must set the cursor shape to SteadyBlock.
#[test]
fn test_csi_decscusr_style2_steady_block() {
    use crate::types::cursor::CursorShape;
    let term = term_with!(b"\x1b[2 q"); // DECSCUSR Ps=2
    assert_eq!(
        term.dec_modes.cursor_shape,
        CursorShape::SteadyBlock,
        "DECSCUSR 2 must set cursor shape to SteadyBlock"
    );
}

// An unknown ESC sequence (e.g. ESC Z — unassigned) must be silently ignored:
// no response, no panic, and the terminal must remain usable.
#[test]
fn test_esc_unknown_sequence_is_noop() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1bZ"); // ESC Z — not a known sequence in kuro
    assert!(
        term.meta.pending_responses.is_empty(),
        "unknown ESC sequence must not produce a response"
    );
    term.advance(b"A"); // terminal must still accept input
    assert!(
        term.screen.cursor().col > 0,
        "terminal must remain usable after unknown ESC"
    );
}

// DCS passthrough with actual data bytes via `hook`/`put`/`unhook`.
// Sending a DCS string with multiple data bytes must not panic and must
// leave the terminal in a usable state.
#[test]
fn test_hook_put_unhook_with_data_bytes_no_panic() {
    let mut term = crate::TerminalCore::new(24, 80);
    // DCS with several data bytes (not a recognised DCS command)
    term.advance(b"\x1bPabcde\x1b\\");
    // Terminal must accept further input without error.
    term.advance(b"OK");
    assert_cell_char!(term, row 0, col 0, 'O');
    assert_cell_char!(term, row 0, col 1, 'K');
}

// DECSCUSR style 1 (CSI 1 SP q) must set the cursor shape to BlinkingBlock.
#[test]
fn test_csi_decscusr_style1_blinking_block() {
    use crate::types::cursor::CursorShape;
    // First set to SteadyBlock, then reset to BlinkingBlock via Ps=1.
    let mut term = term_with!(b"\x1b[2 q"); // SteadyBlock
    assert_eq!(term.dec_modes.cursor_shape, CursorShape::SteadyBlock);
    term.advance(b"\x1b[1 q"); // BlinkingBlock
    assert_eq!(
        term.dec_modes.cursor_shape,
        CursorShape::BlinkingBlock,
        "DECSCUSR 1 must set cursor shape to BlinkingBlock"
    );
}

// SGR bold via `assert_sgr_flag!` macro form (redundant but confirms macro expansion).
#[test]
fn test_vte_sgr_bold_via_macro() {
    assert_sgr_flag!(b"\x1b[1m", SgrFlags::BOLD, "SGR 1 must set BOLD flag");
}

// OSC 0 with empty title must be silently ignored (title unchanged).
#[test]
fn test_osc_dispatch_osc0_empty_title_ignored() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.meta.title = "previous".to_string();
    term.advance(b"\x1b]0;\x07"); // empty title
    assert_eq!(
        term.meta.title, "previous",
        "OSC 0 with empty title must leave the title unchanged"
    );
    assert!(
        !term.meta.title_dirty,
        "title_dirty must not be set for an empty title"
    );
}

// OSC 7 with a non-`file://` URL must be silently ignored.
#[test]
fn test_osc_dispatch_osc7_non_file_url_ignored() {
    let term = term_with!(b"\x1b]7;https://example.com\x07");
    assert!(
        term.osc_data.cwd.is_none(),
        "OSC 7 with non-file:// URL must not set CWD"
    );
    assert!(
        !term.osc_data.cwd_dirty,
        "cwd_dirty must not be set when OSC 7 URL is rejected"
    );
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: print() with any printable Unicode character never panics
    fn prop_print_any_char_no_panic(c in proptest::char::range('\u{0020}', '\u{FFFE}')) {
        let mut term = crate::TerminalCore::new(24, 80);
        let mut buf = [0u8; 4];
        let s = c.encode_utf8(&mut buf);
        term.advance(s.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }

    #[test]
    // PANIC SAFETY: C0 control codes (0x00–0x1F) as execute() never panic
    fn prop_execute_c0_no_panic(byte in 0x00u8..=0x1Fu8) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(&[byte]);
        prop_assert!(term.screen.cursor().row < 24);
    }
}
