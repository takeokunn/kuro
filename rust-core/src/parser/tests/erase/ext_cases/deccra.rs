use super::*;

#[test]
fn deccra_zero_row_rect_is_noop() {
    // DECCRA with src_top > src_bottom (inverted row order) must be a silent
    // no-op: rect_rows = src_bottom.saturating_sub(src_top) = 0 → early return.
    // CSI 5;1;3;5;0;1;1$v on a 5x5 terminal:
    //   src_top=4 (Pt=5), src_bottom=3 (Pb=3) → rect_rows=0.
    let mut term = crate::TerminalCore::new(5, 5);
    // Fill row 0 with 'Z' so we can confirm it is unchanged.
    fill_cells!(term, row 0, cols 0..5usize, 'Z');
    term.advance(b"\x1b[5;1;3;5;0;1;1$v");
    assert_row_range_char!(
        term,
        rows 0..1usize,
        cols 0..5usize,
        'Z',
        "DECCRA zero-row rect must not modify dst cell"
    );
}

#[test]
fn deccra_zero_col_rect_is_noop() {
    // DECCRA with src_left > src_right (inverted col order) must be a no-op:
    // rect_cols = src_right.saturating_sub(src_left) = 0 → early return.
    // CSI 1;5;3;3;0;1;1$v on a 5x5 terminal:
    //   src_left=4 (Pl=5), src_right=3 (Pr=3) → rect_cols=0.
    let mut term = crate::TerminalCore::new(5, 5);
    fill_cells!(term, row 0, cols 0..5usize, 'Q');
    term.advance(b"\x1b[1;5;3;3;0;1;1$v");
    assert_row_range_char!(
        term,
        rows 0..1usize,
        cols 0..5usize,
        'Q',
        "DECCRA zero-col rect must not modify dst cell"
    );
}
