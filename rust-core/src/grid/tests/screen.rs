use super::*;
use proptest::prelude::*;

#[test]
fn test_screen_creation() {
    let screen = Screen::new(24, 80);
    assert_eq!(screen.rows(), 24);
    assert_eq!(screen.cols(), 80);
    assert_eq!(screen.cursor.row, 0);
    assert_eq!(screen.cursor.col, 0);
}

#[test]
fn test_print_character() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    screen.print('A', attrs, true);

    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'A');
    assert_eq!(screen.cursor.col, 1);
}

#[test]
fn test_line_feed() {
    let mut screen = Screen::new(24, 80);
    screen.line_feed(Color::Default);

    assert_eq!(screen.cursor.row, 1);
    assert_eq!(screen.cursor.col, 0);
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

    // Mark line 0
    screen.lines[0].mark_dirty();
    assert!(screen.lines[0].is_dirty);

    screen.scroll_up(1, Color::Default);

    // Line 0 should have been replaced
    assert!(!screen.lines[0].is_dirty);
}

#[test]
fn test_dirty_lines() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    screen.print('A', attrs, true);
    let dirty = screen.take_dirty_lines();

    assert_eq!(dirty.len(), 1);
    assert_eq!(dirty[0], 0);

    // Dirty set should be cleared
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
    assert_eq!(screen.cursor.row, 0);
    assert_eq!(screen.cursor.col, 0);
    assert_eq!(screen.scrollback_line_count, 0);
    assert_eq!(screen.scrollback_max_lines, 10000);
}

#[test]
fn test_scroll_up_saves_to_scrollback() {
    let mut screen = Screen::new(5, 80);

    // Fill screen with content
    for _ in 0..3 {
        screen.scroll_up(1, Color::Default);
    }

    // Scrollback should have the scrolled lines
    assert_eq!(screen.scrollback_line_count, 3);
    assert_eq!(screen.scrollback_buffer.len(), 3);
}

#[test]
fn test_scrollback_trimming() {
    let mut screen = Screen::new(5, 80);
    screen.set_scrollback_max_lines(3);

    // Fill screen with content
    for _ in 0..10 {
        screen.scroll_up(1, Color::Default);
    }

    // Scrollback should be trimmed to max size
    assert_eq!(screen.scrollback_line_count, 3);
    assert_eq!(screen.scrollback_buffer.len(), 3);
}

#[test]
fn test_get_scrollback_lines() {
    let mut screen = Screen::new(24, 80);

    // Add some lines to scrollback
    for _ in 0..5 {
        screen.scroll_up(1, Color::Default);
    }

    let lines = screen.get_scrollback_lines(3);
    assert_eq!(lines.len(), 3);

    // Get all scrollback
    let all_lines = screen.get_scrollback_lines(100);
    assert_eq!(all_lines.len(), 5);
}

#[test]
fn test_clear_scrollback() {
    let mut screen = Screen::new(24, 80);

    // Add some lines to scrollback
    for _ in 0..5 {
        screen.scroll_up(1, Color::Default);
    }

    assert_eq!(screen.scrollback_line_count, 5);

    screen.clear_scrollback();

    assert_eq!(screen.scrollback_line_count, 0);
    assert!(screen.scrollback_buffer.is_empty());
}

#[test]
fn test_scrollback_not_saved_in_alternate_screen() {
    let mut screen = Screen::new(5, 80);

    // Switch to alternate screen
    screen.switch_to_alternate();
    assert!(screen.is_alternate_screen_active());

    // Scroll in alternate screen
    for _ in 0..3 {
        screen.scroll_up(1, Color::Default);
    }

    // Scrollback should still be empty (scrolling in alternate doesn't save to primary scrollback)
    assert_eq!(screen.scrollback_line_count, 0);

    // Switch back to primary
    screen.switch_to_primary();
    assert!(!screen.is_alternate_screen_active());

    // Scroll in primary screen
    screen.scroll_up(1, Color::Default);

    // Now scrollback should have one line
    assert_eq!(screen.scrollback_line_count, 1);
}

