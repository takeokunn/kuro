#[test]
fn test_alt_screen_saves_and_restores_sgr_attrs() {
    use crate::types::cell::SgrFlags;
    use crate::types::{Color, NamedColor};

    let mut term = crate::TerminalCore::new(5, 10);

    // Set bold and foreground color
    term.current_attrs.flags.insert(SgrFlags::BOLD);
    term.current_attrs.foreground = Color::Named(NamedColor::Red);

    // Enter alternate screen (CSI ? 1049 h)
    term.advance(b"\x1b[?1049h");

    // Verify saved_primary_attrs is Some
    assert!(
        term.saved_primary_attrs.is_some(),
        "saved_primary_attrs should be Some after entering alt screen"
    );

    // Change attrs while in alternate screen
    term.current_attrs.flags.remove(SgrFlags::BOLD);
    term.current_attrs.foreground = Color::Named(NamedColor::Green);

    // Exit alternate screen (CSI ? 1049 l)
    term.advance(b"\x1b[?1049l");

    // Original attrs should be restored
    assert!(
        term.current_attrs.flags.contains(SgrFlags::BOLD),
        "bold should be restored to true after exiting alt screen"
    );
    assert_eq!(
        term.current_attrs.foreground,
        Color::Named(NamedColor::Red),
        "foreground should be restored to Red after exiting alt screen"
    );

    // saved_primary_attrs should be consumed (None after take())
    assert!(
        term.saved_primary_attrs.is_none(),
        "saved_primary_attrs should be None after exiting alt screen (consumed by take())"
    );
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]
    #[test]
    fn prop_dec_modes_set_reset_no_panic(mode in 0u16..=65535u16) {
        let mut modes = DecModes::new();
        modes.set_mode(mode);   // must not panic
        modes.reset_mode(mode); // must not panic
        let _ = modes.get_mode(mode);
    }

    #[test]
    /// For every recognised boolean DEC mode: `get_mode` returns `Some(true)`
    /// immediately after `set_mode` and `Some(false)` after a subsequent
    /// `reset_mode`.  Mouse mode uses equality comparison, so 1000/1002/1003
    /// are also covered correctly.
    fn prop_set_then_get_mode_round_trip(
        mode in proptest::prop_oneof![
            Just(1u16), Just(6), Just(7), Just(25),
            Just(1000), Just(1002), Just(1003), Just(1004),
            Just(1006), Just(1016), Just(1049), Just(2004), Just(2026),
        ]
    ) {
        let mut modes = DecModes::new();
        modes.set_mode(mode);
        let after_set = modes.get_mode(mode);
        prop_assert!(
            after_set == Some(true),
            "get_mode({}) after set_mode must be Some(true), got {:?}",
            mode, after_set
        );
        modes.reset_mode(mode);
        let after_reset = modes.get_mode(mode);
        prop_assert!(
            after_reset == Some(false),
            "get_mode({}) after reset_mode must be Some(false), got {:?}",
            mode, after_reset
        );
    }
}

include!("dec_private_kitty_keyboard.rs");

include!("dec_private_edge.rs");

// ── color_scheme_dark + apply_color_scheme + DSR 996 (FR-125) ────────────────
//
// `color_scheme_dark` lives on `TerminalMeta` (Emacs-owned host state), NOT
// on `DecModes` (PTY-settable state). See `types/meta.rs`.

/// T3a: `TerminalMeta::default()` defaults `color_scheme_dark` to `true`
/// (conservative default — most shell apps assume bright-on-dark).
#[test]
fn test_terminal_meta_default_color_scheme_dark_is_true() {
    let term = crate::TerminalCore::new(24, 80);
    assert!(term.meta.color_scheme_dark);
}

/// T3b: `handle_dsr_color_scheme` with `color_scheme_dark = true` pushes
/// `CSI ? 997 ; 1 n` (Ps=1 = dark).
#[test]
fn test_handle_dsr_color_scheme_dark_pushes_ps1() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.meta.color_scheme_dark = true;
    handle_dsr_color_scheme(&mut term);
    assert_eq!(term.meta.pending_responses.len(), 1);
    assert_eq!(term.meta.pending_responses[0], b"\x1b[?997;1n");
}

/// T3c: `handle_dsr_color_scheme` with `color_scheme_dark = false` pushes
/// `CSI ? 997 ; 2 n` (Ps=2 = light).
#[test]
fn test_handle_dsr_color_scheme_light_pushes_ps2() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.meta.color_scheme_dark = false;
    handle_dsr_color_scheme(&mut term);
    assert_eq!(term.meta.pending_responses.len(), 1);
    assert_eq!(term.meta.pending_responses[0], b"\x1b[?997;2n");
}

