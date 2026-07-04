use crate::types::Cursor;

#[derive(Clone, Copy)]
pub(crate) struct Position {
    pub(crate) col: usize,
    pub(crate) row: usize,
}

impl Position {
    pub(crate) const fn new(col: usize, row: usize) -> Self {
        Self { col, row }
    }
}

pub(crate) const DEFAULT_CURSOR_POSITION: Position = Position::new(0, 0);
pub(crate) const CANONICAL_SHAPES: &[(i64, crate::types::CursorShape)] = &[
    (0, crate::types::CursorShape::BlinkingBlock),
    (2, crate::types::CursorShape::SteadyBlock),
    (3, crate::types::CursorShape::BlinkingUnderline),
    (4, crate::types::CursorShape::SteadyUnderline),
    (5, crate::types::CursorShape::BlinkingBar),
    (6, crate::types::CursorShape::SteadyBar),
];

pub(crate) fn cursor_at(position: Position) -> Cursor {
    Cursor::new(position.col, position.row)
}

pub(crate) fn assert_position(cursor: &Cursor, expected: Position) {
    assert_eq!(cursor.col, expected.col, "cursor col");
    assert_eq!(cursor.row, expected.row, "cursor row");
}

pub(crate) fn assert_new_cursor_defaults(cursor: &Cursor) {
    assert!(!cursor.pending_wrap, "pending_wrap must start false");
}