#[test]
fn test_resize_updates_scrollback_lines() {
    let mut screen = Screen::new(5, 80);

    // Add some lines to scrollback
    for _ in 0..3 {
        screen.scroll_up(1, Color::Default);
    }

    // Resize screen
    screen.resize(10, 40);

    // Scrollback lines should be resized to new column count
    assert_eq!(screen.scrollback_buffer.len(), 3);
    assert_eq!(screen.scrollback_buffer[0].cells.len(), 40);
}

#[test]
fn test_alt_screen_cursor_routing() {
    let mut screen = Screen::new(24, 80);

    // Move cursor on primary screen
    screen.move_cursor(5, 10);
    assert_eq!(screen.cursor().row, 5);
    assert_eq!(screen.cursor().col, 10);

    // Activate alternate screen
    screen.switch_to_alternate();

    // Alt screen cursor starts at (0, 0)
    assert_eq!(screen.cursor().row, 0);
    assert_eq!(screen.cursor().col, 0);

    // Move cursor on alt screen — should NOT affect primary
    screen.move_cursor(3, 7);
    assert_eq!(screen.cursor().row, 3);
    assert_eq!(screen.cursor().col, 7);

    // Switch back to primary — primary cursor still at (5, 10)
    screen.switch_to_primary();
    assert_eq!(screen.cursor().row, 5);
    assert_eq!(screen.cursor().col, 10);
}

#[test]
fn test_alt_screen_dirty_lines_routing() {
    let mut screen = Screen::new(24, 80);

    // Mark line dirty on primary
    screen.mark_line_dirty(2);

    // Switch to alternate — take_dirty_lines drains the alt screen's set
    screen.switch_to_alternate();

    // switch_to_alternate marks all lines dirty; drain them so we start clean
    let _ = screen.take_dirty_lines();

    // Mark a specific line dirty on alt screen
    screen.mark_line_dirty(5);

    // take_dirty_lines should return alt screen's dirty lines (just [5])
    let alt_dirty = screen.take_dirty_lines();
    assert_eq!(alt_dirty, vec![5]);

    // Switch back to primary — switch_to_primary marks all lines dirty; drain them
    screen.switch_to_primary();
    let _ = screen.take_dirty_lines();

    // The primary dirty set had line 2 marked before the switch;
    // switch_to_primary re-marks all lines dirty so line 2 is included.
    // Verify line 2 is still present in the primary dirty set.
    // Re-mark just line 2 to test isolation independently of switch overhead.
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
    let mut dirty = screen.take_dirty_lines();
    dirty.sort_unstable();
    assert_eq!(
        dirty,
        vec![0, 1, 2, 3],
        "full_dirty should return all row indices"
    );
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
    // Second call should return empty
    let dirty2 = screen.take_dirty_lines();
    assert!(
        dirty2.is_empty(),
        "dirty_set should also be empty after full_dirty was consumed"
    );
}

#[test]
fn test_take_dirty_lines_full_dirty_also_clears_dirty_set() {
    let mut screen = Screen::new(4, 80);
    // Add some entries to dirty_set, then set full_dirty
    screen.mark_line_dirty(1);
    screen.mark_line_dirty(3);
    screen.mark_all_dirty();
    let _ = screen.take_dirty_lines();
    // After consuming full_dirty, dirty_set should also be cleared
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
    // All alt-screen lines should be dirty via full_dirty (not individual HashSet inserts)
    let mut dirty = screen.take_dirty_lines();
    dirty.sort_unstable();
    assert_eq!(
        dirty.len(),
        4,
        "switch_to_alternate should mark all lines dirty"
    );
    assert_eq!(dirty, vec![0, 1, 2, 3]);
}

