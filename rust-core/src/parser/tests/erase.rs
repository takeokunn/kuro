//! Property-based and example-based tests for `erase` parsing.
//!
//! Module under test: `parser/erase.rs`
//! Tier: T3 — ProptestConfig::with_cases(256)

use super::*;
use crate::types::cell::CellWidth;
use crate::types::{Cell, Color, NamedColor, SgrAttributes};

#[test]
fn test_ed_default() {
    let mut term = crate::TerminalCore::new(5, 20);

    // Fill screen with 'X'
    for r in 0..5 {
        for c in 0..20 {
            if let Some(line) = term.screen.get_line_mut(r) {
                line.update_cell_with(c, Cell::new('X'));
            }
        }
    }

    // Move cursor to row 2, col 5
    term.screen.move_cursor(2, 5);

    // ED with no parameter (default: mode 0)
    let params = vte::Params::default();
    csi_ed(&mut term, &params);

    // Check that cursor line from col 5+ is cleared
    let line = term.screen.get_line(2).unwrap();
    for c in 0..5 {
        assert_eq!(
            line.cells[c].char(),
            'X',
            "Column {} should still be 'X'",
            c
        );
    }
    for c in 5..20 {
        assert_eq!(line.cells[c].char(), ' ', "Column {} should be cleared", c);
    }

    // Check that all lines below are cleared
    for r in 3..5 {
        let line = term.screen.get_line(r).unwrap();
        for c in 0..20 {
            assert_eq!(
                line.cells[c].char(),
                ' ',
                "Row {} column {} should be cleared",
                r,
                c
            );
        }
    }

    // Lines above should still have 'X'
    for r in 0..2 {
        let line = term.screen.get_line(r).unwrap();
        for c in 0..20 {
            assert_eq!(
                line.cells[c].char(),
                'X',
                "Row {} column {} should still be 'X'",
                r,
                c
            );
        }
    }
}

#[test]
fn test_ed_mode0() {
    let mut term = crate::TerminalCore::new(3, 10);

    // Fill screen
    for r in 0..3 {
        for c in 0..10 {
            if let Some(line) = term.screen.get_line_mut(r) {
                line.update_cell_with(c, Cell::new('A'));
            }
        }
    }

    // Move cursor to (1, 5)
    term.screen.move_cursor(1, 5);

    // ED mode 0: cursor to end
    let params = vte::Params::default();
    csi_ed(&mut term, &params);

    // Row 0 should be unchanged
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), 'A');

    // Row 1, cols 0-4 unchanged, cols 5-9 cleared
    let line = term.screen.get_line(1).unwrap();
    assert_eq!(line.cells[4].char(), 'A');
    assert_eq!(line.cells[5].char(), ' ');

    // Row 2 should be completely cleared
    let line = term.screen.get_line(2).unwrap();
    assert_eq!(line.cells[0].char(), ' ');
}

#[test]
fn test_ed_mode1() {
    let mut term = crate::TerminalCore::new(3, 10);

    // Fill screen
    for r in 0..3 {
        for c in 0..10 {
            if let Some(line) = term.screen.get_line_mut(r) {
                line.update_cell_with(c, Cell::new('B'));
            }
        }
    }

    // Move cursor to (1, 5)
    term.screen.move_cursor(1, 5);

    // ED mode 1: start to cursor (CSI 1 J)
    term.advance(b"\x1b[1J");

    // Row 0 should be cleared
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), ' ');

    // Row 1, cols 0-5 cleared, cols 6-9 unchanged
    let line = term.screen.get_line(1).unwrap();
    assert_eq!(line.cells[5].char(), ' ');
    assert_eq!(line.cells[6].char(), 'B');

    // Row 2 should be unchanged
    let line = term.screen.get_line(2).unwrap();
    assert_eq!(line.cells[0].char(), 'B');
}

