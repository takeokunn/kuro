//! Property-based and example-based tests for `tabs` parsing.
//!
//! Module under test: `parser/tabs.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;

// ── Macros ────────────────────────────────────────────────────────────────────

/// Assert that `TabStops::next_stop(from)` returns `expected` for a default
/// 80-column tab-stop set.
///
/// Syntax: `assert_next_stop!(from => expected, "message")`
macro_rules! assert_next_stop {
    ($from:expr => $expected:expr, $msg:expr) => {{
        let tabs = TabStops::new(80);
        assert_eq!(tabs.next_stop($from), $expected, $msg);
    }};
}

/// Assert that after one `handle_ht` call, the cursor lands at `expected_col`.
///
/// Syntax: `assert_ht_moves!(from_col => expected_col, "message")`
macro_rules! assert_ht_moves {
    ($from:expr => $expected:expr, $msg:expr) => {{
        let mut screen = crate::grid::Screen::new(24, 80);
        let tabs = TabStops::new(80);
        screen.cursor.col = $from;
        handle_ht(&mut screen, &tabs);
        assert_eq!(screen.cursor.col, $expected, $msg);
    }};
}

/// Assert that after `resize(new_cols)`, a given stop is either present or absent.
///
/// Syntax:
/// ```text
/// assert_resize_stop!(from_cols, resize_to new_cols, stop N, present)   // must be present
/// assert_resize_stop!(from_cols, resize_to new_cols, stop N, absent)    // must be absent
/// ```
macro_rules! assert_resize_stop {
    ($from_cols:expr, resize_to $new_cols:expr, stop $stop:expr, present) => {{
        let mut tabs = TabStops::new($from_cols);
        tabs.resize($new_cols);
        assert!(
            tabs.get_stops().contains(&$stop),
            "col {} must be present after resize from {} to {}",
            $stop,
            $from_cols,
            $new_cols
        );
    }};
    ($from_cols:expr, resize_to $new_cols:expr, stop $stop:expr, absent) => {{
        let mut tabs = TabStops::new($from_cols);
        tabs.resize($new_cols);
        assert!(
            !tabs.get_stops().contains(&$stop),
            "col {} must be absent after resize from {} to {}",
            $stop,
            $from_cols,
            $new_cols
        );
    }};
}

// ── Basic stop manipulation ───────────────────────────────────────────────────

#[test]
fn test_tabs_default_stops() {
    let tabs = TabStops::new(80);
    let stops = tabs.get_stops();

    // Should have default tabs every 8 columns
    assert!(stops.contains(&8));
    assert!(stops.contains(&16));
    assert!(stops.contains(&24));
    assert!(stops.contains(&72));
}

#[test]
fn test_set_stop() {
    let mut tabs = TabStops::new(80);

    // Set custom tab at column 5
    tabs.set_stop(5);
    let stops = tabs.get_stops();

    assert!(stops.contains(&5));
}

#[test]
fn test_clear_stop() {
    let mut tabs = TabStops::new(80);

    // Remove default tab at column 8
    tabs.clear_stop(Some(8));
    let stops = tabs.get_stops();

    assert!(!stops.contains(&8));
    assert!(stops.contains(&16)); // Other defaults should remain
}

#[test]
fn test_clear_all_stops() {
    let mut tabs = TabStops::new(80);

    // Add some custom stops
    tabs.set_stop(5);
    tabs.set_stop(10);

    // Clear all stops
    tabs.clear_stop(None);
    let stops = tabs.get_stops();

    // Should be back to defaults
    assert!(stops.contains(&8));
    assert!(stops.contains(&16));
    assert!(!stops.contains(&5));
    assert!(!stops.contains(&10));
}

// ── next_stop ─────────────────────────────────────────────────────────────────