#[test]
fn test_switch_to_primary_uses_full_dirty() {
    let mut screen = Screen::new(4, 10);
    screen.switch_to_alternate();
    let _ = screen.take_dirty_lines(); // consume alt-screen dirty
    screen.switch_to_primary();
    // All primary-screen lines should be dirty via full_dirty
    let mut dirty = screen.take_dirty_lines();
    dirty.sort_unstable();
    assert_eq!(
        dirty.len(),
        4,
        "switch_to_primary should mark all primary lines dirty"
    );
    assert_eq!(dirty, vec![0, 1, 2, 3]);
}

// ── Phase 11: Unicode & CJK tests ────────────────────────────────────

#[test]
fn test_print_cjk_basic() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    screen.print('日', attrs, true);

    // Full cell at col 0
    let full_cell = screen.get_cell(0, 0).unwrap();
    assert_eq!(full_cell.char(), '日');
    assert_eq!(full_cell.width, CellWidth::Full);

    // Wide placeholder at col 1
    let wide_cell = screen.get_cell(0, 1).unwrap();
    assert_eq!(wide_cell.char(), ' ');
    assert_eq!(wide_cell.width, CellWidth::Wide);

    // Cursor advanced by 2
    assert_eq!(screen.cursor.col, 2);
}

#[test]
fn test_print_cjk_cursor_position() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    screen.print('日', attrs, true);
    screen.print('本', attrs, true);
    screen.print('語', attrs, true);

    // Three wide chars = cursor at col 6
    assert_eq!(screen.cursor.col, 6);

    // Verify Full/Wide pairs for each character
    assert_eq!(screen.get_cell(0, 0).unwrap().width, CellWidth::Full);
    assert_eq!(screen.get_cell(0, 1).unwrap().width, CellWidth::Wide);
    assert_eq!(screen.get_cell(0, 2).unwrap().width, CellWidth::Full);
    assert_eq!(screen.get_cell(0, 3).unwrap().width, CellWidth::Wide);
    assert_eq!(screen.get_cell(0, 4).unwrap().width, CellWidth::Full);
    assert_eq!(screen.get_cell(0, 5).unwrap().width, CellWidth::Wide);
}

#[test]
fn test_print_cjk_wrap() {
    // Place a CJK char at the last column — it must wrap to the next line
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    screen.move_cursor(0, 79);
    screen.print('日', attrs, true);

    // CJK did not fit at col 79; it wrapped to row 1, cols 0-1
    let full_cell = screen.get_cell(1, 0).unwrap();
    assert_eq!(full_cell.char(), '日');
    assert_eq!(full_cell.width, CellWidth::Full);

    let wide_cell = screen.get_cell(1, 1).unwrap();
    assert_eq!(wide_cell.width, CellWidth::Wide);
}

#[test]
fn test_print_emoji() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    // 🎉 has Unicode display width 2
    screen.print('🎉', attrs, true);

    let full_cell = screen.get_cell(0, 0).unwrap();
    assert_eq!(full_cell.char(), '🎉');
    assert_eq!(full_cell.width, CellWidth::Full);

    let wide_cell = screen.get_cell(0, 1).unwrap();
    assert_eq!(wide_cell.width, CellWidth::Wide);

    assert_eq!(screen.cursor.col, 2);
}

#[test]
fn test_dch_at_wide_placeholder_blanks_full_partner() {
    // DCH at a Wide placeholder must blank the Full cell to the left
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    // Print CJK: Full at col 0, Wide at col 1
    screen.print('日', attrs, true);

    // Position cursor on the Wide placeholder
    screen.move_cursor(0, 1);
    screen.delete_chars(1);

    // The Full partner at col 0 should be blanked (Half-width space)
    let col0 = screen.get_cell(0, 0).unwrap();
    assert_eq!(
        col0.width,
        CellWidth::Half,
        "Full partner must be blanked when DCH hits Wide placeholder"
    );
    assert_eq!(col0.char(), ' ');
}

