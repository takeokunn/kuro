use super::*;
use proptest::prelude::*;

// ── Local test-only macros ────────────────────────────────────────────────────

/// Assert cursor position (uses the active-screen cursor via `cursor()`).
macro_rules! assert_cursor {
    ($screen:expr, row $r:expr, col $c:expr) => {
        assert_eq!($screen.cursor().row, $r, "cursor.row mismatch");
        assert_eq!($screen.cursor().col, $c, "cursor.col mismatch");
    };
}

/// Assert a single cell's char value.
macro_rules! assert_cell_char {
    ($screen:expr, row $r:expr, col $c:expr, $ch:expr) => {
        assert_eq!(
            $screen.get_cell($r, $c).unwrap().char(),
            $ch,
            "cell ({},{}) char mismatch",
            $r,
            $c
        );
    };
    ($screen:expr, row $r:expr, col $c:expr, $ch:expr, $msg:literal) => {
        assert_eq!($screen.get_cell($r, $c).unwrap().char(), $ch, $msg);
    };
}

/// Assert a single cell's `CellWidth`.
macro_rules! assert_cell_width {
    ($screen:expr, row $r:expr, col $c:expr, $w:expr) => {
        assert_eq!(
            $screen.get_cell($r, $c).unwrap().width,
            $w,
            "cell ({},{}) width mismatch",
            $r,
            $c
        );
    };
    ($screen:expr, row $r:expr, col $c:expr, $w:expr, $msg:literal) => {
        assert_eq!($screen.get_cell($r, $c).unwrap().width, $w, $msg);
    };
}

/// Assert that `take_dirty_lines()` (sorted) equals the expected vec.
macro_rules! assert_dirty_sorted {
    ($screen:expr, $expected:expr) => {{
        let mut _d = $screen.take_dirty_lines();
        _d.sort_unstable();
        assert_eq!(_d, $expected);
    }};
}

/// Create a `Screen` and call `scroll_up` `$n` times to build up scrollback.
macro_rules! screen_with_scrollback {
    ($rows:literal x $cols:literal, scrollback $n:expr) => {{
        let mut _s = Screen::new($rows, $cols);
        for _ in 0..$n {
            _s.scroll_up(1, Color::Default);
        }
        _s
    }};
}

// ── Original tests (using macros where they reduce noise) ─────────────────────

#[test]
fn test_screen_creation() {
    let screen = Screen::new(24, 80);
    assert_eq!(screen.rows(), 24);
    assert_eq!(screen.cols(), 80);
    assert_cursor!(screen, row 0, col 0);
}

#[test]
fn test_print_character() {
    let mut screen = Screen::new(24, 80);
    screen.print('A', SgrAttributes::default(), true);

    assert_cell_char!(screen, row 0, col 0, 'A');
    assert_eq!(screen.cursor.col, 1);
}

#[test]
fn test_line_feed() {
    let mut screen = Screen::new(24, 80);
    screen.line_feed(Color::Default);

    assert_cursor!(screen, row 1, col 0);
}

#[test]
fn test_carriage_return() {
    let mut screen = Screen::new(24, 80);
    screen.cursor.col = 10;
    screen.carriage_return();

    assert_eq!(screen.cursor.col, 0);
}

#[test]
fn test_backspace() {
    let mut screen = Screen::new(24, 80);
    screen.cursor.col = 5;
    screen.backspace();

    assert_eq!(screen.cursor.col, 4);
}

#[test]
fn test_tab() {
    let mut screen = Screen::new(24, 80);
    screen.tab();

    assert_eq!(screen.cursor.col, 8);
}

#[test]
fn test_scroll_up() {
    let mut screen = Screen::new(24, 80);
    screen.lines[0].mark_dirty();
    assert!(screen.lines[0].is_dirty);

    screen.scroll_up(1, Color::Default);

    assert!(!screen.lines[0].is_dirty);
}

#[test]
fn test_dirty_lines() {
    let mut screen = Screen::new(24, 80);
    screen.print('A', SgrAttributes::default(), true);
    let dirty = screen.take_dirty_lines();

    assert_eq!(dirty.len(), 1);
    assert_eq!(dirty[0], 0);

    let dirty2 = screen.take_dirty_lines();
    assert_eq!(dirty2.len(), 0);
}

#[test]
fn test_resize() {
    let mut screen = Screen::new(24, 80);
    screen.resize(10, 40);

    assert_eq!(screen.rows(), 10);
    assert_eq!(screen.cols(), 40);
    assert_eq!(screen.lines.len(), 10);
    assert_eq!(screen.lines[0].cells.len(), 40);
}

#[test]
fn test_screen_creation_with_scrollback() {
    let screen = Screen::new(24, 80);
    assert_eq!(screen.rows(), 24);
    assert_eq!(screen.cols(), 80);
    assert_cursor!(screen, row 0, col 0);
    assert_eq!(screen.scrollback_line_count, 0);
    assert_eq!(screen.scrollback_max_lines, 10000);
}

#[test]
fn test_scroll_up_saves_to_scrollback() {
    let screen = screen_with_scrollback!(5 x 80, scrollback 3);

    assert_eq!(screen.scrollback_line_count, 3);
    assert_eq!(screen.scrollback_buffer.len(), 3);
}

