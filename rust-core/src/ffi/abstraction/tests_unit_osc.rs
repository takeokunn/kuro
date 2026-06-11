
// ---------------------------------------------------------------------------
// take_default_colors_dirty: atomic read-and-clear semantics
// ---------------------------------------------------------------------------

#[test]
fn test_take_default_colors_dirty_clears_flag() {
    let mut session = make_session();

    // OSC 10 sets default fg color and raises default_colors_dirty
    session.core.advance(b"\x1b]10;rgb:ff/80/00\x07");

    assert!(
        session.take_default_colors_dirty(),
        "take_default_colors_dirty should return true after OSC 10"
    );
    assert!(
        !session.take_default_colors_dirty(),
        "take_default_colors_dirty should return false after being cleared"
    );
}

#[test]
fn test_take_default_colors_dirty_false_initially() {
    let mut session = make_session();
    assert!(
        !session.take_default_colors_dirty(),
        "default_colors_dirty should be false in a fresh session"
    );
}

include!("tests_unit_session.rs");
include!("tests_unit_scroll.rs");
include!("tests_unit_dirty.rs");

// ---------------------------------------------------------------------------
// New coverage: encode_line_faces, take_cwd_if_dirty, cursor shape, pid
// ---------------------------------------------------------------------------

/// `encode_line_faces` with three consecutive ASCII cells produces 1 or more
/// face ranges covering all three columns; text must be exactly "ABC".
#[test]
fn test_encode_line_faces_three_ascii_cells_text() {
    use crate::types::cell::{Cell, CellWidth, SgrAttributes};
    let cells = vec![
        Cell::with_char_and_width('A', SgrAttributes::default(), CellWidth::Half),
        Cell::with_char_and_width('B', SgrAttributes::default(), CellWidth::Half),
        Cell::with_char_and_width('C', SgrAttributes::default(), CellWidth::Half),
    ];
    let (row, text, face_ranges, col_to_buf) = TerminalSession::encode_line_faces(3, &cells);
    assert_eq!(row, 3, "row index must pass through unchanged");
    assert_eq!(text, "ABC", "three ASCII cells must produce text 'ABC'");
    assert!(
        !face_ranges.is_empty(),
        "three cells must produce at least one face range"
    );
    // All three cells are ASCII: col_to_buf must be empty (identity mapping).
    assert!(
        col_to_buf.is_empty(),
        "pure-ASCII three-cell line must return empty col_to_buf"
    );
}

/// `take_cwd_if_dirty` returns the path stripped of `file://hostname` prefix
/// when OSC 7 is sent with a full URI including hostname.
#[test]
fn test_take_cwd_if_dirty_strips_hostname_prefix() {
    let mut session = make_session();

    // OSC 7 with full file://hostname/path URI
    session.core.advance(b"\x1b]7;file://myhost/tmp/work\x07");

    let result = session.take_cwd_if_dirty();
    assert!(
        result.is_some(),
        "take_cwd_if_dirty must return Some after OSC 7 with hostname"
    );
    let path = result.unwrap();
    // The implementation strips `file://hostname` leaving `/tmp/work`
    assert!(
        path.starts_with('/'),
        "stripped path must start with '/', got: {path:?}"
    );
    assert!(
        path.contains("tmp") || path.contains("work"),
        "stripped path must contain the path component, got: {path:?}"
    );
}

/// `get_cursor_shape` changes to `SteadyUnderline` after `CSI 4 SP q`.
#[test]
fn test_get_cursor_shape_changes_via_decscusr() {
    use crate::types::cursor::CursorShape;
    let mut session = make_session();

    // CSI 4 SP q → SteadyUnderline (DECSCUSR param 4)
    session.core.advance(b"\x1b[4 q");
    let shape = session.get_cursor_shape();
    assert_eq!(
        shape,
        CursorShape::SteadyUnderline,
        "cursor shape must be SteadyUnderline after CSI 4 SP q"
    );
}

/// `encode_line_faces` with row index 23 (last row on a 24-row screen) passes
/// the row index through unchanged.
#[test]
fn test_encode_line_faces_last_row_index_preserved() {
    use crate::types::cell::{Cell, CellWidth, SgrAttributes};
    let cells = vec![Cell::with_char_and_width(
        'Z',
        SgrAttributes::default(),
        CellWidth::Half,
    )];
    let (row, text, _, _) = TerminalSession::encode_line_faces(23, &cells);
    assert_eq!(row, 23, "row index 23 must be preserved");
    assert_eq!(text, "Z");
}

/// `get_scrollback_count` returns 0 on a fresh session (nothing pushed yet).
#[test]
fn test_get_scrollback_count_zero_on_fresh_session() {
    let session = make_session();
    assert_eq!(
        session.get_scrollback_count(),
        0,
        "scrollback count must be 0 on a freshly constructed session"
    );
}

/// `clear_scrollback` is idempotent: calling it on an already-empty session
/// must not panic or corrupt state.
#[test]
fn test_clear_scrollback_idempotent_on_empty() {
    let mut session = make_session();
    // No content pushed — scrollback is already empty.
    session.clear_scrollback();
    session.clear_scrollback(); // second call must be safe
    assert_eq!(
        session.get_scrollback_count(),
        0,
        "scrollback count must remain 0 after two clear_scrollback calls on empty session"
    );
}

include!("tests_unit_isolation.rs");
