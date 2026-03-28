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

include!("screen_unicode.rs");
include!("screen_fr.rs");
include!("screen_insert_delete.rs");
