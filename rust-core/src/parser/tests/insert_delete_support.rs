/// Fill every cell in `row` with character `c`
pub(super) fn fill_line(term: &mut crate::TerminalCore, row: usize, c: char) {
    let cols = term.screen.cols() as usize;
    if let Some(line) = term.screen.get_line_mut(row) {
        for col in 0..cols {
            line.update_cell_with(col, crate::types::Cell::new(c));
        }
    }
}

/// Return the character at (row, col), or ' ' if out of bounds
pub(super) fn char_at(term: &crate::TerminalCore, row: usize, col: usize) -> char {
    term.screen
        .get_cell(row, col)
        .map_or(' ', crate::types::cell::Cell::char)
}
