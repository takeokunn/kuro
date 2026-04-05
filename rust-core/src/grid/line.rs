//! Line type representing a single row in the terminal screen

use crate::types::{cell::CellWidth, Cell, Color, SgrAttributes};
use compact_str::CompactString;
use std::fmt;

/// A single line in the terminal grid
#[derive(Debug, Clone)]
pub struct Line {
    /// Cells in this line
    pub cells: Vec<Cell>,
    /// Whether this line has been modified since last render
    pub is_dirty: bool,
    /// Monotonically increasing mutation counter (wrapping).
    ///
    /// Incremented on every cell write, clear, or resize so that the render
    /// path can skip hash computation for rows that have not changed since the
    /// last frame.  Version `0` is the initial value; any mutation produces `≥ 1`.
    pub(crate) version: u64,
    /// Whether any cell on this line is a wide-character placeholder
    /// (`CellWidth::Wide`).  Set incrementally on writes; cleared on full-line
    /// clear/reset.  Lets `fill_encode_pool` skip the O(cols) pre-scan on the
    /// ~90% of ASCII-only dirty lines.
    pub(crate) has_wide: bool,
}

impl Line {
    /// Create a new line with the specified number of columns
    #[inline]
    #[must_use]
    pub fn new(cols: usize) -> Self {
        Self {
            cells: vec![Cell::default(); cols],
            is_dirty: false,
            version: 0,
            has_wide: false,
        }
    }

    /// Create a new line with all cells carrying the given BCE background color.
    /// When `bg` is `Color::Default` this is identical to `Line::new(cols)`.
    #[inline]
    #[must_use]
    pub fn new_with_bg(cols: usize, bg: Color) -> Self {
        if bg == Color::Default {
            return Self::new(cols);
        }
        let mut cell = Cell::default();
        cell.attrs.background = bg;
        Self {
            cells: vec![cell; cols],
            is_dirty: false,
            version: 0,
            has_wide: false,
        }
    }

    /// Get cell at column index
    #[inline]
    #[must_use]
    pub fn get_cell(&self, col: usize) -> Option<&Cell> {
        self.cells.get(col)
    }

    /// Get mutable reference to cell at column index
    #[inline]
    pub fn get_cell_mut(&mut self, col: usize) -> Option<&mut Cell> {
        self.cells.get_mut(col)
    }

    /// Update cell at column index
    #[inline]
    pub fn update_cell(&mut self, col: usize, c: char, attrs: SgrAttributes) {
        if let Some(cell) = self.cells.get_mut(col) {
            let mut buf = [0u8; 4];
            let s = c.encode_utf8(&mut buf);
            let grapheme_changed = cell.grapheme.as_str() != s;
            let attrs_changed = cell.attrs != attrs;
            if grapheme_changed || attrs_changed {
                if grapheme_changed {
                    cell.grapheme = CompactString::new(s);
                }
                if attrs_changed {
                    cell.attrs = attrs;
                }
                self.is_dirty = true;
                self.version = self.version.wrapping_add(1);
            }
        }
    }

    /// Update cell at column index with a Cell struct (includes width)
    #[inline]
    pub fn update_cell_with(&mut self, col: usize, cell: Cell) {
        if col < self.cells.len() && self.cells[col] != cell {
            // Short-circuit: once has_wide is set it stays set; skip the width
            // enum load on every subsequent cell write to the same line.
            if !self.has_wide && cell.width == CellWidth::Wide {
                self.has_wide = true;
            }
            self.cells[col] = cell;
            self.is_dirty = true;
            self.version = self.version.wrapping_add(1);
        }
    }

    /// Clear all cells in line
    #[inline]
    pub fn clear(&mut self) {
        self.cells.fill(Cell::default());
        self.has_wide = false;
        self.is_dirty = true;
        self.version = self.version.wrapping_add(1);
    }

