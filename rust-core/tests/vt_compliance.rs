//! VT100/VT220 compliance test suite
//!
//! Tests terminal emulator compliance with VT100/VT220 standards.
//! These tests exercise the full advance() pipeline without any Emacs runtime.

use kuro_core::TerminalCore;

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
    assert!(t.current_attrs().bold);
}

#[test]
fn vt_sgr_reset() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;3;4m");
    assert!(t.current_attrs().bold);
    assert!(t.current_attrs().italic);
    t.advance(b"\x1b[0m");
    assert!(!t.current_attrs().bold);
    assert!(!t.current_attrs().italic);
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

#[test]
fn vt_decckm_app_cursor() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1h");
    assert!(t.dec_modes().app_cursor_keys);
    t.advance(b"\x1b[?1l");
    assert!(!t.dec_modes().app_cursor_keys);
}

#[test]
fn vt_decawm_auto_wrap() {
    let mut t = TerminalCore::new(24, 80);
    assert!(t.dec_modes().auto_wrap); // default on
    t.advance(b"\x1b[?7l");
    assert!(!t.dec_modes().auto_wrap);
    t.advance(b"\x1b[?7h");
    assert!(t.dec_modes().auto_wrap);
}

#[test]
fn vt_bracketed_paste() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?2004h");
    assert!(t.dec_modes().bracketed_paste);
    t.advance(b"\x1b[?2004l");
    assert!(!t.dec_modes().bracketed_paste);
}

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

// === DECSC/DECRC ===

#[test]
fn vt_save_restore_cursor() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[10;20H\x1b7\x1b[1;1H\x1b8");
    assert_eq!(t.cursor_row(), 9);
    assert_eq!(t.cursor_col(), 19);
}

// === Mouse Tracking ===

#[test]
fn vt_mouse_modes() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1000h");
    assert_eq!(t.dec_modes().mouse_mode, 1000);
    t.advance(b"\x1b[?1000l");
    assert_eq!(t.dec_modes().mouse_mode, 0);
    t.advance(b"\x1b[?1002h");
    assert_eq!(t.dec_modes().mouse_mode, 1002);
    t.advance(b"\x1b[?1006h");
    assert!(t.dec_modes().mouse_sgr);
}

// === VT220 Extensions ===

#[test]
fn vt_decscusr_cursor_shape() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[5 q");
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::BlinkingBar
    );
    t.advance(b"\x1b[2 q");
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::SteadyBlock
    );
    t.advance(b"\x1b[3 q");
    assert_eq!(
        t.dec_modes().cursor_shape,
        kuro_core::types::cursor::CursorShape::BlinkingUnderline
    );
}

#[test]
fn vt_decstr_soft_reset() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1h\x1b[1m\x1b[10;20H");
    t.advance(b"\x1b[!p");
    assert!(!t.dec_modes().app_cursor_keys);
    assert!(!t.current_attrs().bold);
    assert_eq!(t.cursor_row(), 0);
    assert!(t.dec_modes().auto_wrap);
}

// === Modern Terminal Features ===

#[test]
fn vt_kitty_keyboard_protocol() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[>1u");
    assert_eq!(t.dec_modes().keyboard_flags, 1);
    t.advance(b"\x1b[>3u");
    assert_eq!(t.dec_modes().keyboard_flags, 3);
    t.advance(b"\x1b[<u");
    assert_eq!(t.dec_modes().keyboard_flags, 1);
    t.advance(b"\x1b[<u");
    assert_eq!(t.dec_modes().keyboard_flags, 0);
}

#[test]
fn vt_kitty_keyboard_query() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[>5u");
    t.advance(b"\x1b[?u");
    assert!(!t.pending_responses().is_empty());
    assert_eq!(t.pending_responses().last().unwrap(), b"\x1b[?5u");
}

#[test]
fn vt_osc7_cwd() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]7;file://localhost/tmp/test\x07");
    assert_eq!(t.osc_data().cwd, Some("/tmp/test".to_string()));
    assert!(t.osc_data().cwd_dirty);
}

#[test]
fn vt_osc8_hyperlink() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]8;;https://example.com\x07");
    assert_eq!(
        t.osc_data().hyperlink.uri,
        Some("https://example.com".to_string())
    );
    t.advance(b"\x1b]8;;\x07");
    assert!(t.osc_data().hyperlink.uri.is_none());
}

#[test]
fn vt_osc133_prompt_marks() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]133;A\x07");
    assert_eq!(t.osc_data().prompt_marks.len(), 1);
}

#[test]
fn vt_focus_events() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?1004h");
    assert!(t.dec_modes().focus_events);
    t.advance(b"\x1b[?1004l");
    assert!(!t.dec_modes().focus_events);
}

#[test]
fn vt_synchronized_output() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?2026h");
    assert!(t.dec_modes().synchronized_output);
    t.advance(b"\x1b[?2026l");
    assert!(!t.dec_modes().synchronized_output);
}

#[test]
fn vt_decom_origin_mode() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?6h");
    assert!(t.dec_modes().origin_mode);
    t.advance(b"\x1b[?6l");
    assert!(!t.dec_modes().origin_mode);
}

#[test]
fn vt_underline_styles() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4:3m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::types::cell::UnderlineStyle::Curly
    );
    t.advance(b"\x1b[4:5m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::types::cell::UnderlineStyle::Dashed
    );
    t.advance(b"\x1b[21m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::types::cell::UnderlineStyle::Double
    );
    t.advance(b"\x1b[24m");
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::types::cell::UnderlineStyle::None
    );
}

#[test]
fn vt_underline_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[58;2;255;128;0m");
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::types::color::Color::Rgb(255, 128, 0)
    );
    t.advance(b"\x1b[59m");
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::types::color::Color::Default
    );
}

#[test]
fn vt_wide_char() {
    let mut t = TerminalCore::new(24, 80);
    t.advance("漢".as_bytes());
    assert_eq!(t.get_cell(0, 0).unwrap().char(), '漢');
}

#[test]
fn vt_combining_char() {
    let mut t = TerminalCore::new(24, 80);
    t.advance("e\u{0301}".as_bytes());
    assert_eq!(t.get_cell(0, 0).unwrap().grapheme.as_str(), "e\u{0301}");
}

#[test]
fn vt_title_set() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]2;My Terminal\x07");
    assert_eq!(t.title(), "My Terminal");
    assert!(t.title_dirty());
}

#[test]
fn vt_full_reset() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1m\x1b[?1h");
    t.advance(b"\x1bc"); // RIS - full reset
    assert!(!t.current_attrs().bold);
    assert!(!t.dec_modes().app_cursor_keys);
}
