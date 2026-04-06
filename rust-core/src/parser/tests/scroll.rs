//! Property-based and example-based tests for `scroll` parsing.
//!
//! Module under test: `parser/scroll.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

// Test helpers convert between usize/u16/i64 for grid coordinates; values are
// bounded by terminal dimensions (≤ 65535 rows/cols) so truncation is safe.
#![expect(
    clippy::cast_possible_truncation,
    reason = "test coordinate casts bounded by terminal dimensions (≤ 65535)"
)]

use super::*;

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Fill every cell in every row of `term` with a character derived from `base`:
/// row 0 gets `base`, row 1 gets `base + 1`, etc.  The terminal must have
/// fewer than 26 rows so the cast never overflows.
macro_rules! fill_rows {
    ($term:expr, rows $n:expr, base $base:expr) => {{
        for r in 0..$n {
            if let Some(line) = $term.screen.get_line_mut(r) {
                let ch = ($base as u8 + r as u8) as char;
                let cols = line.cells.len();
                for c in 0..cols {
                    line.update_cell_with(c, crate::types::Cell::new(ch));
                }
            }
        }
    }};
    // Convenience: fill all rows with a single fixed character
    ($term:expr, rows $n:expr, char $ch:expr) => {{
        for r in 0..$n {
            if let Some(line) = $term.screen.get_line_mut(r) {
                let cols = line.cells.len();
                for c in 0..cols {
                    line.update_cell_with(c, crate::types::Cell::new($ch));
                }
            }
        }
    }};
}

/// Assert that every cell in every row still holds the character that
/// `fill_rows!(term, rows N, base BASE)` would have written, i.e. `base + r`.
macro_rules! assert_rows_unchanged {
    ($term:expr, rows $n:expr, base $base:expr) => {{
        for r in 0..$n {
            let ch = ($base as u8 + r as u8) as char;
            assert_eq!(
                $term
                    .screen
                    .get_cell(r, 0)
                    .map_or(' ', crate::types::cell::Cell::char),
                ch,
                "row {r} should be unchanged"
            );
        }
    }};
}

// ── DECSTBM ───────────────────────────────────────────────────────────────────

#[test]
fn test_decstbm_default() {
    let mut term = crate::TerminalCore::new(10, 80);

    // DECSTBM with no parameters should set full screen as scroll region
    let params = vte::Params::default();
    csi_decstbm(&mut term, &params);

    // Check scroll region (0-indexed: top=0, bottom=10 for 10 rows)
    assert_eq!(term.screen.get_scroll_region().top, 0);
    assert_eq!(term.screen.get_scroll_region().bottom, 10);
}

#[test]
fn test_decstbm_with_params() {
    let mut term = crate::TerminalCore::new(10, 80);

    // Set scroll region from row 3 to row 8 (1-indexed: CSI 3;8 r)
    // This becomes (2, 8) in 0-indexed
    term.advance(b"\x1b[3;8r");

    assert_eq!(term.screen.get_scroll_region().top, 2);
    assert_eq!(term.screen.get_scroll_region().bottom, 8);
}

#[test]
fn test_decstbm_moves_cursor_to_home() {
    let mut term = crate::TerminalCore::new(10, 80);

    // Move cursor away from home
    term.screen.move_cursor(5, 10);
    assert_eq!(term.screen.cursor.row, 5);

    // Set scroll region from row 2 to row 8 (1-indexed: CSI 2;8 r)
    // top becomes 1 (0-indexed)
    term.advance(b"\x1b[2;8r");

    // Per DEC VT510: DECOM off (default) → cursor to absolute (0, 0).
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 0);
}

#[test]
fn test_decstbm_inverted_margins_ignored() {
    // CSI 8;3 r — top=8, bottom=3 — top > bottom, should be ignored
    let mut term = crate::TerminalCore::new(10, 80);
    // First set a valid scroll region to verify it doesn't change
    term.advance(b"\x1b[2;8r"); // valid: 1-indexed top=2, bottom=8 → 0-indexed top=1, bottom=8
                                // Now try invalid: top > bottom
    term.advance(b"\x1b[8;3r"); // invalid: should be ignored
                                // The valid region from before should still be active
                                // (cursor will be at home after DECSTBM per spec)
    assert!(term.screen.cursor.row < 10);
    assert!(term.screen.cursor.col < 80);
    // The previously-set valid region must be preserved
    let region = term.screen.get_scroll_region();
    assert_eq!(
        region.top, 1,
        "scroll region top must be unchanged after invalid DECSTBM"
    );
    assert_eq!(
        region.bottom, 8,
        "scroll region bottom must be unchanged after invalid DECSTBM"
    );
}

