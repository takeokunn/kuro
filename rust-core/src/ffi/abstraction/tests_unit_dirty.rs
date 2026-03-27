// ---------------------------------------------------------------------------
// get_dirty_lines: text-only encoding (no face ranges)
// ---------------------------------------------------------------------------

/// `get_dirty_lines` returns `(row, text)` tuples for dirty rows.
///
/// Verifies the basic contract: after writing to the terminal, exactly the
/// written row is returned and the text matches the cell content.
#[test]
fn test_get_dirty_lines_returns_dirty_rows() {
    let mut session = make_session();
    session.core.advance(b"Hello");

    let dirty = session.get_dirty_lines();
    assert!(
        !dirty.is_empty(),
        "get_dirty_lines must return at least one row after writing"
    );

    let row0 = dirty.iter().find(|(r, _)| *r == 0);
    assert!(row0.is_some(), "Row 0 must be present in get_dirty_lines");
    let (_, text) = row0.unwrap();
    assert!(
        text.starts_with("Hello"),
        "Row 0 text must start with 'Hello', got: {text:?}"
    );
}

/// After `get_dirty_lines` the dirty set is cleared; a second call returns empty.
#[test]
fn test_get_dirty_lines_clears_dirty_set() {
    let mut session = make_session();
    session.core.advance(b"ABC");

    let first = session.get_dirty_lines();
    assert!(!first.is_empty(), "First call must return dirty rows");

    let second = session.get_dirty_lines();
    assert!(
        second.is_empty(),
        "Second call with no changes must return empty (dirty set cleared)"
    );
}

/// `get_dirty_lines` on a fresh session returns rows marked dirty by init.
#[test]
fn test_get_dirty_lines_full_dirty_path() {
    let mut session = make_session();
    // full_dirty is set during construction; writing any content triggers it.
    session.core.advance(b"\x1b[?1049h"); // enter alt screen — sets full_dirty
    let dirty = session.get_dirty_lines();
    assert_eq!(dirty.len(), 24, "full_dirty path must return all 24 rows");
}

// ---------------------------------------------------------------------------
// get_scrollback / get_scrollback_count / clear_scrollback / set_scrollback_max_lines
// ---------------------------------------------------------------------------

/// `get_scrollback` returns lines pushed into scrollback.
#[test]
fn test_get_scrollback_returns_pushed_lines() {
    let mut session = make_session();

    // Write a distinctive line, then scroll it into scrollback.
    session.core.advance(b"SCROLLBACK_LINE");
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);

    let sb = session.get_scrollback(100);
    assert!(
        !sb.is_empty(),
        "get_scrollback must return non-empty vec after pushing lines"
    );
    assert!(
        sb.iter().any(|l| l.contains("SCROLLBACK_LINE")),
        "scrollback must contain the written line"
    );
}

/// `get_scrollback` is capped by `max_lines`.
#[test]
fn test_get_scrollback_respects_max_lines() {
    let mut session = make_session();

    // Push many lines into scrollback.
    for _ in 0..50 {
        session.core.advance(b"line\n");
    }

    let sb = session.get_scrollback(5);
    assert!(
        sb.len() <= 5,
        "get_scrollback must return at most max_lines entries, got {}",
        sb.len()
    );
}

/// `get_scrollback_count` returns non-zero after pushing lines.
#[test]
fn test_get_scrollback_count_nonzero_after_push() {
    let mut session = make_session();
    session.core.advance(b"line1\nline2\n");
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);

    assert!(
        session.get_scrollback_count() > 0,
        "scrollback_count must be > 0 after pushing lines into scrollback"
    );
}

/// `clear_scrollback` empties the scrollback buffer and resets the count.
#[test]
fn test_clear_scrollback_empties_buffer() {
    let mut session = make_session();

    // Push lines into scrollback.
    session.core.advance(b"Keep\n");
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);
    assert!(
        session.get_scrollback_count() > 0,
        "Pre-condition: scrollback must be non-empty before clear"
    );

    session.clear_scrollback();

    assert_eq!(
        session.get_scrollback_count(),
        0,
        "clear_scrollback must reset scrollback_count to 0"
    );
    assert!(
        session.get_scrollback(100).is_empty(),
        "clear_scrollback must empty the scrollback lines"
    );
}

/// `set_scrollback_max_lines(0)` causes `get_scrollback` to always return empty.
#[test]
fn test_set_scrollback_max_lines_zero_disables_scrollback() {
    let mut session = make_session();
    session.set_scrollback_max_lines(0);

    session.core.advance(b"line\n");
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);

    let sb = session.get_scrollback(100);
    assert!(
        sb.is_empty(),
        "set_scrollback_max_lines(0) must prevent scrollback accumulation"
    );
}

// ---------------------------------------------------------------------------
// scroll_offset / viewport_scroll_down
// ---------------------------------------------------------------------------

/// `scroll_offset` starts at 0 on a fresh session.
#[test]
fn test_scroll_offset_zero_initially() {
    let session = make_session();
    assert_eq!(
        session.scroll_offset(),
        0,
        "scroll_offset must be 0 on a fresh session"
    );
}

/// `viewport_scroll_up` increases offset; `viewport_scroll_down` decreases it.
#[test]
fn test_viewport_scroll_down_reduces_offset() {
    let mut session = make_session();

    // Push enough lines to have scrollback.
    for _ in 0..30 {
        session.core.advance(b"line\n");
    }

    session.viewport_scroll_up(5);
    let offset_after_up = session.scroll_offset();
    assert!(
        offset_after_up > 0,
        "viewport_scroll_up must increase scroll_offset"
    );

    session.viewport_scroll_down(3);
    let offset_after_down = session.scroll_offset();
    assert!(
        offset_after_down < offset_after_up,
        "viewport_scroll_down must decrease scroll_offset (was {offset_after_up}, now {offset_after_down})"
    );
}

