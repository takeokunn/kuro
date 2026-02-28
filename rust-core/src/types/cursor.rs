//! Cursor state and shape

use serde::{Deserialize, Serialize};

/// Cursor shape variants
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum CursorShape {
    /// Block cursor (underscoring the character)
    #[default]
    Block,
    /// Underline cursor
    Underline,
    /// Bar cursor (vertical line)
    Bar,
}

/// Cursor state
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Cursor {
    /// Column position (0-indexed)
    pub col: usize,
    /// Row position (0-indexed)
    pub row: usize,
    /// Cursor shape
    pub shape: CursorShape,
    /// Cursor is visible
    pub visible: bool,
}

impl Cursor {
    /// Create a new cursor at the specified position
    pub fn new(col: usize, row: usize) -> Self {
        Self {
            col,
            row,
            shape: CursorShape::default(),
            visible: true,
        }
    }

    /// Move cursor to absolute position
    pub fn move_to(&mut self, col: usize, row: usize) {
        self.col = col;
        self.row = row;
    }

    /// Move cursor relative to current position
    pub fn move_by(&mut self, dx: i32, dy: i32) {
        let new_col = if dx >= 0 {
            self.col.saturating_add(dx as usize)
        } else {
            self.col.saturating_sub((-dx) as usize)
        };

        let new_row = if dy >= 0 {
            self.row.saturating_add(dy as usize)
        } else {
            self.row.saturating_sub((-dy) as usize)
        };

        self.col = new_col;
        self.row = new_row;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cursor_creation() {
        let cursor = Cursor::new(10, 5);
        assert_eq!(cursor.col, 10);
        assert_eq!(cursor.row, 5);
        assert!(cursor.visible);
        assert_eq!(cursor.shape, CursorShape::Block);
    }

    #[test]
    fn test_cursor_move_to() {
        let mut cursor = Cursor::new(0, 0);
        cursor.move_to(20, 10);
        assert_eq!(cursor.col, 20);
        assert_eq!(cursor.row, 10);
    }

    #[test]
    fn test_cursor_move_by() {
        let mut cursor = Cursor::new(10, 10);
        cursor.move_by(5, -3);
        assert_eq!(cursor.col, 15);
        assert_eq!(cursor.row, 7);

        cursor.move_by(-20, -20);
        assert_eq!(cursor.col, 0);
        assert_eq!(cursor.row, 0);
    }
}