#[test]
fn test_scrollback_trimming() {
    let mut screen = Screen::new(5, 80);
    screen.set_scrollback_max_lines(3);
    for _ in 0..10 {
        screen.scroll_up(1, Color::Default);
    }

    assert_eq!(screen.scrollback_line_count, 3);
    assert_eq!(screen.scrollback_buffer.len(), 3);
}

#[test]
fn test_get_scrollback_lines() {
    let screen = screen_with_scrollback!(24 x 80, scrollback 5);

    let lines = screen.get_scrollback_lines(3);
    assert_eq!(lines.len(), 3);

    let all_lines = screen.get_scrollback_lines(100);
    assert_eq!(all_lines.len(), 5);
}

#[test]
fn test_clear_scrollback() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 5);
    assert_eq!(screen.scrollback_line_count, 5);

    screen.clear_scrollback();

    assert_eq!(screen.scrollback_line_count, 0);
    assert!(screen.scrollback_buffer.is_empty());
}

#[test]
fn test_scrollback_not_saved_in_alternate_screen() {
    let mut screen = Screen::new(5, 80);
    screen.switch_to_alternate();
    assert!(screen.is_alternate_screen_active());

    for _ in 0..3 {
        screen.scroll_up(1, Color::Default);
    }
    assert_eq!(screen.scrollback_line_count, 0);

    screen.switch_to_primary();
    assert!(!screen.is_alternate_screen_active());

    screen.scroll_up(1, Color::Default);
    assert_eq!(screen.scrollback_line_count, 1);
}

#[test]
fn test_resize_updates_scrollback_lines() {
    let mut screen = screen_with_scrollback!(5 x 80, scrollback 3);
    screen.resize(10, 40);

    assert_eq!(screen.scrollback_buffer.len(), 3);
    assert_eq!(screen.scrollback_buffer[0].cells.len(), 40);
}

#[test]
fn test_alt_screen_cursor_routing() {
    let mut screen = Screen::new(24, 80);
    screen.move_cursor(5, 10);
    assert_cursor!(screen, row 5, col 10);

    screen.switch_to_alternate();
    assert_cursor!(screen, row 0, col 0);

    screen.move_cursor(3, 7);
    assert_cursor!(screen, row 3, col 7);

    screen.switch_to_primary();
    assert_cursor!(screen, row 5, col 10);
}

#[test]
fn test_alt_screen_dirty_lines_routing() {
    let mut screen = Screen::new(24, 80);
    screen.mark_line_dirty(2);

    screen.switch_to_alternate();
    let _ = screen.take_dirty_lines();

    screen.mark_line_dirty(5);
    let alt_dirty = screen.take_dirty_lines();
    assert_eq!(alt_dirty, vec![5]);

    screen.switch_to_primary();
    let _ = screen.take_dirty_lines();

    screen.mark_line_dirty(2);
    let primary_dirty = screen.take_dirty_lines();
    assert!(primary_dirty.contains(&2));
}

#[test]
fn test_full_dirty_initially_false() {
    let screen = Screen::new(24, 80);
    assert!(!screen.full_dirty, "full_dirty should be false on creation");
}

#[test]
fn test_mark_all_dirty_sets_flag() {
    let mut screen = Screen::new(24, 80);
    screen.mark_all_dirty();
    assert!(
        screen.full_dirty,
        "mark_all_dirty should set full_dirty = true"
    );
}

#[test]
fn test_take_dirty_lines_full_dirty_returns_all_rows() {
    let mut screen = Screen::new(4, 80);
    screen.mark_all_dirty();
    assert_dirty_sorted!(screen, vec![0, 1, 2, 3]);
}

#[test]
fn test_take_dirty_lines_clears_full_dirty() {
    let mut screen = Screen::new(4, 80);
    screen.mark_all_dirty();
    let _ = screen.take_dirty_lines();
    assert!(
        !screen.full_dirty,
        "full_dirty should be cleared after take_dirty_lines"
    );
    let dirty2 = screen.take_dirty_lines();
    assert!(dirty2.is_empty(), "dirty_set should also be empty");
}

#[test]
fn test_take_dirty_lines_full_dirty_also_clears_dirty_set() {
    let mut screen = Screen::new(4, 80);
    screen.mark_line_dirty(1);
    screen.mark_line_dirty(3);
    screen.mark_all_dirty();
    let _ = screen.take_dirty_lines();
    let dirty2 = screen.take_dirty_lines();
    assert!(
        dirty2.is_empty(),
        "dirty_set should be cleared when full_dirty is consumed"
    );
}

#[test]
fn test_switch_to_alternate_uses_full_dirty() {
    let mut screen = Screen::new(4, 10);
    screen.switch_to_alternate();
    assert_dirty_sorted!(screen, vec![0, 1, 2, 3]);
}

#[test]
fn test_switch_to_primary_uses_full_dirty() {
    let mut screen = Screen::new(4, 10);
    screen.switch_to_alternate();
    let _ = screen.take_dirty_lines();
    screen.switch_to_primary();
    assert_dirty_sorted!(screen, vec![0, 1, 2, 3]);
}

// ── Phase 11: Unicode & CJK tests ────────────────────────────────────────

