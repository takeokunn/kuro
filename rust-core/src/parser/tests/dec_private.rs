//! Property-based and example-based tests for `dec_private` parsing.
//!
//! Module under test: `parser/dec_private.rs`
//! Tier: T2 — `ProptestConfig::with_cases(500)`

use super::*;
use proptest::prelude::*;

#[test]
fn test_dec_modes_default() {
    let modes = DecModes::new();
    assert!(!modes.app_cursor_keys);
    assert!(modes.auto_wrap);
    assert!(modes.cursor_visible);
    assert!(!modes.alternate_screen);
    assert!(!modes.bracketed_paste);
}

#[test]
fn test_set_decckm() {
    let mut modes = DecModes::new();
    assert!(!modes.app_cursor_keys);

    modes.set_mode(1);
    assert!(modes.app_cursor_keys);
}

#[test]
fn test_reset_decckm() {
    let mut modes = DecModes::new();
    modes.app_cursor_keys = true;
    modes.reset_mode(1);
    assert!(!modes.app_cursor_keys);
}

#[test]
fn test_set_decawm() {
    let mut modes = DecModes::new();
    modes.auto_wrap = false;

    modes.set_mode(7);
    assert!(modes.auto_wrap);
}

#[test]
fn test_reset_decawm() {
    let mut modes = DecModes::new();
    modes.set_mode(7);
    assert!(modes.auto_wrap);

    modes.reset_mode(7);
    assert!(!modes.auto_wrap);
}

#[test]
fn test_set_dectcem() {
    let mut modes = DecModes::new();
    modes.cursor_visible = false;

    modes.set_mode(25);
    assert!(modes.cursor_visible);
}

#[test]
fn test_reset_dectcem() {
    let mut modes = DecModes::new();
    modes.reset_mode(25);
    assert!(!modes.cursor_visible);
}

#[test]
fn test_set_alternate_screen() {
    let mut modes = DecModes::new();
    assert!(!modes.alternate_screen);

    modes.set_mode(1049);
    assert!(modes.alternate_screen);
}

#[test]
fn test_reset_alternate_screen() {
    let mut modes = DecModes::new();
    modes.set_mode(1049);
    assert!(modes.alternate_screen);

    modes.reset_mode(1049);
    assert!(!modes.alternate_screen);
}

#[test]
fn test_set_bracketed_paste() {
    let mut modes = DecModes::new();
    assert!(!modes.bracketed_paste);

    modes.set_mode(2004);
    assert!(modes.bracketed_paste);
}

#[test]
fn test_reset_bracketed_paste() {
    let mut modes = DecModes::new();
    modes.set_mode(2004);
    assert!(modes.bracketed_paste);

    modes.reset_mode(2004);
    assert!(!modes.bracketed_paste);
}

#[test]
fn test_get_mode() {
    let mut modes = DecModes::new();

    modes.set_mode(1);
    modes.set_mode(7);

    assert_eq!(modes.get_mode(1), Some(true));
    assert_eq!(modes.get_mode(7), Some(true));
    assert_eq!(modes.get_mode(25), Some(true)); // default
    assert_eq!(modes.get_mode(1049), Some(false));
    assert_eq!(modes.get_mode(9999), None);
}

#[test]
fn test_app_keypad_default_is_false() {
    let modes = DecModes::new();
    assert!(!modes.app_keypad);
}

#[test]
fn test_app_keypad_set_and_clear() {
    let mut modes = DecModes::new();
    modes.app_keypad = true;
    assert!(modes.app_keypad);
    modes.app_keypad = false;
    assert!(!modes.app_keypad);
}

#[test]
fn test_unknown_mode_no_panic() {
    let mut modes = DecModes::new();
    modes.set_mode(9999); // Unknown mode, should not panic
    modes.reset_mode(9999); // Should also not panic
}

#[test]
fn test_mouse_mode_default_is_zero() {
    let modes = DecModes::new();
    assert_eq!(modes.mouse_mode, 0);
    assert!(!modes.mouse_sgr);
}

#[test]
fn test_set_mouse_mode_1000() {
    let mut modes = DecModes::new();
    modes.set_mode(1000);
    assert_eq!(modes.mouse_mode, 1000);
}

#[test]
fn test_set_mouse_mode_1002() {
    let mut modes = DecModes::new();
    modes.set_mode(1002);
    assert_eq!(modes.mouse_mode, 1002);
}

#[test]
fn test_set_mouse_mode_1003() {
    let mut modes = DecModes::new();
    modes.set_mode(1003);
    assert_eq!(modes.mouse_mode, 1003);
}

