//! Cursor state and shape

use serde::{Deserialize, Serialize};

/// Cursor shape variants (DECSCUSR)
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum CursorShape {
    /// Blinking block cursor (DECSCUSR 0 or 1)
    #[default]
    BlinkingBlock,
    /// Steady block cursor (DECSCUSR 2)
    SteadyBlock,
    /// Blinking underline cursor (DECSCUSR 3)
    BlinkingUnderline,
    /// Steady underline cursor (DECSCUSR 4)
    SteadyUnderline,
    /// Blinking bar cursor (DECSCUSR 5)
    BlinkingBar,
    /// Steady bar cursor (DECSCUSR 6)
    SteadyBar,
}

/// Cursor state
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Cursor {
    /// Column position (0-indexed)
    pub(crate) col: usize,
    /// Row position (0-indexed)
    pub(crate) row: usize,
    /// Cursor shape
    pub(crate) shape: CursorShape,
    /// Cursor is visible
    pub(crate) visible: bool,
    /// DEC pending wrap flag (DECAWM last-column behavior).
    ///
    /// When a character is printed at the last column, the cursor stays at that
    /// column and this flag is set.  The actual wrap (col=0, `line_feed`) is
    /// deferred until the next printable character.  Any explicit cursor
    /// movement clears this flag without wrapping.
    #[serde(skip, default)]
    pub(crate) pending_wrap: bool,
}

impl Cursor {
    /// Create a new cursor at the specified position
    #[must_use] 
    pub fn new(col: usize, row: usize) -> Self {
        Self {
            col,
            row,
            shape: CursorShape::default(),
            visible: true,
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

/// Convert a [`CursorShape`] to its DECSCUSR parameter integer for FFI transfer.
///
/// The canonical encoding is:
/// - `BlinkingBlock` → 0 (DECSCUSR 0/1; 1 is an alias accepted by `TryFrom`)
/// - `SteadyBlock` → 2
/// - `BlinkingUnderline` → 3, `SteadyUnderline` → 4
/// - `BlinkingBar` → 5, `SteadyBar` → 6
///
/// Used by `kuro_core_get_cursor_shape` to send the current shape to Emacs Lisp.
impl From<CursorShape> for i64 {
    #[inline]
    fn from(shape: CursorShape) -> Self {
        match shape {
            CursorShape::BlinkingBlock => 0,
            CursorShape::SteadyBlock => 2,
            CursorShape::BlinkingUnderline => 3,
            CursorShape::SteadyUnderline => 4,
            CursorShape::BlinkingBar => 5,
            CursorShape::SteadyBar => 6,
        }
    }
}

/// Convert a DECSCUSR parameter integer to a [`CursorShape`].
///
/// DECSCUSR values 0 and 1 are both aliases for blinking block; 0 is the canonical
/// round-trip value (`i64::from(BlinkingBlock) == 0`).  Values outside 0–6 return
/// `Err(())` and callers should fall back to `CursorShape::BlinkingBlock`.
///
/// Used by `handle_decscusr` in the CSI parser.
impl TryFrom<i64> for CursorShape {
    type Error = ();
    #[inline]
    fn try_from(v: i64) -> Result<Self, ()> {
        match v {
            0 | 1 => Ok(Self::BlinkingBlock),
            2 => Ok(Self::SteadyBlock),
            3 => Ok(Self::BlinkingUnderline),
            4 => Ok(Self::SteadyUnderline),
            5 => Ok(Self::BlinkingBar),
            6 => Ok(Self::SteadyBar),
            _ => Err(()),
        }
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
        assert_eq!(cursor.shape, CursorShape::BlinkingBlock);
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

    #[test]
    fn cursor_shape_roundtrip() {
        // Values 0,2,3,4,5,6 must round-trip through From/TryFrom.
        // (1 is an alias for BlinkingBlock and maps back to 0.)
        for v in [0i64, 2, 3, 4, 5, 6] {
            let shape = CursorShape::try_from(v).unwrap();
            assert_eq!(i64::from(shape), v);
        }
    }

    #[test]
    fn cursor_shape_param1_alias() {
        // DECSCUSR param 1 is an alias for BlinkingBlock (same as 0).
        let shape = CursorShape::try_from(1i64).unwrap();
        assert_eq!(shape, CursorShape::BlinkingBlock);
        assert_eq!(i64::from(shape), 0);
    }

    #[test]
    fn cursor_shape_unknown_returns_err() {
        assert!(CursorShape::try_from(99i64).is_err());
        assert!(CursorShape::try_from(-1i64).is_err());
        assert!(CursorShape::try_from(7i64).is_err());
    }
}