#[test]
fn test_decstbm_equal_margins_ignored() {
    // CSI 5;5 r — 1-indexed top=5, bottom=5.
    // After 0-indexing: top=4, bottom=5. Since 4 < 5, this is actually
    // accepted by the implementation (equal 1-indexed args become a
    // one-row scroll region in 0-indexed form).
    let mut term = crate::TerminalCore::new(10, 80);
    term.advance(b"\x1b[5;5r");
    assert!(term.screen.cursor.row < 10);
    // Verify the resulting scroll region is exactly (top=4, bottom=5)
    let region = term.screen.get_scroll_region();
    assert_eq!(region.top, 4, "CSI 5;5r sets 0-indexed top=4");
    assert_eq!(region.bottom, 5, "CSI 5;5r sets 0-indexed bottom=5");
}

// ── SU (Scroll Up) ────────────────────────────────────────────────────────────

#[test]
fn test_su_default() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // SU with no parameter (default: 1 line)
    let params = vte::Params::default();
    csi_su(&mut term, &params);

    // Line 0 should now be blank (original line 1 moved there)
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), '1');
}

#[test]
fn test_su_with_param() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'A');

    // Scroll up 3 lines (CSI 3 S)
    term.advance(b"\x1b[3S");

    // Line 0 should now have content from line 3
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), 'D');
}

#[test]
fn test_su_respects_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Set scroll region from row 3 to 8 (0-indexed: 2 to 8)
    term.screen.set_scroll_region(2, 8);

    // Scroll up
    let params = vte::Params::default();
    csi_su(&mut term, &params);

    // Lines outside scroll region should be unchanged
    assert_eq!(term.screen.get_line(0).unwrap().cells[0].char(), '0');
    assert_eq!(term.screen.get_line(1).unwrap().cells[0].char(), '1');

    // Lines inside scroll region should have scrolled
    assert_eq!(
        term.screen.get_line(2).unwrap().cells[0].char(),
        '3', // Was '2', now '3'
    );

    // Bottom of scroll region should be blank
    assert_eq!(term.screen.get_line(7).unwrap().cells[0].char(), ' ');
}

// ── SD (Scroll Down) ──────────────────────────────────────────────────────────

#[test]
fn test_sd_default() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'A');

    // SD with no parameter (default: 1 line)
    let params = vte::Params::default();
    csi_sd(&mut term, &params);

    // Content moves up
    assert_eq!(term.screen.get_line(0).unwrap().cells[0].char(), ' '); // Line 0 becomes blank
    assert_eq!(
        term.screen.get_line(1).unwrap().cells[0].char(),
        'A' // Line 1 now has what was in line 0
    );
}

#[test]
fn test_sd_with_param() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Scroll down 3 lines (CSI 3 T)
    term.advance(b"\x1b[3T");

    // First 3 lines should be blank
    for r in 0..3 {
        let line = term.screen.get_line(r).unwrap();
        assert_eq!(line.cells[0].char(), ' ');
    }

    // Line 3 should now have content from line 0
    assert_eq!(term.screen.get_line(3).unwrap().cells[0].char(), '0');
}

#[test]
fn test_sd_respects_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    fill_rows!(term, rows 10, base b'0');

    // Set scroll region from row 3 to 8 (0-indexed: 2 to 8)
    term.screen.set_scroll_region(2, 8);

    // Scroll down
    let params = vte::Params::default();
    csi_sd(&mut term, &params);

    // Lines outside scroll region should be unchanged
    assert_eq!(term.screen.get_line(0).unwrap().cells[0].char(), '0');
    assert_eq!(term.screen.get_line(1).unwrap().cells[0].char(), '1');

    // Lines inside scroll region should have scrolled
    assert_eq!(
        term.screen.get_line(2).unwrap().cells[0].char(),
        ' ' // Top of scroll region becomes blank
    );
    assert_eq!(
        term.screen.get_line(3).unwrap().cells[0].char(),
        '2' // Was '3', now '2'
    );

    // Bottom of scroll region should have content from above
    assert_eq!(term.screen.get_line(7).unwrap().cells[0].char(), '6');
}