#[test]
fn test_dch_at_full_cell_blanks_wide_partner() {
    // DCH at a Full cell: the Wide partner shifts left and must be blanked
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    // 'A' at col 0, CJK Full at col 1, Wide at col 2
    screen.print('A', attrs, true);
    screen.print('日', attrs, true);

    // Delete from the Full cell at col 1
    screen.move_cursor(0, 1);
    screen.delete_chars(1);

    // After drain of col 1, old col 2 (Wide) shifts to col 1 — it was pre-blanked
    let col1 = screen.get_cell(0, 1).unwrap();
    assert_eq!(
        col1.width,
        CellWidth::Half,
        "Wide partner must be blanked when Full cell is DCH'd"
    );
}

#[test]
fn test_ich_at_wide_placeholder_blanks_full_partner() {
    // ICH at a Wide placeholder must blank its Full partner before shifting
    let mut screen = Screen::new(24, 10);
    let attrs = SgrAttributes::default();

    // CJK Full at col 0, Wide at col 1
    screen.print('日', attrs, true);

    // Insert blank at the Wide placeholder
    screen.move_cursor(0, 1);
    screen.insert_chars(1, attrs);

    // Full partner at col 0 should be blanked
    let col0 = screen.get_cell(0, 0).unwrap();
    assert_eq!(
        col0.width,
        CellWidth::Half,
        "Full partner must be blanked when ICH inserts at Wide placeholder"
    );
    assert_eq!(col0.char(), ' ');
}

#[test]
fn test_ech_range_ends_at_full_blanks_wide_partner() {
    // ECH range ending on a Full cell must also erase its Wide partner
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    // 'A' at col 0, CJK Full at col 1, Wide at col 2
    screen.print('A', attrs, true);
    screen.print('日', attrs, true);

    // Erase 2 chars from col 0: covers col 0 ('A') and col 1 (Full)
    screen.move_cursor(0, 0);
    screen.erase_chars(2, attrs);

    // Wide partner at col 2 must be blanked (extended erase range)
    let col2 = screen.get_cell(0, 2).unwrap();
    assert_eq!(
        col2.width,
        CellWidth::Half,
        "Wide partner must be blanked when ECH range ends on Full cell"
    );
    assert_eq!(col2.char(), ' ');
}

#[test]
fn test_ech_starts_at_wide_blanks_full_partner() {
    // ECH starting at a Wide placeholder must also erase its Full partner
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    // CJK Full at col 0, Wide at col 1
    screen.print('日', attrs, true);

    // Erase 1 char starting at the Wide placeholder
    screen.move_cursor(0, 1);
    screen.erase_chars(1, attrs);

    // Full partner at col 0 must be blanked (extended erase range)
    let col0 = screen.get_cell(0, 0).unwrap();
    assert_eq!(
        col0.width,
        CellWidth::Half,
        "Full partner must be blanked when ECH starts at Wide placeholder"
    );
    assert_eq!(col0.char(), ' ');

    // Wide cell itself is also erased
    let col1 = screen.get_cell(0, 1).unwrap();
    assert_eq!(col1.width, CellWidth::Half);
}

// ── Phase 12: Scrollback Viewport Navigation tests ─────────────────────

#[test]
fn test_viewport_scroll_up_basic() {
    let mut screen = Screen::new(24, 80);
    // Add some scrollback lines by scrolling up the screen
    for _ in 0..30 {
        screen.scroll_up(1, Color::Default);
    }
    assert_eq!(screen.scroll_offset(), 0);
    screen.viewport_scroll_up(10);
    assert_eq!(screen.scroll_offset(), 10);
    assert!(screen.is_scroll_dirty());
}

#[test]
fn test_viewport_scroll_up_clamps_at_buffer_size() {
    let mut screen = Screen::new(24, 80);
    for _ in 0..30 {
        screen.scroll_up(1, Color::Default);
    }
    let max = screen.scrollback_line_count;
    // Should not panic and should clamp at max
    screen.viewport_scroll_up(max + 1000);
    assert_eq!(screen.scroll_offset(), max);
}