#[test]
fn test_print_cjk_basic() {
    let mut screen = Screen::new(24, 80);
    screen.print('日', SgrAttributes::default(), true);

    assert_cell_char!(screen, row 0, col 0, '日');
    assert_cell_width!(screen, row 0, col 0, CellWidth::Full);
    assert_cell_char!(screen, row 0, col 1, ' ');
    assert_cell_width!(screen, row 0, col 1, CellWidth::Wide);
    assert_eq!(screen.cursor.col, 2);
}

#[test]
fn test_print_cjk_cursor_position() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();
    screen.print('日', attrs, true);
    screen.print('本', attrs, true);
    screen.print('語', attrs, true);

    assert_eq!(screen.cursor.col, 6);
    for (col, expected_width) in [
        (0, CellWidth::Full),
        (1, CellWidth::Wide),
        (2, CellWidth::Full),
        (3, CellWidth::Wide),
        (4, CellWidth::Full),
        (5, CellWidth::Wide),
    ] {
        assert_cell_width!(screen, row 0, col col, expected_width);
    }
}

#[test]
fn test_print_cjk_wrap() {
    let mut screen = Screen::new(24, 80);
    screen.move_cursor(0, 79);
    screen.print('日', SgrAttributes::default(), true);

    assert_cell_char!(screen, row 1, col 0, '日');
    assert_cell_width!(screen, row 1, col 0, CellWidth::Full);
    assert_cell_width!(screen, row 1, col 1, CellWidth::Wide);
}

#[test]
fn test_print_emoji() {
    let mut screen = Screen::new(24, 80);
    screen.print('🎉', SgrAttributes::default(), true);

    assert_cell_char!(screen, row 0, col 0, '🎉');
    assert_cell_width!(screen, row 0, col 0, CellWidth::Full);
    assert_cell_width!(screen, row 0, col 1, CellWidth::Wide);
    assert_eq!(screen.cursor.col, 2);
}

#[test]
fn test_dch_at_wide_placeholder_blanks_full_partner() {
    let mut screen = Screen::new(24, 80);
    screen.print('日', SgrAttributes::default(), true);

    screen.move_cursor(0, 1);
    screen.delete_chars(1);

    assert_cell_width!(screen, row 0, col 0, CellWidth::Half, "Full partner must be blanked when DCH hits Wide placeholder");
    assert_cell_char!(screen, row 0, col 0, ' ');
}

#[test]
fn test_dch_at_full_cell_blanks_wide_partner() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();
    screen.print('A', attrs, true);
    screen.print('日', attrs, true);

    screen.move_cursor(0, 1);
    screen.delete_chars(1);

    assert_cell_width!(screen, row 0, col 1, CellWidth::Half, "Wide partner must be blanked when Full cell is DCH'd");
}

#[test]
fn test_ich_at_wide_placeholder_blanks_full_partner() {
    let mut screen = Screen::new(24, 10);
    screen.print('日', SgrAttributes::default(), true);

    screen.move_cursor(0, 1);
    screen.insert_chars(1, SgrAttributes::default());

    assert_cell_width!(screen, row 0, col 0, CellWidth::Half, "Full partner must be blanked when ICH inserts at Wide placeholder");
    assert_cell_char!(screen, row 0, col 0, ' ');
}

#[test]
fn test_ech_range_ends_at_full_blanks_wide_partner() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();
    screen.print('A', attrs, true);
    screen.print('日', attrs, true);

    screen.move_cursor(0, 0);
    screen.erase_chars(2, attrs);

    assert_cell_width!(screen, row 0, col 2, CellWidth::Half, "Wide partner must be blanked when ECH range ends on Full cell");
    assert_cell_char!(screen, row 0, col 2, ' ');
}

#[test]
fn test_ech_starts_at_wide_blanks_full_partner() {
    let mut screen = Screen::new(24, 80);
    screen.print('日', SgrAttributes::default(), true);

    screen.move_cursor(0, 1);
    screen.erase_chars(1, SgrAttributes::default());

    assert_cell_width!(screen, row 0, col 0, CellWidth::Half, "Full partner must be blanked when ECH starts at Wide placeholder");
    assert_cell_char!(screen, row 0, col 0, ' ');
    assert_cell_width!(screen, row 0, col 1, CellWidth::Half);
}

// ── Phase 12: Scrollback Viewport Navigation tests ─────────────────────

#[test]
fn test_viewport_scroll_up_basic() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    assert_eq!(screen.scroll_offset(), 0);
    screen.viewport_scroll_up(10);
    assert_eq!(screen.scroll_offset(), 10);
    assert!(screen.is_scroll_dirty());
}

#[test]
fn test_viewport_scroll_up_clamps_at_buffer_size() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    let max = screen.scrollback_line_count;
    screen.viewport_scroll_up(max + 1000);
    assert_eq!(screen.scroll_offset(), max);
}

#[test]
fn test_viewport_scroll_up_noop_at_max() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    let max = screen.scrollback_line_count;
    screen.viewport_scroll_up(max);
    screen.clear_scroll_dirty();
    screen.viewport_scroll_up(1);
    assert!(!screen.is_scroll_dirty());
}