/// T3d: `apply_color_scheme(false)` with notifications enabled and previous
/// state dark — returns `true`, pushes exactly one `CSI ? 997 ; 2 n` byte
/// string (light unsolicited notification).
#[test]
fn test_apply_color_scheme_change_with_notifications_pushes_response() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.dec_modes.color_scheme_notifications = true;
    // Default is dark; switch to light.
    let changed = apply_color_scheme(&mut term, false);
    assert!(changed, "switching dark → light must report changed = true");
    assert!(!term.meta.color_scheme_dark);
    assert_eq!(term.meta.pending_responses.len(), 1);
    assert_eq!(term.meta.pending_responses[0], b"\x1b[?997;2n");
}

/// T3e: `apply_color_scheme(true)` while already dark with notifications on —
/// idempotent, returns `false`, pushes zero bytes.
#[test]
fn test_apply_color_scheme_idempotent_no_change_no_response() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.dec_modes.color_scheme_notifications = true;
    // Default already dark — calling with the same value must be a no-op.
    let changed = apply_color_scheme(&mut term, true);
    assert!(!changed, "no-op call must report changed = false");
    assert!(term.meta.color_scheme_dark);
    assert!(
        term.meta.pending_responses.is_empty(),
        "idempotent call must not push any response bytes"
    );
}

/// T3f: `apply_color_scheme(false)` with notifications **disabled** — state
/// updates and `true` is returned, but no notification is pushed (mode 2031
/// gates the proactive emit).
#[test]
fn test_apply_color_scheme_change_without_notifications_pushes_nothing() {
    let mut term = crate::TerminalCore::new(24, 80);
    assert!(!term.dec_modes.color_scheme_notifications); // default off
    let changed = apply_color_scheme(&mut term, false);
    assert!(changed);
    assert!(!term.meta.color_scheme_dark);
    assert!(
        term.meta.pending_responses.is_empty(),
        "notifications disabled must suppress CSI ? 997 ; Ps n push"
    );
}

/// T3g (isolation): OSC 11 — set default background color — must NOT modify
/// `color_scheme_dark`. The two pieces of color state are independent: OSC
/// 10/11/12 control palette colors; mode 2031 + DSR 996 advertise the *theme*.
#[test]
fn test_osc_11_does_not_modify_color_scheme_dark() {
    let mut term = crate::TerminalCore::new(24, 80);
    let initial = term.meta.color_scheme_dark;
    // OSC 11 ; rgb:ffff/ffff/ffff — set bg to white. This is a palette change,
    // not a theme change; color_scheme_dark must stay untouched.
    let params: &[&[u8]] = &[b"11", b"rgb:ffff/ffff/ffff"];
    crate::parser::osc_protocol::handle_osc_default_colors(&mut term, params);
    assert_eq!(
        term.meta.color_scheme_dark, initial,
        "OSC 11 must not modify color_scheme_dark — palette ≠ theme"
    );
}

// ── Dual-fire ordering tests (V#5, V#8) ──────────────────────────────────────

/// V#5: `apply_color_scheme(false)` followed by DSR 996 emits two identical
/// `CSI ? 997 ; 2 n` byte strings — both reflect the new (light) state.
///
/// Notifications mode 2031 is enabled so that the change emits a proactive
/// notification; the subsequent DSR 996 query then re-reads the same state.
#[test]
fn test_apply_color_scheme_then_dsr_996_emits_two_identical_responses() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2031h"); // enable color scheme notifications
    let _ = apply_color_scheme(&mut term, false);
    term.advance(b"\x1b[?996n"); // DSR 996 query
    assert_eq!(
        term.meta.pending_responses.len(),
        2,
        "expected one notification + one DSR response = 2 entries"
    );
    assert_eq!(term.meta.pending_responses[0], b"\x1b[?997;2n");
    assert_eq!(term.meta.pending_responses[1], b"\x1b[?997;2n");
}

/// V#5 (reverse): DSR 996 first, then `apply_color_scheme(false)` —
/// the prior `?997;1n` response must remain untouched while the new
/// `?997;2n` notification is appended.
#[test]
fn test_dsr_996_then_apply_color_scheme_preserves_prior_response() {
    let mut term = crate::TerminalCore::new(24, 80);
    // Default dark + enable notifications
    term.advance(b"\x1b[?2031h");
    term.advance(b"\x1b[?996n"); // DSR 996 → pushes "?997;1n"
    let _ = apply_color_scheme(&mut term, false); // change → pushes "?997;2n"
    assert_eq!(
        term.meta.pending_responses.len(),
        2,
        "expected query response + change notification = 2 entries"
    );
    assert_eq!(
        term.meta.pending_responses[0], b"\x1b[?997;1n",
        "prior DSR 996 response must remain ?997;1n; state change must not mutate \
         already-pushed bytes"
    );
    assert_eq!(term.meta.pending_responses[1], b"\x1b[?997;2n");
}

