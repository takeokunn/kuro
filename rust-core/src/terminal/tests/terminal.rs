//! Basic terminal creation, resize, input, and cursor tests.

use crate::types;
use crate::types::cell::SgrFlags;
use crate::types::cursor::CursorShape;
use proptest::prelude::*;

// ── Local test-only macros ─────────────────────────────────────────────────

/// Assert the cursor is at an exact (row, col) position (0-indexed).
///
/// ```
/// assert_cursor!(term, row 4, col 0);
/// ```
macro_rules! assert_cursor {
    ($term:expr, row $r:expr, col $c:expr) => {{
        assert_eq!(
            $term.screen.cursor().row,
            $r,
            "cursor row: expected {}, got {}",
            $r,
            $term.screen.cursor().row
        );
        assert_eq!(
            $term.screen.cursor().col,
            $c,
            "cursor col: expected {}, got {}",
            $c,
            $term.screen.cursor().col
        );
    }};
}

/// Assert a single cell's character value by (row, col).
///
/// ```
/// assert_cell_char!(term, row 0, col 2, 'l');
/// ```
macro_rules! assert_cell_char {
    ($term:expr, row $r:expr, col $c:expr, $ch:expr) => {{
        assert_eq!(
            $term.get_cell($r, $c).unwrap().char(),
            $ch,
            "cell ({}, {}) expected {:?}",
            $r,
            $c,
            $ch
        );
    }};
}

/// Assert a specific SGR flag is set on `current_attrs`.
///
/// ```
/// assert_flag!(term, SgrFlags::BOLD);
/// ```
macro_rules! assert_flag {
    ($term:expr, $flag:expr) => {{
        assert!(
            $term.current_attrs.flags.contains($flag),
            "expected flag {:?} to be set",
            $flag
        );
    }};
}

/// Assert a specific SGR flag is NOT set on `current_attrs`.
macro_rules! assert_no_flag {
    ($term:expr, $flag:expr) => {{
        assert!(
            !$term.current_attrs.flags.contains($flag),
            "expected flag {:?} to be clear",
            $flag
        );
    }};
}

// ── Tests ──────────────────────────────────────────────────────────────────

#[test]
fn test_terminal_creation() {
    let term = super::make_term();
    assert_eq!(term.screen.rows(), 24);
    assert_eq!(term.screen.cols(), 80);
}

#[test]
fn test_simple_print() {
    let mut term = super::make_term();
    term.advance(b"Hello");
    assert_cell_char!(term, row 0, col 0, 'H');
}

#[test]
fn test_decsc_decrc_basic() {
    let mut term = super::make_term();

    term.advance(b"\x1b[6;11H"); // CSI 6;11H -> row 5, col 10 (0-indexed)
    let row_before = term.screen.cursor().row;
    let col_before = term.screen.cursor().col;

    term.advance(b"\x1b7"); // DECSC
    assert!(
        term.saved_cursor.is_some(),
        "saved_cursor should be set after ESC 7"
    );

    term.advance(b"\x1b[1;1H");
    assert_cursor!(term, row 0, col 0);

    term.advance(b"\x1b8"); // DECRC
    assert_eq!(term.screen.cursor().row, row_before);
    assert_eq!(term.screen.cursor().col, col_before);
    assert!(
        term.saved_cursor.is_none(),
        "saved_cursor should be cleared after ESC 8"
    );
}

#[test]
fn test_decsc_decrc_preserves_attrs() {
    let mut term = super::make_term();

    term.advance(b"\x1b[1m"); // bold on
    assert_flag!(term, SgrFlags::BOLD);

    term.advance(b"\x1b7"); // DECSC
    term.advance(b"\x1b[0m"); // reset
    assert_no_flag!(term, SgrFlags::BOLD);

    term.advance(b"\x1b8"); // DECRC
    assert_flag!(term, SgrFlags::BOLD);
}

#[test]
fn test_ris_full_reset() {
    let mut term = super::make_term();

    term.advance(b"\x1b[10;20H");
    term.advance(b"\x1b[1m");
    term.advance(b"\x1b7");
    term.advance(b"\x1bc"); // RIS

    assert_cursor!(term, row 0, col 0);
    assert_no_flag!(term, SgrFlags::BOLD);
    assert!(term.saved_cursor.is_none());
    assert!(term.saved_attrs.is_none());
    assert!(!term.screen.is_alternate_screen_active());
}

#[test]
fn test_dectcem_cursor_visibility() {
    let mut term = super::make_term();

    assert!(term.dec_modes.cursor_visible);

    term.advance(b"\x1b[?25l");
    assert!(
        !term.dec_modes.cursor_visible,
        "cursor should be hidden after CSI ?25l"
    );

    term.advance(b"\x1b[?25h");
    assert!(
        term.dec_modes.cursor_visible,
        "cursor should be visible after CSI ?25h"
    );
}

#[test]
fn test_dectcem_after_ris() {
    let mut term = super::make_term();
    assert!(term.dec_modes.cursor_visible);

    term.advance(b"\x1b[?25l");
    assert!(!term.dec_modes.cursor_visible);

    term.advance(b"\x1bc");
    assert!(
        term.dec_modes.cursor_visible,
        "cursor should be visible after RIS (DecModes::new() sets cursor_visible=true)"
    );
}

#[test]
fn test_ris_resets_cursor_shape() {
    let mut term = super::make_term();

    term.advance(b"\x1b[6 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        CursorShape::SteadyBar,
        "cursor shape should be SteadyBar after CSI 6 SP q"
    );

    term.advance(b"\x1bc");
    assert_eq!(
        term.dec_modes.cursor_shape,
        CursorShape::BlinkingBlock,
        "RIS must reset cursor_shape to BlinkingBlock"
    );
}

#[test]
fn test_ris_clears_kitty_keyboard_stack() {
    let mut term = super::make_term();

    term.advance(b"\x1b[>1u");
    term.advance(b"\x1b[>3u");
    assert_eq!(
        term.dec_modes.keyboard_flags_stack.len(),
        2,
        "keyboard_flags_stack should have 2 entries after two pushes"
    );

    term.advance(b"\x1bc");
    assert!(
        term.dec_modes.keyboard_flags_stack.is_empty(),
        "RIS must clear keyboard_flags_stack"
    );
    assert_eq!(
        term.dec_modes.keyboard_flags, 0,
        "RIS must reset keyboard_flags to 0"
    );
}

#[test]
fn test_deckpam_sets_app_keypad() {
    let mut term = super::make_term();
    assert!(
        !term.dec_modes.app_keypad,
        "app_keypad should default to false"
    );
    term.advance(b"\x1b="); // DECKPAM
    assert!(
        term.dec_modes.app_keypad,
        "app_keypad should be set after ESC ="
    );
}

#[test]
fn test_deckpnm_clears_app_keypad() {
    let mut term = super::make_term();
    term.advance(b"\x1b=");
    assert!(term.dec_modes.app_keypad);
    term.advance(b"\x1b>");
    assert!(
        !term.dec_modes.app_keypad,
        "app_keypad should be cleared after ESC >"
    );
}

#[test]
fn test_deckpam_toggle_sequence() {
    let mut term = super::make_term();
    term.advance(b"\x1b=\x1b>\x1b="); // DECKPAM -> DECKPNM -> DECKPAM
    assert!(
        term.dec_modes.app_keypad,
        "final state should be app_keypad=true"
    );
}


include!("terminal_part2.rs");
include!("terminal_ext.rs");
