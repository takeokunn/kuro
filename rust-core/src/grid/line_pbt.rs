// ── Property-based tests (merged from tests/unit/grid/line.rs) ──────────────

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

// ── Additional example-based tests (merged from tests/unit/grid/line.rs) ─────

#[test]
fn pbt_new_with_bg_default_equals_new() {
    let cols = 40usize;
    let plain = Line::new(cols);
    let with_default_bg = Line::new_with_bg(cols, Color::Default);
    assert_eq!(plain.cells.len(), with_default_bg.cells.len());
    for (i, (a, b)) in plain
        .cells
        .iter()
        .zip(with_default_bg.cells.iter())
        .enumerate()
    {
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
    assert_eq!(
        line.get_cell(3).unwrap().attrs.background,
        Color::Indexed(1)
    );
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
        assert_eq!(
            cell.attrs.background, expected_bg,
            "{label}: cell at col {i} must have background {expected_bg:?}"
        );
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

assert_new_with_bg!(
    pbt_new_with_bg_all_cells_carry_bg,
    8,
    Color::Indexed(42),
    "new_with_bg(Indexed(42))"
);
assert_new_with_bg!(
    pbt_new_with_bg_rgb_first_and_last,
    5,
    Color::Rgb(10, 20, 30),
    "new_with_bg(Rgb(10,20,30))"
);

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
    {
        let mut l = Line::new(6);
        l.update_cell(2, 'Q', SgrAttributes::default());
        l
    },
    Color::Default,
    |cell, i| {
        assert_eq!(
            cell,
            &Cell::default(),
            "cell at col {i} must equal Cell::default()"
        );
    },
    "clear_with_bg(Default)"
);

assert_clear_with_bg_cells!(
    pbt_clear_with_bg_overwrites_existing_bg,
    Line::new_with_bg(4, Color::Indexed(1)),
    Color::Indexed(7),
    |cell, i| {
        assert_eq!(
            cell.attrs.background,
            Color::Indexed(7),
            "cell at col {i} must have new bg"
        );
    },
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
    let new_attrs = SgrAttributes {
        background: Color::Indexed(5),
        ..Default::default()
    };
    line.update_cell(3, 'A', new_attrs);
    assert!(line.is_dirty);
    assert_eq!(
        line.get_cell(3).unwrap().attrs.background,
        Color::Indexed(5)
    );
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
        line.update_cell(
            i,
            char::from_u32(b'A' as u32 + i as u32).unwrap(),
            SgrAttributes::default(),
        );
    }
    line.resize(4);
    assert_eq!(line.cells.len(), 4);
    for i in 0..4 {
        let expected = char::from_u32(b'A' as u32 + i as u32).unwrap();
        assert_eq!(
            line.get_cell(i).unwrap().grapheme.as_str(),
            expected.to_string()
        );
    }
}
