//! Cursor position state and shape metadata.

mod shape;

pub use shape::CursorShape;

/// Cursor state
#[derive(Debug, Clone, Copy)]
pub struct Cursor {
    /// Column position (0-indexed)
    pub(crate) col: usize,
    /// Row position (0-indexed)
    pub(crate) row: usize,
    /// DEC pending wrap flag (DECAWM last-column behavior).
    ///
    /// When a character is printed at the last column, the cursor stays at that
    /// column and this flag is set.  The actual wrap (col=0, `line_feed`) is
    /// deferred until the next printable character.  Any explicit cursor
    /// movement clears this flag without wrapping.
    pub(crate) pending_wrap: bool,
}

impl Cursor {
    /// Create a new cursor at the specified position
    #[must_use]
    pub fn new(col: usize, row: usize) -> Self {
        Self {
            col,
            row,
            pending_wrap: false,
        }
    }

    /// Move cursor to absolute position
    pub const fn move_to(&mut self, col: usize, row: usize) {
        self.col = col;
        self.row = row;
    }

    /// Move cursor relative to current position
    pub const fn move_by(&mut self, dx: i32, dy: i32) {
        let new_col = if dx >= 0 {
            self.col.saturating_add(dx.unsigned_abs() as usize)
        } else {
            self.col.saturating_sub(dx.unsigned_abs() as usize)
        };

        let new_row = if dy >= 0 {
            self.row.saturating_add(dy.unsigned_abs() as usize)
        } else {
            self.row.saturating_sub(dy.unsigned_abs() as usize)
        };

        self.col = new_col;
        self.row = new_row;
    }
}

#[cfg(test)]
mod tests;