    /// Clear all cells, setting background to specified color.
    /// Implements Background Color Erase (BCE) per VT220: erased cells
    /// receive the given background color rather than the terminal default.
    #[inline]
    pub fn clear_with_bg(&mut self, bg: Color) {
        let mut blank = Cell::default();
        blank.attrs.background = bg;
        self.cells.fill(blank);
        self.has_wide = false;
        self.is_dirty = true;
        self.version = self.version.wrapping_add(1);
    }

    /// Mark line as dirty
    #[inline]
    pub const fn mark_dirty(&mut self) {
        self.is_dirty = true;
    }

    /// Mark line as clean (not dirty)
    #[inline]
    pub const fn mark_clean(&mut self) {
        self.is_dirty = false;
    }

    /// Resize line to new column count
    pub fn resize(&mut self, new_cols: usize) {
        if new_cols > self.cells.len() {
            // Expand with default cells; no wide cells added, has_wide unchanged.
            self.cells.resize(new_cols, Cell::default());
        } else if new_cols < self.cells.len() {
            let old_len = self.cells.len();
            // Only rescan the retained cells if the removed suffix contained a wide
            // cell.  On ASCII-only terminals the suffix has no wide cells, so the full
            // O(new_cols) retained-cell rescan is skipped — O(suffix_len) instead.
            let removed_had_wide = self.cells[new_cols..old_len]
                .iter()
                .any(|c| c.width == CellWidth::Wide);
            // Truncate. Only shrink allocated capacity when it greatly exceeds the new
            // length, to avoid repeated reallocs during interactive window-resize drags.
            self.cells.truncate(new_cols);
            if self.cells.capacity() > new_cols * 2 + 16 {
                // shrink_to retains 16-cell headroom, absorbing the next drag step
                // without an immediate realloc (unlike shrink_to_fit which drops to exact).
                self.cells.shrink_to(new_cols + 16);
            }
            if removed_had_wide {
                self.has_wide = self.cells.iter().any(|c| c.width == CellWidth::Wide);
            }
        }
        self.is_dirty = true;
        self.version = self.version.wrapping_add(1);
    }
}

impl fmt::Display for Line {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for cell in &self.cells {
            write!(f, "{}", cell.grapheme.as_str())?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::cell::SgrFlags;

    #[test]
    fn test_line_creation() {
        let line = Line::new(80);
        assert_eq!(line.cells.len(), 80);
        assert!(!line.is_dirty);
    }

    #[test]
    fn test_line_update_cell() {
        let mut line = Line::new(10);
        let attrs = SgrAttributes::default();

        line.update_cell(5, 'X', attrs);

        assert!(line.is_dirty);
        assert_eq!(line.get_cell(5).unwrap().char(), 'X');
    }

    #[test]
    fn test_line_clear() {
        let mut line = Line::new(10);
        line.update_cell(0, 'A', SgrAttributes::default());

        line.clear();

        assert!(line.is_dirty);
        assert_eq!(line.get_cell(0).unwrap().char(), ' ');
    }

    #[test]
    fn test_line_resize_expand() {
        let mut line = Line::new(10);
        line.resize(20);

        assert_eq!(line.cells.len(), 20);
        assert!(line.is_dirty);
    }

    #[test]
    fn test_line_resize_shrink() {
        let mut line = Line::new(20);
        line.resize(10);

        assert_eq!(line.cells.len(), 10);
        assert!(line.is_dirty);
    }

    // ── Additional coverage ──────────────────────────────────────────────────

    #[test]
    fn test_line_new_starts_clean_and_all_space() {
        let line = Line::new(5);
        assert!(!line.is_dirty, "new line must be clean");
        for col in 0..5 {
            assert_eq!(
                line.get_cell(col).unwrap().char(),
                ' ',
                "all cells must default to space"
            );
        }
    }

    #[test]
    fn test_line_new_with_bg_default_equals_new() {
        // new_with_bg(n, Color::Default) is identical to new(n)
        let a = Line::new(8);
        let b = Line::new_with_bg(8, Color::Default);
        assert_eq!(a.cells.len(), b.cells.len());
        for col in 0..8 {
            assert_eq!(a.cells[col].char(), b.cells[col].char());
        }
    }

