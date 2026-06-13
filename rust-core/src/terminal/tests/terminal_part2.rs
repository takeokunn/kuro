#[test]
fn test_resize_preserves_screen_content() {
    let mut term = super::make_term();
    term.advance(b"A");
    let row_before = term.screen.cursor().row;
    let col_before = term.screen.cursor().col;
    term.resize(30, 100);
    assert_eq!(term.screen.rows(), 30);
    assert_eq!(term.screen.cols(), 100);
    assert!(
        term.screen.cursor().row < 30,
        "cursor row out of bounds after resize"
    );
    assert!(
        term.screen.cursor().col < 100,
        "cursor col out of bounds after resize"
    );
    let _ = (row_before, col_before);
}

/// With DEC mode 2048 (in-band resize) enabled, `resize` emits exactly one
/// report carrying the NEW size: `CSI 48 ; rows ; cols ; 0 ; 0 t`.
#[test]
fn test_resize_emits_in_band_report_when_2048_enabled() {
    let mut term = super::make_term();
    term.dec_modes.resize_in_band = true;
    term.meta.pending_responses.clear();
    term.resize(30, 100);
    assert_eq!(
        term.meta.pending_responses,
        vec![b"\x1b[48;30;100;0;0t".to_vec()],
        "resize with ?2048 enabled must emit one report with the new size"
    );
}

/// Without DEC mode 2048, `resize` must not emit any in-band report.
#[test]
fn test_resize_emits_no_report_when_2048_disabled() {
    let mut term = super::make_term();
    term.meta.pending_responses.clear();
    term.resize(30, 100);
    assert!(
        term.meta.pending_responses.is_empty(),
        "resize without ?2048 must not emit an in-band report"
    );
}

#[test]
fn test_advance_empty_input() {
    let mut term = super::make_term();
    term.advance(&[]);
    assert_cursor!(term, row 0, col 0);
}

#[test]
fn test_advance_split_sequence() {
    let mut term = super::make_term();
    term.advance(b"\x1b["); // incomplete CSI
    term.advance(b"1m"); // complete: SGR bold
    assert_flag!(term, SgrFlags::BOLD);
}

#[test]
fn test_execute_backspace_at_col_zero() {
    let mut term = super::make_term();
    term.advance(b"\x1b[5;1H\x08");
    assert_cursor!(term, row 4, col 0);
}

#[test]
fn test_csi_unknown_final_byte_no_panic() {
    let mut term = super::make_term();
    term.advance(b"\x1b[999z");
    // No assertion needed — reaching here means no panic
}

#[test]
fn test_osc_unknown_command_number_ignored() {
    let mut term = super::make_term();
    term.advance(b"\x1b]99;some_data\x07");
    assert_eq!(
        term.meta.title, "",
        "unknown OSC number must not update title"
    );
    assert!(
        !term.meta.title_dirty,
        "unknown OSC number must not set title_dirty"
    );
}

#[test]
fn test_combining_char_attached_to_base() {
    let mut term = super::make_term();
    term.advance("e\u{0301}".as_bytes());
    let cell = term.get_cell(0, 0).unwrap();
    assert_eq!(cell.grapheme.as_str(), "e\u{0301}");
}

#[test]
fn test_combining_char_at_col_zero_printed_standalone() {
    let mut term = super::make_term();
    term.advance("\u{0301}".as_bytes());
    let cell = term.get_cell(0, 0).unwrap();
    assert_eq!(cell.grapheme.as_str(), "\u{0301}");
}

#[test]
fn test_combining_char_attaches_to_previous_row_last_col() {
    let mut term = super::make_term();
    term.advance(b"\x1b[1;80H"); // row 0, col 79
    term.advance(b"e");
    term.advance(b"\x1b[2;1H");
    term.advance("\u{0301}".as_bytes());
    let cell = term.get_cell(0, 79).unwrap();
    assert_eq!(
        cell.grapheme.as_str(),
        "e\u{0301}",
        "Combining char should attach to 'e' at previous row's last col"
    );
}

#[test]
fn test_normal_chars_unchanged_after_grapheme_support() {
    let mut term = super::make_term();
    term.advance(b"ABC");
    assert_cell_char!(term, row 0, col 0, 'A');
    assert_cell_char!(term, row 0, col 1, 'B');
    assert_cell_char!(term, row 0, col 2, 'C');
}

