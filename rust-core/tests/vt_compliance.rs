//! VT100/VT220 compliance test suite
//!
//! Tests terminal emulator compliance with VT100/VT220 standards.
//! These tests exercise the full `advance()` pipeline without any Emacs runtime.

use kuro_core::types::cell::SgrFlags;
use kuro_core::TerminalCore;

/// Assert DEC private mode N enables on `h` and disables on `l`.
///
/// Form: `vt_dec_toggle!(fn_name, set_seq, reset_seq, field)`
/// where `field` is the bool field on `DecModes`.
macro_rules! vt_dec_toggle {
    ($fn_name:ident, $set:literal, $reset:literal, $field:ident) => {
        #[test]
        fn $fn_name() {
            let mut t = TerminalCore::new(24, 80);
            t.advance($set);
            assert!(t.dec_modes().$field);
            t.advance($reset);
            assert!(!t.dec_modes().$field);
        }
    };
}

// === VT100 Basic Cursor Movement ===

#[test]
fn vt_cup_moves_cursor() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H");
    assert_eq!(t.cursor_row(), 4, "CUP row");
    assert_eq!(t.cursor_col(), 9, "CUP col");
}

#[test]
fn vt_cuu_moves_up() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H\x1b[2A");
    assert_eq!(t.cursor_row(), 2);
}

#[test]
fn vt_cud_moves_down() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5;10H\x1b[3B");
    assert_eq!(t.cursor_row(), 7);
}

#[test]
fn vt_cuf_moves_forward() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;10H\x1b[5C");
    assert_eq!(t.cursor_col(), 14);
}

#[test]
fn vt_cub_moves_back() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;15H\x1b[3D");
    assert_eq!(t.cursor_col(), 11);
}

#[test]
fn vt_home_moves_to_origin() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[10;20H\x1b[H");
    assert_eq!(t.cursor_row(), 0);
    assert_eq!(t.cursor_col(), 0);
}

// === VT100 Erase Operations ===

#[test]
fn vt_el_erases_line() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"ABCDE\x1b[1;1H\x1b[K");
    assert_eq!(t.get_cell(0, 0).unwrap().char(), ' ');
}

#[test]
fn vt_ed_erases_display() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"Hello\x1b[2J");
    assert_eq!(t.get_cell(0, 0).unwrap().char(), ' ');
}

// === SGR Attributes ===

#[test]
fn vt_sgr_bold() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1m");
    assert!(t.current_attrs().flags.contains(SgrFlags::BOLD));
}

#[test]
fn vt_sgr_reset() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;3;4m");
    assert!(t.current_attrs().flags.contains(SgrFlags::BOLD));
    assert!(t.current_attrs().flags.contains(SgrFlags::ITALIC));
    t.advance(b"\x1b[0m");
    assert!(!t.current_attrs().flags.contains(SgrFlags::BOLD));
    assert!(!t.current_attrs().flags.contains(SgrFlags::ITALIC));
}

#[test]
fn vt_sgr_named_colors() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[31m");
    assert!(matches!(
        t.current_attrs().foreground,
        kuro_core::types::Color::Named(_)
    ));
}

#[test]
fn vt_sgr_rgb_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38;2;255;128;0m");
    assert_eq!(
        t.current_attrs().foreground,
        kuro_core::types::Color::Rgb(255, 128, 0)
    );
}

#[test]
fn vt_sgr_256_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[38;5;196m");
    assert_eq!(
        t.current_attrs().foreground,
        kuro_core::types::Color::Indexed(196)
    );
}

// === DEC Private Modes ===

#[test]
fn vt_dectcem_cursor_visibility() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?25l");
    assert!(!t.dec_modes().cursor_visible);
    t.advance(b"\x1b[?25h");
    assert!(t.dec_modes().cursor_visible);
}

vt_dec_toggle!(
    vt_decckm_app_cursor,
    b"\x1b[?1h",
    b"\x1b[?1l",
    app_cursor_keys
);

#[test]
fn vt_decawm_auto_wrap() {
    let mut t = TerminalCore::new(24, 80);
    assert!(t.dec_modes().auto_wrap); // default on
    t.advance(b"\x1b[?7l");
    assert!(!t.dec_modes().auto_wrap);
    t.advance(b"\x1b[?7h");
    assert!(t.dec_modes().auto_wrap);
}

