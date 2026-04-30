// ---------------------------------------------------------------------------
// DEC mode accessor smoke tests
// ---------------------------------------------------------------------------

/// All DEC mode accessors return their expected defaults on a fresh session.
#[test]
fn test_dec_mode_accessors_initial_defaults() {
    let session = make_session();

    assert!(!session.get_mouse_pixel(), "mouse_pixel defaults to false");
    assert_eq!(session.get_mouse_mode(), 0, "mouse_mode defaults to 0");
    assert!(!session.get_mouse_sgr(), "mouse_sgr defaults to false");
    assert!(
        !session.get_app_cursor_keys(),
        "app_cursor_keys defaults to false"
    );
    assert!(!session.get_app_keypad(), "app_keypad defaults to false");
    assert_eq!(
        session.get_keyboard_flags(),
        0,
        "keyboard_flags defaults to 0"
    );
    assert!(
        !session.get_bracketed_paste(),
        "bracketed_paste defaults to false"
    );
    assert!(
        !session.get_focus_events(),
        "focus_events defaults to false"
    );
    assert!(
        !session.get_synchronized_output(),
        "synchronized_output defaults to false"
    );
}

/// `get_cursor_shape` starts at `BlinkingBlock`.
#[test]
fn test_get_cursor_shape_default() {
    use crate::types::cursor::CursorShape;
    let session = make_session();
    assert_eq!(
        session.get_cursor_shape(),
        CursorShape::BlinkingBlock,
        "cursor_shape must default to BlinkingBlock"
    );
}

/// `get_app_cursor_keys` returns `true` after `CSI ?1h` (DECCKM set).
#[test]
fn test_get_app_cursor_keys_set_by_decckm() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1h"); // DECCKM on
    assert!(
        session.get_app_cursor_keys(),
        "get_app_cursor_keys must return true after CSI ?1h"
    );
    session.core.advance(b"\x1b[?1l"); // DECCKM off
    assert!(
        !session.get_app_cursor_keys(),
        "get_app_cursor_keys must return false after CSI ?1l"
    );
}

/// `get_bracketed_paste` returns `true` after `CSI ?2004h`.
#[test]
fn test_get_bracketed_paste_set_by_mode() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?2004h");
    assert!(
        session.get_bracketed_paste(),
        "get_bracketed_paste must return true after CSI ?2004h"
    );
}

/// `get_focus_events` returns `true` after `CSI ?1004h`.
#[test]
fn test_get_focus_events_set_by_mode() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1004h");
    assert!(
        session.get_focus_events(),
        "get_focus_events must return true after CSI ?1004h"
    );
}

/// `get_keyboard_flags` reflects the kitty keyboard flags pushed by `CSI > Ps u`.
#[test]
fn test_get_keyboard_flags_after_push() {
    let mut session = make_session();
    session.core.advance(b"\x1b[>5u"); // push flags=5
    assert_eq!(
        session.get_keyboard_flags(),
        5,
        "get_keyboard_flags must return 5 after CSI >5u"
    );
}

// ---------------------------------------------------------------------------
// take_prompt_marks: drain-once semantics
// ---------------------------------------------------------------------------

/// `take_prompt_marks` returns empty on a fresh session.
#[test]
fn test_take_prompt_marks_empty_initially() {
    let mut session = make_session();
    assert!(
        session.take_prompt_marks().is_empty(),
        "take_prompt_marks must return empty vec on a fresh session"
    );
}

/// `take_prompt_marks` returns an event after OSC 133 and drains the queue.
#[test]
fn test_take_prompt_marks_drains_after_osc133() {
    let mut session = make_session();
    session.core.advance(b"\x1b]133;A\x1b\\");
    assert_drain_once!(session, take_prompt_marks, vec);
}

// ---------------------------------------------------------------------------
// FR-124: 7-tuple FFI shape — field-level coverage of the contract that
// `kuro_core_poll_prompt_marks` (rust-core/src/ffi/bridge/events.rs) consumes.
//
// The FFI bridge requires Emacs `Env` and cannot be unit-tested in this crate
// without a real Emacs runtime, so these tests pin the producer-side invariants
// that the bridge depends on:
//   - aid="" round-trips as Some("") (empty string, NOT None)
//   - all-None extras stay None (rendered as 3 tail nils)
//   - all-Some extras stay Some (rendered as 3 non-nil tail values)
//   - duration_ms accepts the full u64 range; the bridge tolerates u64→i64
//     via the cast_possible_wrap expect attribute on the defun
//   - Pre-FR-124 callers reading only mark/row/col/exit-code see no breakage
//     because the new fields land strictly in the cons-cell tail.
// ---------------------------------------------------------------------------