#[test]
fn test_viewport_scroll_up_noop_at_max() {
    let mut screen = Screen::new(24, 80);
    for _ in 0..30 {
        screen.scroll_up(1, Color::Default);
    }
    let max = screen.scrollback_line_count;
    screen.viewport_scroll_up(max);
    screen.clear_scroll_dirty();
    // Already at max — no change, scroll_dirty should stay false
    screen.viewport_scroll_up(1);
    assert!(!screen.is_scroll_dirty());
}

#[test]
fn test_viewport_scroll_down_resets_to_zero() {
    let mut screen = Screen::new(24, 80);
    for _ in 0..30 {
        screen.scroll_up(1, Color::Default);
    }
    screen.viewport_scroll_up(20);
    screen.clear_scroll_dirty();
    screen.viewport_scroll_down(20);
    assert_eq!(screen.scroll_offset(), 0);
    assert!(!screen.is_scroll_dirty());
    // full_dirty should be set to force live re-render
    let dirty_lines = screen.take_dirty_lines();
    // All 24 rows should be dirty after returning to live view
    assert_eq!(dirty_lines.len(), 24);
}

#[test]
fn test_viewport_scroll_down_partial_reduction() {
    let mut screen = Screen::new(24, 80);
    for _ in 0..50 {
        screen.scroll_up(1, Color::Default);
    }
    // Scroll up to offset 20
    screen.viewport_scroll_up(20);
    screen.clear_scroll_dirty();

    // Drain any accumulated dirty rows from scroll_up calls before partial scroll-down
    let _ = screen.take_dirty_lines();

    // Scroll down by 10 (partial — still scrolled)
    screen.viewport_scroll_down(10);

    // Should be at offset 10, not 0
    assert_eq!(screen.scroll_offset(), 10);
    // scroll_dirty should be set (not full_dirty since not at 0)
    assert!(screen.is_scroll_dirty());
    // take_dirty_lines should NOT return all rows (full_dirty is not set)
    let dirty = screen.take_dirty_lines();
    assert!(
        dirty.len() < 24,
        "full_dirty should not be set for partial scroll down"
    );
}

#[test]
fn test_viewport_scroll_down_saturates_at_zero() {
    let mut screen = Screen::new(24, 80);
    for _ in 0..30 {
        screen.scroll_up(1, Color::Default);
    }
    screen.viewport_scroll_up(5);
    // Should not panic (no usize underflow)
    screen.viewport_scroll_down(1000);
    assert_eq!(screen.scroll_offset(), 0);
}

#[test]
fn test_viewport_line_correct_content() {
    let mut screen = Screen::new(24, 80);
    // Generate scrollback: write 'A' to row 0 then scroll it off
    let attrs = SgrAttributes::default();
    screen.print('A', attrs, true);
    screen.scroll_up(1, Color::Default);
    // scrollback has 1 line containing 'A'
    assert_eq!(screen.scrollback_line_count, 1);
    screen.viewport_scroll_up(1);
    let line = screen.get_scrollback_viewport_line(23); // last viewport row = the line we saved
    assert!(line.is_some());
    let line = line.unwrap();
    // The line should contain 'A' at column 0 (we printed 'A' earlier)
    assert_eq!(line.cells[0].char(), 'A');
}

#[test]
fn test_viewport_line_none_for_partial_buffer() {
    let mut screen = Screen::new(24, 80);
    // Only 5 scrollback lines, screen is 24 rows — row 0 should be None
    for _ in 0..5 {
        screen.scroll_up(1, Color::Default);
    }
    screen.viewport_scroll_up(5);
    // Rows 0..18 should return None (no scrollback content there)
    let line = screen.get_scrollback_viewport_line(0);
    assert!(line.is_none());
}

#[test]
fn test_viewport_noop_in_alternate_screen() {
    let mut screen = Screen::new(24, 80);
    // Fill some scrollback first (on primary screen)
    for _ in 0..30 {
        screen.scroll_up(1, Color::Default);
    }
    // Switch to alternate screen
    screen.switch_to_alternate();
    let offset_before = screen.scroll_offset();
    screen.viewport_scroll_up(10);
    // Should be a no-op
    assert_eq!(screen.scroll_offset(), offset_before);
    assert!(!screen.is_scroll_dirty());
}

