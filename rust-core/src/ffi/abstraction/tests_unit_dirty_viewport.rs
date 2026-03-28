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