#[test]
fn test_next_stop() {
    let tabs = TabStops::new(80);

    // From column 0, next stop should be 8
    assert_eq!(tabs.next_stop(0), 8);

    // From column 5, next stop should be 8
    assert_eq!(tabs.next_stop(5), 8);

    // From column 8, next stop should be 8 (already at stop)
    assert_eq!(tabs.next_stop(8), 8);

    // From column 9, next stop should be 16
    assert_eq!(tabs.next_stop(9), 16);

    // From beyond last stop, should return end of screen
    let next = tabs.next_stop(75);
    assert!(next <= 79);
}

#[test]
fn test_next_stop_at_existing_stop() {
    // next_stop(8) should return 8 (already on a stop)
    assert_next_stop!(8  => 8,  "next_stop(8) should return 8 (stop exists there)");
    // next_stop(16) should return 16
    assert_next_stop!(16 => 16, "next_stop(16) should return 16");
    // next_stop(72) should return 72 (last default stop)
    assert_next_stop!(72 => 72, "next_stop(72) should return 72 (last default stop)");
}

#[test]
fn test_next_stop_past_all_stops_returns_last_col() {
    // Last default stop in an 80-col terminal is col 72.
    // Querying from 73..79 should return 79 (cols - 1).
    assert_next_stop!(73 => 79, "next_stop(73) must return 79 (last col)");
    assert_next_stop!(79 => 79, "next_stop(79) must return 79 (last col)");
}

/// next_stop from column 1 should find the stop at col 8, not col 0.
#[test]
fn test_next_stop_from_col_one() {
    assert_next_stop!(1 => 8, "next_stop(1) should return first default stop at col 8");
}

/// next_stop from exactly col 7 (one before the first default stop) should
/// return col 8.
#[test]
fn test_next_stop_one_before_default_stop() {
    assert_next_stop!(7 => 8, "next_stop(7) should return 8");
}

// ── handle_ht ────────────────────────────────────────────────────────────────

#[test]
fn test_handle_ht() {
    // Start at column 0, should move to first tab stop (column 8)
    assert_ht_moves!(0  => 8,  "HT from col 0 should move to col 8");
}

#[test]
fn test_handle_ht_multiple() {
    // Start at column 10, should move to next tab stop (column 16)
    assert_ht_moves!(10 => 16, "HT from col 10 should move to col 16");
}

#[test]
fn test_handle_ht_at_last_column_stays_in_bounds() {
    let mut screen = crate::grid::Screen::new(24, 80);
    let tabs = TabStops::new(80);
    screen.cursor.col = 79;
    handle_ht(&mut screen, &tabs);
    assert!(
        screen.cursor.col < 80,
        "HT at last column must not move cursor past col 79"
    );
}

/// HT from col 8 (already at a stop) should advance to the NEXT stop (col 16),
/// not stay at col 8 — handle_ht always moves forward.
#[test]
fn test_handle_ht_from_existing_stop_advances() {
    assert_ht_moves!(8 => 16, "HT from an existing stop (col 8) must advance to next stop (col 16)");
}

/// HT from col 17 (one past the col-16 stop) should advance to col 24.
#[test]
fn test_handle_ht_between_stops() {
    assert_ht_moves!(17 => 24, "HT from col 17 should advance to col 24");
}

// ── handle_hts ───────────────────────────────────────────────────────────────

#[test]
fn test_handle_hts() {
    let mut screen = crate::grid::Screen::new(24, 80);
    let mut tabs = TabStops::new(80);

    // Move cursor to column 5
    screen.cursor.col = 5;

    // Set tab stop at cursor
    handle_hts(&screen, &mut tabs);

    let stops = tabs.get_stops();
    assert!(stops.contains(&5));
}

// ── handle_tbc ───────────────────────────────────────────────────────────────

#[test]
fn test_handle_tbc_clear_current() {
    let mut screen = crate::grid::Screen::new(24, 80);
    let mut tabs = TabStops::new(80);

    // Move cursor to column 8 (default tab stop)
    screen.cursor.col = 8;

    // Clear tab stop at cursor
    let params = vte::Params::default();
    handle_tbc(&screen, &mut tabs, &params);

    let stops = tabs.get_stops();
    assert!(!stops.contains(&8));
}

