use super::*;

#[test]
fn deccara_applies_bold_to_rectangle() {
    let mut term = crate::TerminalCore::new(5, 10);
    // Fill rows 1-3, cols 2-5 via: CSI 2;3;4;6;1 $ r  (1-indexed, bold=1)
    term.advance(b"\x1b[2;3;4;6;1$r");
    assert_row_range_flags!(
        term,
        rows 1..4usize,
        cols 2..6usize,
        SgrFlags::BOLD,
        "cells in the rect must be bold after DECCARA"
    );
    // cells outside rect must NOT be bold
    let line0 = term.screen.get_line(0).unwrap();
    assert!(
        !line0.cells[0].attrs.flags.contains(SgrFlags::BOLD),
        "row 0 outside rect"
    );
}

#[test]
fn deccara_applies_red_foreground() {
    let mut term = crate::TerminalCore::new(4, 8);
    // CSI 1;1;2;8;31 $ r  → rows 0-1, cols 0-7, SGR 31 (red fg)
    term.advance(b"\x1b[1;1;2;8;31$r");
    assert_row_range_foreground!(
        term,
        rows 0..2usize,
        cols 0..8usize,
        Color::Named(NamedColor::Red),
        "cells in the rect must have red fg"
    );
    // row 2 unaffected
    let line2 = term.screen.get_line(2).unwrap();
    for c in 0..8usize {
        assert_ne!(
            line2.cells[c].attrs.foreground,
            Color::Named(NamedColor::Red),
            "row 2 outside rect must not be red"
        );
    }
}

#[test]
fn deccara_reset_clears_attributes() {
    let mut term = crate::TerminalCore::new(3, 6);
    // First apply bold
    term.advance(b"\x1b[1;1;3;6;1$r");
    // Then reset with SGR 0
    term.advance(b"\x1b[1;1;3;6;0$r");
    assert_row_range_char!(
        term,
        rows 0..3usize,
        cols 0..6usize,
        ' ',
        "reset does not change the cell glyphs"
    );
    for r in 0..3usize {
        let line = term.screen.get_line(r).unwrap();
        for c in 0..6usize {
            assert!(
                !line.cells[c].attrs.flags.contains(SgrFlags::BOLD),
                "cell ({r},{c}) must not be bold after DECCARA reset"
            );
        }
    }
}

#[test]
fn deccara_oob_coords_clamped() {
    // Out-of-bounds coordinates must not panic; they are clamped to screen size.
    let mut term = crate::TerminalCore::new(5, 10);
    term.advance(b"\x1b[0;0;999;999;1$r");
}

#[test]
fn deccara_inverted_rect_is_noop() {
    // When bottom < top (inverted row order), DECCARA must be a silent no-op.
    // CSI 4;1;2;5;1 $ r  → top=3, left=0, bottom=1, right=4 (bottom < top).
    // No cell should become bold.
    let mut term = crate::TerminalCore::new(5, 10);
    term.advance(b"\x1b[4;1;2;5;1$r");
    for r in 0..5usize {
        if let Some(line) = term.screen.get_line(r) {
            for c in 0..10usize {
                assert!(
                    !line.cells[c].attrs.flags.contains(SgrFlags::BOLD),
                    "cell ({r},{c}) must not be bold after inverted-rect DECCARA"
                );
            }
        }
    }
}