/// V#8: Two consecutive DSR 996 queries push two distinct response entries.
///
/// Each DSR 996 must produce its own pending_responses entry — the parser
/// must not deduplicate or coalesce them (Emacs may have drained between
/// queries).
#[test]
fn test_two_consecutive_dsr_996_pushes_two_responses() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?996n\x1b[?996n");
    assert_eq!(
        term.meta.pending_responses.len(),
        2,
        "two DSR 996 queries must produce two distinct pending response entries"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// In-band resize notifications (?2048)
// ─────────────────────────────────────────────────────────────────────────────

/// Enabling ?2048 sets `resize_in_band` and immediately pushes one report of
/// the current size: `CSI 48 ; rows ; cols ; 0 ; 0 t` (pixels are always 0).
#[test]
fn test_dec_2048_enable_emits_immediate_size_report() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2048h");
    assert!(term.dec_modes.resize_in_band, "?2048h must set resize_in_band");
    assert_eq!(
        term.meta.pending_responses,
        vec![b"\x1b[48;24;80;0;0t".to_vec()],
        "?2048h must immediately emit one current-size report"
    );
}

/// Disabling ?2048 clears `resize_in_band` and emits nothing.
#[test]
fn test_dec_2048_disable_emits_no_report() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2048h");
    term.meta.pending_responses.clear();
    term.advance(b"\x1b[?2048l");
    assert!(
        !term.dec_modes.resize_in_band,
        "?2048l must clear resize_in_band"
    );
    assert!(
        term.meta.pending_responses.is_empty(),
        "?2048l (disable) must not emit a report"
    );
}

/// When ?2048 is active, `resize()` pushes a new in-band size report.
#[test]
fn test_dec_2048_resize_emits_report_when_active() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2048h");
    term.meta.pending_responses.clear(); // discard the initial report from enable
    term.resize(30, 100);
    assert_eq!(
        term.meta.pending_responses,
        vec![b"\x1b[48;30;100;0;0t".to_vec()],
        "resize() while ?2048 is set must emit a new size report"
    );
}

/// When ?2048 is NOT active, `resize()` emits nothing.
#[test]
fn test_dec_2048_resize_emits_nothing_when_inactive() {
    let mut term = crate::TerminalCore::new(24, 80);
    // mode 2048 is off by default
    term.resize(30, 100);
    assert!(
        term.meta.pending_responses.is_empty(),
        "resize() without ?2048 must not emit any report"
    );
}

/// `DecModes::apply_mode` / `get_mode` round-trip for 2048 in isolation.
#[test]
fn test_dec_modes_2048_apply_get_round_trip() {
    let mut modes = super::DecModes::new();
    assert_eq!(modes.get_mode(2048), Some(false), "2048 defaults to reset");
    modes.apply_mode(2048, true);
    assert!(modes.resize_in_band);
    assert_eq!(modes.get_mode(2048), Some(true), "2048 reports set after apply");
    modes.apply_mode(2048, false);
    assert!(!modes.resize_in_band);
    assert_eq!(modes.get_mode(2048), Some(false), "2048 reports reset after clear");
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    // PANIC SAFETY: Unknown DECSET mode numbers (50000–65000) never panic
    fn prop_decset_unknown_no_panic(mode in 50000u16..=65000u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        // DECSET: CSI ? {mode} h
        term.advance(format!("\x1b[?{mode}h").as_bytes());
        // DECRST: CSI ? {mode} l
        term.advance(format!("\x1b[?{mode}l").as_bytes());
        // Terminal must still have a valid cursor position
        prop_assert!(term.screen.cursor.row < 24);
    }

    #[test]
    // PANIC SAFETY: DECSCUSR (CSI Ps SP q) valid range 0–6 never panics
    fn prop_decscusr_valid_range(ps in 0u16..=6u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(format!("\x1b[{ps} q").as_bytes());
        // Cursor must still be within bounds
        prop_assert!(term.screen.cursor.row < 24);
    }

    #[test]
    // PANIC SAFETY: mouse mode DECSET/DECRST for known modes never panics
    fn prop_mouse_mode_toggle_no_panic(
        mode in prop_oneof![
            Just(1000u16),
            Just(1002u16),
            Just(1003u16),
            Just(1006u16),
            Just(1015u16),
        ]
    ) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(format!("\x1b[?{mode}h").as_bytes());
        term.advance(format!("\x1b[?{mode}l").as_bytes());
        prop_assert!(term.screen.cursor.row < 24);
    }

    #[test]
    // PANIC SAFETY: arbitrary DECSET mode 1–9999 never panics
    fn prop_decset_arbitrary_range_no_panic(mode in 1u16..=9999u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(format!("\x1b[?{mode}h").as_bytes());
        term.advance(format!("\x1b[?{mode}l").as_bytes());
        prop_assert!(term.screen.cursor.row < 24);
    }
}