/// DEC pending wrap: writing at the last column must NOT immediately wrap.
///
/// Per DEC VT510 manual, DECAWM defers the wrap until the next printable
/// character.  This is essential for TUI apps (btop, htop) that draw
/// box-drawing characters at the last column without wanting a scroll.
#[test]
fn vt_decawm_pending_wrap() {
    let mut t = TerminalCore::new(3, 5);
    // Fill row 0 with 'A'
    t.advance(b"\x1b[1;1HAAAAA");
    // Cursor should be at last col with pending wrap, NOT on row 1
    assert_eq!(t.cursor_col(), 4, "cursor stays at last col (pending wrap)");
    assert_eq!(t.cursor_row(), 0, "cursor stays on row 0 (no wrap yet)");
    // Row 0 must have all 5 A's
    for col in 0..5 {
        assert_eq!(t.get_cell(0, col).unwrap().char(), 'A');
    }
    // CUP clears pending wrap — subsequent print must NOT wrap
    t.advance(b"\x1b[1;5H"); // move to (0,4) — last col
    t.advance(b"B");
    assert_eq!(
        t.cursor_col(),
        4,
        "after overwriting last col, pending wrap again"
    );
    assert_eq!(t.cursor_row(), 0, "still on row 0");
    // Now print another char — this must fire the deferred wrap
    t.advance(b"C");
    assert_eq!(t.cursor_row(), 1, "deferred wrap fires on next char");
    assert_eq!(
        t.cursor_col(),
        1,
        "cursor at col 1 after wrapping and printing 'C'"
    );
    // 'C' should be at row 1, col 0
    assert_eq!(t.get_cell(1, 0).unwrap().char(), 'C');
}

/// DECAWM off: printing at last column stays clamped, never wraps.
#[test]
fn vt_decawm_off_no_wrap() {
    let mut t = TerminalCore::new(3, 5);
    t.advance(b"\x1b[?7l"); // disable auto-wrap
    t.advance(b"\x1b[1;1HABCDE");
    // With DECAWM off, cursor stays at last column
    assert_eq!(t.cursor_col(), 4);
    assert_eq!(t.cursor_row(), 0);
    // Additional chars overwrite at last column, never wrap
    t.advance(b"FGH");
    assert_eq!(t.cursor_col(), 4, "DECAWM off: cursor clamped at last col");
    assert_eq!(t.cursor_row(), 0, "DECAWM off: never wraps to next row");
    // Last col should have 'H' (the last overwrite)
    assert_eq!(t.get_cell(0, 4).unwrap().char(), 'H');
}

vt_dec_toggle!(
    vt_bracketed_paste,
    b"\x1b[?2004h",
    b"\x1b[?2004l",
    bracketed_paste
);

// === Alt Screen ===

#[test]
fn vt_alt_screen_switch() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"Hello");
    t.advance(b"\x1b[?1049h");
    assert!(t.dec_modes().alternate_screen);
    t.advance(b"\x1b[?1049l");
    assert!(!t.dec_modes().alternate_screen);
    assert_eq!(t.get_cell(0, 0).unwrap().char(), 'H');
}

// === Tab Stops ===

#[test]
fn vt_tab_default_stops() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[H\t");
    assert_eq!(t.cursor_col(), 8);
}

// === VPA/CHA ===

#[test]
fn vt_vpa_moves_to_row() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5d");
    assert_eq!(t.cursor_row(), 4);
}

#[test]
fn vt_cha_moves_to_col() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[10G");
    assert_eq!(t.cursor_col(), 9);
}

// === Device Attributes ===

#[test]
fn vt_da1_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[c");
    assert!(
        !t.pending_responses().is_empty(),
        "DA1 must generate response"
    );
    let resp = &t.pending_responses()[0];
    assert!(resp.starts_with(b"\x1b[?"), "DA1 response format");
}

#[test]
fn vt_da2_response() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[>c");
    assert!(
        !t.pending_responses().is_empty(),
        "DA2 must generate response"
    );
}

#[test]
fn da3_tertiary_device_attributes_responds_with_unit_id() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[=c");
    assert!(
        !t.pending_responses().is_empty(),
        "DA3 must generate response"
    );
    let resp = t.pending_responses().last().expect("response present");
    assert_eq!(
        resp.as_slice(),
        b"\x1bP!|00000000\x1b\\",
        "DA3 response must be DCS ! | 00000000 ST"
    );
}

#[test]
fn da3_with_zero_param() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[=0c");
    assert!(
        !t.pending_responses().is_empty(),
        "DA3 with zero param must generate response"
    );
    let resp = t.pending_responses().last().expect("response present");
    assert_eq!(
        resp.as_slice(),
        b"\x1bP!|00000000\x1b\\",
        "DA3 zero-param response must be DCS ! | 00000000 ST"
    );
}

#[path = "include/vt_compliance_device_attrs.rs"]
mod device_attrs;

#[path = "include/vt_compliance_cursor_movement.rs"]
mod cursor_movement;

#[path = "include/vt_compliance_save_restore.rs"]
mod save_restore;

#[path = "include/vt_compliance_ext.rs"]
mod ext;