/// `viewport_scroll_down` to 0 restores the live view (scroll_offset == 0).
#[test]
fn test_viewport_scroll_down_to_zero_restores_live() {
    let mut session = make_session();

    for _ in 0..30 {
        session.core.advance(b"line\n");
    }

    session.viewport_scroll_up(5);
    session.viewport_scroll_down(usize::MAX); // clamp to 0
    assert_eq!(
        session.scroll_offset(),
        0,
        "viewport_scroll_down past 0 must clamp offset to 0"
    );
}

// ---------------------------------------------------------------------------
// command() / pid()
// ---------------------------------------------------------------------------

/// `command()` returns the shell command string stored at construction.
#[test]
fn test_command_returns_stored_command() {
    let mut session = make_session();
    session.command = "fish".to_owned();
    assert_eq!(session.command(), "fish");
}

/// `command()` returns an empty string for sessions created with no command.
#[test]
fn test_command_empty_for_make_session() {
    let session = make_session();
    assert_eq!(
        session.command(),
        "",
        "make_session sets command to empty string"
    );
}

/// `pid()` returns `None` for test sessions with `pty: None`.
#[test]
fn test_pid_returns_none_without_pty() {
    let session = make_session();
    assert!(
        session.pid().is_none(),
        "pid() must return None when no PTY is attached"
    );
}

// ---------------------------------------------------------------------------
// get_palette_updates / get_default_colors
// ---------------------------------------------------------------------------

/// `get_palette_updates` returns empty vec when no OSC 4 has been sent.
#[test]
fn test_get_palette_updates_empty_initially() {
    let session = make_session();
    let updates = session.get_palette_updates();
    assert!(
        updates.is_empty(),
        "get_palette_updates must return empty vec on a fresh session"
    );
}

/// After OSC 4 sets palette entry 1, `get_palette_updates` includes that entry.
#[test]
fn test_get_palette_updates_after_osc4() {
    let mut session = make_session();
    // OSC 4 ; 1 ; rgb:ff/00/00 ST
    session.core.advance(b"\x1b]4;1;rgb:ff/00/00\x1b\\");

    let updates = session.get_palette_updates();
    assert!(
        updates
            .iter()
            .any(|(idx, r, g, b)| *idx == 1 && *r == 0xff && *g == 0 && *b == 0),
        "get_palette_updates must include index=1 with rgb(255,0,0) after OSC 4"
    );
}

/// `get_default_colors` returns the `0xFF00_0000` sentinel when no OSC 10/11/12 set.
#[test]
fn test_get_default_colors_sentinel_when_unset() {
    let session = make_session();
    let (fg, bg, cursor) = session.get_default_colors();
    assert_eq!(
        fg, 0xFF00_0000u32,
        "Default fg must be 0xFF00_0000 when no OSC 10 was sent"
    );
    assert_eq!(
        bg, 0xFF00_0000u32,
        "Default bg must be 0xFF00_0000 when no OSC 11 was sent"
    );
    assert_eq!(
        cursor, 0xFF00_0000u32,
        "Default cursor color must be 0xFF00_0000 when no OSC 12 was sent"
    );
}

/// After OSC 10 sets default fg, `get_default_colors` returns the new value.
#[test]
fn test_get_default_colors_after_osc10() {
    let mut session = make_session();
    session.core.advance(b"\x1b]10;rgb:ff/80/00\x07");

    let (fg, _bg, _cursor) = session.get_default_colors();
    assert_ne!(
        fg, 0xFF00_0000u32,
        "get_default_colors fg must not be the sentinel after OSC 10"
    );
}

// ---------------------------------------------------------------------------
// DEC mode accessor smoke tests
// ---------------------------------------------------------------------------

/// All DEC mode accessors return their expected defaults on a fresh session.
#[test]
fn test_dec_mode_accessors_initial_defaults() {
    let session = make_session();

    assert!(!session.get_mouse_pixel(), "mouse_pixel defaults to false");
    assert_eq!(session.get_mouse_mode(), 0, "mouse_mode defaults to 0");
    assert!(!session.get_mouse_sgr(), "mouse_sgr defaults to false");
    assert!(
        !session.get_app_cursor_keys(),
        "app_cursor_keys defaults to false"
    );
    assert!(!session.get_app_keypad(), "app_keypad defaults to false");
    assert_eq!(
        session.get_keyboard_flags(),
        0,
        "keyboard_flags defaults to 0"
    );
    assert!(
        !session.get_bracketed_paste(),
        "bracketed_paste defaults to false"
    );
    assert!(
        !session.get_focus_events(),
        "focus_events defaults to false"
    );
    assert!(
        !session.get_synchronized_output(),
        "synchronized_output defaults to false"
    );
}

/// `get_cursor_shape` starts at `BlinkingBlock`.
#[test]
fn test_get_cursor_shape_default() {
    use crate::types::cursor::CursorShape;
    let session = make_session();
    assert_eq!(
        session.get_cursor_shape(),
        CursorShape::BlinkingBlock,
        "cursor_shape must default to BlinkingBlock"
    );
}