#[test]
fn test_ed_mode2() {
    let mut term = crate::TerminalCore::new(3, 10);

    // Fill screen
    for r in 0..3 {
        for c in 0..10 {
            if let Some(line) = term.screen.get_line_mut(r) {
                line.update_cell_with(c, Cell::new('C'));
            }
        }
    }

    // ED mode 2: entire screen (CSI 2 J)
    term.advance(b"\x1b[2J");

    // All rows should be cleared
    for r in 0..3 {
        let line = term.screen.get_line(r).unwrap();
        for c in 0..10 {
            assert_eq!(
                line.cells[c].char(),
                ' ',
                "Row {} col {} should be cleared",
                r,
                c
            );
        }
    }
}

#[test]
fn test_ed_mode3_clears_scrollback() {
    let mut term = crate::TerminalCore::new(5, 10);

    // Add lines to scrollback
    for _ in 0..5 {
        term.screen
            .scroll_up(1, crate::types::color::Color::Default);
    }

    assert_eq!(term.screen.scrollback_line_count, 5);

    // ED mode 3: entire screen and scrollback (CSI 3 J)
    term.advance(b"\x1b[3J");

    // Scrollback should be cleared
    assert_eq!(term.screen.scrollback_line_count, 0);
}

#[test]
fn test_el_default() {
    let mut term = crate::TerminalCore::new(5, 20);

    // Fill a line with 'Y'
    let row = 2;
    for c in 0..20 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('Y'));
        }
    }

    // Move cursor to row 2, col 5
    term.screen.move_cursor(row, 5);

    // EL with no parameter (default: mode 0)
    let params = vte::Params::default();
    csi_el(&mut term, &params);

    // Check line
    let line = term.screen.get_line(row).unwrap();
    for c in 0..5 {
        assert_eq!(
            line.cells[c].char(),
            'Y',
            "Column {} should still be 'Y'",
            c
        );
    }
    for c in 5..20 {
        assert_eq!(line.cells[c].char(), ' ', "Column {} should be cleared", c);
    }
}

#[test]
fn test_el_mode0() {
    let mut term = crate::TerminalCore::new(5, 10);

    let row = 2;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('Z'));
        }
    }

    term.screen.move_cursor(row, 3);

    // EL mode 0: cursor to end
    let params = vte::Params::default();
    csi_el(&mut term, &params);

    let line = term.screen.get_line(row).unwrap();
    assert_eq!(line.cells[2].char(), 'Z');
    assert_eq!(line.cells[3].char(), ' ');
}

#[test]
fn test_el_mode1() {
    let mut term = crate::TerminalCore::new(5, 10);

    let row = 2;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('W'));
        }
    }

    term.screen.move_cursor(row, 5);

    // EL mode 1: start to cursor (CSI 1 K)
    term.advance(b"\x1b[1K");

    let line = term.screen.get_line(row).unwrap();
    assert_eq!(line.cells[5].char(), ' ');
    assert_eq!(line.cells[6].char(), 'W');
}

#[test]
fn test_el_mode2() {
    let mut term = crate::TerminalCore::new(5, 10);

    let row = 2;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('V'));
        }
    }

    term.screen.move_cursor(row, 5);

    // EL mode 2: entire line (CSI 2 K)
    term.advance(b"\x1b[2K");

    let line = term.screen.get_line(row).unwrap();
    for c in 0..10 {
        assert_eq!(line.cells[c].char(), ' ', "Column {} should be cleared", c);
    }
}

#[test]
fn test_erase_with_default_bg_preserves_default() {
    let mut term = crate::TerminalCore::new(5, 10);
    // No background color set (default attrs)
    term.screen.print('A', SgrAttributes::default(), true);
    term.screen.move_cursor(0, 0);
    let params = vte::Params::default();
    csi_el(&mut term, &params);
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), ' ');
    assert_eq!(line.cells[0].attrs.background, Color::Default);
}

#[test]
fn test_erase_with_colored_bg_applies_bce() {
    let mut term = crate::TerminalCore::new(5, 10);
    let attrs = SgrAttributes { background: Color::Named(NamedColor::Blue), ..Default::default() };
    term.current_attrs = attrs;
    term.screen.print('A', attrs, true);
    term.screen.move_cursor(0, 0);
    let params = vte::Params::default();
    csi_el(&mut term, &params);
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].char(), ' ');
    assert_eq!(
        line.cells[0].attrs.background,
        Color::Named(NamedColor::Blue)
    );
}

