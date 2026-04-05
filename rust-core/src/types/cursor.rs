//! Cursor state and shape

/// Cursor shape variants (DECSCUSR)
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash)]
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
#[derive(Debug, Clone, Copy)]
pub struct Cursor {
    /// Column position (0-indexed)
    pub(crate) col: usize,
    /// Row position (0-indexed)
    pub(crate) row: usize,
    /// Cursor shape
    #[expect(
        dead_code,
        reason = "set by VTE parser; read only in #[cfg(test)] blocks"
    )]
    pub(crate) shape: CursorShape,
    /// Cursor is visible
    #[expect(
        dead_code,
        reason = "set by VTE parser; read only in #[cfg(test)] blocks"
    )]
    pub(crate) visible: bool,
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

    // -------------------------------------------------------------------------
    // Merged from tests/unit/types/cursor.rs
    // -------------------------------------------------------------------------

    #[test]
    // ROUNDTRIP: Canonical DECSCUSR values 0,2,3,4,5,6 must survive a
    // From->TryFrom round-trip unchanged.
    fn test_cursor_shape_canonical_roundtrip() {
        for v in [0i64, 2, 3, 4, 5, 6] {
            let shape = CursorShape::try_from(v)
                .unwrap_or_else(|()| panic!("try_from({v}) must succeed for canonical value"));
            assert_eq!(
                i64::from(shape),
                v,
                "round-trip failed: {v} → {shape:?} → {}",
                i64::from(shape)
            );
        }
    }

    #[test]
    // SATURATION: move_by with large negative deltas from (0,0) must clamp to
    // (0,0) via saturating_sub, not wrap around or panic.
    fn test_move_by_saturating() {
        let mut cursor = Cursor::new(0, 0);
        cursor.move_by(-1000, -1000);
        assert_eq!(cursor.col, 0, "col must saturate to 0");
        assert_eq!(cursor.row, 0, "row must saturate to 0");
    }

    #[test]
    // SATURATION: Large positive deltas must saturate at usize::MAX, not panic.
    fn test_move_by_saturating_positive() {
        let mut cursor = Cursor::new(usize::MAX, usize::MAX);
        cursor.move_by(i32::MAX, i32::MAX);
        assert_eq!(cursor.col, usize::MAX);
        assert_eq!(cursor.row, usize::MAX);
    }

    #[test]
    // INVARIANT: Cursor::new positions the cursor at the given column and row.
    fn test_cursor_new_sets_initial_position() {
        let cursor = Cursor::new(42, 7);
        assert_eq!(cursor.col, 42);
        assert_eq!(cursor.row, 7);
        assert!(cursor.visible);
        assert_eq!(cursor.shape, CursorShape::BlinkingBlock);
        assert!(!cursor.pending_wrap);
    }

    #[test]
    // ALIAS: DECSCUSR param 1 is an alias for BlinkingBlock; From<CursorShape>
    // must encode it back as 0 (the canonical value), not 1.
    fn test_cursor_shape_param1_alias_maps_to_zero() {
        let shape = CursorShape::try_from(1i64).expect("param 1 must be valid");
        assert_eq!(shape, CursorShape::BlinkingBlock);
        assert_eq!(
            i64::from(shape),
            0,
            "canonical encoding of BlinkingBlock is 0"
        );
    }

    #[test]
    // INVARIANT: Cursor::new(0, 0) has correct default field values:
    // visible=true, shape=BlinkingBlock, pending_wrap=false.
    fn test_cursor_default_values() {
        let cursor = Cursor::new(0, 0);
        assert_eq!(cursor.col, 0);
        assert_eq!(cursor.row, 0);
        assert!(cursor.visible, "new cursor must be visible by default");
        assert_eq!(
            cursor.shape,
            CursorShape::BlinkingBlock,
            "default shape is BlinkingBlock"
        );
        assert!(!cursor.pending_wrap, "pending_wrap must start false");
    }

    #[test]
    // ROUNDTRIP: After move_to(col, row) and a subsequent move_to back to the
    // previously recorded position, the cursor is restored to that position.
    fn test_cursor_save_restore() {
        let mut cursor = Cursor::new(10, 20);
        let saved_col = cursor.col;
        let saved_row = cursor.row;
        cursor.move_to(99, 99);
        assert_eq!(cursor.col, 99);
        assert_eq!(cursor.row, 99);
        cursor.move_to(saved_col, saved_row);
        assert_eq!(cursor.col, 10, "col must be restored to saved value");
        assert_eq!(cursor.row, 20, "row must be restored to saved value");
    }

    #[test]
    // FIELD: The visible field can be toggled freely.
    fn test_cursor_visibility_toggle() {
        let mut cursor = Cursor::new(0, 0);
        assert!(cursor.visible);
        cursor.visible = false;
        assert!(
            !cursor.visible,
            "visible must be false after setting to false"
        );
        cursor.visible = true;
        assert!(cursor.visible, "visible must be true after restoring");
    }

    #[test]
    // INVARIANT: CursorShape::default() returns BlinkingBlock.
    fn test_cursor_shape_block_is_default() {
        assert_eq!(CursorShape::default(), CursorShape::BlinkingBlock);
        assert_eq!(
            CursorShape::try_from(0i64).unwrap(),
            CursorShape::BlinkingBlock
        );
        assert_eq!(
            CursorShape::try_from(1i64).unwrap(),
            CursorShape::BlinkingBlock
        );
    }

    #[test]
    // INVARIANT: Cursor::new(5, 10) has col=5 and row=10.
    fn test_cursor_new_sets_position() {
        let cursor = Cursor::new(5, 10);
        assert_eq!(cursor.col, 5, "first argument is col");
        assert_eq!(cursor.row, 10, "second argument is row");
    }

    mod pbt {
        use super::*;
        use proptest::prelude::*;

        proptest! {
            #![proptest_config(ProptestConfig::with_cases(1000))]

            #[test]
            // BOUNDARY: Values outside 0-6 must be rejected by TryFrom<i64>.
            fn prop_cursor_shape_invalid_rejects_positive(v in 7i64..=1000i64) {
                prop_assert!(
                    CursorShape::try_from(v).is_err(),
                    "expected Err for DECSCUSR value {v}, got Ok"
                );
            }

            #[test]
            // BOUNDARY: Values outside 0-6 must be rejected by TryFrom<i64>.
            fn prop_cursor_shape_invalid_rejects_negative(v in -1000i64..=-1i64) {
                prop_assert!(
                    CursorShape::try_from(v).is_err(),
                    "expected Err for DECSCUSR value {v}, got Ok"
                );
            }

            #[test]
            // PANIC SAFETY: move_by must never panic for any combination of i32 deltas.
            fn prop_move_by_no_panic(
                col in 0usize..=10000usize,
                row in 0usize..=10000usize,
                dx  in i32::MIN..=i32::MAX,
                dy  in i32::MIN..=i32::MAX,
            ) {
                let mut cursor = Cursor::new(col, row);
                cursor.move_by(dx, dy);
                let _ = cursor.col;
                let _ = cursor.row;
            }

            #[test]
            // INVARIANT: move_to(col, row) sets cursor.col and cursor.row exactly.
            fn prop_move_to_sets_position(
                start_col in 0usize..=1000usize,
                start_row in 0usize..=1000usize,
                dest_col  in 0usize..=1000usize,
                dest_row  in 0usize..=1000usize,
            ) {
                let mut cursor = Cursor::new(start_col, start_row);
                cursor.move_to(dest_col, dest_row);
                prop_assert_eq!(cursor.col, dest_col);
                prop_assert_eq!(cursor.row, dest_row);
            }

            #[test]
            // INVARIANT: Cursor::new(col, row).visible is always true.
            fn prop_new_cursor_visible_default(
                col in 0usize..=10000usize,
                row in 0usize..=10000usize,
            ) {
                let cursor = Cursor::new(col, row);
                prop_assert!(cursor.visible, "Cursor::new must default to visible=true");
            }
        }

        proptest! {
            #![proptest_config(ProptestConfig::with_cases(256))]

            #[test]
            // BOUNDARY: move_by with a negative delta larger than the current position
            // must clamp col/row to 0 via saturating_sub.
            fn prop_move_by_clamps_to_zero(
                col in 0usize..=500usize,
                row in 0usize..=500usize,
            ) {
                let mut cursor = Cursor::new(col, row);
                cursor.move_by(i32::MIN, i32::MIN);
                prop_assert_eq!(cursor.col, 0, "col must clamp to 0 for large negative dx");
                prop_assert_eq!(cursor.row, 0, "row must clamp to 0 for large negative dy");
            }

            #[test]
            // INVARIANT: move_to(col, row) stores the values exactly.
            fn prop_move_to_stores_exact_values(
                col in 0usize..=100_000usize,
                row in 0usize..=100_000usize,
            ) {
                let mut cursor = Cursor::new(0, 0);
                cursor.move_to(col, row);
                prop_assert_eq!(cursor.col, col);
                prop_assert_eq!(cursor.row, row);
            }

            #[test]
            // PANIC SAFETY: CursorShape::try_from(v) for v in 0..=6 must never panic.
            fn prop_try_from_valid_range(v in 0i64..=6i64) {
                let result = CursorShape::try_from(v);
                prop_assert!(result.is_ok(), "try_from({v}) must succeed for v in 0..=6");
            }

            #[test]
            // INVARIANT: move_by(1, 1) increments both col and row by exactly 1.
            fn prop_move_by_positive_increments(
                col in 0usize..=10_000usize,
                row in 0usize..=10_000usize,
            ) {
                let mut cursor = Cursor::new(col, row);
                cursor.move_by(1, 1);
                prop_assert_eq!(cursor.col, col + 1, "col must increase by exactly 1");
                prop_assert_eq!(cursor.row, row + 1, "row must increase by exactly 1");
            }
        }
    }
}
