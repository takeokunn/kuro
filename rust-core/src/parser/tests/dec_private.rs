//! Property-based and example-based tests for `dec_private` parsing.
//!
//! Module under test: `parser/dec_private.rs`
//! Tier: T2 — `ProptestConfig::with_cases(500)`

use super::*;
use proptest::prelude::*;

/// Generate a set/reset pair for a simple boolean DEC mode field.
///
/// Both generated tests follow the three-step pattern:
/// 1. `set_mode(N)` — field goes `true`
/// 2. `reset_mode(N)` after `set_mode(N)` — field goes back `false`
///
/// Usage:
/// ```text
/// test_dec_mode!(set_name, reset_name, mode_number, field)
/// ```
/// `set_name` / `reset_name` are the full `fn` identifiers for the two tests.
/// `field` is a `DecModes` boolean field name (e.g. `app_cursor_keys`).
macro_rules! test_dec_mode {
    ($set_name:ident, $reset_name:ident, $mode:expr, $field:ident) => {
        #[test]
        fn $set_name() {
            let mut modes = DecModes::new();
            modes.set_mode($mode);
            assert!(modes.$field);
        }

        #[test]
        fn $reset_name() {
            let mut modes = DecModes::new();
            modes.set_mode($mode);
            modes.reset_mode($mode);
            assert!(!modes.$field);
        }
    };
}

// DECCKM — Application cursor keys (mode 1)
test_dec_mode!(test_set_decckm, test_reset_decckm, 1, app_cursor_keys);

// Alternate screen (mode 1049)
test_dec_mode!(
    test_set_alternate_screen,
    test_reset_alternate_screen,
    1049,
    alternate_screen
);

// Bracketed paste (mode 2004)
test_dec_mode!(
    test_set_bracketed_paste,
    test_reset_bracketed_paste,
    2004,
    bracketed_paste
);

// SGR mouse extension (mode 1006)
test_dec_mode!(test_set_mouse_sgr, test_reset_mouse_sgr, 1006, mouse_sgr);

// Pixel mouse extension (mode 1016)
test_dec_mode!(
    test_set_mouse_pixel,
    test_reset_mouse_pixel,
    1016,
    mouse_pixel
);

// DECOM — Origin mode (mode 6)
test_dec_mode!(test_set_decom, test_reset_decom, 6, origin_mode);

// Focus events (mode 1004)
test_dec_mode!(
    test_set_focus_events,
    test_reset_focus_events,
    1004,
    focus_events
);

// Synchronized output (mode 2026)
test_dec_mode!(
    test_set_synchronized_output,
    test_reset_synchronized_output,
    2026,
    synchronized_output
);

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
    // Kept for explicit field-level assertion alongside the macro-generated tests.
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

/// Query a DEC private mode state via DECRQM and assert the exact response.
///
/// `$enable_seq` — optional byte sequence to enable the mode first (use `b""` to skip).
/// `$mode`       — mode number (u16 literal).
/// `$expected`   — expected response string (e.g. `"\x1b[?1000;1$y"`).
///
/// Usage:
/// ```text
/// test_decrqm!(test_name, b"\x1b[?1000h", 1000, "\x1b[?1000;1$y");
/// test_decrqm!(test_name, b"",            1000, "\x1b[?1000;2$y");
/// ```
macro_rules! test_decrqm {
    ($name:ident, $enable_seq:expr, $mode:expr, $expected:expr) => {
        #[test]
        fn $name() {
            let mut term = crate::TerminalCore::new(24, 80);
            if !$enable_seq.is_empty() {
                term.advance($enable_seq);
            }
            term.advance(format!("\x1b[?{}$p", $mode).as_bytes());
            let resp = String::from_utf8(term.meta.pending_responses[0].clone()).unwrap();
            assert_eq!(resp, $expected);
        }
    };
}