    #[test]
    fn test_line_new_with_bg_rgb_carries_bg_on_every_cell() {
        let bg = Color::Rgb(0xFF, 0x00, 0x80);
        let line = Line::new_with_bg(6, bg);
        assert!(!line.is_dirty, "new_with_bg line must start clean");
        for col in 0..6 {
            assert_eq!(
                line.cells[col].attrs.background, bg,
                "cell {col} must carry the specified BCE background"
            );
        }
    }

    #[test]
    fn test_line_new_with_bg_indexed_color() {
        let bg = Color::Indexed(200);
        let line = Line::new_with_bg(4, bg);
        for col in 0..4 {
            assert_eq!(
                line.cells[col].attrs.background, bg,
                "indexed background color must propagate to cell {col}"
            );
        }
    }

    #[test]
    fn test_get_cell_out_of_bounds_returns_none() {
        let line = Line::new(10);
        assert!(
            line.get_cell(10).is_none(),
            "index 10 must be None for a 10-column line"
        );
        assert!(
            line.get_cell(usize::MAX).is_none(),
            "usize::MAX index must be None"
        );
    }

    #[test]
    fn test_get_cell_mut_out_of_bounds_returns_none() {
        let mut line = Line::new(4);
        assert!(line.get_cell_mut(4).is_none());
    }

    #[test]
    fn test_get_cell_mut_allows_in_place_mutation() {
        let mut line = Line::new(4);
        if let Some(cell) = line.get_cell_mut(2) {
            cell.attrs.flags |= SgrFlags::BOLD;
        }
        assert!(
            line.get_cell(2)
                .unwrap()
                .attrs
                .flags
                .contains(SgrFlags::BOLD),
            "mutation through get_cell_mut must be visible on next read"
        );
    }

    #[test]
    fn test_update_cell_no_change_does_not_set_dirty() {
        let mut line = Line::new(10);
        // Write a space with default attrs — identical to the initial state.
        line.update_cell(0, ' ', SgrAttributes::default());
        assert!(
            !line.is_dirty,
            "updating a cell with identical content must not mark line dirty"
        );
    }

    #[test]
    fn test_update_cell_out_of_bounds_is_noop() {
        let mut line = Line::new(5);
        // update_cell to an out-of-range column must not panic and must not dirty.
        line.update_cell(100, 'X', SgrAttributes::default());
        assert!(
            !line.is_dirty,
            "out-of-bounds update_cell must not set dirty"
        );
    }

    #[test]
    fn test_update_cell_attrs_change_marks_dirty() {
        let mut line = Line::new(5);
        let mut attrs = SgrAttributes::default();
        attrs.flags |= SgrFlags::ITALIC;
        line.update_cell(0, ' ', attrs); // same char, different attrs
        assert!(line.is_dirty, "attribute change must mark line dirty");
    }

    #[test]
    fn test_update_cell_with_same_cell_no_dirty() {
        let mut line = Line::new(5);
        let default_cell = line.cells[1].clone();
        line.update_cell_with(1, default_cell);
        assert!(
            !line.is_dirty,
            "update_cell_with identical cell must not set dirty"
        );
    }

    #[test]
    fn test_update_cell_with_different_cell_marks_dirty() {
        let mut line = Line::new(5);
        let new_cell = Cell::new('Z');
        line.update_cell_with(3, new_cell);
        assert!(
            line.is_dirty,
            "update_cell_with differing cell must mark dirty"
        );
        assert_eq!(line.cells[3].char(), 'Z');
    }

    #[test]
    fn test_update_cell_with_out_of_bounds_is_noop() {
        let mut line = Line::new(5);
        let cell = Cell::new('X');
        line.update_cell_with(99, cell);
        assert!(
            !line.is_dirty,
            "out-of-bounds update_cell_with must not set dirty"
        );
    }