#[test]
fn test_reset_mouse_mode_sets_zero() {
    let mut modes = DecModes::new();
    modes.set_mode(1002);
    modes.reset_mode(1002);
    assert_eq!(modes.mouse_mode, 0);
}

#[test]
fn test_reset_any_mouse_mode_clears_all() {
    let mut modes = DecModes::new();
    modes.set_mode(1003);
    // Resetting mode 1000 still clears mouse_mode
    modes.reset_mode(1000);
    assert_eq!(modes.mouse_mode, 0);
}

#[test]
fn test_set_mouse_mode_replaces_previous() {
    let mut modes = DecModes::new();
    modes.set_mode(1000);
    modes.set_mode(1002); // switch to a different mode
    assert_eq!(modes.mouse_mode, 1002);
}

#[test]
fn test_set_mouse_sgr() {
    let mut modes = DecModes::new();
    modes.set_mode(1006);
    assert!(modes.mouse_sgr);
}

#[test]
fn test_reset_mouse_sgr() {
    let mut modes = DecModes::new();
    modes.set_mode(1006);
    modes.reset_mode(1006);
    assert!(!modes.mouse_sgr);
}

#[test]
fn test_get_mode_mouse_1000_active() {
    let mut modes = DecModes::new();
    modes.set_mode(1000);
    assert_eq!(modes.get_mode(1000), Some(true));
    assert_eq!(modes.get_mode(1002), Some(false));
    assert_eq!(modes.get_mode(1003), Some(false));
}

#[test]
fn test_get_mode_mouse_sgr() {
    let mut modes = DecModes::new();
    assert_eq!(modes.get_mode(1006), Some(false));
    modes.set_mode(1006);
    assert_eq!(modes.get_mode(1006), Some(true));
}

#[test]
fn test_decom_mode_set_reset() {
    let mut modes = DecModes::new();
    assert!(!modes.origin_mode, "origin_mode should default to false");

    modes.set_mode(6);
    assert!(
        modes.origin_mode,
        "origin_mode should be set after set_mode(6)"
    );

    modes.reset_mode(6);
    assert!(
        !modes.origin_mode,
        "origin_mode should be cleared after reset_mode(6)"
    );
}

#[test]
fn test_focus_events_mode_set_reset() {
    let mut modes = DecModes::new();
    assert!(!modes.focus_events, "focus_events should default to false");

    modes.set_mode(1004);
    assert!(
        modes.focus_events,
        "focus_events should be set after set_mode(1004)"
    );

    modes.reset_mode(1004);
    assert!(
        !modes.focus_events,
        "focus_events should be cleared after reset_mode(1004)"
    );
}

#[test]
fn test_sync_output_mode_set_reset() {
    let mut modes = DecModes::new();
    assert!(
        !modes.synchronized_output,
        "synchronized_output should default to false"
    );

    modes.set_mode(2026);
    assert!(
        modes.synchronized_output,
        "synchronized_output should be set after set_mode(2026)"
    );

    modes.reset_mode(2026);
    assert!(
        !modes.synchronized_output,
        "synchronized_output should be cleared after reset_mode(2026)"
    );
}

#[test]
fn test_get_mode_new_modes() {
    let mut modes = DecModes::new();
    assert_eq!(modes.get_mode(6), Some(false));
    assert_eq!(modes.get_mode(1004), Some(false));
    assert_eq!(modes.get_mode(2026), Some(false));

    modes.set_mode(6);
    modes.set_mode(1004);
    modes.set_mode(2026);

    assert_eq!(modes.get_mode(6), Some(true));
    assert_eq!(modes.get_mode(1004), Some(true));
    assert_eq!(modes.get_mode(2026), Some(true));
}

#[test]
fn test_alt_screen_saves_and_restores_sgr_attrs() {
    use crate::types::{Color, NamedColor};
    use crate::types::cell::SgrFlags;

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
}

// ── Kitty keyboard push/pop tests ────────────────────────────────────

#[test]
fn test_kitty_kb_push_with_valid_flags() {
    // Push keyboard flags 0b11 (disambiguate + report events) via CSI > 3 u.
    // The previous flags (0) are pushed onto the stack; current becomes 3.
    let mut term = crate::TerminalCore::new(24, 80);
    assert_eq!(term.dec_modes.keyboard_flags, 0);

    term.advance(b"\x1b[>3u");

    assert_eq!(
        term.dec_modes.keyboard_flags_stack.len(),
        1,
        "stack must have exactly 1 entry after one push"
    );
    assert_eq!(
        term.dec_modes.keyboard_flags, 3,
        "current keyboard_flags must be 0b11 after pushing flags=3"
    );
}

