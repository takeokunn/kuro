use super::tests_support::*;
use crate::grid::Line;
use crate::types::cell::{Cell, CellWidth, SgrAttributes, SgrFlags};
use crate::types::color::Color;
use proptest::prelude::*;

line_state_case!(
    new_line_starts_clean_with_spaces,
    Line::new(4),
    len: 4,
    dirty: false,
    text: "    "
);

line_state_case!(
    zero_width_line_is_valid,
    Line::new(0),
    len: 0,
    dirty: false,
    text: ""
);

line_state_case!(
    display_renders_graphemes_in_order,
    line_with_text("Hi  "),
    len: 4,
    dirty: true,
    text: "Hi  "
);

#[test]
fn new_with_bg_cases_apply_background_without_dirtying() {
    for (cols, bg) in [
        (0, Color::Default),
        (4, Color::Default),
        (5, Color::Indexed(200)),
        (6, Color::Rgb(0xff, 0x00, 0x80)),
    ] {
        let line = Line::new_with_bg(cols, bg);
        assert_eq!(line.cells.len(), cols);
        assert!(!line.is_dirty);
        assert_all_cells_have_bg(&line, bg);
    }
}

#[test]
fn get_cell_cases_handle_bounds() {
    let mut line = Line::new(4);

    assert!(line.get_cell(0).is_some());
    assert!(line.get_cell(3).is_some());
    assert!(line.get_cell(4).is_none());
    assert!(line.get_cell(usize::MAX).is_none());

    assert!(line.get_cell_mut(0).is_some());
    assert!(line.get_cell_mut(3).is_some());
    assert!(line.get_cell_mut(4).is_none());
}

#[test]
fn get_cell_mut_exposes_in_place_mutation() {
    let mut line = Line::new(DEFAULT_COLS);

    line.get_cell_mut(2).unwrap().attrs.flags |= SgrFlags::BOLD;

    assert!(
        line.get_cell(2)
            .unwrap()
            .attrs
            .flags
            .contains(SgrFlags::BOLD)
    );
}

#[test]
fn update_cell_cases_change_only_when_content_or_attrs_change() {
    let mut line = Line::new(DEFAULT_COLS);

    line.update_cell(0, ' ', SgrAttributes::default());
    assert!(!line.is_dirty, "same content and attrs stay clean");

    line.update_cell(DEFAULT_COLS, 'X', SgrAttributes::default());
    assert!(!line.is_dirty, "out-of-bounds write stays clean");

    line.update_cell(3, 'X', SgrAttributes::default());
    assert!(line.is_dirty);
    assert_eq!(line.get_cell(3).unwrap().char(), 'X');

    line.mark_clean();
    line.update_cell(3, 'X', attrs_with_bg(Color::Indexed(5)));
    assert!(line.is_dirty, "attrs-only change marks dirty");
    assert_eq!(
        line.get_cell(3).unwrap().attrs.background,
        Color::Indexed(5)
    );
}

#[test]
fn update_cell_with_cases_track_dirty_and_wide_flag() {
    let mut line = Line::new(DEFAULT_COLS);
    let default_cell = line.cells[1].clone();

    line.update_cell_with(1, default_cell);
    assert!(!line.is_dirty, "identical cell stays clean");

    line.update_cell_with(DEFAULT_COLS, Cell::new('X'));
    assert!(!line.is_dirty, "out-of-bounds cell write stays clean");

    line.update_cell_with(3, Cell::new('Z'));
    assert!(line.is_dirty);
    assert_eq!(line.cells[3].char(), 'Z');
    assert!(!line.has_wide);

    line.mark_clean();
    line.update_cell_with(
        4,
        Cell::with_char_and_width(' ', SgrAttributes::default(), CellWidth::Wide),
    );
    assert!(line.is_dirty);
    assert!(line.has_wide);
}

#[test]
fn clear_cases_reset_cells_wide_and_wrap_state() {
    let mut line = Line::new(DEFAULT_COLS);
    line.update_cell_with(
        2,
        Cell::with_char_and_width(' ', SgrAttributes::default(), CellWidth::Wide),
    );
    line.wrapped = true;
    line.mark_clean();

    line.clear();

    assert!(line.is_dirty);
    assert!(!line.has_wide);
    assert!(!line.wrapped);
    assert_cells_are_default(&line);
}

#[test]
fn clear_with_bg_cases_apply_bce_and_reset_flags() {
    for bg in [
        Color::Default,
        Color::Indexed(7),
        Color::Rgb(10, 20, 30),
    ] {
        let mut line = line_with_text("abcdef");
        line.has_wide = true;
        line.wrapped = true;
        line.mark_clean();

        line.clear_with_bg(bg);

        assert!(line.is_dirty);
        assert!(!line.has_wide);
        assert!(!line.wrapped);
        assert_eq!(line.to_string(), "      ");
        assert_all_cells_have_bg(&line, bg);
    }
}