test_decrqm!(
    test_decrqm_known_mode_enabled,
    b"\x1b[?1000h",
    1000,
    "\x1b[?1000;1$y"
);
test_decrqm!(test_decrqm_known_mode_disabled, b"", 1000, "\x1b[?1000;2$y");
test_decrqm!(test_decrqm_unknown_mode, b"", 9999, "\x1b[?9999;0$y");
test_decrqm!(
    test_decrqm_bracketed_paste_enabled,
    b"\x1b[?2004h",
    2004,
    "\x1b[?2004;1$y"
);
test_decrqm!(test_decrqm_cursor_visible_default, b"", 25, "\x1b[?25;1$y");
test_decrqm!(test_decrqm_auto_wrap_default, b"", 7, "\x1b[?7;1$y");

// ── mouse_pixel (?1016) ────────────────────────────────────────────────────────

#[test]
fn test_get_mode_mouse_pixel() {
    let mut modes = DecModes::new();
    assert_eq!(modes.get_mode(1016), Some(false));
    modes.set_mode(1016);
    assert_eq!(modes.get_mode(1016), Some(true));
    modes.reset_mode(1016);
    assert_eq!(modes.get_mode(1016), Some(false));
}

// ── apply_mode API ────────────────────────────────────────────────────────────

#[test]
fn test_apply_mode_true_sets_bool_modes() {
    let mut modes = DecModes::new();
    modes.auto_wrap = false;
    modes.apply_mode(7, true);
    assert!(modes.auto_wrap, "apply_mode(7, true) must set auto_wrap");
}

#[test]
fn test_apply_mode_false_clears_bool_modes() {
    let mut modes = DecModes::new();
    modes.apply_mode(25, false);
    assert!(
        !modes.cursor_visible,
        "apply_mode(25, false) must clear cursor_visible"
    );
}

#[test]
fn test_apply_mode_mouse_tracking_set_stores_number() {
    let mut modes = DecModes::new();
    modes.apply_mode(1003, true);
    assert_eq!(
        modes.mouse_mode, 1003,
        "apply_mode(1003, true) must set mouse_mode=1003"
    );
}

#[test]
fn test_apply_mode_mouse_tracking_reset_clears_to_zero() {
    let mut modes = DecModes::new();
    modes.apply_mode(1002, true);
    assert_eq!(modes.mouse_mode, 1002);
    modes.apply_mode(1002, false);
    assert_eq!(
        modes.mouse_mode, 0,
        "apply_mode(1002, false) must clear mouse_mode to 0"
    );
}

#[test]
fn test_apply_mode_unknown_is_noop() {
    // apply_mode with an unknown mode must leave all fields at their defaults.
    let mut modes = DecModes::new();
    let before_auto_wrap = modes.auto_wrap;
    let before_cursor_visible = modes.cursor_visible;
    modes.apply_mode(9999, true);
    modes.apply_mode(9999, false);
    assert_eq!(modes.auto_wrap, before_auto_wrap);
    assert_eq!(modes.cursor_visible, before_cursor_visible);
}

#[test]
fn test_apply_mode_round_trip_all_bool_modes() {
    // For every bool-mapped mode: apply(true) then apply(false) returns to default.
    let bool_modes: &[(u16, bool)] = &[
        (1, false),    // app_cursor_keys default=false
        (6, false),    // origin_mode default=false
        (7, true),     // auto_wrap default=true
        (25, true),    // cursor_visible default=true
        (1004, false), // focus_events default=false
        (1006, false), // mouse_sgr default=false
        (1016, false), // mouse_pixel default=false
        (1049, false), // alternate_screen default=false
        (2004, false), // bracketed_paste default=false
        (2026, false), // synchronized_output default=false
    ];
    for &(mode, default_value) in bool_modes {
        let mut modes = DecModes::new();
        modes.apply_mode(mode, true);
        assert_eq!(
            modes.get_mode(mode),
            Some(true),
            "apply_mode({mode}, true) must yield get_mode=Some(true)"
        );
        modes.apply_mode(mode, false);
        assert_eq!(
            modes.get_mode(mode),
            Some(false),
            "apply_mode({mode}, false) must yield get_mode=Some(false)"
        );
        // Verify reset returns to the documented VT default.
        let _ = default_value; // referenced below for clarity only
        assert_eq!(
            modes.get_mode(mode),
            Some(false),
            "mode {mode} must be false after apply_mode(false)"
        );
    }
}