/// `get_app_cursor_keys` returns `true` after `CSI ?1h` (DECCKM set).
#[test]
fn test_get_app_cursor_keys_set_by_decckm() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1h"); // DECCKM on
    assert!(
        session.get_app_cursor_keys(),
        "get_app_cursor_keys must return true after CSI ?1h"
    );
    session.core.advance(b"\x1b[?1l"); // DECCKM off
    assert!(
        !session.get_app_cursor_keys(),
        "get_app_cursor_keys must return false after CSI ?1l"
    );
}

/// `get_bracketed_paste` returns `true` after `CSI ?2004h`.
#[test]
fn test_get_bracketed_paste_set_by_mode() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?2004h");
    assert!(
        session.get_bracketed_paste(),
        "get_bracketed_paste must return true after CSI ?2004h"
    );
}

/// `get_focus_events` returns `true` after `CSI ?1004h`.
#[test]
fn test_get_focus_events_set_by_mode() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1004h");
    assert!(
        session.get_focus_events(),
        "get_focus_events must return true after CSI ?1004h"
    );
}

/// `get_keyboard_flags` reflects the kitty keyboard flags pushed by `CSI > Ps u`.
#[test]
fn test_get_keyboard_flags_after_push() {
    let mut session = make_session();
    session.core.advance(b"\x1b[>5u"); // push flags=5
    assert_eq!(
        session.get_keyboard_flags(),
        5,
        "get_keyboard_flags must return 5 after CSI >5u"
    );
}

// ---------------------------------------------------------------------------
// take_prompt_marks: drain-once semantics
// ---------------------------------------------------------------------------

/// `take_prompt_marks` returns empty on a fresh session.
#[test]
fn test_take_prompt_marks_empty_initially() {
    let mut session = make_session();
    assert!(
        session.take_prompt_marks().is_empty(),
        "take_prompt_marks must return empty vec on a fresh session"
    );
}

/// `take_prompt_marks` returns an event after OSC 133 and drains the queue.
#[test]
fn test_take_prompt_marks_drains_after_osc133() {
    let mut session = make_session();
    session.core.advance(b"\x1b]133;A\x1b\\");
    assert_drain_once!(session, take_prompt_marks, vec);
}

// ---------------------------------------------------------------------------
// get_image_png_base64 / take_pending_image_notifications
// ---------------------------------------------------------------------------

/// `get_image_png_base64` returns empty string for unknown image IDs.
#[test]
fn test_get_image_png_base64_unknown_id_returns_empty() {
    let session = make_session();
    let result = session.get_image_png_base64(999_999);
    assert!(
        result.is_empty(),
        "get_image_png_base64 must return empty string for unknown image ID"
    );
}

/// `take_pending_image_notifications` returns empty vec on a fresh session.
#[test]
fn test_take_pending_image_notifications_empty_initially() {
    let mut session = make_session();
    let notifs = session.take_pending_image_notifications();
    assert!(
        notifs.is_empty(),
        "take_pending_image_notifications must return empty vec on a fresh session"
    );
}

// ---------------------------------------------------------------------------
// has_pending_output: non-unix stub
// ---------------------------------------------------------------------------

/// `has_pending_output` returns `false` on test sessions with no PTY.
#[test]
fn test_has_pending_output_false_without_pty() {
    let session = make_session();
    // On Unix, pty is None so has_pending_output checks pending_input + pty.
    // Both are empty/None → must return false.
    assert!(
        !session.has_pending_output(),
        "has_pending_output must return false for a test session with no PTY"
    );
}

// ---------------------------------------------------------------------------
// get_cursor / get_cursor_visible
// ---------------------------------------------------------------------------

/// `get_cursor` starts at (0, 0) on a fresh session.
#[test]
fn test_get_cursor_initial_position() {
    let session = make_session();
    assert_eq!(
        session.get_cursor(),
        (0, 0),
        "cursor must start at (row=0, col=0) on a fresh session"
    );
}

/// After writing 3 chars, `get_cursor` column advances to 3.
#[test]
fn test_get_cursor_advances_after_write() {
    let mut session = make_session();
    session.core.advance(b"ABC");
    let (row, col) = session.get_cursor();
    assert_eq!(row, 0, "cursor row must remain 0 after writing to line 0");
    assert_eq!(col, 3, "cursor col must be 3 after writing 3 ASCII chars");
}

/// `get_cursor` reflects `CUP` (CSI H) escape sequences correctly.
#[test]
fn test_get_cursor_reflects_cup_escape() {
    let mut session = make_session();
    session.core.advance(b"\x1b[5;10H"); // move to row 5, col 10 (1-based)
    let (row, col) = session.get_cursor();
    assert_eq!(row, 4, "CUP row 5 must map to 0-based row 4");
    assert_eq!(col, 9, "CUP col 10 must map to 0-based col 9");
}

/// `get_cursor_visible` is true by default (DECTCEM default = on).
#[test]
fn test_get_cursor_visible_default_true() {
    let session = make_session();
    assert!(
        session.get_cursor_visible(),
        "cursor must be visible by default (DECTCEM on)"
    );
}

/// `get_cursor_visible` returns `false` after `CSI ?25l`.
#[test]
fn test_get_cursor_visible_hidden_by_escape() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?25l"); // DECTCEM off
    assert!(
        !session.get_cursor_visible(),
        "get_cursor_visible must return false after CSI ?25l"
    );
    session.core.advance(b"\x1b[?25h"); // DECTCEM on
    assert!(
        session.get_cursor_visible(),
        "get_cursor_visible must return true after CSI ?25h"
    );
}

// ---------------------------------------------------------------------------
// resize: row-hash invalidation
// ---------------------------------------------------------------------------

