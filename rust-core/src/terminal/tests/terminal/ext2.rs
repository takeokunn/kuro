use super::super::make_term;
use super::*;

#[test]
fn test_resize_updates_tab_stops() {
    let mut term = make_term();
    term.resize(24, 40);
    // Tab every 8 columns — the first tab stop after resize should be at col 8.
    term.advance(b"\x1b[1;1H"); // cursor to col 0
    term.advance(b"\t"); // advance to first tab stop
    assert_eq!(
        term.screen.cursor().col,
        8,
        "first tab stop on a 40-col terminal must be at col 8"
    );
}

/// `flush_print_buf` with an empty buffer is a no-op.
#[test]
fn test_flush_print_buf_empty_is_noop() {
    let mut term = make_term();
    assert!(term.print_buf.is_empty(), "print_buf must start empty");
    term.flush_print_buf(); // must not panic, must not change cursor
    assert_cursor!(term, row 0, col 0);
}

/// `flush_print_buf` flushes buffered ASCII to the screen and clears the buffer.
#[test]
fn test_flush_print_buf_writes_content() {
    let mut term = make_term();
    term.print_buf.extend_from_slice(b"ABC");
    assert_eq!(
        term.print_buf.len(),
        3,
        "buffer must hold 3 bytes before flush"
    );
    term.flush_print_buf();
    assert!(
        term.print_buf.is_empty(),
        "flush_print_buf must clear print_buf"
    );
    // The three ASCII chars must now be on the screen.
    assert_cell_char!(term, row 0, col 0, 'A');
    assert_cell_char!(term, row 0, col 1, 'B');
    assert_cell_char!(term, row 0, col 2, 'C');
}

/// `scrollback_chars` returns character rows for content that was scrolled off.
#[test]
fn test_scrollback_chars_returns_pushed_lines() {
    let mut term = make_term();
    term.advance(b"SCROLLED");
    // Push the line into scrollback with 24 newlines.
    for _ in 0..24 {
        term.advance(b"\n");
    }
    let chars = term.scrollback_chars(100);
    assert!(
        !chars.is_empty(),
        "scrollback_chars must be non-empty after scrolling content off-screen"
    );
    // The first scrolled line must contain our marker.
    let has_marker = chars
        .iter()
        .any(|row| row.iter().collect::<String>().contains("SCROLLED"));
    assert!(
        has_marker,
        "scrollback_chars must include the 'SCROLLED' marker line"
    );
}

/// `scrollback_chars` with `max_lines=0` returns an empty vec.
#[test]
fn test_scrollback_chars_max_lines_zero() {
    let mut term = make_term();
    term.advance(b"line\n");
    for _ in 0..24 {
        term.advance(b"\n");
    }
    let chars = term.scrollback_chars(0);
    assert!(
        chars.is_empty(),
        "scrollback_chars(0) must return an empty vec"
    );
}

/// `title()` and `title_dirty()` reflect OSC 2 sequences.
#[test]
fn test_title_and_title_dirty_accessors() {
    let mut term = make_term();
    assert_eq!(term.title(), "", "title must be empty initially");
    assert!(!term.title_dirty(), "title_dirty must be false initially");

    term.advance(b"\x1b]2;MyTitle\x07");
    assert_eq!(term.title(), "MyTitle", "title must match OSC 2 payload");
    assert!(
        term.title_dirty(),
        "title_dirty must be true after OSC 2 sets a title"
    );
}

/// `palette_dirty()` is false initially and true after OSC 4.
#[test]
fn test_palette_dirty_accessor() {
    let mut term = make_term();
    assert!(
        !term.palette_dirty(),
        "palette_dirty must be false initially"
    );

    term.advance(b"\x1b]4;1;rgb:ff/00/00\x1b\\"); // OSC 4 sets palette entry 1
    assert!(
        term.palette_dirty(),
        "palette_dirty must be true after OSC 4"
    );
}