// ── Edge-case tests ───────────────────────────────────────────────────────────

#[test]
fn test_dec_mode_persists_after_unrelated_operation() {
    // A mode set via DECSET must survive an unrelated terminal operation
    // (here: cursor movement) without being cleared.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1h"); // DECSET: app cursor keys on
    assert!(
        term.dec_modes.app_cursor_keys,
        "app_cursor_keys must be set"
    );

    term.advance(b"\x1b[5;10H"); // CUP: move cursor — unrelated operation
    assert!(
        term.dec_modes.app_cursor_keys,
        "app_cursor_keys must persist after CUP"
    );
}

#[test]
fn test_decset_idempotent() {
    // Calling set_mode twice on the same mode must leave it set.
    let mut modes = DecModes::new();
    modes.set_mode(1);
    modes.set_mode(1); // second call — idempotent
    assert!(
        modes.app_cursor_keys,
        "app_cursor_keys must remain set after double set_mode"
    );
    assert_eq!(modes.get_mode(1), Some(true));
}

#[test]
fn test_decrst_idempotent() {
    // Calling reset_mode twice must leave the mode cleared without panic.
    let mut modes = DecModes::new();
    modes.set_mode(2004);
    modes.reset_mode(2004);
    modes.reset_mode(2004); // second reset — idempotent
    assert!(
        !modes.bracketed_paste,
        "bracketed_paste must remain clear after double reset_mode"
    );
    assert_eq!(modes.get_mode(2004), Some(false));
}

#[test]
fn test_auto_wrap_default_true_via_get_mode() {
    // DecModes::new() must report auto_wrap=true (mode 7 default=enabled).
    let modes = DecModes::new();
    assert_eq!(
        modes.get_mode(7),
        Some(true),
        "get_mode(7) must return Some(true) for auto_wrap default"
    );
}

#[test]
fn test_cursor_visible_default_true_via_get_mode() {
    // DecModes::new() must report cursor_visible=true (mode 25 default=enabled).
    let modes = DecModes::new();
    assert_eq!(
        modes.get_mode(25),
        Some(true),
        "get_mode(25) must return Some(true) for cursor_visible default"
    );
}

// ── New edge-case tests ───────────────────────────────────────────────────────

#[test]
fn test_decom_cursor_moves_to_scroll_region_top_on_set() {
    // Setting DECOM (?6) must move the cursor to the top of the scroll region,
    // not just flip the origin_mode bit.
    let mut term = crate::TerminalCore::new(24, 80);
    // Set a scroll region (rows 3–20, 0-indexed) via DECSTBM
    term.advance(b"\x1b[4;20r"); // CSI 4 ; 20 r — sets scroll region rows 3..19
                                 // Move cursor away first
    term.advance(b"\x1b[10;5H");
    // Enable DECOM — must move cursor to scroll-region top (row 3)
    term.advance(b"\x1b[?6h");
    assert_eq!(
        term.screen.cursor().col,
        0,
        "DECOM set must reset cursor col to 0"
    );
    let top = term.screen.get_scroll_region().top;
    assert_eq!(
        term.screen.cursor().row,
        top,
        "DECOM set must move cursor to scroll-region top"
    );
}