/// After `resize`, `row_hashes` must be empty (cache invalidated).
#[test]
fn test_resize_clears_row_hashes() {
    let mut session = make_session();
    // Write content so row-hash cache gets populated via get_dirty_lines_with_faces.
    session.core.advance(b"Hello");
    let _ = session.get_dirty_lines_with_faces();
    // Cache may have entries now; resize must clear them.
    session
        .resize(30, 100)
        .expect("resize must not fail on test session");
    assert!(
        session.row_hashes.iter().all(|slot| slot.is_none()),
        "resize must invalidate all row_hashes cache entries"
    );
}

/// After `resize`, terminal dimensions reflect the new values.
#[test]
fn test_resize_updates_terminal_dimensions() {
    let mut session = make_session();
    session.resize(30, 120).expect("resize must not fail");
    assert_eq!(
        session.core.screen.rows(),
        30,
        "rows must be 30 after resize(30, 120)"
    );
    assert_eq!(
        session.core.screen.cols(),
        120,
        "cols must be 120 after resize(30, 120)"
    );
}

// ---------------------------------------------------------------------------
// get_app_keypad / get_mouse_sgr / get_mouse_pixel
// ---------------------------------------------------------------------------

/// `get_app_keypad` returns `true` after `CSI ?1h` (DECKPAM on = DECCKM also).
/// Use `ESC =` (application keypad) to set app_keypad mode directly.
#[test]
fn test_get_app_keypad_set_by_escape() {
    let mut session = make_session();
    session.core.advance(b"\x1b="); // DECKPAM (application keypad on)
    assert!(
        session.get_app_keypad(),
        "get_app_keypad must return true after ESC ="
    );
    session.core.advance(b"\x1b>"); // DECKPNM (numeric keypad)
    assert!(
        !session.get_app_keypad(),
        "get_app_keypad must return false after ESC >"
    );
}

/// `get_mouse_sgr` returns `true` after `CSI ?1006h` (SGR mouse encoding).
#[test]
fn test_get_mouse_sgr_set_by_mode() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1006h");
    assert!(
        session.get_mouse_sgr(),
        "get_mouse_sgr must return true after CSI ?1006h"
    );
    session.core.advance(b"\x1b[?1006l");
    assert!(
        !session.get_mouse_sgr(),
        "get_mouse_sgr must return false after CSI ?1006l"
    );
}

/// `get_mouse_mode` reflects mouse tracking mode set by `CSI ?1000h`.
#[test]
fn test_get_mouse_mode_set_by_mode_1000() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1000h"); // X10 mouse tracking
    assert_eq!(
        session.get_mouse_mode(),
        1000,
        "get_mouse_mode must return 1000 after CSI ?1000h"
    );
    session.core.advance(b"\x1b[?1000l");
    assert_eq!(
        session.get_mouse_mode(),
        0,
        "get_mouse_mode must return 0 after CSI ?1000l"
    );
}

// ---------------------------------------------------------------------------
// assert_rows_dirty! macro smoke test
// ---------------------------------------------------------------------------

/// `get_dirty_lines` returns row 0 dirty after writing to row 0.
#[test]
fn test_assert_rows_dirty_macro_row_zero() {
    let mut session = make_session();
    // Drain any initial full_dirty state.
    session.core.screen.take_dirty_lines();
    assert_rows_dirty!(session, advance b"Hello", rows [0]);
}

/// Writing to a specific row via CUP marks only that row dirty.
#[test]
fn test_assert_rows_dirty_macro_specific_row() {
    let mut session = make_session();
    // Drain full_dirty from session construction.
    session.core.screen.take_dirty_lines();
    // Move to row 3 (0-based), col 0, then write.
    assert_rows_dirty!(session, advance b"\x1b[4;1HContent", rows [3]);
}

// ---------------------------------------------------------------------------
// viewport_scroll_up additional tests
// ---------------------------------------------------------------------------

/// `viewport_scroll_up(3)` increases `scroll_offset` to 3 after scrollback exists.
#[test]
fn test_viewport_scroll_up_from_scrollback() {
    let mut session = make_session();
    // Scroll 5 lines into scrollback by printing 5*24 lines (each batch pushes 24 rows off).
    for _ in 0..5 {
        let newlines = b"\n".repeat(24);
        session.core.advance(&newlines);
    }
    assert!(
        session.core.screen.scrollback_line_count > 0,
        "scrollback must be non-empty before scroll_up"
    );
    session.viewport_scroll_up(3);
    assert_eq!(
        session.scroll_offset(),
        3,
        "viewport_scroll_up(3) must set scroll_offset to 3"
    );
}

/// `viewport_scroll_up(9999)` clamps the offset at `scrollback_line_count`.
#[test]
fn test_viewport_scroll_up_clamped_at_max() {
    let mut session = make_session();
    // Fill scrollback with plenty of lines.
    for _ in 0..10 {
        let newlines = b"\n".repeat(24);
        session.core.advance(&newlines);
    }
    let max = session.core.screen.scrollback_line_count;
    assert!(max > 0, "scrollback must be non-empty before clamping test");
    session.viewport_scroll_up(9999);
    assert_eq!(
        session.scroll_offset(),
        max,
        "viewport_scroll_up(9999) must clamp offset to scrollback_line_count ({max})"
    );
}