#[test]
fn test_viewport_scroll_down_resets_to_zero() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    screen.viewport_scroll_up(20);
    screen.clear_scroll_dirty();
    screen.viewport_scroll_down(20);
    assert_eq!(screen.scroll_offset(), 0);
    assert!(!screen.is_scroll_dirty());
    let dirty_lines = screen.take_dirty_lines();
    assert_eq!(dirty_lines.len(), 24);
}

#[test]
fn test_viewport_scroll_down_partial_reduction() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 50);
    screen.viewport_scroll_up(20);
    screen.clear_scroll_dirty();

    let _ = screen.take_dirty_lines();

    screen.viewport_scroll_down(10);
    assert_eq!(screen.scroll_offset(), 10);
    assert!(screen.is_scroll_dirty());
    let dirty = screen.take_dirty_lines();
    assert!(
        dirty.len() < 24,
        "full_dirty should not be set for partial scroll down"
    );
}

#[test]
fn test_viewport_scroll_down_saturates_at_zero() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    screen.viewport_scroll_up(5);
    screen.viewport_scroll_down(1000);
    assert_eq!(screen.scroll_offset(), 0);
}

#[test]
fn test_viewport_line_correct_content() {
    let mut screen = Screen::new(24, 80);
    screen.print('A', SgrAttributes::default(), true);
    screen.scroll_up(1, Color::Default);
    assert_eq!(screen.scrollback_line_count, 1);
    screen.viewport_scroll_up(1);
    let line = screen.get_scrollback_viewport_line(23);
    assert!(line.is_some());
    assert_eq!(line.unwrap().cells[0].char(), 'A');
}

#[test]
fn test_viewport_line_none_for_partial_buffer() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 5);
    screen.viewport_scroll_up(5);
    let line = screen.get_scrollback_viewport_line(0);
    assert!(line.is_none());
}

#[test]
fn test_viewport_noop_in_alternate_screen() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    screen.switch_to_alternate();
    let offset_before = screen.scroll_offset();
    screen.viewport_scroll_up(10);
    assert_eq!(screen.scroll_offset(), offset_before);
    assert!(!screen.is_scroll_dirty());
}

#[test]
fn test_resize_while_alternate_screen_active() {
    let mut screen = Screen::new(10, 10);
    screen.switch_to_alternate();
    assert!(screen.is_alternate_screen_active());
    screen.resize(20, 40);
    assert_eq!(screen.rows(), 20);
    assert_eq!(screen.cols(), 40);
    screen.switch_to_primary();
    assert_eq!(screen.rows(), 20);
    assert_eq!(screen.cols(), 40);
}

// ── push_combining boundary tests ─────────────────────────────────────────────

#[test]
fn test_push_combining_at_col0_no_panic() {
    let mut screen = Screen::new(24, 80);
    screen.attach_combining(0, 0, '\u{0301}');
    let cell = screen.get_cell(0, 0).unwrap();
    assert!(
        !cell.grapheme().is_empty(),
        "cell grapheme must remain non-empty"
    );
}

#[test]
fn test_push_combining_after_wide_char_no_corruption() {
    let mut screen = Screen::new(24, 80);
    screen.print('日', SgrAttributes::default(), true);
    screen.attach_combining(0, 1, '\u{0301}');

    let full_cell = screen.get_cell(0, 0).unwrap();
    let wide_cell = screen.get_cell(0, 1).unwrap();
    assert!(!full_cell.grapheme().is_empty());
    assert!(!wide_cell.grapheme().is_empty());
    assert_cell_char!(screen, row 0, col 0, '日');
}

#[test]
fn test_push_combining_cap_at_32_bytes() {
    let mut screen = Screen::new(24, 80);
    screen.print('a', SgrAttributes::default(), true);
    for _ in 0..20 {
        screen.attach_combining(0, 0, '\u{0301}');
    }
    let cell = screen.get_cell(0, 0).unwrap();
    assert!(
        cell.grapheme().len() <= 32,
        "grapheme byte length {} must not exceed 32-byte cap",
        cell.grapheme().len()
    );
    assert_cell_char!(screen, row 0, col 0, 'a');
}

proptest! {
    #[test]
    fn prop_scrollback_bounded_by_max(n in 1usize..=200usize) {
        let mut screen = Screen::new(10, 40);
        screen.set_scrollback_max_lines(50);
        for _ in 0..n {
            screen.scroll_up(1, Color::Default);
        }
        prop_assert!(screen.scrollback_line_count <= 50);
    }
}

// ── FR-001: Property-based tests for Screen::print() cursor bounds ──────

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]
    #[test]
    // INVARIANT: after any print(), cursor.row < rows AND cursor.col < cols
    fn prop_print_cursor_bounds(
        rows in 1u16..=100u16,
        cols in 1u16..=200u16,
        ch in proptest::char::any(),
        auto_wrap in proptest::bool::ANY,
    ) {
        let mut screen = Screen::new(rows, cols);
        screen.print(ch, SgrAttributes::default(), auto_wrap);
        prop_assert!(screen.cursor.row < rows as usize,
            "cursor.row {} >= rows {}", screen.cursor.row, rows);
        prop_assert!(screen.cursor.col < cols as usize,
            "cursor.col {} >= cols {}", screen.cursor.col, cols);
    }

    #[test]
    // INVARIANT: cursor bounds hold regardless of starting position
    fn prop_print_cursor_bounds_from_last_col(
        rows in 1u16..=50u16,
        cols in 2u16..=100u16,
        ch in proptest::char::any(),
        auto_wrap in proptest::bool::ANY,
    ) {
        let mut screen = Screen::new(rows, cols);
        screen.move_cursor(0, cols as usize - 1);
        screen.print(ch, SgrAttributes::default(), auto_wrap);
        prop_assert!(screen.cursor.row < rows as usize);
        prop_assert!(screen.cursor.col < cols as usize);
    }
}