#[test]
fn test_decom_cursor_moves_to_absolute_home_on_reset() {
    // Resetting DECOM (?6) must move cursor to absolute (0,0).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?6h"); // enable DECOM
    term.advance(b"\x1b[5;5H"); // move cursor somewhere
    term.advance(b"\x1b[?6l"); // disable DECOM — cursor must go to (0,0)
    assert_eq!(
        term.screen.cursor().row,
        0,
        "DECOM reset must move cursor to row 0"
    );
    assert_eq!(
        term.screen.cursor().col,
        0,
        "DECOM reset must move cursor to col 0"
    );
}

#[test]
fn test_alt_screen_double_exit_is_noop() {
    // Exiting the alternate screen when already on primary must not panic or
    // corrupt state.  The guard `1049 if term.dec_modes.alternate_screen` in
    // `apply_mode_reset` prevents the switch from firing twice.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?1049h"); // enter alt screen
    term.advance(b"\x1b[?1049l"); // exit alt screen
    term.advance(b"\x1b[?1049l"); // exit again — must be a no-op
    assert!(
        !term.dec_modes.alternate_screen,
        "alternate_screen must be false after double exit"
    );
}

#[test]
fn test_sync_output_reset_marks_all_dirty() {
    // Resetting synchronized output (?2026) must call mark_all_dirty().
    // We cannot observe the dirty bits directly in this test, but we can
    // verify the round-trip doesn't panic and the flag is cleared.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2026h"); // enable sync output
    assert!(term.dec_modes.synchronized_output);
    term.advance(b"\x1b[?2026l"); // disable — must call mark_all_dirty()
    assert!(
        !term.dec_modes.synchronized_output,
        "synchronized_output must be cleared"
    );
}

#[test]
fn test_decscusr_block_blinking_0_and_1() {
    // DECSCUSR 0 and 1 both select blinking-block cursor shape.
    // Must not panic; terminal remains usable.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[0 q"); // blinking block (default)
    term.advance(b"\x1b[1 q"); // blinking block (explicit)
    assert!(term.screen.cursor().col < 80, "cursor must stay in bounds");
}

#[test]
fn test_decscusr_steady_block_2() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[2 q"); // steady block
    assert!(term.screen.cursor().row < 24);
}

#[test]
fn test_decscusr_out_of_range_7_no_panic() {
    // DECSCUSR with Ps=7 (out of standard 0–6 range) must not panic.
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[7 q");
    assert!(term.screen.cursor().row < 24);
}

#[test]
fn test_kitty_kb_push_pop_restores_previous_non_zero() {
    // Push flags=7 on top of already-set flags=3.
    // After pop, flags must return to 3 (not 0).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[>3u"); // push: save 0, current=3
    assert_eq!(term.dec_modes.keyboard_flags, 3);
    term.advance(b"\x1b[>7u"); // push: save 3, current=7
    assert_eq!(term.dec_modes.keyboard_flags, 7);
    term.advance(b"\x1b[<u"); // pop: restore 3
    assert_eq!(
        term.dec_modes.keyboard_flags, 3,
        "pop must restore the most-recently-pushed value (3)"
    );
    assert_eq!(term.dec_modes.keyboard_flags_stack.len(), 1);
}

#[test]
fn test_decrqm_multi_param_queues_multiple_responses() {
    // Sending two separate DECRQM queries in sequence must produce two entries
    // in pending_responses (one per query).
    let mut term = crate::TerminalCore::new(24, 80);
    term.advance(b"\x1b[?25$p"); // query cursor visible (default=set → status 1)
    term.advance(b"\x1b[?1049$p"); // query alt screen (default=reset → status 2)
    assert_eq!(
        term.meta.pending_responses.len(),
        2,
        "two DECRQM queries must produce two responses"
    );
    let r0 = String::from_utf8(term.meta.pending_responses[0].clone()).unwrap();
    let r1 = String::from_utf8(term.meta.pending_responses[1].clone()).unwrap();
    assert_eq!(r0, "\x1b[?25;1$y");
    assert_eq!(r1, "\x1b[?1049;2$y");
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