/// `viewport_scroll_up(2)` then `viewport_scroll_down(2)` returns offset to 0.
#[test]
fn test_viewport_scroll_up_then_down_restores_live() {
    let mut session = make_session();
    // Push scrollback.
    for _ in 0..5 {
        let newlines = b"\n".repeat(24);
        session.core.advance(&newlines);
    }
    session.viewport_scroll_up(2);
    assert_eq!(session.scroll_offset(), 2, "offset must be 2 after scroll_up");
    session.viewport_scroll_down(2);
    assert_eq!(
        session.scroll_offset(),
        0,
        "scroll_down(2) after scroll_up(2) must restore offset to 0"
    );
}

// ---------------------------------------------------------------------------
// get_synchronized_output mode getter
// ---------------------------------------------------------------------------

/// `get_synchronized_output` returns `false` on a fresh session.
#[test]
fn test_get_synchronized_output_initially_false() {
    let session = make_session();
    assert!(
        !session.get_synchronized_output(),
        "get_synchronized_output must return false on a fresh session"
    );
}

/// `get_synchronized_output` returns `true` after `CSI ?2026h`.
#[test]
fn test_get_synchronized_output_true_after_mode_set() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?2026h");
    assert!(
        session.get_synchronized_output(),
        "get_synchronized_output must return true after CSI ?2026h"
    );
}

/// `get_synchronized_output` returns `false` after set then reset with `CSI ?2026l`.
#[test]
fn test_get_synchronized_output_false_after_mode_reset() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?2026h");
    assert!(
        session.get_synchronized_output(),
        "get_synchronized_output must be true after ?2026h"
    );
    session.core.advance(b"\x1b[?2026l");
    assert!(
        !session.get_synchronized_output(),
        "get_synchronized_output must return false after CSI ?2026l"
    );
}

// ---------------------------------------------------------------------------
// get_mouse_pixel mode getter
// ---------------------------------------------------------------------------

/// `get_mouse_pixel` returns `false` on a fresh session.
#[test]
fn test_get_mouse_pixel_initially_false() {
    let session = make_session();
    assert!(
        !session.get_mouse_pixel(),
        "get_mouse_pixel must return false on a fresh session"
    );
}

/// `get_mouse_pixel` returns `true` after `CSI ?1016h`.
#[test]
fn test_get_mouse_pixel_true_after_mode_1016() {
    let mut session = make_session();
    session.core.advance(b"\x1b[?1016h");
    assert!(
        session.get_mouse_pixel(),
        "get_mouse_pixel must return true after CSI ?1016h"
    );
}

// ---------------------------------------------------------------------------
// encode_line_faces non-empty cell tests
// ---------------------------------------------------------------------------

/// Single ASCII cell 'A' with default attrs: text = "A", 1 face range, empty col_to_buf.
#[test]
fn test_encode_line_faces_single_ascii_cell() {
    use crate::types::cell::{Cell, SgrAttributes};
    let cells = vec![Cell::with_char_and_width(
        'A',
        SgrAttributes::default(),
        crate::types::cell::CellWidth::Half,
    )];
    let (row, text, face_ranges, col_to_buf) = TerminalSession::encode_line_faces(0, &cells);
    assert_eq!(row, 0, "row index must be passed through unchanged");
    assert_eq!(text, "A", "text must be the single character 'A'");
    assert_eq!(face_ranges.len(), 1, "single-cell line must produce exactly 1 face range");
    // ASCII fast-path: col_to_buf is empty (identity mapping implied).
    assert!(
        col_to_buf.is_empty(),
        "ASCII-only line must return empty col_to_buf (identity mapping)"
    );
}

/// A single wide (Full) cell followed by its Wide placeholder produces a
/// col_to_buf with 2 entries — one per display column.
#[test]
fn test_encode_line_faces_wide_char_has_col_to_buf_entry() {
    use crate::types::cell::{Cell, CellWidth, SgrAttributes};
    // Construct a wide character pair: Full cell + Wide placeholder.
    let full_cell = Cell::with_char_and_width('\u{3042}', SgrAttributes::default(), CellWidth::Full); // 'あ'
    let placeholder = Cell::with_char_and_width(' ', SgrAttributes::default(), CellWidth::Wide);
    let cells = vec![full_cell, placeholder];
    let (_row, text, _face_ranges, col_to_buf) = TerminalSession::encode_line_faces(0, &cells);
    assert_eq!(text, "\u{3042}", "wide char text must contain only the base character");
    assert_eq!(
        col_to_buf.len(),
        2,
        "col_to_buf must have 2 entries for a single wide character (one per display column)"
    );
}

/// A cell with `SgrFlags::BOLD` set must encode bit 0 in the face-range `flags` field.
#[test]
fn test_encode_line_faces_bold_cell_encodes_flag_in_attrs() {
    use crate::types::cell::{Cell, CellWidth, SgrAttributes, SgrFlags};
    let attrs = SgrAttributes {
        flags: SgrFlags::BOLD,
        ..SgrAttributes::default()
    };
    let cells = vec![Cell::with_char_and_width('X', attrs, CellWidth::Half)];
    let (_row, _text, face_ranges, _col_to_buf) = TerminalSession::encode_line_faces(0, &cells);
    assert_eq!(face_ranges.len(), 1, "bold cell must produce exactly 1 face range");
    let (_start, _end, _fg, _bg, flags, _ul_color) = face_ranges[0];
    assert_ne!(flags, 0, "face-range flags must be non-zero for a bold cell");
    // Bit 0 of the encoded attrs corresponds to BOLD (SgrFlags::BOLD = bit 0, maps to encode bit 0).
    assert_eq!(flags & 1, 1, "bit 0 of face-range flags must be set for BOLD");
}

// ---------------------------------------------------------------------------
// set_detached / set_bound: direct state-transition unit tests
// ---------------------------------------------------------------------------