// ── FR-005: Screen resize edge case tests ────────────────────────────────

#[test]
fn test_resize_cursor_clamping() {
    let mut screen = Screen::new(24, 80);
    screen.move_cursor(23, 79);
    assert_cursor!(screen, row 23, col 79);
    screen.resize(10, 40);
    assert!(
        screen.cursor.row < 10,
        "cursor.row {} should be < 10",
        screen.cursor.row
    );
    assert!(
        screen.cursor.col < 40,
        "cursor.col {} should be < 40",
        screen.cursor.col
    );
}

#[test]
fn test_resize_minimum_1x1() {
    let mut screen = Screen::new(24, 80);
    screen.move_cursor(23, 79);
    screen.resize(1, 1);
    assert_cursor!(screen, row 0, col 0);
}

#[test]
fn test_resize_zero_rows_does_not_panic() {
    let mut screen = Screen::new(10, 80);
    screen.resize(0, 80);
    assert_eq!(
        screen.cursor.row, 0,
        "cursor.row should be clamped to 0 when resizing to 0 rows"
    );
}

#[test]
fn test_resize_zero_cols_does_not_panic() {
    let mut screen = Screen::new(10, 80);
    screen.resize(10, 0);
    assert_eq!(
        screen.cursor.col, 0,
        "cursor.col should be clamped to 0 when resizing to 0 cols"
    );
}

#[test]
fn test_resize_larger() {
    let mut screen = Screen::new(10, 40);
    screen.move_cursor(9, 39);
    screen.resize(24, 80);
    assert_cursor!(screen, row 9, col 39);
}

#[test]
fn test_line_feed_at_scroll_region_bottom() {
    let mut screen = Screen::new(24, 80);
    screen.set_scroll_region(5, 10);
    screen.cursor.row = 9;
    screen.cursor.col = 0;

    if let Some(line) = screen.lines.get_mut(5) {
        line.update_cell_with(0, Cell::new('A'));
    }
    if let Some(line) = screen.lines.get_mut(9) {
        line.update_cell_with(0, Cell::new('Z'));
    }

    screen.line_feed(Color::Default);

    assert_eq!(
        screen.cursor.row, 9,
        "Cursor should stay at bottom of scroll region"
    );
    assert_eq!(
        screen.lines[5].cells[0].char(),
        ' ',
        "Row 5 should be cleared after scroll"
    );
    assert_eq!(
        screen.lines[8].cells[0].char(),
        'Z',
        "Row 8 should now have 'Z'"
    );
    assert_eq!(
        screen.lines[9].cells[0].char(),
        ' ',
        "Row 9 should be a fresh blank line"
    );
}

// ── Scrollback-specific unit tests ────────────────────────────────────────────

#[test]
fn test_push_lines_to_scrollback() {
    let mut screen = Screen::new(24, 80);
    assert_eq!(screen.scrollback_line_count, 0);
    assert!(screen.scrollback_buffer.is_empty());

    screen.scroll_up(1, Color::Default);
    assert_eq!(screen.scrollback_line_count, 1);
    screen.scroll_up(1, Color::Default);
    assert_eq!(screen.scrollback_line_count, 2);
    screen.scroll_up(1, Color::Default);
    assert_eq!(screen.scrollback_line_count, 3);
    assert_eq!(screen.scrollback_buffer.len(), 3);
}

#[test]
fn test_scrollback_max_size_eviction() {
    let mut screen = Screen::new(24, 80);
    screen.set_scrollback_max_lines(5);
    assert_eq!(screen.scrollback_max_lines, 5);

    for _ in 0..10 {
        screen.scroll_up(1, Color::Default);
    }

    assert_eq!(
        screen.scrollback_line_count, 5,
        "scrollback_line_count must be clamped"
    );
    assert_eq!(
        screen.scrollback_buffer.len(),
        5,
        "scrollback_buffer.len() must equal max after eviction"
    );
}

#[test]
fn test_scrollback_eviction_retains_newest_lines() {
    let mut screen = Screen::new(24, 80);
    screen.set_scrollback_max_lines(3);
    let attrs = SgrAttributes::default();

    let labels = ['1', '2', '3', '4', '5', '6'];
    for &ch in &labels {
        screen.cursor.row = 0;
        screen.cursor.col = 0;
        screen.print(ch, attrs, true);
        screen.scroll_up(1, Color::Default);
    }

    assert_eq!(screen.scrollback_buffer.len(), 3);

    let surviving: Vec<char> = screen
        .scrollback_buffer
        .iter()
        .map(|line| line.get_cell(0).map_or(' ', crate::types::cell::Cell::char))
        .collect();

    assert_eq!(
        surviving,
        vec!['4', '5', '6'],
        "oldest lines must be evicted; only newest 3 survive"
    );
}

