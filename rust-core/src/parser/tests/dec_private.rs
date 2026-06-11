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

// UTF-8 mouse encoding (mode 1005)
test_dec_mode!(test_set_mouse_utf8, test_reset_mouse_utf8, 1005, mouse_utf8);

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

include!("dec_private_ext.rs");