#[test]
fn test_handle_tbc_clear_all() {
    // Use TerminalCore.advance to send CSI 3 g (TBC - clear all tab stops)
    let mut term = crate::TerminalCore::new(24, 80);

    // Add custom stops
    term.tab_stops.set_stop(5);
    term.tab_stops.set_stop(10);

    // Clear all tab stops via escape sequence (CSI 3 g)
    term.advance(b"\x1b[3g");

    // Should be back to defaults
    let stops = term.tab_stops.get_stops();
    assert!(stops.contains(&8));
    assert!(stops.contains(&16));
    assert!(!stops.contains(&5));
    assert!(!stops.contains(&10));
}

// ── resize ───────────────────────────────────────────────────────────────────

#[test]
fn test_resize_tabs() {
    let mut tabs = TabStops::new(80);

    // Resize to 40 columns
    tabs.resize(40);

    // Stops beyond 40 should be removed
    let stops = tabs.get_stops();
    assert!(stops.contains(&8));
    assert!(stops.contains(&16));
    assert!(stops.contains(&24));
    assert!(stops.contains(&32));
    assert!(!stops.contains(&40));
    assert!(!stops.contains(&72));
}

#[test]
fn test_resize_expand_adds_new_default_stops() {
    // After expanding from 40 to 80 cols, stops at 40 and 72 must appear.
    assert_resize_stop!(40, resize_to 80, stop 40, present);
    assert_resize_stop!(40, resize_to 80, stop 72, present);
}

#[test]
fn test_resize_same_width_is_noop() {
    let mut tabs = TabStops::new(80);
    tabs.set_stop(5); // custom stop
    let before = tabs.get_stops();
    tabs.resize(80);
    let after = tabs.get_stops();
    assert_eq!(before, after, "resize to same width must not change stops");
}

/// Shrinking to 16 cols must remove stops >= 16 (e.g. col 16 itself should vanish
/// because the new terminal only has columns 0..15).
#[test]
fn test_resize_shrink_removes_stops_at_boundary() {
    assert_resize_stop!(80, resize_to 16, stop 16, absent);
    assert_resize_stop!(80, resize_to 16, stop 72, absent);
}

/// After expanding from 16 to 32 cols, col 24 must be a default stop.
#[test]
fn test_resize_expand_adds_intermediate_default_stop() {
    assert_resize_stop!(16, resize_to 32, stop 24, present);
}

// ── save / restore ───────────────────────────────────────────────────────────

#[test]
fn test_save_restore_tabs() {
    let mut tabs = TabStops::new(80);

    // Add custom stops
    tabs.set_stop(5);
    tabs.set_stop(10);
    tabs.clear_stop(Some(8)); // Remove default tab at 8

    // Save
    let saved = tabs.save();

    // Modify
    tabs.clear_stop(None); // Reset to defaults

    // Verify changed
    let stops = tabs.get_stops();
    assert!(stops.contains(&8)); // Back to default

    // Restore
    tabs.restore(saved);

    // Verify restored
    let stops = tabs.get_stops();
    assert!(stops.contains(&5));
    assert!(stops.contains(&10));
    assert!(!stops.contains(&8));
}

#[test]
fn test_restore_shorter_saved_state_pads_with_false() {
    let mut tabs = TabStops::new(80);
    // Save a 40-col bitmap (will be shorter than current width of 80).
    let narrow = TabStops::new(40);
    let saved = narrow.save();
    assert_eq!(saved.len(), 40);

    tabs.restore(saved);
    let stops = tabs.get_stops();
    // Only the stops from the 40-col default bitmap should be present.
    // col 48 (8*6) is beyond the saved 40-col range → must NOT be set.
    assert!(
        !stops.contains(&48),
        "col 48 must not be a stop after restoring a 40-col bitmap into 80-col tabs"
    );
    // col 8 (within the 40-col range) should still be present.
    assert!(stops.contains(&8), "col 8 must be present after restore");
}