#[test]
fn test_kitty_kb_push_zero_flags() {
    // Push with flags=0 via CSI > 0 u.
    // The push is still recorded (stack grows), and current flags stay 0.
    let mut term = crate::TerminalCore::new(24, 80);
    assert_eq!(term.dec_modes.keyboard_flags, 0);

    term.advance(b"\x1b[>0u");

    assert_eq!(
        term.dec_modes.keyboard_flags_stack.len(),
        1,
        "stack must grow by 1 even when pushing flags=0"
    );
    assert_eq!(
        term.dec_modes.keyboard_flags, 0,
        "current keyboard_flags must remain 0 after pushing flags=0"
    );
}

#[test]
fn test_kitty_kb_push_max_stack_depth() {
    // Push 65 times (1 beyond the 64-entry hard cap).
    // The stack must be capped at 64 entries and must not panic.
    let mut term = crate::TerminalCore::new(24, 80);

    for i in 0u8..65 {
        // Vary the flags so each push is distinct (not required, but realistic)
        let seq = format!("\x1b[>{i}u");
        term.advance(seq.as_bytes());
    }

    assert_eq!(
        term.dec_modes.keyboard_flags_stack.len(),
        64,
        "keyboard_flags_stack must be capped at 64 entries"
    );
    // No panic occurred — the test passes simply by completing execution.
}

#[test]
fn test_kitty_kb_pop_restores_flags() {
    // Push flags=3, then pop.
    // After pop, keyboard_flags must be restored to the original value (0)
    // and the stack must be empty.
    let mut term = crate::TerminalCore::new(24, 80);
    assert_eq!(term.dec_modes.keyboard_flags, 0);

    // Push: stack saves 0, current becomes 3
    term.advance(b"\x1b[>3u");
    assert_eq!(term.dec_modes.keyboard_flags, 3);
    assert_eq!(term.dec_modes.keyboard_flags_stack.len(), 1);

    // Pop: restores saved value 0, stack becomes empty
    term.advance(b"\x1b[<u");
    assert_eq!(
        term.dec_modes.keyboard_flags, 0,
        "keyboard_flags must be restored to original value after pop"
    );
    assert!(
        term.dec_modes.keyboard_flags_stack.is_empty(),
        "keyboard_flags_stack must be empty after popping the only entry"
    );
}

#[test]
fn test_kitty_kb_pop_empty_stack_is_noop() {
    // Pop with empty stack must not panic and must leave keyboard_flags unchanged.
    let mut term = crate::TerminalCore::new(24, 80);
    assert_eq!(term.dec_modes.keyboard_flags, 0);

    // Pop on empty stack
    term.advance(b"\x1b[<u");

    assert_eq!(
        term.dec_modes.keyboard_flags, 0,
        "keyboard_flags must remain 0 after popping empty stack"
    );
    assert!(
        term.dec_modes.keyboard_flags_stack.is_empty(),
        "stack must remain empty after noop pop"
    );
}

#[test]
fn test_decrqm_known_mode_enabled() {
    // Enable mouse mode 1000, then query it.
    // Expected response: CSI ? 1000 ; 1 $ y  (status 1 = set)
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1000h"); // enable mouse mode 1000
    term.advance(b"\x1b[?1000$p"); // query
    let resp = String::from_utf8(term.meta.pending_responses[0].clone()).unwrap();
    assert_eq!(resp, "\x1b[?1000;1$y", "enabled mode must report status 1");
}

#[test]
fn test_decrqm_known_mode_disabled() {
    // Mouse mode 1000 starts disabled; query it without enabling.
    // Expected response: CSI ? 1000 ; 2 $ y  (status 2 = reset)
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1000$p"); // query without enabling
    let resp = String::from_utf8(term.meta.pending_responses[0].clone()).unwrap();
    assert_eq!(resp, "\x1b[?1000;2$y", "disabled mode must report status 2");
}

#[test]
fn test_decrqm_unknown_mode() {
    // Mode 9999 is not recognised.
    // Expected response: CSI ? 9999 ; 0 $ y  (status 0 = not recognised)
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?9999$p"); // query unknown mode
    let resp = String::from_utf8(term.meta.pending_responses[0].clone()).unwrap();
    assert_eq!(resp, "\x1b[?9999;0$y", "unknown mode must report status 0");
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
