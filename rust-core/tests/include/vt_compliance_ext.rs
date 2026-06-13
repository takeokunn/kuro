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
    assert!(!t.current_attrs().flags.contains(SgrFlags::BOLD));
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
    assert_eq!(t.osc_data().cwd, Some("/tmp/test".to_owned()));
    assert!(t.osc_data().cwd_dirty);
}

#[test]
fn vt_osc8_hyperlink() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b]8;;https://example.com\x07");
    assert_eq!(
        t.osc_data().hyperlink.uri.as_deref(),
        Some("https://example.com")
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

// === DEC mode 2031 — Color Scheme Notifications (Contour/Ghostty) ===

#[test]
fn dec_mode_2031_set_stores_state() {
    let mut t = TerminalCore::new(24, 80);
    assert!(
        !t.dec_modes().color_scheme_notifications,
        "color_scheme_notifications must default to false"
    );
    t.advance(b"\x1b[?2031h");
    assert!(
        t.dec_modes().color_scheme_notifications,
        "?2031h must set color_scheme_notifications = true"
    );
    t.advance(b"\x1b[?2031l");
    assert!(
        !t.dec_modes().color_scheme_notifications,
        "?2031l must clear color_scheme_notifications"
    );
}

#[test]
fn dec_mode_2031_decrqm_reports_status() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?2031h");
    t.advance(b"\x1b[?2031$p");
    let resp = t
        .pending_responses()
        .last()
        .expect("DECRQM must emit a response for mode 2031");
    assert_eq!(
        resp.as_slice(),
        b"\x1b[?2031;1$y",
        "?2031 enabled must report status=1"
    );
    t.advance(b"\x1b[?2031l");
    t.advance(b"\x1b[?2031$p");
    let resp = t
        .pending_responses()
        .last()
        .expect("DECRQM must emit a response after reset");
    assert_eq!(
        resp.as_slice(),
        b"\x1b[?2031;2$y",
        "?2031 disabled must report status=2"
    );
}

#[test]
fn dsr_996_color_scheme_query_responds_dark() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[?996n");
    let resp = t
        .pending_responses()
        .last()
        .expect("DSR 996 must emit a response");
    assert_eq!(
        resp.as_slice(),
        b"\x1b[?997;1n",
        "DSR 996 must report dark (Ps=1) until theme detection is wired"
    );
}
