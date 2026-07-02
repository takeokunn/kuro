use super::support::{advance, decscusr, make_osc_session, osc10};

// ---------------------------------------------------------------------------
// take_default_colors_dirty: atomic read-and-clear semantics
// ---------------------------------------------------------------------------

#[test]
fn test_take_default_colors_dirty_clears_flag() {
    let mut session = make_osc_session();

    advance(&mut session, &osc10("rgb:ff/80/00"));

    assert!(session.take_default_colors_dirty());
    assert!(!session.take_default_colors_dirty());
}

#[test]
fn test_take_default_colors_dirty_false_initially() {
    let mut session = make_osc_session();
    assert!(!session.take_default_colors_dirty());
}

// ---------------------------------------------------------------------------
// New coverage: encode_line_faces, cursor shape, scrollback
// ---------------------------------------------------------------------------

#[test]
fn test_encode_line_faces_three_ascii_cells_text() {
    use crate::types::cell::{Cell, CellWidth, SgrAttributes};

    let cells = vec![
        Cell::with_char_and_width('A', SgrAttributes::default(), CellWidth::Half),
        Cell::with_char_and_width('B', SgrAttributes::default(), CellWidth::Half),
        Cell::with_char_and_width('C', SgrAttributes::default(), CellWidth::Half),
    ];
    let encoded = crate::ffi::abstraction::session::TerminalSession::encode_line_faces(3, &cells);

    assert_eq!(encoded.row_index, 3);
    assert_eq!(encoded.text, "ABC");
    assert!(!encoded.face_ranges.is_empty());
    assert!(encoded.col_to_buf.is_empty());
}

#[test]
fn test_get_cursor_shape_changes_via_decscusr() {
    use crate::types::cursor::CursorShape;

    let mut session = make_osc_session();
    advance(&mut session, &decscusr(4));

    assert_eq!(session.get_cursor_shape(), CursorShape::SteadyUnderline);
}

#[test]
fn test_encode_line_faces_last_row_index_preserved() {
    use crate::types::cell::{Cell, CellWidth, SgrAttributes};

    let cells = vec![Cell::with_char_and_width(
        'Z',
        SgrAttributes::default(),
        CellWidth::Half,
    )];
    let encoded = crate::ffi::abstraction::session::TerminalSession::encode_line_faces(23, &cells);

    assert_eq!(encoded.row_index, 23);
    assert_eq!(encoded.text, "Z");
}

#[test]
fn test_get_scrollback_count_zero_on_fresh_session() {
    let session = make_osc_session();
    assert_eq!(session.get_scrollback_count(), 0);
}

#[test]
fn test_clear_scrollback_idempotent_on_empty() {
    let mut session = make_osc_session();

    session.clear_scrollback();
    session.clear_scrollback();

    assert_eq!(session.get_scrollback_count(), 0);
}