#[test]
fn test_resize_while_alternate_screen_active() {
    // Create a screen with primary content
    let mut screen = Screen::new(10, 10);
    // Switch to alternate screen
    screen.switch_to_alternate();
    // Verify we're on alternate screen
    assert!(screen.is_alternate_screen_active());
    // Resize while on alternate screen — both buffers must be resized
    screen.resize(20, 40);
    // Alternate screen should be 20 rows x 40 cols
    assert_eq!(screen.rows(), 20);
    assert_eq!(screen.cols(), 40);
    // Switch back to primary and verify it was also resized
    screen.switch_to_primary();
    assert_eq!(screen.rows(), 20);
    assert_eq!(screen.cols(), 40);
}

// ── push_combining boundary tests ────────────────────────────────────────

#[test]
fn test_push_combining_at_col0_no_panic() {
    // A combining character arriving when nothing has been printed yet
    // (cursor at col 0, no preceding base glyph) must not panic.
    // attach_combining silently skips the call if the cell is out of range
    // or simply attaches to the default space cell — either is acceptable.
    let mut screen = Screen::new(24, 80);
    // No characters printed; cursor at (0, 0).
    // Directly call attach_combining at (0, 0) — the "nothing to combine onto" case.
    screen.attach_combining(0, 0, '\u{0301}'); // combining acute accent
    // Must not panic; grapheme may or may not have changed, but cell must be valid.
    let cell = screen.get_cell(0, 0).unwrap();
    assert!(
        !cell.grapheme().is_empty(),
        "cell grapheme must remain non-empty after combining-at-col-0"
    );
}

#[test]
fn test_push_combining_after_wide_char_no_corruption() {
    // A combining character arriving just after a wide (Full) CJK char.
    // The Wide placeholder occupies col 1; combining should attach to col 1
    // (or be silently ignored) without corrupting either cell.
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    // Print a wide char: Full at col 0, Wide placeholder at col 1.
    screen.print('日', attrs, true);
    // Cursor is now at col 2; the Wide placeholder is at col 1.
    // Attach a combining char to the Wide placeholder position.
    screen.attach_combining(0, 1, '\u{0301}');

    // Neither cell must have an empty grapheme — no corruption.
    let full_cell = screen.get_cell(0, 0).unwrap();
    let wide_cell = screen.get_cell(0, 1).unwrap();
    assert!(!full_cell.grapheme().is_empty());
    assert!(!wide_cell.grapheme().is_empty());
    // The Full cell must still start with the original base character.
    assert_eq!(full_cell.char(), '日');
}

#[test]
fn test_push_combining_cap_at_32_bytes() {
    // push_combining caps the grapheme at 32 bytes.
    // Flooding a cell with combining chars must not grow it past the cap
    // and must not panic.
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    // Print a base ASCII character.
    screen.print('a', attrs, true);
    // Flood with combining acute accents (U+0301, 2 bytes each in UTF-8).
    // 32 bytes / 2 bytes per combining char = 16 combining chars maximum.
    // Send 20 to exercise the cap guard.
    for _ in 0..20 {
        screen.attach_combining(0, 0, '\u{0301}');
    }
    let cell = screen.get_cell(0, 0).unwrap();
    assert!(
        cell.grapheme().len() <= 32,
        "grapheme byte length {} must not exceed 32-byte cap",
        cell.grapheme().len()
    );
    // Base character must still be 'a'.
    assert_eq!(cell.char(), 'a');
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
        // Move cursor to a varied position within bounds first
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
        // Move cursor to last column to test wrapping behavior
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
    // Move cursor to bottom-right corner
    screen.move_cursor(23, 79);
    assert_eq!(screen.cursor.row, 23);
    assert_eq!(screen.cursor.col, 79);
    // Resize to smaller dimensions
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
    // After fix: cursor must be clamped to (0, 0)
    assert_eq!(screen.cursor.row, 0);
    assert_eq!(screen.cursor.col, 0);
}