#[test]
fn test_scroll_offset_clamping() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 10);
    screen.viewport_scroll_up(9999);

    assert_eq!(
        screen.scroll_offset(),
        screen.scrollback_line_count,
        "scroll_offset must not exceed scrollback_line_count"
    );
}

#[test]
fn test_scroll_to_live_view() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 20);
    screen.viewport_scroll_up(15);
    assert_eq!(screen.scroll_offset(), 15);
    assert!(screen.is_scroll_dirty());

    screen.clear_scroll_dirty();
    screen.viewport_scroll_down(15);

    assert_eq!(
        screen.scroll_offset(),
        0,
        "scroll_offset must be 0 when returned to live view"
    );
    let dirty = screen.take_dirty_lines();
    assert_eq!(
        dirty.len(),
        24,
        "all rows must be dirty after returning to live view"
    );
}

// ── FR-007: Alternate screen isolation and default scrollback eviction ────────

#[test]
fn test_alt_screen_cell_content_is_isolated() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    screen.print('X', attrs, true);
    assert_cell_char!(screen, row 0, col 0, 'X');

    screen.switch_to_alternate();
    screen.print('Y', attrs, true);
    assert_cell_char!(screen, row 0, col 0, 'Y');

    screen.switch_to_primary();
    assert_cell_char!(screen, row 0, col 0, 'X', "Primary screen cell must not be polluted by alternate screen writes");
}

#[test]
fn test_default_scrollback_max_exact_eviction() {
    let mut screen = Screen::new(24, 80);
    screen.set_scrollback_max_lines(DEFAULT_SCROLLBACK_MAX);

    for _ in 0..=DEFAULT_SCROLLBACK_MAX {
        screen.scroll_up(1, Color::Default);
    }

    assert_eq!(screen.scrollback_line_count, DEFAULT_SCROLLBACK_MAX);
    assert_eq!(screen.scrollback_buffer.len(), DEFAULT_SCROLLBACK_MAX);
}

#[test]
fn test_scroll_down_no_pending_in_alternate_screen() {
    let mut screen = Screen::new(24, 80);
    screen.switch_to_alternate();
    screen.scroll_down(3, Color::Default);
    let (up, down) = screen.consume_scroll_events();
    assert_eq!(
        up, 0,
        "alternate screen scroll_down must not set pending_scroll_up"
    );
    assert_eq!(
        down, 0,
        "alternate screen scroll_down must not set pending_scroll_down"
    );
}

#[test]
fn test_viewport_scroll_down_resets_pending_scroll_counters() {
    let mut screen = screen_with_scrollback!(24 x 80, scrollback 30);
    let _ = screen.consume_scroll_events();

    screen.viewport_scroll_up(10);
    screen.scroll_up(5, Color::Default);

    screen.viewport_scroll_down(10);
    assert_eq!(screen.scroll_offset(), 0);

    let (up, down) = screen.consume_scroll_events();
    assert_eq!(
        up, 0,
        "pending_scroll_up must be reset when returning to live view"
    );
    assert_eq!(
        down, 0,
        "pending_scroll_down must be reset when returning to live view"
    );
}

// --- insert_lines / delete_lines / clear_lines ---

/// Helper: write a distinct character into column 0 of each row.
/// Row 0 → 'A', row 1 → 'B', … (wraps at 26).
fn fill_rows(screen: &mut Screen) {
    let attrs = SgrAttributes::default();
    let rows = screen.rows() as usize;
    for r in 0..rows {
        let ch = char::from(b'A' + (r % 26) as u8);
        if let Some(line) = screen.lines.get_mut(r) {
            line.update_cell_with(0, Cell::new(ch));
        }
        let _ = attrs;
    }
}

/// Return the character at column 0 of the given row.
fn row_char(screen: &Screen, row: usize) -> char {
    screen.get_cell(row, 0).map_or(' ', Cell::char)
}

/// Return true if every cell in a row is the default blank (' ', Half width).
fn row_is_blank(screen: &Screen, row: usize) -> bool {
    if let Some(line) = screen.get_line(row) {
        line.cells.iter().all(|c| c.char() == ' ')
    } else {
        false
    }
}

// ── insert_lines ──────────────────────────────────────────────────────────────

#[test]
fn insert_lines_shifts_content_down() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 1;
    screen.insert_lines(1);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 must be unchanged");
    assert!(row_is_blank(&screen, 1), "row 1 must be blank after insert");
    assert_eq!(
        row_char(&screen, 2),
        'B',
        "row 2 must have old row 1 content"
    );
    assert_eq!(
        row_char(&screen, 3),
        'C',
        "row 3 must have old row 2 content"
    );
    assert_eq!(
        row_char(&screen, 4),
        'D',
        "row 4 must have old row 3 content (E dropped)"
    );
}