// ── Miscellaneous ─────────────────────────────────────────────────────────────

#[test]
fn test_tabs_clamps_to_width() {
    let mut tabs = TabStops::new(40);

    // Try to set stop beyond width
    tabs.set_stop(100);
    let stops = tabs.get_stops();

    assert!(!stops.contains(&100));
}

#[test]
fn test_clear_stop_out_of_bounds_is_noop() {
    let mut tabs = TabStops::new(40);
    let before = tabs.get_stops();
    tabs.clear_stop(Some(100)); // out-of-bounds
    let after = tabs.get_stops();
    assert_eq!(
        before, after,
        "clear_stop with out-of-bounds col must be a no-op"
    );
}

/// ESC H (HTS) sets a tab stop at the cursor's current column. Sending a
/// horizontal tab (0x09) from column 0 should then jump to that column.
#[test]
fn test_hts_sets_tab_stop_at_current_column() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Move cursor to column 5 via cursor-right CSI sequence
    term.advance(b"\x1b[6G"); // CSI 6 G -> column 6 (1-indexed) = 5 (0-indexed)
    assert_eq!(term.screen.cursor.col, 5, "cursor should be at column 5");

    // ESC H: set a tab stop at column 5
    term.advance(b"\x1bH");

    // Move cursor back to column 0
    term.advance(b"\r"); // CR
    assert_eq!(term.screen.cursor.col, 0);

    // HT (tab) from col 0: the default stop at col 8 exists, but col 5 is
    // now also a stop. The `next_stop(1)` scan will find col 5 first.
    term.advance(b"\t");
    assert_eq!(
        term.screen.cursor.col, 5,
        "tab from col 0 should stop at the custom tab stop set at col 5"
    );
}

/// TBC with mode 3 (CSI 3 g) in this implementation resets tab stops to
/// default positions (every 8 columns) rather than clearing to empty.
#[test]
fn test_tbc_clears_and_resets_to_defaults() {
    // TBC with mode 3 (CSI 3 g) in this implementation resets tab stops
    // to default positions (every 8 columns) rather than clearing to empty.
    let mut term = crate::TerminalCore::new(24, 80);
    // First set a custom tab stop at column 5
    term.advance(b"\x1b[1;6H"); // move to col 5 (1-indexed)
    term.advance(b"\x1bH"); // HTS: set tab stop at col 5
                            // Now clear all (resets to defaults)
    term.advance(b"\x1b[3g");
    // After reset, the default stop at col 8 should be present
    term.advance(b"\x1b[1;1H"); // move to col 0
    term.advance(b"\t"); // tab
    assert_eq!(
        term.screen.cursor.col, 8,
        "Default tab stop at col 8 should be restored"
    );
}

/// Tab from column 0 with no custom modifications should move to column 8
/// (the first default tab stop).
#[test]
fn test_tab_movement_basic() {
    let mut term = crate::TerminalCore::new(24, 80);

    // Cursor starts at column 0
    assert_eq!(term.screen.cursor.col, 0);

    // Send a horizontal tab
    term.advance(b"\t");

    // Default first tab stop is at column 8
    assert_eq!(
        term.screen.cursor.col, 8,
        "tab from col 0 should jump to default stop at col 8"
    );
}

// ── New edge-case tests (Round 29+) ───────────────────────────────────────────

/// CHT (Cursor Horizontal Tabulation, CSI n I) is not yet dispatched by the
/// vte_handler (`'I'` falls through to `_ => {}`), so the cursor must remain
/// at its starting column without panicking.
#[test]
fn test_cht_unimplemented_is_noop() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(0, 5);
    term.advance(b"\x1b[2I"); // CHT 2 — silently ignored
    assert_eq!(
        term.screen.cursor().col,
        5,
        "CHT 2 must be a no-op (unimplemented) and leave the cursor at col 5"
    );
}