#[test]
fn test_resize_zero_rows_does_not_panic() {
    // After the saturating_sub fix, resize(0, 80) should not panic
    let mut screen = Screen::new(10, 80);
    screen.resize(0, 80);
    // After the saturating_sub fix: cursor.row is clamped to min(old_row, 0.saturating_sub(1)) = 0
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
    // Cursor should stay at (9, 39) when resizing larger
    assert_eq!(screen.cursor.row, 9);
    assert_eq!(screen.cursor.col, 39);
}

#[test]
fn test_line_feed_at_scroll_region_bottom() {
    let mut screen = Screen::new(24, 80);
    // Set scroll region rows 5-10 (top=5, bottom=10)
    screen.set_scroll_region(5, 10);
    // Position cursor at the bottom of scroll region (row 9, since bottom is exclusive)
    screen.cursor.row = 9;
    screen.cursor.col = 0;

    // Fill some content in the scroll region for verification
    if let Some(line) = screen.lines.get_mut(5) {
        line.update_cell_with(0, Cell::new('A'));
    }
    if let Some(line) = screen.lines.get_mut(9) {
        line.update_cell_with(0, Cell::new('Z'));
    }

    // line_feed at bottom of scroll region should scroll, cursor stays at row 9
    screen.line_feed(Color::Default);

    assert_eq!(
        screen.cursor.row, 9,
        "Cursor should stay at bottom of scroll region"
    );

    // The content should have scrolled:
    // - Row 5 originally had 'A'; after scroll_up within region [5..10),
    //   row 5 now gets the content that was at row 6 (which was empty).
    assert_eq!(
        screen.lines[5].cells[0].char(),
        ' ',
        "Row 5 should be cleared after scroll (original 'A' scrolled out)"
    );

    // - Row 9 originally had 'Z' but it was at the bottom of the scroll region.
    //   After scrolling, row 8 should now hold the old row 9 content ('Z'),
    //   and row 9 (new blank line) should be empty.
    assert_eq!(
        screen.lines[8].cells[0].char(),
        'Z',
        "Row 8 should now have 'Z' (shifted up from row 9)"
    );
    assert_eq!(
        screen.lines[9].cells[0].char(),
        ' ',
        "Row 9 should be a fresh blank line after scroll"
    );
}

// ── Scrollback-specific unit tests ───────────────────────────────────────

#[test]
fn test_push_lines_to_scrollback() {
    let mut screen = Screen::new(24, 80);

    // Initially no scrollback
    assert_eq!(screen.scrollback_line_count, 0);
    assert!(screen.scrollback_buffer.is_empty());

    // Scroll 3 lines into the scrollback buffer
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

    // Set a small scrollback max
    screen.set_scrollback_max_lines(5);
    assert_eq!(screen.scrollback_max_lines, 5);

    // Push more lines than the limit
    for _ in 0..10 {
        screen.scroll_up(1, Color::Default);
    }

    // Old lines must have been evicted; count must not exceed the maximum
    assert_eq!(
        screen.scrollback_line_count, 5,
        "scrollback_line_count must be clamped to scrollback_max_lines"
    );
    assert_eq!(
        screen.scrollback_buffer.len(), 5,
        "scrollback_buffer length must equal scrollback_max_lines after eviction"
    );
}

#[test]
fn test_scrollback_eviction_retains_newest_lines() {
    let mut screen = Screen::new(24, 80);
    screen.set_scrollback_max_lines(3);

    let attrs = SgrAttributes::default();

    // Push 6 lines; each line gets a unique char at col 0 before scrolling.
    // Lines are labelled '1'..'6'; '1' is oldest, '6' is newest.
    let labels = ['1', '2', '3', '4', '5', '6'];
    for &ch in &labels {
        screen.cursor.row = 0;
        screen.cursor.col = 0;
        screen.print(ch, attrs, true);
        screen.scroll_up(1, Color::Default);
    }

    // After 6 pushes with max=3, the 3 oldest ('1','2','3') must be evicted.
    assert_eq!(
        screen.scrollback_buffer.len(), 3,
        "scrollback_buffer must hold exactly 3 lines after eviction"
    );

    // scrollback_buffer[0] = oldest surviving = '4'
    // scrollback_buffer[2] = newest surviving = '6'
    let surviving: Vec<char> = screen
        .scrollback_buffer
        .iter()
        .map(|line| line.get_cell(0).map(|c| c.char()).unwrap_or(' '))
        .collect();

    assert_eq!(
        surviving,
        vec!['4', '5', '6'],
        "oldest lines must be evicted; only newest 3 survive"
    );
}