#[test]
fn test_ed_with_colored_bg_applies_bce() {
    let mut term = crate::TerminalCore::new(5, 10);

    // Fill screen with content
    for r in 0..5 {
        for c in 0..10 {
            if let Some(line) = term.screen.get_line_mut(r) {
                line.update_cell_with(c, Cell::new('X'));
            }
        }
    }

    // Move cursor to row 2, col 0
    term.screen.move_cursor(2, 0);

    // Set a non-default background color
    term.current_attrs.background = Color::Named(NamedColor::Blue);

    // ED mode 0: erase from cursor to end of screen (CSI J)
    term.advance(b"\x1b[J");

    // Rows 2-4 (erased) should have Blue background
    for r in 2..5 {
        let line = term.screen.get_line(r).unwrap();
        for c in 0..10 {
            assert_eq!(
                line.cells[c].attrs.background,
                Color::Named(NamedColor::Blue),
                "Row {} col {} should have Blue background after ED",
                r,
                c
            );
            assert_eq!(
                line.cells[c].char(),
                ' ',
                "Row {} col {} should be cleared",
                r,
                c
            );
        }
    }

    // Rows above cursor (0-1) should retain original default background
    for r in 0..2 {
        let line = term.screen.get_line(r).unwrap();
        for c in 0..10 {
            assert_eq!(
                line.cells[c].char(),
                'X',
                "Row {} col {} should still be 'X'",
                r,
                c
            );
            assert_eq!(
                line.cells[c].attrs.background,
                Color::Default,
                "Row {} col {} should retain default background",
                r,
                c
            );
        }
    }
}

#[test]
fn test_erase_marks_dirty() {
    let mut term = crate::TerminalCore::new(5, 10);

    // Take initial dirty lines
    let dirty1 = term.screen.take_dirty_lines();
    assert_eq!(dirty1.len(), 0);

    // Fill a line
    let row = 2;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('T'));
            line.is_dirty = false;
        }
    }

    // Erase the line
    term.screen.move_cursor(row, 0);
    let params = vte::Params::default();
    csi_el(&mut term, &params);

    // Line should be marked dirty
    let line = term.screen.get_line(row).unwrap();
    assert!(line.is_dirty);

    // Also test ED
    term.screen.move_cursor(0, 0);
    let params = vte::Params::default();
    csi_ed(&mut term, &params);

    // All lines should be dirty
    let dirty = term.screen.take_dirty_lines();
    assert!(!dirty.is_empty());
}

#[test]
fn test_el_mode0_splits_wide_char() {
    // EL mode 0 starting at the Wide placeholder of a CJK character should
    // also erase the Full partner cell.
    let mut term = crate::TerminalCore::new(5, 20);
    // Print a wide character at columns 0-1 (Full + Wide)
    term.screen
        .print('\u{65E5}', SgrAttributes::default(), true); // '日'
                                                            // Verify setup: col 0 is Full, col 1 is Wide
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[0].width, CellWidth::Full);
    assert_eq!(line.cells[1].width, CellWidth::Wide);

    // Move cursor to column 1 (the Wide placeholder)
    term.screen.move_cursor(0, 1);

    // EL mode 0: erase from cursor to end of line
    let params = vte::Params::default();
    csi_el(&mut term, &params);

    // Both cells 0 and 1 should be cleared
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(
        line.cells[0].char(),
        ' ',
        "Full cell (col 0) should be cleared when its Wide partner is erased"
    );
    assert_eq!(line.cells[0].width, CellWidth::Half);
    assert_eq!(
        line.cells[1].char(),
        ' ',
        "Wide cell (col 1) should be cleared"
    );
    assert_eq!(line.cells[1].width, CellWidth::Half);
}