#[test]
fn insert_lines_at_row_zero_shifts_all_content() {
    let mut screen = Screen::new(4, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 0;
    screen.insert_lines(1);

    assert!(row_is_blank(&screen, 0), "row 0 must be blank");
    assert_eq!(
        row_char(&screen, 1),
        'A',
        "row 1 must have old row 0 content"
    );
    assert_eq!(
        row_char(&screen, 2),
        'B',
        "row 2 must have old row 1 content"
    );
    assert_eq!(
        row_char(&screen, 3),
        'C',
        "row 3 must have old row 2 content (D dropped)"
    );
}

#[test]
fn insert_lines_count_exceeding_remaining_rows_clears_to_bottom() {
    let mut screen = Screen::new(4, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 2;
    screen.insert_lines(10);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 unchanged");
    assert_eq!(row_char(&screen, 1), 'B', "row 1 unchanged");
    assert!(row_is_blank(&screen, 2), "row 2 must be blank");
    assert!(row_is_blank(&screen, 3), "row 3 must be blank");
}

#[test]
fn insert_lines_respects_scroll_region() {
    let mut screen = Screen::new(6, 10);
    fill_rows(&mut screen);
    screen.set_scroll_region(2, 5);
    screen.cursor.row = 2;
    screen.insert_lines(1);

    assert_eq!(
        row_char(&screen, 0),
        'A',
        "row 0 outside region — unchanged"
    );
    assert_eq!(
        row_char(&screen, 1),
        'B',
        "row 1 outside region — unchanged"
    );
    assert!(
        row_is_blank(&screen, 2),
        "row 2 must be blank (inserted line)"
    );
    assert_eq!(
        row_char(&screen, 3),
        'C',
        "row 3 must have old row 2 content"
    );
    assert_eq!(
        row_char(&screen, 4),
        'D',
        "row 4 must have old row 3 content (E dropped)"
    );
    assert_eq!(
        row_char(&screen, 5),
        'F',
        "row 5 outside region — unchanged"
    );
}

#[test]
fn insert_lines_noop_when_cursor_outside_scroll_region() {
    let mut screen = Screen::new(6, 10);
    fill_rows(&mut screen);
    screen.set_scroll_region(1, 4);
    screen.cursor.row = 4;
    screen.insert_lines(1);

    for r in 0..6usize {
        let expected = char::from(b'A' + r as u8);
        assert_eq!(row_char(&screen, r), expected, "row {r} must be unchanged");
    }
}

// ── delete_lines ──────────────────────────────────────────────────────────────

#[test]
fn delete_lines_shifts_content_up() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 1;
    screen.delete_lines(1);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 unchanged");
    assert_eq!(
        row_char(&screen, 1),
        'C',
        "row 1 must have old row 2 content"
    );
    assert_eq!(
        row_char(&screen, 2),
        'D',
        "row 2 must have old row 3 content"
    );
    assert_eq!(
        row_char(&screen, 3),
        'E',
        "row 3 must have old row 4 content"
    );
    assert!(row_is_blank(&screen, 4), "row 4 must be blank");
}

#[test]
fn delete_lines_at_last_row_clears_that_row() {
    let mut screen = Screen::new(4, 10);
    fill_rows(&mut screen);
    screen.cursor.row = 3;
    screen.delete_lines(1);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 unchanged");
    assert_eq!(row_char(&screen, 1), 'B', "row 1 unchanged");
    assert_eq!(row_char(&screen, 2), 'C', "row 2 unchanged");
    assert!(row_is_blank(&screen, 3), "row 3 must be blank after delete");
}

#[test]
fn delete_lines_respects_scroll_region() {
    let mut screen = Screen::new(6, 10);
    fill_rows(&mut screen);
    screen.set_scroll_region(1, 5);
    screen.cursor.row = 1;
    screen.delete_lines(1);

    assert_eq!(
        row_char(&screen, 0),
        'A',
        "row 0 outside region — unchanged"
    );
    assert_eq!(
        row_char(&screen, 1),
        'C',
        "row 1 must have old row 2 content"
    );
    assert_eq!(
        row_char(&screen, 2),
        'D',
        "row 2 must have old row 3 content"
    );
    assert_eq!(
        row_char(&screen, 3),
        'E',
        "row 3 must have old row 4 content"
    );
    assert!(row_is_blank(&screen, 4), "row 4 must be blank");
    assert_eq!(
        row_char(&screen, 5),
        'F',
        "row 5 outside region — unchanged"
    );
}

#[test]
fn delete_lines_noop_when_cursor_outside_scroll_region() {
    let mut screen = Screen::new(6, 10);
    fill_rows(&mut screen);
    screen.set_scroll_region(2, 5);
    screen.cursor.row = 1;
    screen.delete_lines(1);

    for r in 0..6usize {
        let expected = char::from(b'A' + r as u8);
        assert_eq!(row_char(&screen, r), expected, "row {r} must be unchanged");
    }
}

// ── clear_lines ───────────────────────────────────────────────────────────────

#[test]
fn clear_lines_blanks_range() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.clear_lines(1, 4);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 must be unchanged");
    assert!(row_is_blank(&screen, 1), "row 1 must be blank");
    assert!(row_is_blank(&screen, 2), "row 2 must be blank");
    assert!(row_is_blank(&screen, 3), "row 3 must be blank");
    assert_eq!(row_char(&screen, 4), 'E', "row 4 must be unchanged");
}

#[test]
fn clear_lines_single_row() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.clear_lines(2, 3);

    assert_eq!(row_char(&screen, 1), 'B', "row 1 unchanged");
    assert!(row_is_blank(&screen, 2), "row 2 must be blank");
    assert_eq!(row_char(&screen, 3), 'D', "row 3 unchanged");
}

