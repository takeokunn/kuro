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

// ── Edge cases: narrow/empty terminals ───────────────────────────────────────

/// A 1-column terminal has no default tab stops (the loop `8, 16, ...` never
/// fires for cols == 1).  `get_stops()` must return an empty vec.
#[test]
fn test_new_one_col_has_no_default_stops() {
    let tabs = TabStops::new(1);
    assert!(
        tabs.get_stops().is_empty(),
        "a 1-column terminal must have no default tab stops"
    );
}

/// `next_stop` on a 1-column terminal with no stops must return 0 (cols-1).
#[test]
fn test_next_stop_one_col_returns_zero() {
    let tabs = TabStops::new(1);
    assert_eq!(
        tabs.next_stop(0),
        0,
        "next_stop(0) on a 1-col terminal must return 0 (last col)"
    );
}

/// `handle_ht` on a 1-column terminal must not move the cursor (it stays
/// within bounds and there are no stops to advance to).
#[test]
fn test_handle_ht_one_col_stays_in_bounds() {
    let mut screen = crate::grid::Screen::new(24, 1);
    let tabs = TabStops::new(1);
    screen.cursor.col = 0;
    handle_ht(&mut screen, &tabs);
    assert_eq!(
        screen.cursor.col, 0,
        "HT on a 1-column terminal must keep cursor at col 0"
    );
}

// ── set_stop idempotency ───────────────────────────────────────────────────

/// Setting the same stop twice must produce the same result as setting it once.
#[test]
fn test_set_stop_idempotent() {
    let mut tabs = TabStops::new(80);
    tabs.set_stop(5);
    tabs.set_stop(5); // second call must be a no-op
    let stops = tabs.get_stops();
    let count = stops.iter().filter(|&&c| c == 5).count();
    assert_eq!(count, 1, "col 5 must appear exactly once in get_stops()");
}

// ── clear_stop on a column with no stop ───────────────────────────────────

/// `clear_stop(Some(col))` when there is no stop at `col` must be a no-op.
#[test]
fn test_clear_stop_no_stop_at_col_is_noop() {
    let mut tabs = TabStops::new(80);
    let before = tabs.get_stops();
    tabs.clear_stop(Some(5)); // col 5 has no stop by default
    let after = tabs.get_stops();
    assert_eq!(
        before, after,
        "clear_stop of a non-existent stop must be a no-op"
    );
}

// ── multiple sequential HT calls ─────────────────────────────────────────

/// Sending 9 consecutive HT bytes from col 0 must advance the cursor through
/// all default stops and eventually clamp at col 79.
#[test]
fn test_multiple_ht_advance_through_all_stops() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(0, 0);
    for _ in 0..9 {
        term.advance(b"\t");
    }
    // After 9 tabs from col 0: 8,16,24,32,40,48,56,64,72 — then clamped at 79.
    assert!(
        term.screen.cursor().col <= 79,
        "cursor must not exceed col 79 after many HT calls"
    );
}

/// Three consecutive HT calls from col 0 must place the cursor at col 24
/// (default stops: 8, 16, 24).
#[test]
fn test_three_ht_from_col_zero_lands_at_24() {
    let mut term = crate::TerminalCore::new(24, 80);
    term.screen.move_cursor(0, 0);
    term.advance(b"\t\t\t"); // three HT bytes
    assert_eq!(
        term.screen.cursor().col,
        24,
        "three HT calls from col 0 must land at the third default stop (col 24)"
    );
}

// ── resize edge cases ─────────────────────────────────────────────────────

/// Resizing to 1 column must remove all default stops (no stop ≥ 1 can be
/// placed, since valid indices are 0..1 and the loop starts at col 8).
#[test]
fn test_resize_to_one_col_removes_all_stops() {
    let mut tabs = TabStops::new(80);
    tabs.resize(1);
    assert!(
        tabs.get_stops().is_empty(),
        "resizing to 1 column must remove all tab stops"
    );
}

/// `resize` shrink: col 8 must be absent after shrinking to 8 columns (the
/// stop at exactly the boundary index is removed by truncation).
#[test]
fn test_resize_shrink_to_8_removes_col_8() {
    assert_resize_stop!(80, resize_to 8, stop 8, absent);
}

// ── handle_hts at column 0 ────────────────────────────────────────────────

/// `handle_hts` (ESC H) at column 0 must set a stop at col 0, which survives
/// a `get_stops()` query.
#[test]
fn test_handle_hts_at_col_zero() {
    let mut screen = crate::grid::Screen::new(24, 80);
    let mut tabs = TabStops::new(80);
    screen.cursor.col = 0;
    handle_hts(&screen, &mut tabs);
    assert!(
        tabs.get_stops().contains(&0),
        "HTS at col 0 must add a tab stop at col 0"
    );
}

// ── save / restore with cleared state ────────────────────────────────────

/// Save a state where ALL stops have been individually cleared (not via
/// clear_stop(None) which resets to defaults), then restore it.  The restored
/// state must have no stops at the manually-cleared positions.
///
/// We accomplish this by calling `clear_stop(Some(col))` for every default stop
/// (8, 16, … 72) and then saving the resulting all-false bitmap.
#[test]
fn test_save_restore_all_cleared_state() {
    let mut tabs = TabStops::new(80);
    // Manually remove every default stop.
    for col in (8..80usize).step_by(8) {
        tabs.clear_stop(Some(col));
    }
    // Verify all stops are gone.
    assert!(
        tabs.get_stops().is_empty(),
        "all default stops must be removable individually"
    );
    let saved = tabs.save();

    // Now create a fresh set and restore into it.
    let mut tabs2 = TabStops::new(80);
    tabs2.restore(saved);
    assert!(
        tabs2.get_stops().is_empty(),
        "restoring an all-cleared bitmap must yield no stops"
    );
}