/// CBT (Cursor Backward Tabulation, CSI n Z) is not yet dispatched by the
/// vte_handler (`'Z'` falls through to `_ => {}`), so the cursor must remain
/// at its starting column without panicking.
#[test]
fn test_cbt_unimplemented_is_noop() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(0, 20);
    term.advance(b"\x1b[1Z"); // CBT 1 — silently ignored
    assert_eq!(
        term.screen.cursor().col,
        20,
        "CBT 1 must be a no-op (unimplemented) and leave the cursor at col 20"
    );
}

/// Sending multiple CHT sequences in a row must not panic and must leave the
/// cursor within terminal bounds (same invariant as the proptest, tested
/// deterministically so failures report a fixed sequence).
#[test]
fn test_cbt_from_col_zero_stays_in_bounds() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(0, 0);
    term.advance(b"\x1b[1Z"); // CBT 1 from col 0
    assert!(
        term.screen.cursor().col < 80,
        "CBT 1 from col 0 must not move the cursor out of bounds"
    );
}

/// set_stop at column 0 is a valid (though unusual) tab position; it should
/// survive a save/restore round-trip.
#[test]
fn test_set_stop_at_col_zero_survives_restore() {
    let mut tabs = TabStops::new(80);
    tabs.set_stop(0); // set stop at column 0
    let saved = tabs.save();
    let mut tabs2 = TabStops::new(80);
    tabs2.restore(saved);
    assert!(
        tabs2.get_stops().contains(&0),
        "col 0 stop must survive a save/restore round-trip"
    );
}

/// TBC 0 (CSI g — clear tab stop at current column) via advance: after clearing
/// the stop at col 8, a tab from col 1 must skip past col 8 to col 16.
#[test]
fn test_tbc_zero_clears_specific_stop_via_advance() {
    let mut term = crate::TerminalCore::new(24, 80);
    // Move cursor to col 8 (the stop to remove)
    term.advance(b"\x1b[9G"); // CSI 9 G → 1-indexed col 9 = 0-indexed col 8
                              // TBC 0: clear stop at current column
    term.advance(b"\x1b[g");
    // Move cursor back to col 1
    term.screen.move_cursor(0, 1);
    // Tab: col 8 stop is gone, must skip to col 16
    term.advance(b"\t");
    assert_eq!(
        term.screen.cursor().col,
        16,
        "after TBC 0 removes col 8 stop, tab from col 1 must land at col 16"
    );
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // BOUNDARY: tab advance (HT) never moves cursor past last column
    fn prop_ht_never_exceeds_cols(n_tabs in 1usize..=20usize) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.screen.move_cursor(0, 0);
        for _ in 0..n_tabs {
            term.advance(b"\x09"); // HT
        }
        prop_assert!(term.screen.cursor().col < 80, "HT must not move cursor past col 79");
    }

    #[test]
    // PANIC SAFETY: CHT (CSI n I) with large n never panics
    fn prop_cht_no_panic(n in 0u16..=200u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.advance(format!("\x1b[{n}I").as_bytes());
        prop_assert!(term.screen.cursor().col < 80);
    }

    #[test]
    // PANIC SAFETY: CBT (CSI n Z) with large n never panics
    fn prop_cbt_no_panic(n in 0u16..=200u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.screen.move_cursor(0, 79); // start at last column
        term.advance(format!("\x1b[{n}Z").as_bytes());
        prop_assert!(term.screen.cursor().col < 80);
    }

    #[test]
    // INVARIANT: After TBC 3 (reset to defaults), HT from col 0 goes to col 8 (default stop)
    fn prop_tbc3_resets_to_defaults(start_col in 0usize..=7usize) {
        let mut term = crate::TerminalCore::new(24, 80);
        // Reset tab stops to defaults
        term.advance(b"\x1b[3g");
        // Move to a column before the first default stop (col 8)
        term.screen.move_cursor(0, start_col);
        // One HT should go to default stop at col 8
        term.advance(b"\x09");
        prop_assert_eq!(term.screen.cursor().col, 8, "after TBC 3, HT from before col 8 must go to default stop at col 8");
    }
}