#[test]
fn clear_lines_empty_range_is_noop() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.clear_lines(2, 2);

    for r in 0..5usize {
        let expected = char::from(b'A' + r as u8);
        assert_eq!(row_char(&screen, r), expected, "row {r} must be unchanged");
    }
}

#[test]
fn clear_lines_clamps_end_past_screen_height() {
    let mut screen = Screen::new(5, 10);
    fill_rows(&mut screen);
    screen.clear_lines(3, 999);

    assert_eq!(row_char(&screen, 0), 'A', "row 0 unchanged");
    assert_eq!(row_char(&screen, 1), 'B', "row 1 unchanged");
    assert_eq!(row_char(&screen, 2), 'C', "row 2 unchanged");
    assert!(row_is_blank(&screen, 3), "row 3 must be blank");
    assert!(row_is_blank(&screen, 4), "row 4 must be blank");
}

// ── New edge-case tests (made feasible by macros) ─────────────────────────────

/// Scrollback line count never goes negative after clear_scrollback on an empty buffer.
#[test]
fn test_clear_scrollback_on_empty_is_noop() {
    let mut screen = Screen::new(5, 10);
    assert_eq!(screen.scrollback_line_count, 0);
    screen.clear_scrollback();
    assert_eq!(screen.scrollback_line_count, 0);
    assert!(screen.scrollback_buffer.is_empty());
}

/// Resizing to the same dimensions must not change cursor or buffer.
#[test]
fn test_resize_same_dimensions_is_noop() {
    let mut screen = Screen::new(10, 20);
    screen.move_cursor(3, 7);
    screen.resize(10, 20);
    assert_cursor!(screen, row 3, col 7);
    assert_eq!(screen.rows(), 10);
    assert_eq!(screen.cols(), 20);
}

/// Printing to the last cell of a row and then a newline must advance to
/// the next row without wrapping the cursor column past the screen edge.
#[test]
fn test_print_at_last_col_then_newline_stays_in_bounds() {
    let mut screen = Screen::new(5, 5);
    screen.move_cursor(0, 4);
    screen.print('Z', SgrAttributes::default(), true);
    screen.line_feed(Color::Default);
    assert!(
        screen.cursor.row < 5,
        "cursor.row must be in bounds after LF"
    );
    assert!(
        screen.cursor.col < 5,
        "cursor.col must be in bounds after LF"
    );
}

/// `take_dirty_lines` returns indices in a range that only contains lines that
/// were explicitly marked dirty (no false positives from unrelated lines).
#[test]
fn test_take_dirty_lines_precision() {
    let mut screen = Screen::new(8, 10);
    // Mark only rows 2 and 5
    screen.mark_line_dirty(2);
    screen.mark_line_dirty(5);
    let mut dirty = screen.take_dirty_lines();
    dirty.sort_unstable();
    assert_eq!(dirty, vec![2, 5], "only rows 2 and 5 should be dirty");
}

/// Multiple consecutive tab stops accumulate correctly.
#[test]
fn test_multiple_tabs_accumulate() {
    let mut screen = Screen::new(5, 80);
    screen.tab();
    screen.tab();
    // After two tabs: 0→8→16
    assert_eq!(
        screen.cursor.col, 16,
        "two tabs should advance cursor to col 16"
    );
}

/// Backspace at column 0 must not underflow (cursor must stay at 0).
#[test]
fn test_backspace_at_col_zero_no_underflow() {
    let mut screen = Screen::new(5, 10);
    assert_eq!(screen.cursor.col, 0);
    screen.backspace();
    assert_eq!(
        screen.cursor.col, 0,
        "backspace at col 0 must not underflow"
    );
}

/// Scroll_up by more than the screen height must not panic and the buffer
/// grows monotonically (capped at max).
#[test]
fn test_scroll_up_large_count_no_panic() {
    let mut screen = Screen::new(3, 10);
    screen.set_scrollback_max_lines(10);
    for _ in 0..20 {
        screen.scroll_up(1, Color::Default);
    }
    assert!(
        screen.scrollback_line_count <= 10,
        "scrollback must not exceed max"
    );
}

/// `get_scrollback_lines(0)` must return an empty slice without panicking.
#[test]
fn test_get_scrollback_lines_zero_count() {
    let screen = screen_with_scrollback!(5 x 10, scrollback 5);
    let lines = screen.get_scrollback_lines(0);
    assert_eq!(
        lines.len(),
        0,
        "requesting 0 scrollback lines must return empty slice"
    );
}

/// Alternate screen is initially clean (full_dirty = false) after the switch
/// is followed by consuming dirty lines.
#[test]
fn test_alt_screen_clean_after_dirty_consumed() {
    let mut screen = Screen::new(4, 10);
    screen.switch_to_alternate();
    let _ = screen.take_dirty_lines(); // consume the initial full_dirty
    assert!(
        !screen.full_dirty,
        "alt screen must be clean after dirty lines consumed"
    );
    let dirty = screen.take_dirty_lines();
    assert!(
        dirty.is_empty(),
        "no spurious dirty lines after consumption"
    );
}