/// `default_colors_dirty()` is false initially and true after OSC 10.
#[test]
fn test_default_colors_dirty_accessor() {
    let mut term = make_term();
    assert!(
        !term.default_colors_dirty(),
        "default_colors_dirty must be false initially"
    );

    term.advance(b"\x1b]10;rgb:ff/80/00\x07"); // OSC 10 sets default fg
    assert!(
        term.default_colors_dirty(),
        "default_colors_dirty must be true after OSC 10"
    );
}

/// `pending_responses()` returns a slice of queued responses.
#[test]
fn test_pending_responses_accessor() {
    let mut term = make_term();
    assert!(
        term.pending_responses().is_empty(),
        "pending_responses must be empty initially"
    );

    term.advance(b"\x1b[6n"); // DSR — queues a CPR response
    assert_eq!(
        term.pending_responses().len(),
        1,
        "pending_responses must hold 1 entry after DSR"
    );
}

/// `current_foreground()` returns `Color::Default` initially.
#[test]
fn test_current_foreground_default() {
    let term = make_term();
    assert_eq!(
        *term.current_foreground(),
        crate::types::Color::Default,
        "current_foreground must be Color::Default initially"
    );
}

/// After SGR 31 (red foreground), `current_foreground()` is a Named color.
#[test]
fn test_current_foreground_after_sgr31() {
    let mut term = make_term();
    term.advance(b"\x1b[31m"); // SGR 31: red foreground
    assert!(
        matches!(*term.current_foreground(), crate::types::Color::Named(_)),
        "current_foreground must be a Named color after SGR 31, got {:?}",
        term.current_foreground()
    );
}

/// `dec_modes()` accessor returns the live DecModes ref.
#[test]
fn test_dec_modes_accessor_reflects_live_state() {
    let mut term = make_term();
    assert!(
        term.dec_modes().cursor_visible,
        "cursor_visible must be true initially"
    );
    term.advance(b"\x1b[?25l"); // DECTCEM off
    assert!(
        !term.dec_modes().cursor_visible,
        "dec_modes().cursor_visible must be false after CSI ?25l"
    );
}

/// `current_attrs()` accessor returns the live SgrAttributes ref.
#[test]
fn test_current_attrs_accessor_reflects_sgr() {
    let mut term = make_term();
    assert!(
        !term.current_attrs().flags.contains(SgrFlags::BOLD),
        "bold must be clear initially"
    );
    term.advance(b"\x1b[1m"); // bold on
    assert!(
        term.current_attrs().flags.contains(SgrFlags::BOLD),
        "current_attrs() must reflect bold after SGR 1"
    );
}

/// `osc_data()` accessor returns the live OscData ref (CWD example).
#[test]
fn test_osc_data_accessor_reflects_osc7() {
    let mut term = make_term();
    assert!(
        term.osc_data().cwd.is_none(),
        "osc_data().cwd must be None initially"
    );
    term.advance(b"\x1b]7;file://localhost/tmp\x07");
    assert!(
        term.osc_data().cwd.is_some(),
        "osc_data().cwd must be Some after OSC 7"
    );
}

/// `soft_reset` clears `saved_primary_attrs` (the alt-screen SGR snapshot).
#[test]
fn test_soft_reset_clears_saved_primary_attrs() {
    let mut term = make_term();
    // Force-set saved_primary_attrs to simulate a previous alt-screen save.
    term.saved_primary_attrs = Some(crate::types::cell::SgrAttributes::default());
    assert!(
        term.saved_primary_attrs.is_some(),
        "pre-condition: saved_primary_attrs must be Some"
    );
    term.advance(b"\x1b[!p"); // DECSTR (soft reset)
    assert!(
        term.saved_primary_attrs.is_none(),
        "soft_reset must clear saved_primary_attrs"
    );
}

/// After `reset()`, `parser_in_ground` is `true` and `print_buf` is empty.
#[test]
fn test_reset_restores_parser_state() {
    let mut term = make_term();
    // Corrupt parser state manually to simulate mid-sequence input.
    term.parser_in_ground = false;
    term.print_buf.extend_from_slice(b"leftover");

    term.reset();

    assert!(
        term.parser_in_ground,
        "reset must set parser_in_ground to true"
    );
    assert!(term.print_buf.is_empty(), "reset must clear print_buf");
}
