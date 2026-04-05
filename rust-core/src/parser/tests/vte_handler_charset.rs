// ── DEC line drawing charset tests ──────────────────────────────────────────

/// ESC(0 activates DEC line drawing; 'j' (0x6A) should become '┘'.
#[test]
fn dec_line_drawing_esc_0_translates_j_to_corner() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b(0j");
    assert_cell_char!(term, row 0, col 0, '\u{2518}');
}

/// ESC(B restores US ASCII; 'j' should be literal 'j' again.
#[test]
fn dec_line_drawing_esc_b_restores_ascii() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b(0j\x1b(Bj");
    assert_cell_char!(term, row 0, col 0, '\u{2518}');
    assert_cell_char!(term, row 0, col 1, 'j');
}

/// SO (0x0E) shifts GL to G1; SI (0x0F) shifts back to G0.
#[test]
fn dec_line_drawing_so_si_shift() {
    let mut term = TerminalCore::new(24, 80);
    // Designate G1 as DEC line drawing, then SO to activate G1
    term.advance(b"\x1b)0\x0Ej\x0Fj");
    assert_cell_char!(term, row 0, col 0, '\u{2518}');
    assert_cell_char!(term, row 0, col 1, 'j');
}

/// Draw a simple box using DEC line drawing characters.
#[test]
fn dec_line_drawing_full_box() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b(0lqk\r\nx x\r\nmqj\x1b(B");
    // Row 0: ┌─┐
    assert_cell_char!(term, row 0, col 0, '\u{250C}');
    assert_cell_char!(term, row 0, col 1, '\u{2500}');
    assert_cell_char!(term, row 0, col 2, '\u{2510}');
    // Row 1: │ │
    assert_cell_char!(term, row 1, col 0, '\u{2502}');
    assert_cell_char!(term, row 1, col 2, '\u{2502}');
    // Row 2: └─┘
    assert_cell_char!(term, row 2, col 0, '\u{2514}');
    assert_cell_char!(term, row 2, col 1, '\u{2500}');
    assert_cell_char!(term, row 2, col 2, '\u{2518}');
}

/// Characters outside the 0x60-0x7E range pass through unchanged in line drawing mode.
#[test]
fn dec_line_drawing_non_translated_range_passes_through() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b(0A");
    assert_cell_char!(term, row 0, col 0, 'A');
}

/// RIS (ESC c) resets charset state back to ASCII.
#[test]
fn dec_line_drawing_reset_clears_charset() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b(0");
    term.advance(b"\x1bc"); // RIS
    term.advance(b"j");
    assert_cell_char!(term, row 0, col 0, 'j');
}

/// DECSTR (CSI ! p) resets charset state back to ASCII.
#[test]
fn dec_line_drawing_soft_reset_clears_charset() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b(0");
    term.advance(b"\x1b[!p"); // DECSTR
    term.advance(b"j");
    assert_cell_char!(term, row 0, col 0, 'j');
}

/// Line drawing mode translates all characters in the 0x60-0x7E range.
#[test]
fn dec_line_drawing_translates_backtick_to_diamond() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b(0`");
    assert_cell_char!(term, row 0, col 0, '\u{25C6}');
}

/// Line drawing 'n' (0x6E) should become ┼ (crossing lines).
#[test]
fn dec_line_drawing_crossing_lines() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b(0n");
    assert_cell_char!(term, row 0, col 0, '\u{253C}');
}

/// Tee characters: t=├, u=┤, v=┴, w=┬.
#[test]
fn dec_line_drawing_tee_characters() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b(0tuvw");
    assert_cell_char!(term, row 0, col 0, '\u{251C}');
    assert_cell_char!(term, row 0, col 1, '\u{2524}');
    assert_cell_char!(term, row 0, col 2, '\u{2534}');
    assert_cell_char!(term, row 0, col 3, '\u{252C}');
}

/// SO without prior G1 designation uses default ASCII — no translation.
#[test]
fn so_without_g1_designation_is_ascii() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x0Ej"); // SO with G1 still ASCII
    assert_cell_char!(term, row 0, col 0, 'j');
}

/// G0 and G1 can have independent charset designations.
#[test]
fn g0_g1_independent_designations() {
    let mut term = TerminalCore::new(24, 80);
    // G0 = line drawing, G1 = ASCII (separate advance calls to avoid VTE confusion)
    term.advance(b"\x1b(0");
    term.advance(b"\x1b)B");
    // In G0 (default GL): line drawing active
    term.advance(b"j");
    assert_cell_char!(term, row 0, col 0, '\u{2518}');
    // Switch to G1 via SO: ASCII
    term.advance(b"\x0Ej");
    assert_cell_char!(term, row 0, col 1, 'j');
    // Switch back to G0 via SI: line drawing again
    term.advance(b"\x0Fj");
    assert_cell_char!(term, row 0, col 2, '\u{2518}');
}

/// RIS also resets GL shift state (SO/SI).
#[test]
fn reset_clears_gl_shift_state() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b)0\x0E"); // G1=line drawing, SO
    term.advance(b"\x1bc"); // RIS
    term.advance(b"j");
    assert_cell_char!(term, row 0, col 0, 'j');
}

/// Soft reset also resets GL shift state (SO/SI).
#[test]
fn soft_reset_clears_gl_shift_state() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b)0\x0E"); // G1=line drawing, SO
    term.advance(b"\x1b[!p"); // DECSTR
    term.advance(b"j");
    assert_cell_char!(term, row 0, col 0, 'j');
}

// ── DECSC/DECRC charset save/restore tests ──────────────────────────────────

/// DECSC (ESC 7) saves G0 charset; DECRC (ESC 8) restores it.
#[test]
fn dec_line_drawing_decsc_saves_g0_charset() {
    let mut term = TerminalCore::new(24, 80);
    // Designate G0 = line drawing, then save
    term.advance(b"\x1b(0");
    term.advance(b"\x1b7"); // DECSC
    // Switch G0 back to ASCII
    term.advance(b"\x1b(B");
    // 'j' should be literal ASCII now
    term.advance(b"j");
    assert_cell_char!(term, row 0, col 0, 'j');
    // Restore — G0 should be line drawing again
    // NOTE: DECRC also restores cursor position (back to col 0),
    // so move cursor to col 1 first to avoid overwriting the 'j'.
    term.advance(b"\x1b8"); // DECRC
    term.advance(b"\x1b[1C"); // CUF 1: move cursor right to col 1
    term.advance(b"j");
    assert_cell_char!(term, row 0, col 1, '\u{2518}');
}

/// DECSC (ESC 7) saves G1 charset; DECRC (ESC 8) restores it.
#[test]
fn dec_line_drawing_decsc_saves_g1_charset() {
    let mut term = TerminalCore::new(24, 80);
    // Designate G1 = line drawing, then save
    term.advance(b"\x1b)0");
    term.advance(b"\x1b7"); // DECSC
    // Switch G1 back to ASCII
    term.advance(b"\x1b)B");
    // SO to use G1 — should be ASCII now
    term.advance(b"\x0Ej");
    assert_cell_char!(term, row 0, col 0, 'j');
    // SI back, then restore
    // NOTE: DECRC also restores cursor position (back to col 0).
    term.advance(b"\x0F");
    term.advance(b"\x1b8"); // DECRC
    term.advance(b"\x1b[1C"); // CUF 1: move cursor right to col 1
    // SO again — G1 should be line drawing again
    term.advance(b"\x0Ej");
    assert_cell_char!(term, row 0, col 1, '\u{2518}');
}

/// DECSC (ESC 7) saves GL shift state; DECRC (ESC 8) restores it.
#[test]
fn dec_line_drawing_decsc_saves_gl_shift() {
    let mut term = TerminalCore::new(24, 80);
    // Designate G1 = line drawing
    term.advance(b"\x1b)0");
    // SO to shift GL to G1, then save
    term.advance(b"\x0E");
    term.advance(b"\x1b7"); // DECSC
    // SI to shift GL back to G0
    term.advance(b"\x0F");
    // 'j' should be ASCII (GL=G0=ASCII)
    term.advance(b"j");
    assert_cell_char!(term, row 0, col 0, 'j');
    // Restore — GL should be G1 (line drawing) again
    // NOTE: DECRC also restores cursor position (back to col 0).
    term.advance(b"\x1b8"); // DECRC
    term.advance(b"\x1b[1C"); // CUF 1: move cursor right to col 1
    term.advance(b"j");
    assert_cell_char!(term, row 0, col 1, '\u{2518}');
}

/// DECRC (ESC 8) without prior DECSC leaves charset at defaults.
#[test]
fn dec_line_drawing_decrc_without_save_uses_defaults() {
    let mut term = TerminalCore::new(24, 80);
    // Set G0 to line drawing (no save)
    term.advance(b"\x1b(0");
    // DECRC without prior DECSC — charset state should NOT change
    // (no saved state to restore from)
    term.advance(b"\x1b8"); // DECRC
    // G0 should still be line drawing since nothing was saved/restored
    term.advance(b"j");
    assert_cell_char!(term, row 0, col 0, '\u{2518}');
}