/// T1a — explicit `aid=""` round-trips as `Some(String::new())`, NOT None.
/// FFI bridge encodes this as the empty Emacs string (not nil) so the consumer
/// can distinguish "absent" from "explicitly empty".
#[test]
fn test_take_prompt_marks_aid_empty_string_preserved() {
    let mut session = make_session();
    session.core.advance(b"\x1b]133;D;0;aid=\x1b\\");
    let marks = session.take_prompt_marks();
    assert_eq!(marks.len(), 1, "expected exactly one drained mark");
    assert_eq!(
        marks[0].aid.as_deref(),
        Some(""),
        "aid=\"\" must survive as Some(empty), never collapse to None"
    );
}

/// T1b — all extras absent: aid/duration_ms/err_path are all None so the
/// bridge tail of `(... aid duration-ms err-path)` is `(nil nil nil)`.
#[test]
fn test_take_prompt_marks_no_extras_all_none() {
    let mut session = make_session();
    session.core.advance(b"\x1b]133;D;0\x1b\\");
    let marks = session.take_prompt_marks();
    assert_eq!(marks.len(), 1);
    let ev = &marks[0];
    assert!(ev.aid.is_none(), "aid must be None when no aid= kv is sent");
    assert!(
        ev.duration_ms.is_none(),
        "duration_ms must be None when no duration= kv is sent"
    );
    assert!(
        ev.err_path.is_none(),
        "err_path must be None when no err= kv is sent"
    );
}

/// T1c — all extras present: aid/duration_ms/err_path are all Some so the
/// bridge tail emits three non-nil Lisp values.
#[test]
fn test_take_prompt_marks_all_extras_some() {
    let mut session = make_session();
    session.core.advance(
        b"\x1b]133;D;0;aid=app1;duration=1234;err=/var/log/x.log\x1b\\",
    );
    let marks = session.take_prompt_marks();
    assert_eq!(marks.len(), 1);
    let ev = &marks[0];
    assert_eq!(ev.aid.as_deref(), Some("app1"));
    assert_eq!(ev.duration_ms, Some(1234));
    assert_eq!(ev.err_path.as_deref(), Some("/var/log/x.log"));
    assert_eq!(ev.exit_code, Some(0));
}

/// T1d — `duration_ms = u64::MAX` is REJECTED by the parser (Security W3).
/// The cap is `MAX_PROMPT_DURATION_MS = 365 * 24 * 3600 * 1000` (one year in ms);
/// any value above is dropped to `None` rather than passed through. This protects
/// the FFI bridge consumer from misleadingly huge durations supplied by an
/// adversarial or buggy shell.
#[test]
fn test_take_prompt_marks_duration_u64_max_rejected() {
    let mut session = make_session();
    let payload = b"\x1b]133;D;0;duration=18446744073709551615\x1b\\";
    session.core.advance(payload);
    let marks = session.take_prompt_marks();
    assert_eq!(marks.len(), 1);
    assert_eq!(
        marks[0].duration_ms, None,
        "u64::MAX exceeds MAX_PROMPT_DURATION_MS (1 year); parser must drop to None"
    );
}

/// T1d-cap — `duration_ms` exactly at `MAX_PROMPT_DURATION_MS` is accepted
/// (boundary).
#[test]
fn test_take_prompt_marks_duration_at_cap_accepted() {
    let mut session = make_session();
    const MAX_MS: u64 = 365 * 24 * 3600 * 1000;
    let payload = format!("\x1b]133;D;0;duration={MAX_MS}\x1b\\");
    session.core.advance(payload.as_bytes());
    let marks = session.take_prompt_marks();
    assert_eq!(marks.len(), 1);
    assert_eq!(
        marks[0].duration_ms,
        Some(MAX_MS),
        "duration_ms exactly at cap must round-trip"
    );
}

/// T1d-over — `duration_ms` one above the cap is rejected (boundary).
#[test]
fn test_take_prompt_marks_duration_above_cap_rejected() {
    let mut session = make_session();
    const OVER_CAP: u64 = 365 * 24 * 3600 * 1000 + 1;
    let payload = format!("\x1b]133;D;0;duration={OVER_CAP}\x1b\\");
    session.core.advance(payload.as_bytes());
    let marks = session.take_prompt_marks();
    assert_eq!(marks.len(), 1);
    assert_eq!(
        marks[0].duration_ms, None,
        "duration_ms one above MAX_PROMPT_DURATION_MS must drop to None"
    );
}