#[test]
fn test_el_mode1_splits_wide_char() {
    // EL mode 1 ending at the Full cell of a CJK character should
    // also erase the Wide partner cell.
    let mut term = crate::TerminalCore::new(5, 20);
    // Print some filler then a wide character at columns 4-5
    for c in 0..4 {
        if let Some(line) = term.screen.get_line_mut(0) {
            line.update_cell_with(c, Cell::new('A'));
        }
    }
    term.screen.move_cursor(0, 4);
    term.screen
        .print('\u{65E5}', SgrAttributes::default(), true); // '日'
                                                            // Verify setup: col 4 is Full, col 5 is Wide
    let line = term.screen.get_line(0).unwrap();
    assert_eq!(line.cells[4].width, CellWidth::Full);
    assert_eq!(line.cells[5].width, CellWidth::Wide);

    // Move cursor to column 4 (the Full cell)
    term.screen.move_cursor(0, 4);

    // EL mode 1: erase from start of line to cursor
    term.advance(b"\x1b[1K");

    // Cells 0-5 should all be cleared (0-4 by the erase range, 5 as the Wide partner)
    let line = term.screen.get_line(0).unwrap();
    for c in 0..=5 {
        assert_eq!(line.cells[c].char(), ' ', "Column {} should be cleared", c);
        assert_eq!(
            line.cells[c].width,
            CellWidth::Half,
            "Column {} should be Half width after clearing",
            c
        );
    }
}

#[test]
fn test_ed_mode0_splits_wide_char() {
    // ED mode 0 starting at the Wide placeholder should also erase the Full partner
    let mut term = crate::TerminalCore::new(3, 20);
    term.screen
        .print('\u{65E5}', SgrAttributes::default(), true);
    term.screen.move_cursor(0, 1); // on the Wide placeholder

    let params = vte::Params::default();
    csi_ed(&mut term, &params);

    let line = term.screen.get_line(0).unwrap();
    assert_eq!(
        line.cells[0].char(),
        ' ',
        "Full cell should be cleared by ED mode 0"
    );
    assert_eq!(line.cells[0].width, CellWidth::Half);
}

#[test]
fn test_ed_mode1_splits_wide_char() {
    // ED mode 1 ending at the Full cell should also erase the Wide partner
    let mut term = crate::TerminalCore::new(3, 20);
    term.screen.move_cursor(0, 4);
    term.screen
        .print('\u{65E5}', SgrAttributes::default(), true);
    term.screen.move_cursor(0, 4); // on the Full cell

    term.advance(b"\x1b[1J");

    let line = term.screen.get_line(0).unwrap();
    assert_eq!(
        line.cells[5].char(),
        ' ',
        "Wide partner should be cleared by ED mode 1"
    );
    assert_eq!(line.cells[5].width, CellWidth::Half);
}

#[test]
fn test_el_mode1_with_colored_bg_applies_bce() {
    // EL mode 1 (erase from start of line to cursor) should use the current SGR background.
    let mut term = crate::TerminalCore::new(5, 10);
    let attrs = SgrAttributes { background: Color::Named(NamedColor::Red), ..Default::default() };
    term.current_attrs = attrs;

    // Fill row 2 with content, then erase from start to col 5
    let row = 2;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('Q'));
        }
    }
    term.screen.move_cursor(row, 5);
    term.advance(b"\x1b[1K");

    let line = term.screen.get_line(row).unwrap();
    // Cells 0..=5 should be cleared with Red background (BCE)
    for c in 0..=5 {
        assert_eq!(
            line.cells[c].attrs.background,
            Color::Named(NamedColor::Red),
            "EL mode 1: col {} should have Red background",
            c
        );
        assert_eq!(line.cells[c].char(), ' ');
    }
    // Cells 6-9 should be untouched ('Q' with default background)
    for c in 6..10 {
        assert_eq!(line.cells[c].char(), 'Q');
    }
}

#[test]
fn test_el_mode2_with_colored_bg_applies_bce() {
    // EL mode 2 (erase entire line) should use the current SGR background.
    let mut term = crate::TerminalCore::new(5, 10);
    let attrs = SgrAttributes { background: Color::Named(NamedColor::Green), ..Default::default() };
    term.current_attrs = attrs;

    let row = 1;
    for c in 0..10 {
        if let Some(line) = term.screen.get_line_mut(row) {
            line.update_cell_with(c, Cell::new('P'));
        }
    }
    term.screen.move_cursor(row, 3);
    term.advance(b"\x1b[2K");

    let line = term.screen.get_line(row).unwrap();
    for c in 0..10 {
        assert_eq!(
            line.cells[c].attrs.background,
            Color::Named(NamedColor::Green),
            "EL mode 2: col {} should have Green background",
            c
        );
        assert_eq!(line.cells[c].char(), ' ');
    }
}