/// A fresh session via `make_session()` is Bound, so `is_detached()` returns false.
#[test]
fn test_is_detached_false_on_fresh_session() {
    let session = make_session();
    assert!(
        !session.is_detached(),
        "is_detached() must return false on a freshly constructed (Bound) session"
    );
}

/// `set_detached()` transitions the session state so `is_detached()` returns true.
#[test]
fn test_set_detached_changes_state() {
    let mut session = make_session();
    assert!(
        !session.is_detached(),
        "pre-condition: session must be Bound before set_detached()"
    );
    session.set_detached();
    assert!(
        session.is_detached(),
        "is_detached() must return true after set_detached()"
    );
}

/// `set_bound()` after `set_detached()` reverses the state transition.
#[test]
fn test_set_bound_reverses_detach() {
    let mut session = make_session();
    session.set_detached();
    assert!(
        session.is_detached(),
        "pre-condition: session must be Detached before set_bound()"
    );
    session.set_bound();
    assert!(
        !session.is_detached(),
        "is_detached() must return false after set_bound()"
    );
}

/// Multiple `set_detached` calls are idempotent.
#[test]
fn test_set_detached_idempotent() {
    let mut session = make_session();
    session.set_detached();
    session.set_detached(); // second call — must not panic or corrupt state
    assert!(
        session.is_detached(),
        "is_detached() must remain true after multiple set_detached() calls"
    );
}

// ---------------------------------------------------------------------------
// get_palette_updates: multiple OSC 4 entries
// ---------------------------------------------------------------------------

/// Two OSC 4 sequences set two palette entries; `get_palette_updates` must
/// return both with correct index and RGB values.
#[test]
fn test_get_palette_updates_multiple_entries() {
    let mut session = make_session();
    // Index 0 → red
    session.core.advance(b"\x1b]4;0;rgb:ff/00/00\x1b\\");
    // Index 1 → green
    session.core.advance(b"\x1b]4;1;rgb:00/ff/00\x1b\\");

    let updates = session.get_palette_updates();

    assert!(
        updates
            .iter()
            .any(|(idx, r, g, b)| *idx == 0 && *r == 0xff && *g == 0 && *b == 0),
        "get_palette_updates must include index=0 with rgb(255,0,0)"
    );
    assert!(
        updates
            .iter()
            .any(|(idx, r, g, b)| *idx == 1 && *r == 0 && *g == 0xff && *b == 0),
        "get_palette_updates must include index=1 with rgb(0,255,0)"
    );
    assert!(
        updates.len() >= 2,
        "get_palette_updates must return at least 2 entries after two OSC 4 sequences, got {}",
        updates.len()
    );
}

/// Three OSC 4 sequences set three distinct entries; all three must appear.
#[test]
fn test_get_palette_updates_three_entries() {
    let mut session = make_session();
    session.core.advance(b"\x1b]4;0;rgb:ff/00/00\x1b\\"); // red
    session.core.advance(b"\x1b]4;1;rgb:00/ff/00\x1b\\"); // green
    session.core.advance(b"\x1b]4;2;rgb:00/00/ff\x1b\\"); // blue

    let updates = session.get_palette_updates();

    let found: Vec<u8> = updates.iter().map(|(idx, ..)| *idx).collect();
    assert!(
        found.contains(&0),
        "index 0 must be present in palette updates"
    );
    assert!(
        found.contains(&1),
        "index 1 must be present in palette updates"
    );
    assert!(
        found.contains(&2),
        "index 2 must be present in palette updates"
    );
    assert!(
        updates
            .iter()
            .any(|(idx, r, g, b)| *idx == 2 && *r == 0 && *g == 0 && *b == 0xff),
        "index 2 must carry rgb(0,0,255)"
    );
}

// ---------------------------------------------------------------------------
// get_scrollback_count: multiple sequential scroll batches
// ---------------------------------------------------------------------------

/// After three distinct scroll batches, `get_scrollback_count` must reflect
/// the cumulative number of lines pushed into scrollback.
#[test]
fn test_get_scrollback_count_after_multiple_scrolls() {
    let mut session = make_session();

    // Each batch of 24 newlines on a 24-row terminal pushes exactly 24 rows
    // into scrollback (the live screen content scrolls off the top).
    for _ in 0..3 {
        let newlines = b"\n".repeat(24);
        session.core.advance(&newlines);
    }

    let count = session.get_scrollback_count();
    assert!(
        count >= 48,
        "after 3 scroll batches of 24 lines each, scrollback count must be \
         at least 48 (two batches fully pushed), got {count}"
    );
}

/// `get_scrollback_count` increases monotonically with each scroll batch.
#[test]
fn test_get_scrollback_count_increases_monotonically() {
    let mut session = make_session();

    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);
    let count_after_1 = session.get_scrollback_count();

    session.core.advance(&newlines);
    let count_after_2 = session.get_scrollback_count();

    session.core.advance(&newlines);
    let count_after_3 = session.get_scrollback_count();

    assert!(
        count_after_1 > 0,
        "scrollback count must be > 0 after first scroll batch"
    );
    assert!(
        count_after_2 > count_after_1,
        "scrollback count must increase after second scroll batch \
         (was {count_after_1}, now {count_after_2})"
    );
    assert!(
        count_after_3 > count_after_2,
        "scrollback count must increase after third scroll batch \
         (was {count_after_2}, now {count_after_3})"
    );
}

// ---------------------------------------------------------------------------
// viewport_scroll_up then get_scrollback returns content
// ---------------------------------------------------------------------------

