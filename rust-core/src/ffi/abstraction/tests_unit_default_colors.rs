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
    session
        .resize(24, 80)
        .expect("second resize with same dims must not fail");
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
