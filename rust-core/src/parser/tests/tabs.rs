//! Property-based and example-based tests for `tabs` parsing.
//!
//! Module under test: `parser/tabs.rs`
//! Tier: T3 — ProptestConfig::with_cases(256)

use super::*;

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
fn test_handle_ht() {
    let mut screen = crate::grid::Screen::new(24, 80);
    let tabs = TabStops::new(80);

    // Start at column 0
    assert_eq!(screen.cursor.col, 0);

    // Horizontal tab
    handle_ht(&mut screen, &tabs);

    // Should move to first tab stop (column 8)
    assert_eq!(screen.cursor.col, 8);
}

#[test]
fn test_handle_ht_multiple() {
    let mut screen = crate::grid::Screen::new(24, 80);
    let tabs = TabStops::new(80);

    // Start at column 10
    screen.cursor.col = 10;

    handle_ht(&mut screen, &tabs);

    // Should move to next tab stop (column 16)
    assert_eq!(screen.cursor.col, 16);
}

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
fn test_tabs_clamps_to_width() {
    let mut tabs = TabStops::new(40);

    // Try to set stop beyond width
    tabs.set_stop(100);
    let stops = tabs.get_stops();

    assert!(!stops.contains(&100));
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
        term.advance(format!("\x1b[{}I", n).as_bytes());
        prop_assert!(term.screen.cursor().col < 80);
    }

    #[test]
    // PANIC SAFETY: CBT (CSI n Z) with large n never panics
    fn prop_cbt_no_panic(n in 0u16..=200u16) {
        let mut term = crate::TerminalCore::new(24, 80);
        term.screen.move_cursor(0, 79); // start at last column
        term.advance(format!("\x1b[{}Z", n).as_bytes());
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