#[test]
fn dirty_marking_and_version_bump_cases() {
    let mut line = Line::new(DEFAULT_COLS);
    let version = line.version;

    line.mark_dirty();
    assert!(line.is_dirty);

    line.mark_clean();
    assert!(!line.is_dirty);

    line.mark_dirty_and_bump();
    assert!(line.is_dirty);
    assert_eq!(line.version, version.wrapping_add(1));

    line.mark_dirty_and_bump();
    assert_eq!(line.version, version.wrapping_add(2));
}

#[test]
fn resize_cases_adjust_cells_and_reset_wrap() {
    let mut line = line_with_text("HelloWorld");
    line.update_cell_with(
        7,
        Cell::with_char_and_width(' ', SgrAttributes::default(), CellWidth::Wide),
    );

    line.wrapped = true;
    line.mark_clean();
    line.resize(5);
    assert_eq!(line.cells.len(), 5);
    assert_eq!(line.to_string(), "Hello");
    assert!(line.is_dirty);
    assert!(!line.wrapped);
    assert!(!line.has_wide, "removed suffix contained the only wide cell");

    line.mark_clean();
    line.wrapped = true;
    line.resize(8);
    assert_eq!(line.cells.len(), 8);
    assert_eq!(line.to_string(), "Hello   ");
    assert!(line.is_dirty);
    assert!(!line.wrapped);

    line.mark_clean();
    line.resize(8);
    assert!(line.is_dirty, "same-size resize still invalidates render state");

    line.resize(0);
    assert_eq!(line.cells.len(), 0);
    assert!(line.get_cell(0).is_none());
}

#[test]
fn resize_keeps_wide_flag_when_retained_cells_are_wide() {
    let mut line = Line::new(DEFAULT_COLS);
    line.update_cell_with(
        1,
        Cell::with_char_and_width(' ', SgrAttributes::default(), CellWidth::Wide),
    );

    line.resize(4);

    assert!(line.has_wide);
}

fn arb_color() -> impl Strategy<Value = Color> {
    prop_oneof![
        Just(Color::Default),
        Just(Color::Indexed(1)),
        Just(Color::Indexed(200)),
        Just(Color::Rgb(255, 0, 128)),
    ]
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    fn prop_new_preserves_requested_width_and_starts_clean(cols in 0usize..200usize) {
        let line = Line::new(cols);
        prop_assert_eq!(line.cells.len(), cols);
        prop_assert!(!line.is_dirty);
        prop_assert!(!line.wrapped);
    }

    #[test]
    fn prop_new_with_bg_preserves_width_and_background(
        cols in 0usize..200usize,
        bg in arb_color(),
    ) {
        let line = Line::new_with_bg(cols, bg);
        prop_assert_eq!(line.cells.len(), cols);
        prop_assert!(!line.is_dirty);
        for cell in &line.cells {
            prop_assert_eq!(cell.attrs.background, bg);
        }
    }

    #[test]
    fn prop_get_cell_matches_bounds(cols in 0usize..100usize, col in 0usize..200usize) {
        let line = Line::new(cols);
        prop_assert_eq!(line.get_cell(col).is_some(), col < cols);
    }

    #[test]
    fn prop_update_cell_is_noop_outside_bounds(
        cols in 0usize..100usize,
        col in 0usize..200usize,
    ) {
        let mut line = Line::new(cols);
        line.update_cell(col, 'X', SgrAttributes::default());
        prop_assert_eq!(line.is_dirty, col < cols);
    }

    #[test]
    fn prop_clear_restores_default_cells(cols in 0usize..100usize) {
        let mut line = Line::new(cols);
        for col in 0..cols {
            if col % 3 == 0 {
                line.update_cell(col, 'Q', SgrAttributes::default());
            }
        }

        line.clear();

        prop_assert!(line.is_dirty);
        for cell in &line.cells {
            prop_assert_eq!(cell, &Cell::default());
        }
    }

    #[test]
    fn prop_clear_with_bg_applies_background(cols in 0usize..100usize, bg in arb_color()) {
        let mut line = Line::new(cols);

        line.clear_with_bg(bg);

        prop_assert!(line.is_dirty);
        for cell in &line.cells {
            prop_assert_eq!(cell.attrs.background, bg);
        }
    }

    #[test]
    fn prop_resize_sets_exact_len(
        cols in 0usize..100usize,
        new_cols in 0usize..150usize,
    ) {
        let mut line = Line::new(cols);

        line.resize(new_cols);

        prop_assert_eq!(line.cells.len(), new_cols);
        prop_assert!(line.is_dirty);
        prop_assert!(!line.wrapped);
    }

    #[test]
    fn prop_mark_dirty_clean_toggle(cols in 0usize..100usize) {
        let mut line = Line::new(cols);

        prop_assert!(!line.is_dirty);
        line.mark_dirty();
        prop_assert!(line.is_dirty);
        line.mark_clean();
        prop_assert!(!line.is_dirty);
    }
}