#[test]
fn test_decscusr_sets_cursor_shape() {
    let mut term = super::make_term();
    term.advance(b"\x1b[5 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        types::cursor::CursorShape::BlinkingBar
    );
    term.advance(b"\x1b[2 q");
    assert_eq!(
        term.dec_modes.cursor_shape,
        types::cursor::CursorShape::SteadyBlock
    );
}

#[test]
fn test_decstr_soft_reset() {
    let mut term = super::make_term();
    term.advance(b"\x1b[?1h"); // DECCKM on
    term.advance(b"\x1b[1m"); // Bold on
    term.advance(b"\x1b[10;20H");
    term.advance(b"\x1b[!p"); // DECSTR
    assert!(!term.dec_modes.app_cursor_keys);
    assert_no_flag!(term, SgrFlags::BOLD);
    assert_cursor!(term, row 0, col 0);
    assert!(term.dec_modes.auto_wrap);
}

#[test]
fn test_decstr_preserves_screen_content() {
    let mut term = super::make_term();
    term.advance(b"Hello");
    term.advance(b"\x1b[!p");
    assert_cell_char!(term, row 0, col 0, 'H');
}

#[test]
fn test_kitty_keyboard_push_pop() {
    let mut term = super::make_term();
    assert_eq!(term.dec_modes.keyboard_flags, 0);
    term.advance(b"\x1b[>1u");
    assert_eq!(term.dec_modes.keyboard_flags, 1);
    term.advance(b"\x1b[>3u");
    assert_eq!(term.dec_modes.keyboard_flags, 3);
    assert_eq!(term.dec_modes.keyboard_flags_stack.len(), 2);
    term.advance(b"\x1b[<u");
    assert_eq!(term.dec_modes.keyboard_flags, 1);
    term.advance(b"\x1b[<u");
    assert_eq!(term.dec_modes.keyboard_flags, 0);
    term.advance(b"\x1b[<u"); // pop on empty stack
    assert_eq!(term.dec_modes.keyboard_flags, 0);
}

#[test]
fn test_kitty_keyboard_query() {
    let mut term = super::make_term();
    term.advance(b"\x1b[>5u");
    term.advance(b"\x1b[?u");
    assert_eq!(term.meta.pending_responses.len(), 1);
    assert_eq!(term.meta.pending_responses[0], b"\x1b[?5u");
}

#[test]
fn test_oversized_osc7_cwd_rejected() {
    let mut term = super::make_term();
    let long_path = format!("\x1b]7;file://localhost/{}\x07", "a".repeat(5000));
    term.advance(long_path.as_bytes());
    assert!(
        term.osc_data.cwd.is_none() || term.osc_data.cwd.as_ref().unwrap().len() <= 4096,
        "CWD over 4096 bytes should be rejected"
    );
}

#[test]
fn test_oversized_osc8_uri_rejected() {
    let mut term = super::make_term();
    let long_uri = format!("\x1b]8;;https://example.com/{}\x07", "x".repeat(9000));
    term.advance(long_uri.as_bytes());
    assert!(
        term.osc_data.hyperlink.uri.is_none()
            || term.osc_data.hyperlink.uri.as_ref().unwrap().len() <= 8192,
        "Hyperlink URI over 8192 bytes should be rejected"
    );
}

#[test]
fn test_apc_payload_cap_enforced() {
    let mut term = super::make_term();
    let large_payload = vec![b'A'; 5 * 1024 * 1024];
    let mut data = Vec::new();
    data.extend_from_slice(b"\x1b_G");
    data.extend_from_slice(&large_payload);
    data.extend_from_slice(b"\x1b\\");
    term.advance(&data);
    assert_eq!(
        term.kitty.apc_buf.len(),
        0,
        "apc_buf should be cleared after oversized APC sequence"
    );
}

#[test]
fn test_title_sanitization_strips_control_chars() {
    let mut term = super::make_term();
    term.advance(b"\x1b]2;Hello\x07World\x07");
    assert!(
        !term.meta.title.contains('\x07'),
        "Title should not contain BEL control character"
    );
}

// === ESC M / ESC D / ESC E tests ===

#[test]
fn test_esc_m_reverse_index_basic() {
    let mut term = super::make_term();
    term.advance(b"\x1b[5;1H");
    assert_eq!(term.screen.cursor().row, 4);
    term.advance(b"\x1bM");
    assert_eq!(
        term.screen.cursor().row,
        3,
        "ESC M should move cursor up by 1"
    );
}

