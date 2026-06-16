use super::dirty_viewport_support::{
    assert_scrollback_non_empty, make_viewport_session, scrollback_batch,
};
use super::TerminalSession;

// ---------------------------------------------------------------------------
// viewport_scroll_up additional tests
// ---------------------------------------------------------------------------

/// `viewport_scroll_up(3)` increases `scroll_offset` to 3 after scrollback exists.
#[test]
fn test_viewport_scroll_up_from_scrollback() {
    let mut session = make_viewport_session();
    scrollback_batch(&mut session, 5);
    assert_scrollback_non_empty(&session, "scrollback must be non-empty before scroll_up");
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
    let mut session = make_viewport_session();
    scrollback_batch(&mut session, 10);
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
    let mut session = make_viewport_session();
    scrollback_batch(&mut session, 5);
    session.viewport_scroll_up(2);
    assert_eq!(
        session.scroll_offset(),
        2,
        "offset must be 2 after scroll_up"
    );
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
    let session = make_viewport_session();
    assert!(
        !session.get_synchronized_output(),
        "get_synchronized_output must return false on a fresh session"
    );
}

/// `get_synchronized_output` returns `true` after `CSI ?2026h`.
#[test]
fn test_get_synchronized_output_true_after_mode_set() {
    let mut session = make_viewport_session();
    session.core.advance(b"\x1b[?2026h");
    assert!(
        session.get_synchronized_output(),
        "get_synchronized_output must return true after CSI ?2026h"
    );
}

/// `get_synchronized_output` returns `false` after set then reset with `CSI ?2026l`.
#[test]
fn test_get_synchronized_output_false_after_mode_reset() {
    let mut session = make_viewport_session();
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
    let session = make_viewport_session();
    assert!(
        !session.get_mouse_pixel(),
        "get_mouse_pixel must return false on a fresh session"
    );
}

/// `get_mouse_pixel` returns `true` after `CSI ?1016h`.
#[test]
fn test_get_mouse_pixel_true_after_mode_1016() {
    let mut session = make_viewport_session();
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
    assert_eq!(
        face_ranges.len(),
        1,
        "single-cell line must produce exactly 1 face range"
    );
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
    let full_cell =
        Cell::with_char_and_width('\u{3042}', SgrAttributes::default(), CellWidth::Full); // 'あ'
    let placeholder = Cell::with_char_and_width(' ', SgrAttributes::default(), CellWidth::Wide);
    let cells = vec![full_cell, placeholder];
    let (_row, text, _face_ranges, col_to_buf) = TerminalSession::encode_line_faces(0, &cells);
    assert_eq!(
        text, "\u{3042}",
        "wide char text must contain only the base character"
    );
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
    assert_eq!(
        face_ranges.len(),
        1,
        "bold cell must produce exactly 1 face range"
    );
    let (_start, _end, _fg, _bg, flags, _ul_color) = face_ranges[0];
    assert_ne!(
        flags, 0,
        "face-range flags must be non-zero for a bold cell"
    );
    // Bit 0 of the encoded attrs corresponds to BOLD (SgrFlags::BOLD = bit 0, maps to encode bit 0).
    assert_eq!(
        flags & 1,
        1,
        "bit 0 of face-range flags must be set for BOLD"
    );
}

// ---------------------------------------------------------------------------
// set_detached / set_bound: direct state-transition unit tests
// ---------------------------------------------------------------------------

/// A fresh session via `make_viewport_session()` is Bound, so `is_detached()` returns false.
#[test]
fn test_is_detached_false_on_fresh_session() {
    let session = make_viewport_session();
    assert!(
        !session.is_detached(),
        "is_detached() must return false on a freshly constructed (Bound) session"
    );
}