/// After `viewport_scroll_up`, `get_scrollback` must return a non-empty Vec
/// whose content includes text that was pushed into scrollback.
#[test]
fn test_viewport_scroll_up_then_lines_appear_in_get_scrollback() {
    let mut session = make_session();

    // Write a distinctive marker then push it into scrollback with 24 newlines.
    session.core.advance(b"VISIBLE_IN_SCROLLBACK");
    let newlines = b"\n".repeat(24);
    session.core.advance(&newlines);

    // Confirm scrollback is non-empty before scrolling the viewport.
    assert!(
        session.core.screen.scrollback_line_count > 0,
        "pre-condition: scrollback must be non-empty before viewport_scroll_up"
    );

    // Scroll the viewport up — this moves the view into the scrollback region.
    session.viewport_scroll_up(1);
    assert!(
        session.scroll_offset() > 0,
        "scroll_offset must be > 0 after viewport_scroll_up(1)"
    );

    // get_scrollback must return the stored scrollback lines regardless of
    // the current viewport position.
    let sb = session.get_scrollback(100);
    assert!(
        !sb.is_empty(),
        "get_scrollback must return non-empty content after viewport_scroll_up"
    );
    assert!(
        sb.iter().any(|l| l.contains("VISIBLE_IN_SCROLLBACK")),
        "get_scrollback must include the line that was pushed into scrollback"
    );
}

// ---------------------------------------------------------------------------
// get_cursor_visible: hide then show round-trip (explicit show after hide)
// ---------------------------------------------------------------------------

/// After hiding the cursor with `CSI ?25l` and then showing it with `CSI ?25h`,
/// `get_cursor_visible()` must return `true` again.
#[test]
fn test_get_cursor_visible_after_show_command() {
    let mut session = make_session();

    // Hide cursor.
    session.core.advance(b"\x1b[?25l");
    assert!(
        !session.get_cursor_visible(),
        "cursor must be hidden after CSI ?25l"
    );

    // Show cursor again.
    session.core.advance(b"\x1b[?25h");
    assert!(
        session.get_cursor_visible(),
        "get_cursor_visible() must return true after CSI ?25h (show cursor)"
    );
}

// ---------------------------------------------------------------------------
// get_default_colors: OSC 11 (bg) and OSC 12 (cursor) setters
// ---------------------------------------------------------------------------

/// After OSC 11 sets the default background color, `get_default_colors` must
/// return a non-sentinel value for the `bg` field.
#[test]
fn test_get_default_colors_after_osc11_bg() {
    let mut session = make_session();
    // OSC 11 sets the default background color.
    session.core.advance(b"\x1b]11;rgb:00/80/ff\x07");

    let (_fg, bg, _cursor) = session.get_default_colors();
    assert_ne!(
        bg, 0xFF00_0000u32,
        "get_default_colors bg must not be the sentinel after OSC 11"
    );
}

/// After OSC 12 sets the cursor color, `get_default_colors` must return a
/// non-sentinel value for the `cursor` field.
#[test]
fn test_get_default_colors_after_osc12_cursor() {
    let mut session = make_session();
    // OSC 12 sets the cursor highlight color.
    session.core.advance(b"\x1b]12;rgb:ff/ff/00\x07");

    let (_fg, _bg, cursor) = session.get_default_colors();
    assert_ne!(
        cursor, 0xFF00_0000u32,
        "get_default_colors cursor must not be the sentinel after OSC 12"
    );
}

// ---------------------------------------------------------------------------
// take_default_colors_dirty: OSC 11 / OSC 12 also raise the flag
// ---------------------------------------------------------------------------

/// `take_default_colors_dirty` returns `true` after OSC 11 sets bg color.
#[test]
fn test_take_default_colors_dirty_set_by_osc11() {
    let mut session = make_session();
    session.core.advance(b"\x1b]11;rgb:00/ff/80\x07");

    assert!(
        session.take_default_colors_dirty(),
        "take_default_colors_dirty must return true after OSC 11"
    );
    assert!(
        !session.take_default_colors_dirty(),
        "take_default_colors_dirty must return false on second call (flag cleared)"
    );
}

// ---------------------------------------------------------------------------
// take_title_if_dirty: OSC 0 (combined icon+title) also sets the title
// ---------------------------------------------------------------------------

/// `take_title_if_dirty` returns the title set via OSC 0 (sets both icon and
/// window title simultaneously).
#[test]
fn test_take_title_if_dirty_via_osc0() {
    let mut session = make_session();
    // OSC 0 sets the icon title and the window title to the same string.
    session.core.advance(b"\x1b]0;osc-zero-title\x07");

    let result = session.take_title_if_dirty();
    assert_eq!(
        result.as_deref(),
        Some("osc-zero-title"),
        "take_title_if_dirty must return the title set via OSC 0"
    );
    // Second call must return None (drain-once semantics).
    assert!(
        session.take_title_if_dirty().is_none(),
        "take_title_if_dirty must return None after the flag was cleared"
    );
}

// ---------------------------------------------------------------------------
// set_scrollback_max_lines: capping behaviour with small non-zero limit
// ---------------------------------------------------------------------------

/// `set_scrollback_max_lines(5)` caps the scrollback buffer so that after
/// pushing many lines, `get_scrollback_count` never exceeds 5.
#[test]
fn test_set_scrollback_max_lines_caps_buffer() {
    let mut session = make_session();
    session.set_scrollback_max_lines(5);

    // Push far more lines than the cap.
    for _ in 0..50 {
        session.core.advance(b"line\n");
    }

    let count = session.get_scrollback_count();
    assert!(
        count <= 5,
        "scrollback count must not exceed max_lines=5, got {count}"
    );
}