/// T1e — legacy consumers that only read the first 4 fields (mark, row, col,
/// exit-code) keep working when the FFI tail grows by 3 fields.
///
/// This test simulates such a consumer entirely on the Rust side: it reads the
/// 4 "classic" fields off `PromptMarkEvent` and must not need to touch the new
/// fields, proving the extension is strictly additive.
#[test]
fn test_take_prompt_marks_legacy_4field_consumer_unaffected() {
    let mut session = make_session();
    session.core.advance(
        b"\x1b]133;D;42;aid=app1;duration=999;err=/tmp/e\x1b\\",
    );
    let marks = session.take_prompt_marks();
    assert_eq!(marks.len(), 1);

    // A "legacy" consumer destructures only the first 4 logical fields.
    // It must succeed without referencing aid/duration_ms/err_path.
    let ev = &marks[0];
    let legacy_view: (
        crate::types::osc::PromptMark,
        usize,
        usize,
        Option<i32>,
    ) = (ev.mark.clone(), ev.row, ev.col, ev.exit_code);

    assert!(matches!(legacy_view.0, crate::types::osc::PromptMark::CommandEnd));
    assert_eq!(legacy_view.1, 0, "row must reflect cursor at OSC 133 D time");
    assert_eq!(legacy_view.2, 0, "col must reflect cursor at OSC 133 D time");
    assert_eq!(legacy_view.3, Some(42), "exit-code positional param survives");
}

// ---------------------------------------------------------------------------
// FR-124 PBT: random aid/duration/err_path triples round-trip through the
// parser into the drained Vec exactly. Mirrors the property that the FFI
// bridge's per-field encoding preserves field identity.
// ---------------------------------------------------------------------------

mod fr_124_pbt {
    use super::make_session;
    use proptest::prelude::*;

    /// Format an OSC 133 D escape sequence with the given optional extras.
    /// All extras use ST (`ESC \`) terminator.
    fn build_osc133_d(
        exit_code: i32,
        aid: Option<&str>,
        duration: Option<u64>,
        err: Option<&str>,
    ) -> Vec<u8> {
        let mut out = Vec::with_capacity(64);
        out.extend_from_slice(b"\x1b]133;D;");
        out.extend_from_slice(exit_code.to_string().as_bytes());
        if let Some(a) = aid {
            out.extend_from_slice(b";aid=");
            out.extend_from_slice(a.as_bytes());
        }
        if let Some(d) = duration {
            out.extend_from_slice(b";duration=");
            out.extend_from_slice(d.to_string().as_bytes());
        }
        if let Some(e) = err {
            out.extend_from_slice(b";err=");
            out.extend_from_slice(e.as_bytes());
        }
        out.extend_from_slice(b"\x1b\\");
        out
    }

    // Restrict err_path to printable ASCII without OSC delimiters (`;`, `\x1b`,
    // controls). The parser drops values containing C0/DEL bytes (see
    // `parser/osc_protocol.rs::has_control_bytes`); the property here
    // asserts round-trip on inputs the parser is contractually required
    // to preserve.
    fn safe_err_str(max_len: usize) -> impl Strategy<Value = String> {
        prop::collection::vec(
            prop_oneof![
                32u8..=58u8,    // ' ' .. ':'  (excludes ';' = 0x3B)
                60u8..=126u8,   // '<' .. '~'  (excludes DEL)
            ],
            0..=max_len,
        )
        .prop_map(|v| String::from_utf8(v).expect("ASCII subset is always valid UTF-8"))
    }