    #[test]
    fn test_clear_with_bg_propagates_color_to_all_cells() {
        let mut line = Line::new(6);
        // Pre-populate some cells.
        line.update_cell(2, 'A', SgrAttributes::default());
        line.is_dirty = false; // reset dirty flag manually.

        let bg = Color::Rgb(10, 20, 30);
        line.clear_with_bg(bg);

        assert!(line.is_dirty, "clear_with_bg must mark dirty");
        for col in 0..6 {
            assert_eq!(
                line.cells[col].char(),
                ' ',
                "cell {col} must be space after clear_with_bg"
            );
            assert_eq!(
                line.cells[col].attrs.background, bg,
                "cell {col} must carry BCE background after clear_with_bg"
            );
        }
    }

    #[test]
    fn test_clear_with_bg_default_color_produces_plain_spaces() {
        let mut line = Line::new(4);
        line.update_cell(0, 'A', SgrAttributes::default());
        line.clear_with_bg(Color::Default);
        for col in 0..4 {
            assert_eq!(line.cells[col].attrs.background, Color::Default);
        }
    }

    #[test]
    fn test_mark_dirty_and_mark_clean() {
        let mut line = Line::new(4);
        assert!(!line.is_dirty);
        line.mark_dirty();
        assert!(line.is_dirty, "mark_dirty must set is_dirty");
        line.mark_clean();
        assert!(!line.is_dirty, "mark_clean must clear is_dirty");
    }

    #[test]
    fn test_resize_same_size_still_marks_dirty() {
        // resize always sets is_dirty even when the column count does not change.
        let mut line = Line::new(10);
        line.resize(10);
        assert!(line.is_dirty, "resize to same size must still mark dirty");
        assert_eq!(line.cells.len(), 10);
    }

    #[test]
    fn test_resize_expand_new_cells_are_default() {
        let mut line = Line::new(3);
        line.update_cell(0, 'A', SgrAttributes::default());
        line.resize(6);
        // Original cells preserved.
        assert_eq!(line.cells[0].char(), 'A');
        // New cells must be default (space).
        for col in 3..6 {
            assert_eq!(
                line.cells[col].char(),
                ' ',
                "expanded cell {col} must default to space"
            );
        }
    }

    #[test]
    fn test_resize_shrink_preserves_remaining_content() {
        let mut line = Line::new(10);
        line.update_cell(0, 'H', SgrAttributes::default());
        line.update_cell(4, 'E', SgrAttributes::default());
        line.resize(5); // keep first 5 columns
        assert_eq!(line.cells.len(), 5);
        assert_eq!(line.cells[0].char(), 'H');
        assert_eq!(line.cells[4].char(), 'E');
    }

    #[test]
    fn test_display_renders_graphemes_in_order() {
        use std::fmt::Write as _;
        let mut line = Line::new(4);
        line.update_cell(0, 'H', SgrAttributes::default());
        line.update_cell(1, 'i', SgrAttributes::default());
        // cells 2 and 3 remain space
        let mut s = String::new();
        let _ = write!(s, "{line}");
        assert_eq!(s, "Hi  ", "Display must render graphemes in column order");
    }

    #[test]
    fn test_zero_width_line_is_valid() {
        let line = Line::new(0);
        assert_eq!(line.cells.len(), 0);
        assert!(!line.is_dirty);
        assert!(line.get_cell(0).is_none());
    }

    // ── Property-based tests (merged from tests/unit/grid/line.rs) ��─────

    use proptest::prelude::*;

    fn arb_color() -> impl Strategy<Value = Color> {
        prop_oneof![
            Just(Color::Default),
            Just(Color::Indexed(1)),
            Just(Color::Rgb(255, 0, 128)),
            Just(Color::Indexed(200)),
        ]
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(500))]

        #[test]
        fn prop_new_cell_count(cols in 1usize..200usize) {
            let line = Line::new(cols);
            prop_assert_eq!(line.cells.len(), cols);
        }

