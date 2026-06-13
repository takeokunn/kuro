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

