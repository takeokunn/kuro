/// Cursor shape variants (DECSCUSR).
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

const CANONICAL_DECSCUSR_SHAPES: &[(i64, CursorShape)] = &[
    (0, CursorShape::BlinkingBlock),
    (2, CursorShape::SteadyBlock),
    (3, CursorShape::BlinkingUnderline),
    (4, CursorShape::SteadyUnderline),
    (5, CursorShape::BlinkingBar),
    (6, CursorShape::SteadyBar),
];

/// Convert a [`CursorShape`] to its DECSCUSR parameter integer for FFI transfer.
///
/// The canonical encoding is:
/// - `BlinkingBlock` -> 0 (DECSCUSR 0/1; 1 is accepted by `TryFrom`)
/// - `SteadyBlock` -> 2
/// - `BlinkingUnderline` -> 3, `SteadyUnderline` -> 4
/// - `BlinkingBar` -> 5, `SteadyBar` -> 6
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
/// round-trip value (`i64::from(BlinkingBlock) == 0`). Values outside 0-6 return
/// `Err(())` and callers should fall back to `CursorShape::BlinkingBlock`.
///
/// Used by `handle_decscusr` in the CSI parser.
impl TryFrom<i64> for CursorShape {
    type Error = ();

    #[inline]
    fn try_from(v: i64) -> Result<Self, ()> {
        if v == 1 {
            return Ok(Self::BlinkingBlock);
        }

        CANONICAL_DECSCUSR_SHAPES
            .iter()
            .find_map(|(value, shape)| (*value == v).then_some(*shape))
            .ok_or(())
    }
}