        #[test]
        fn prop_new_is_clean(cols in 1usize..200usize, bg in arb_color()) {
            let line_plain = Line::new(cols);
            prop_assert!(!line_plain.is_dirty, "Line::new must start clean");
            let line_bg = Line::new_with_bg(cols, bg);
            prop_assert!(!line_bg.is_dirty, "Line::new_with_bg must start clean");
        }

        #[test]
        fn prop_get_cell_bounds(cols in 1usize..100usize, col in 0usize..200usize) {
            let line = Line::new(cols);
            if col < cols {
                prop_assert!(line.get_cell(col).is_some());
            } else {
                prop_assert!(line.get_cell(col).is_none());
            }
        }

        #[test]
        fn prop_update_cell_marks_dirty(cols in 1usize..100usize, col in 0usize..100usize) {
            let col = col % cols;
            let mut line = Line::new(cols);
            line.update_cell(col, 'X', SgrAttributes::default());
            prop_assert!(line.is_dirty);
        }

        #[test]
        fn prop_clear_all_default(cols in 1usize..100usize) {
            let mut line = Line::new(cols);
            for i in 0..cols {
                if i % 3 == 0 {
                    line.update_cell(i, 'Q', SgrAttributes::default());
                }
            }
            line.clear();
            prop_assert!(line.is_dirty);
            let expected = Cell::default();
            for (i, cell) in line.cells.iter().enumerate() {
                prop_assert_eq!(cell, &expected,
                    "cell at col {} is not Cell::default() after clear()", i);
            }
        }

        #[test]
        fn prop_clear_with_bg_applies_background(
            cols in 1usize..100usize,
            bg in arb_color(),
        ) {
            let mut line = Line::new(cols);
            line.clear_with_bg(bg);
            prop_assert!(line.is_dirty);
            for (i, cell) in line.cells.iter().enumerate() {
                prop_assert_eq!(cell.attrs.background, bg,
                    "cell at col {} has wrong background after clear_with_bg()", i);
            }
        }

        #[test]
        fn prop_resize_up_preserves_len(
            cols in 1usize..100usize,
            extra in 0usize..100usize,
        ) {
            let mut line = Line::new(cols);
            let new_cols = cols + extra;
            line.resize(new_cols);
            prop_assert_eq!(line.cells.len(), new_cols);
        }

        #[test]
        fn prop_resize_down_truncates(
            cols in 2usize..100usize,
            shrink in 1usize..100usize,
        ) {
            let new_cols = (cols.saturating_sub(shrink)).max(1);
            prop_assume!(new_cols < cols);
            let mut line = Line::new(cols);
            line.resize(new_cols);
            prop_assert_eq!(line.cells.len(), new_cols);
        }