// ---------------------------------------------------------------------------
// viewport_scroll_down at offset 0 is a no-op
// ---------------------------------------------------------------------------

/// Calling `viewport_scroll_down` when `scroll_offset` is already 0 must
/// leave the offset at 0 (no underflow).
#[test]
fn test_viewport_scroll_down_noop_at_zero_offset() {
    let mut session = make_session();
    // No scrollback pushed — offset is definitely 0.
    assert_eq!(
        session.scroll_offset(),
        0,
        "pre-condition: offset must start at 0"
    );
    session.viewport_scroll_down(5);
    assert_eq!(
        session.scroll_offset(),
        0,
        "viewport_scroll_down at offset 0 must leave offset at 0 (no underflow)"
    );
}

// ---------------------------------------------------------------------------
// resize: idempotent when called twice with the same dimensions
// ---------------------------------------------------------------------------

/// Resizing to the same dimensions twice must not panic and must leave the
/// terminal in a consistent state with the specified dimensions.
#[test]
fn test_resize_idempotent_same_dimensions() {
    let mut session = make_session();
    session.resize(24, 80).expect("first resize must not fail");
    session.resize(24, 80).expect("second resize with same dims must not fail");
    assert_eq!(
        session.core.screen.rows(),
        24,
        "rows must still be 24 after idempotent resize"
    );
    assert_eq!(
        session.core.screen.cols(),
        80,
        "cols must still be 80 after idempotent resize"
    );
}

// ---------------------------------------------------------------------------
// get_cursor_shape: additional variants beyond BlinkingBlock / SteadyUnderline
// ---------------------------------------------------------------------------

/// `CSI 2 SP q` sets cursor shape to `SteadyBlock`.
#[test]
fn test_get_cursor_shape_steady_block() {
    use crate::types::cursor::CursorShape;
    let mut session = make_session();
    session.core.advance(b"\x1b[2 q"); // DECSCUSR param 2 = SteadyBlock
    assert_eq!(
        session.get_cursor_shape(),
        CursorShape::SteadyBlock,
        "cursor shape must be SteadyBlock after CSI 2 SP q"
    );
}

/// `CSI 5 SP q` sets cursor shape to `BlinkingBar`.
#[test]
fn test_get_cursor_shape_blinking_bar() {
    use crate::types::cursor::CursorShape;
    let mut session = make_session();
    session.core.advance(b"\x1b[5 q"); // DECSCUSR param 5 = BlinkingBar
    assert_eq!(
        session.get_cursor_shape(),
        CursorShape::BlinkingBar,
        "cursor shape must be BlinkingBar after CSI 5 SP q"
    );
}

/// `CSI 6 SP q` sets cursor shape to `SteadyBar`.
#[test]
fn test_get_cursor_shape_steady_bar() {
    use crate::types::cursor::CursorShape;
    let mut session = make_session();
    session.core.advance(b"\x1b[6 q"); // DECSCUSR param 6 = SteadyBar
    assert_eq!(
        session.get_cursor_shape(),
        CursorShape::SteadyBar,
        "cursor shape must be SteadyBar after CSI 6 SP q"
    );
}

// ---------------------------------------------------------------------------
// get_dirty_lines: full_dirty path via alt screen exit (DEC 1049l)
// ---------------------------------------------------------------------------

/// Exiting the alternate screen with `CSI ?1049l` marks all rows dirty via
/// `full_dirty`, so `get_dirty_lines` must return all 24 rows.
#[test]
fn test_get_dirty_lines_full_dirty_on_alt_screen_exit() {
    let mut session = make_session();
    // Enter alternate screen.
    session.core.advance(b"\x1b[?1049h");
    // Drain the full_dirty set by the enter event.
    let _ = session.core.screen.take_dirty_lines();

    // Write some content on the alt screen.
    session.core.advance(b"ALT_CONTENT");
    let _ = session.core.screen.take_dirty_lines();

    // Exit alternate screen — must set full_dirty.
    session.core.advance(b"\x1b[?1049l");
    let dirty = session.get_dirty_lines();
    assert_eq!(
        dirty.len(),
        24,
        "exiting alt screen must set full_dirty and return all 24 rows; got {}",
        dirty.len()
    );
}

// ---------------------------------------------------------------------------
// take_clipboard_actions: two sequential OSC 52 write sequences
// ---------------------------------------------------------------------------

/// Two consecutive OSC 52 write sequences produce two clipboard actions in
/// the queue; `take_clipboard_actions` returns both in a single call.
#[test]
fn test_take_clipboard_actions_two_writes_drained_together() {
    let mut session = make_session();
    // base64("hello") = "aGVsbG8="; base64("world") = "d29ybGQ="
    session.core.advance(b"\x1b]52;c;aGVsbG8=\x07");
    session.core.advance(b"\x1b]52;c;d29ybGQ=\x07");

    let actions = session.take_clipboard_actions();
    assert_eq!(
        actions.len(),
        2,
        "take_clipboard_actions must return 2 actions after two OSC 52 sequences, got {}",
        actions.len()
    );
    // Both must be Write variants.
    for action in &actions {
        assert!(
            matches!(action, crate::types::osc::ClipboardAction::Write(_)),
            "both actions must be Write variants"
        );
    }
    // After draining, the queue must be empty.
    assert!(
        session.take_clipboard_actions().is_empty(),
        "second take_clipboard_actions call must return empty Vec"
    );
}