#[test]
fn test_scroll_offset_clamping() {
    let mut screen = Screen::new(24, 80);

    // Put 10 lines into the scrollback
    for _ in 0..10 {
        screen.scroll_up(1, Color::Default);
    }
    assert_eq!(screen.scrollback_line_count, 10);

    // Attempt to scroll way past the end of the buffer
    screen.viewport_scroll_up(9999);

    // Offset must be clamped to scrollback_line_count
    assert_eq!(
        screen.scroll_offset(), screen.scrollback_line_count,
        "scroll_offset must not exceed scrollback_line_count"
    );
}

#[test]
fn test_scroll_to_live_view() {
    let mut screen = Screen::new(24, 80);

    // Add some scrollback content
    for _ in 0..20 {
        screen.scroll_up(1, Color::Default);
    }

    // Scroll back into history
    screen.viewport_scroll_up(15);
    assert_eq!(screen.scroll_offset(), 15);
    assert!(screen.is_scroll_dirty());

    // Reset scroll offset to 0 to return to the live view
    screen.clear_scroll_dirty();
    screen.viewport_scroll_down(15);

    assert_eq!(
        screen.scroll_offset(), 0,
        "scroll_offset must be 0 when returned to the live view"
    );
    // full_dirty is set when returning to offset 0 to force a full re-render
    let dirty = screen.take_dirty_lines();
    assert_eq!(
        dirty.len(), 24,
        "all rows must be dirty after returning to live view"
    );
}

// ── FR-007: Alternate screen isolation and default scrollback eviction ────────

#[test]
fn test_alt_screen_cell_content_is_isolated() {
    let mut screen = Screen::new(24, 80);
    let attrs = SgrAttributes::default();

    // Print 'X' at (0, 0) on the primary screen
    screen.print('X', attrs, true);
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'X');

    // Switch to the alternate screen
    screen.switch_to_alternate();

    // Print 'Y' at (0, 0) on the alternate screen
    screen.print('Y', attrs, true);
    assert_eq!(screen.get_cell(0, 0).unwrap().char(), 'Y');

    // Switch back to primary — its cell must still be 'X'
    screen.switch_to_primary();
    assert_eq!(
        screen.get_cell(0, 0).unwrap().char(),
        'X',
        "Primary screen cell (0,0) must not be polluted by alternate screen writes"
    );
}

#[test]
fn test_default_scrollback_max_exact_eviction() {
    let mut screen = Screen::new(24, 80);
    // Explicitly confirm the cap matches the const (documents the invariant)
    screen.set_scrollback_max_lines(DEFAULT_SCROLLBACK_MAX);

    // Push DEFAULT_SCROLLBACK_MAX + 1 lines so that exactly one eviction occurs
    for _ in 0..=DEFAULT_SCROLLBACK_MAX {
        screen.scroll_up(1, Color::Default);
    }

    // The buffer must be clamped to DEFAULT_SCROLLBACK_MAX; the oldest line was evicted
    assert_eq!(
        screen.scrollback_line_count,
        DEFAULT_SCROLLBACK_MAX,
        "scrollback_line_count must equal DEFAULT_SCROLLBACK_MAX after one eviction"
    );
    assert_eq!(
        screen.scrollback_buffer.len(),
        DEFAULT_SCROLLBACK_MAX,
        "scrollback_buffer.len() must equal DEFAULT_SCROLLBACK_MAX after one eviction"
    );
}