        #[test]
        fn prop_mark_dirty_clean_toggle(cols in 1usize..100usize) {
            let mut line = Line::new(cols);
            prop_assert!(!line.is_dirty);
            line.mark_dirty();
            prop_assert!(line.is_dirty);
            line.mark_clean();
            prop_assert!(!line.is_dirty);
            line.mark_dirty();
            prop_assert!(line.is_dirty);
            line.mark_clean();
            prop_assert!(!line.is_dirty);
        }
    }

    // ── Additional example-based tests (merged from tests/unit/grid/line.rs) ─

    #[test]
    fn pbt_new_with_bg_default_equals_new() {
        let cols = 40usize;
        let plain = Line::new(cols);
        let with_default_bg = Line::new_with_bg(cols, Color::Default);
        assert_eq!(plain.cells.len(), with_default_bg.cells.len());
        for (i, (a, b)) in plain.cells.iter().zip(with_default_bg.cells.iter()).enumerate() {
            assert_eq!(a, b, "cell mismatch at col {i}");
        }
    }

    #[test]
    fn pbt_update_cell_same_content_stays_clean() {
        let mut line = Line::new(10);
        line.update_cell(3, 'A', SgrAttributes::default());
        line.mark_clean();
        line.update_cell(3, 'A', SgrAttributes::default());
        assert!(!line.is_dirty);
    }

    #[test]
    fn pbt_update_cell_different_content_marks_dirty() {
        let mut line = Line::new(10);
        line.update_cell(5, 'X', SgrAttributes::default());
        line.mark_clean();
        line.update_cell(5, 'Y', SgrAttributes::default());
        assert!(line.is_dirty);
    }

    #[test]
    fn pbt_update_cell_with_same_cell_stays_clean() {
        let mut line = Line::new(10);
        line.mark_clean();
        line.update_cell_with(3, Cell::default());
        assert!(!line.is_dirty);
    }

    #[test]
    fn pbt_update_cell_with_different_cell_marks_dirty() {
        let mut line = Line::new(10);
        line.mark_clean();
        let mut scratch = Line::new(1);
        scratch.update_cell(0, 'Z', SgrAttributes::default());
        let z_cell = scratch.cells[0].clone();
        line.update_cell_with(4, z_cell);
        assert!(line.is_dirty);
    }

    #[test]
    fn pbt_update_cell_with_out_of_bounds_is_noop() {
        let mut line = Line::new(5);
        line.mark_clean();
        line.update_cell_with(10, Cell::default());
        assert!(!line.is_dirty);
    }

    #[test]
    fn pbt_get_cell_mut_bounds() {
        let mut line = Line::new(8);
        assert!(line.get_cell_mut(0).is_some());
        assert!(line.get_cell_mut(7).is_some());
        assert!(line.get_cell_mut(8).is_none());
    }

    #[test]
    fn pbt_get_cell_mut_modifies_cell() {
        let mut line = Line::new(8);
        line.update_cell(3, 'Z', SgrAttributes::default());
        {
            let cell = line.get_cell_mut(3).unwrap();
            assert_eq!(cell.grapheme.as_str(), "Z");
            cell.attrs.background = Color::Indexed(1);
        }
        assert_eq!(line.get_cell(3).unwrap().attrs.background, Color::Indexed(1));
    }

    #[test]
    fn pbt_display_renders_graphemes() {
        let mut line = Line::new(5);
        line.update_cell(0, 'H', SgrAttributes::default());
        line.update_cell(1, 'i', SgrAttributes::default());
        let s = line.to_string();
        assert_eq!(&s[..2], "Hi");
        assert_eq!(s.len(), 5);
    }

    #[test]
    fn pbt_resize_same_size_marks_dirty() {
        let mut line = Line::new(10);
        assert!(!line.is_dirty);
        line.resize(10);
        assert!(line.is_dirty);
        assert_eq!(line.cells.len(), 10);
    }

    /// Assert that every cell in `line` carries `expected_bg` as its background.
    #[inline]
    fn assert_all_cells_have_bg(line: &Line, expected_bg: Color, label: &str) {
        assert!(!line.cells.is_empty(), "{label}: line must be non-empty");
        for (i, cell) in line.cells.iter().enumerate() {
            assert_eq!(cell.attrs.background, expected_bg,
                "{label}: cell at col {i} must have background {expected_bg:?}");
        }
    }

    macro_rules! assert_new_with_bg {
        ($name:ident, $cols:expr, $bg:expr, $label:expr) => {
            #[test]
            fn $name() {
                let bg = $bg;
                let line = Line::new_with_bg($cols, bg);
                assert_eq!(line.cells.len(), $cols);
                assert_all_cells_have_bg(&line, bg, $label);
            }
        };
    }

    assert_new_with_bg!(pbt_new_with_bg_all_cells_carry_bg, 8, Color::Indexed(42), "new_with_bg(Indexed(42))");
    assert_new_with_bg!(pbt_new_with_bg_rgb_first_and_last, 5, Color::Rgb(10, 20, 30), "new_with_bg(Rgb(10,20,30))");

    macro_rules! assert_clear_with_bg_cells {
        ($name:ident, $setup:expr, $bg:expr, $check:expr, $msg:expr) => {
            #[test]
            fn $name() {
                let bg = $bg;
                let mut line = $setup;
                line.clear_with_bg(bg);
                assert!(line.is_dirty);
                for (i, cell) in line.cells.iter().enumerate() {
                    let check: &dyn Fn(&Cell, usize) = &$check;
                    check(cell, i);
                }
            }
        };
    }

    assert_clear_with_bg_cells!(
        pbt_clear_with_bg_default_equals_cell_default,
        { let mut l = Line::new(6); l.update_cell(2, 'Q', SgrAttributes::default()); l },
        Color::Default,
        |cell, i| { assert_eq!(cell, &Cell::default(), "cell at col {i} must equal Cell::default()"); },
        "clear_with_bg(Default)"
    );

    assert_clear_with_bg_cells!(
        pbt_clear_with_bg_overwrites_existing_bg,
        Line::new_with_bg(4, Color::Indexed(1)),
        Color::Indexed(7),
        |cell, i| { assert_eq!(cell.attrs.background, Color::Indexed(7), "cell at col {i} must have new bg"); },
        "clear_with_bg overwrite"
    );

    #[test]
    fn pbt_update_cell_out_of_bounds_is_noop() {
        let mut line = Line::new(5);
        line.mark_clean();
        line.update_cell(5, 'X', SgrAttributes::default());
        assert!(!line.is_dirty);
        line.update_cell(999, 'Y', SgrAttributes::default());
        assert!(!line.is_dirty);
    }

    #[test]
    fn pbt_update_cell_attrs_change_marks_dirty() {
        let mut line = Line::new(10);
        line.update_cell(3, 'A', SgrAttributes::default());
        line.mark_clean();
        let new_attrs = SgrAttributes { background: Color::Indexed(5), ..Default::default() };
        line.update_cell(3, 'A', new_attrs);
        assert!(line.is_dirty);
        assert_eq!(line.get_cell(3).unwrap().attrs.background, Color::Indexed(5));
    }

    #[test]
    fn pbt_new_zero_cols_is_empty_line() {
        let line = Line::new(0);
        assert_eq!(line.cells.len(), 0);
        assert!(!line.is_dirty);
        assert!(line.get_cell(0).is_none());
    }

    #[test]
    fn pbt_get_cell_first_and_last_valid_indices() {
        let cols = 8usize;
        let line = Line::new(cols);
        assert!(line.get_cell(0).is_some());
        assert!(line.get_cell(cols - 1).is_some());
        assert!(line.get_cell(cols).is_none());
    }

    #[test]
    fn pbt_clear_on_clean_line_sets_dirty() {
        let mut line = Line::new(4);
        assert!(!line.is_dirty);
        line.clear();
        assert!(line.is_dirty);
    }

    #[test]
    fn pbt_display_single_char_sequence() {
        let mut line = Line::new(3);
        line.update_cell(0, 'A', SgrAttributes::default());
        line.update_cell(1, 'B', SgrAttributes::default());
        line.update_cell(2, 'C', SgrAttributes::default());
        assert_eq!(line.to_string(), "ABC");
    }

    #[test]
    fn pbt_resize_to_zero_truncates_all_cells() {
        let mut line = Line::new(10);
        line.resize(0);
        assert_eq!(line.cells.len(), 0);
        assert!(line.is_dirty);
        assert!(line.get_cell(0).is_none());
    }

    #[test]
    fn pbt_resize_shrink_preserves_remaining_cells() {
        let mut line = Line::new(10);
        for i in 0..10 {
            line.update_cell(i, char::from_u32(b'A' as u32 + i as u32).unwrap(), SgrAttributes::default());
        }
        line.resize(4);
        assert_eq!(line.cells.len(), 4);
        for i in 0..4 {
            let expected = char::from_u32(b'A' as u32 + i as u32).unwrap();
            assert_eq!(line.get_cell(i).unwrap().grapheme.as_str(), expected.to_string());
        }
    }
}