    /// Strict printable-ASCII generator for `aid=` values (`[!-~]+`, no `;` or `=`).
    /// Mirrors the `is_printable_aid` parser-side predicate (Security W1):
    /// `aid=` rejects space, C0/DEL, and OSC delimiter bytes. Empty strings are
    /// produced separately (the parser preserves empty `aid=` as `Some("")`).
    fn safe_aid_str(max_len: usize) -> impl Strategy<Value = String> {
        prop::collection::vec(
            prop_oneof![
                33u8..=58u8,    // '!' .. ':'  (excludes ';' = 0x3B and ' ' = 0x20)
                60u8..=60u8,    // '<'         (excludes '=' = 0x3D)
                62u8..=126u8,   // '>' .. '~'  (excludes DEL)
            ],
            0..=max_len,
        )
        .prop_map(|v| String::from_utf8(v).expect("ASCII subset is always valid UTF-8"))
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(64))]

        #[test]
        // INVARIANT: parser→take_prompt_marks preserves every extra field
        // identically. This is the producer-side half of the FFI roundtrip
        // (`kuro_core_poll_prompt_marks` then maps each Some/None directly to
        // a Lisp string-or-nil / int-or-nil with no further mutation).
        //
        // `aid` uses the strict printable-ASCII generator (`is_printable_aid`).
        // `duration` is capped at `MAX_PROMPT_DURATION_MS` (1 year in ms,
        // Security W3); larger values are dropped to None by the parser.
        fn prop_osc133_d_extras_roundtrip_through_parser(
            exit_code in -128i32..=127i32,
            aid_opt in proptest::option::of(safe_aid_str(64)),
            duration_opt in proptest::option::of(0u64..=(365_u64 * 24 * 3600 * 1000)),
            err_opt in proptest::option::of(safe_err_str(64)),
        ) {
            let payload = build_osc133_d(
                exit_code,
                aid_opt.as_deref(),
                duration_opt,
                err_opt.as_deref(),
            );

            let mut session = make_session();
            session.core.advance(&payload);
            let marks = session.take_prompt_marks();
            prop_assert_eq!(marks.len(), 1);

            let ev = &marks[0];
            prop_assert!(matches!(ev.mark, crate::types::osc::PromptMark::CommandEnd));
            prop_assert_eq!(ev.exit_code, Some(exit_code));
            prop_assert_eq!(ev.aid.clone(), aid_opt);
            prop_assert_eq!(ev.duration_ms, duration_opt);
            prop_assert_eq!(ev.err_path.clone(), err_opt);
        }
    }
}

// ---------------------------------------------------------------------------
// get_image_png_base64 / take_pending_image_notifications
// ---------------------------------------------------------------------------

/// `get_image_png_base64` returns empty string for unknown image IDs.
#[test]
fn test_get_image_png_base64_unknown_id_returns_empty() {
    let session = make_session();
    let result = session.get_image_png_base64(999_999);
    assert!(
        result.is_empty(),
        "get_image_png_base64 must return empty string for unknown image ID"
    );
}

/// `take_pending_image_notifications` returns empty vec on a fresh session.
#[test]
fn test_take_pending_image_notifications_empty_initially() {
    let mut session = make_session();
    let notifs = session.take_pending_image_notifications();
    assert!(
        notifs.is_empty(),
        "take_pending_image_notifications must return empty vec on a fresh session"
    );
}

// ---------------------------------------------------------------------------
// has_pending_output: non-unix stub
// ---------------------------------------------------------------------------

/// `has_pending_output` returns `false` on test sessions with no PTY.
#[test]
fn test_has_pending_output_false_without_pty() {
    let session = make_session();
    // On Unix, pty is None so has_pending_output checks pending_input + pty.
    // Both are empty/None → must return false.
    assert!(
        !session.has_pending_output(),
        "has_pending_output must return false for a test session with no PTY"
    );
}

// ---------------------------------------------------------------------------
// get_cursor / get_cursor_visible
// ---------------------------------------------------------------------------

/// `get_cursor` starts at (0, 0) on a fresh session.
#[test]
fn test_get_cursor_initial_position() {
    let session = make_session();
    assert_eq!(
        session.get_cursor(),
        (0, 0),
        "cursor must start at (row=0, col=0) on a fresh session"
    );
}

/// After writing 3 chars, `get_cursor` column advances to 3.
#[test]
fn test_get_cursor_advances_after_write() {
    let mut session = make_session();
    session.core.advance(b"ABC");
    let (row, col) = session.get_cursor();
    assert_eq!(row, 0, "cursor row must remain 0 after writing to line 0");
    assert_eq!(col, 3, "cursor col must be 3 after writing 3 ASCII chars");
}

/// `get_cursor` reflects `CUP` (CSI H) escape sequences correctly.
#[test]
fn test_get_cursor_reflects_cup_escape() {
    let mut session = make_session();
    session.core.advance(b"\x1b[5;10H"); // move to row 5, col 10 (1-based)
    let (row, col) = session.get_cursor();
    assert_eq!(row, 4, "CUP row 5 must map to 0-based row 4");
    assert_eq!(col, 9, "CUP col 10 must map to 0-based col 9");
}

/// `get_cursor_visible` is true by default (DECTCEM default = on).
#[test]
fn test_get_cursor_visible_default_true() {
    let session = make_session();
    assert!(
        session.get_cursor_visible(),
        "cursor must be visible by default (DECTCEM on)"
    );
}