#[test]
fn test_ed_mode1_with_colored_bg_applies_bce() {
    // ED mode 1 (erase from start of screen to cursor) should use the current SGR background.
    let mut term = crate::TerminalCore::new(5, 10);
    for r in 0..5 {
        for c in 0..10 {
            if let Some(line) = term.screen.get_line_mut(r) {
                line.update_cell_with(c, Cell::new('M'));
            }
        }
    }
    term.current_attrs.background = Color::Named(NamedColor::Cyan);
    // Cursor at row 2, col 5; erase from start of screen to here
    term.screen.move_cursor(2, 5);
    term.advance(b"\x1b[1J");

    // Rows 0-1 (fully erased) should have Cyan background
    for r in 0..2 {
        let line = term.screen.get_line(r).unwrap();
        for c in 0..10 {
            assert_eq!(
                line.cells[c].attrs.background,
                Color::Named(NamedColor::Cyan),
                "ED mode 1: row {} col {} should have Cyan background",
                r,
                c
            );
        }
    }
    // Row 2, cols 0..=5 also erased with Cyan background
    let line = term.screen.get_line(2).unwrap();
    for c in 0..=5 {
        assert_eq!(
            line.cells[c].attrs.background,
            Color::Named(NamedColor::Cyan),
            "ED mode 1: row 2 col {} should have Cyan background",
            c
        );
    }
}

#[test]
fn test_ed_mode2_with_colored_bg_applies_bce() {
    // ED mode 2 (erase entire screen) should use the current SGR background.
    let mut term = crate::TerminalCore::new(3, 8);
    for r in 0..3 {
        for c in 0..8 {
            if let Some(line) = term.screen.get_line_mut(r) {
                line.update_cell_with(c, Cell::new('N'));
            }
        }
    }
    term.current_attrs.background = Color::Named(NamedColor::Magenta);
    term.advance(b"\x1b[2J");

    for r in 0..3 {
        let line = term.screen.get_line(r).unwrap();
        for c in 0..8 {
            assert_eq!(
                line.cells[c].attrs.background,
                Color::Named(NamedColor::Magenta),
                "ED mode 2: row {} col {} should have Magenta background",
                r,
                c
            );
            assert_eq!(line.cells[c].char(), ' ');
        }
    }
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: ED (CSI n J) with any parameter never panics
    fn prop_ed_no_panic(ps in 0u16..=10u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{}J", ps).as_bytes());
        prop_assert_eq!(term.screen.rows() as usize, 10);
    }

    #[test]
    // PANIC SAFETY: EL (CSI n K) with any parameter never panics
    fn prop_el_no_panic(ps in 0u16..=10u16) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.advance(format!("\x1b[{}K", ps).as_bytes());
        prop_assert_eq!(term.screen.rows() as usize, 10);
    }

    #[test]
    // PANIC SAFETY: ECH (CSI n X) with any parameter never panics; line width preserved
    fn prop_ech_no_panic(n in 0u16..=300u16, col in 0usize..20usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        term.screen.move_cursor(0, col);
        term.advance(format!("\x1b[{}X", n).as_bytes());
        prop_assert_eq!(
            term.screen.get_line(0).unwrap().cells.len(),
            20,
            "line width must be preserved after ECH"
        );
    }

    #[test]
    // INVARIANT: ED 2 (erase entire display) leaves all cells blank
    fn prop_ed2_clears_all_cells(row in 0usize..10usize, col in 0usize..20usize) {
        let mut term = crate::TerminalCore::new(10, 20);
        // Write something first
        term.screen.move_cursor(row, col);
        term.screen.print('X', crate::types::cell::SgrAttributes::default(), true);
        // Erase display
        term.advance(b"\x1b[2J");
        for r in 0..10usize {
            for c in 0..20usize {
                prop_assert_eq!(
                    term.screen.get_cell(r, c).unwrap().char(), ' ',
                    "cell ({},{}) must be blank after ED 2", r, c
                );
            }
        }
    }
}