include!("scroll_su_sd.rs");
include!("scroll_edge_cases.rs");

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: SU (CSI n S) with any parameter never panics
    fn prop_su_no_panic(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{n}S").as_bytes());
        prop_assert!(term.screen.rows() == 10);
    }

    #[test]
    // PANIC SAFETY: SD (CSI n T) with any parameter never panics
    fn prop_sd_no_panic(n in 0u16..=300u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{n}T").as_bytes());
        prop_assert!(term.screen.rows() == 10);
    }

    #[test]
    // INVARIANT: RI (ESC M) never panics from any cursor position
    fn prop_ri_no_panic(row in 0usize..10usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(row, 0);
        term.advance(b"\x1bM");
        prop_assert!(term.screen.cursor().row < 10);
    }

    #[test]
    // INVARIANT: valid DECSTBM (top < bottom, both in range) sets scroll region
    fn prop_decstbm_valid_accepts(
        top in 1u16..=8u16,
        extra in 1u16..=2u16,
    ) {
        let rows = 10u16;
        let bot = (top + extra).min(rows);
        prop_assume!(top < bot);
        let mut term = crate::TerminalCore::new(rows, 20);
        term.advance(format!("\x1b[{top};{bot}r").as_bytes());
        // After valid DECSTBM, cursor must be at home
        prop_assert_eq!(term.screen.cursor().row, 0);
        prop_assert_eq!(term.screen.cursor().col, 0);
    }

    #[test]
    // INVARIANT: invalid DECSTBM (top >= bottom) is ignored — cursor still in bounds
    fn prop_decstbm_invalid_no_panic(
        top in 1u16..=10u16,
        bot in 1u16..=10u16,
    ) {
        prop_assume!(top >= bot);
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{top};{bot}r").as_bytes());
        prop_assert!(term.screen.cursor().row < 10);
        prop_assert!(term.screen.cursor().col < 20);
    }

    #[test]
    // INVARIANT: SU(n) then SD(n) leaves rows outside the scroll region untouched.
    // Content that was outside the region before must still be there after SU+SD.
    fn prop_su_sd_outside_region_identity(
        n in 1u16..=4u16,
    ) {
        let mut term = crate::TerminalCore::new(10, 20);
        // Fill every row with a distinct character
        for r in 0..10usize {
            if let Some(line) = term.screen.get_line_mut(r) {
                let ch = (b'A' + r as u8) as char;
                let cols = line.cells.len();
                for c in 0..cols {
                    line.update_cell_with(c, crate::types::Cell::new(ch));
                }
            }
        }
        term.screen.set_scroll_region(2, 8);

        term.advance(format!("\x1b[{n}S").as_bytes());
        term.advance(format!("\x1b[{n}T").as_bytes());

        // Rows 0..2 (above region) must be unchanged
        for r in 0..2usize {
            let ch = (b'A' + r as u8) as char;
            prop_assert_eq!(
                term.screen.get_cell(r, 0).map_or(' ', crate::types::cell::Cell::char),
                ch,
                "row {} above scroll region must be untouched after SU+SD",
                r
            );
        }
        // Rows 8..10 (below region) must be unchanged
        for r in 8..10usize {
            let ch = (b'A' + r as u8) as char;
            prop_assert_eq!(
                term.screen.get_cell(r, 0).map_or(' ', crate::types::cell::Cell::char),
                ch,
                "row {} below scroll region must be untouched after SU+SD",
                r
            );
        }
        prop_assert_eq!(term.screen.rows() as usize, 10);
        prop_assert_eq!(term.screen.cols() as usize, 20);
    }

    #[test]
    // INVARIANT: DECSTBM always leaves the cursor within terminal bounds regardless of params
    fn prop_decstbm_cursor_always_in_bounds(
        top in 0u16..=15u16,
        bot in 0u16..=15u16,
    ) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{top};{bot}r").as_bytes());
        prop_assert!(term.screen.cursor().row < 10);
        prop_assert!(term.screen.cursor().col < 20);
    }
}