/// `get_cursor_visible` returns `false` after `CSI ?25l`.
#[test]
fn test_get_cursor_visible_hidden_by_escape() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?25l"); // DECTCEM off
    assert!(
        !session.get_cursor_visible(),
        "get_cursor_visible must return false after CSI ?25l"
    );
    session.core.advance(b"\x1b[?25h"); // DECTCEM on
    assert!(
        session.get_cursor_visible(),
        "get_cursor_visible must return true after CSI ?25h"
    );
}

// ---------------------------------------------------------------------------
// resize: row-hash invalidation
// ---------------------------------------------------------------------------

/// After `resize`, `row_hashes` must be empty (cache invalidated).
#[test]
fn test_resize_clears_row_hashes() {
    let mut session = make_session();
    // Write content so row-hash cache gets populated via get_dirty_lines_with_faces.
    session.core.advance(b"Hello");
    let _ = session.get_dirty_lines_with_faces();
    // Cache may have entries now; resize must clear them.
    session
        .resize(30, 100)
        .expect("resize must not fail on test session");
    assert!(
        session.row_hashes.iter().all(|slot| slot.is_none()),
        "resize must invalidate all row_hashes cache entries"
    );
}

/// After `resize`, terminal dimensions reflect the new values.
#[test]
fn test_resize_updates_terminal_dimensions() {
    let mut session = make_session();
    session.resize(30, 120).expect("resize must not fail");
    assert_eq!(
        session.core.screen.rows(),
        30,
        "rows must be 30 after resize(30, 120)"
    );
    assert_eq!(
        session.core.screen.cols(),
        120,
        "cols must be 120 after resize(30, 120)"
    );
}

// ---------------------------------------------------------------------------
// get_app_keypad / get_mouse_sgr / get_mouse_pixel
// ---------------------------------------------------------------------------

/// `get_app_keypad` returns `true` after `CSI ?1h` (DECKPAM on = DECCKM also).
/// Use `ESC =` (application keypad) to set app_keypad mode directly.
#[test]
fn test_get_app_keypad_set_by_escape() {
    let mut session = make_session();
    session.core.advance(b"\x1b="); // DECKPAM (application keypad on)
    assert!(
        session.get_app_keypad(),
        "get_app_keypad must return true after ESC ="
    );
    session.core.advance(b"\x1b>"); // DECKPNM (numeric keypad)
    assert!(
        !session.get_app_keypad(),
        "get_app_keypad must return false after ESC >"
    );
}

/// `get_mouse_sgr` returns `true` after `CSI ?1006h` (SGR mouse encoding).
#[test]
fn test_get_mouse_sgr_set_by_mode() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1006h");
    assert!(
        session.get_mouse_sgr(),
        "get_mouse_sgr must return true after CSI ?1006h"
    );
    session.core.advance(b"\x1b[?1006l");
    assert!(
        !session.get_mouse_sgr(),
        "get_mouse_sgr must return false after CSI ?1006l"
    );
}

/// `get_mouse_mode` reflects mouse tracking mode set by `CSI ?1000h`.
#[test]
fn test_get_mouse_mode_set_by_mode_1000() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1000h"); // X10 mouse tracking
    assert_eq!(
        session.get_mouse_mode(),
        1000,
        "get_mouse_mode must return 1000 after CSI ?1000h"
    );
    session.core.advance(b"\x1b[?1000l");
    assert_eq!(
        session.get_mouse_mode(),
        0,
        "get_mouse_mode must return 0 after CSI ?1000l"
    );
}

// ---------------------------------------------------------------------------
// assert_rows_dirty! macro smoke test
// ---------------------------------------------------------------------------

/// `get_dirty_lines` returns row 0 dirty after writing to row 0.
#[test]
fn test_assert_rows_dirty_macro_row_zero() {
    let mut session = make_session();
    // Drain any initial full_dirty state.
    session.core.screen.take_dirty_lines();
    assert_rows_dirty!(session, advance b"Hello", rows [0]);
}

/// Writing to a specific row via CUP marks only that row dirty.
#[test]
fn test_assert_rows_dirty_macro_specific_row() {
    let mut session = make_session();
    // Drain full_dirty from session construction.
    session.core.screen.take_dirty_lines();
    // Move to row 3 (0-based), col 0, then write.
    assert_rows_dirty!(session, advance b"\x1b[4;1HContent", rows [3]);
}
