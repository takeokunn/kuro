//! Line and character editing methods for Screen

use super::{Cell, CellWidth, Line, Screen, SgrAttributes};

impl Screen {
    /// Clear all lines in range
    pub fn clear_lines(&mut self, start: usize, end: usize) {
        if let Some(lines) = self.active_lines_mut() {
            let end = end.min(lines.len());
            if start < end {
                // VecDeque does not support range-slice indexing; use iter_mut.
                for line in lines.iter_mut().skip(start).take(end - start) {
                    line.clear();
                }
            }
        }
    }

    /// Insert `count` blank lines at the cursor row within the scroll region (IL — CSI Ps L)
    ///
    /// Lines from the cursor row to the scroll region bottom shift down. Lines
    /// pushed past the bottom margin are discarded. Blank lines are filled using
    /// default cell attributes. No-op when the cursor is outside the scroll region.
    #[inline]
    pub fn insert_lines(&mut self, count: usize) {
        let Some(screen) = self.active_screen_mut() else {
            return;
        };
        let cursor_row = screen.cursor.row;
        let top = screen.scroll_region.top;
        let bottom = screen.scroll_region.bottom;

        // Strict guard: no-op when cursor is outside [top, bottom)
        if cursor_row < top || cursor_row >= bottom {
            return;
        }

        // Clamp to lines available between cursor and scroll region bottom
        let count = count.min(bottom - cursor_row);

        // NOTE: O(n * region_size) for n > 1 due to per-iteration VecDeque::remove + insert.
        // Acceptable because n == 1 is the overwhelmingly common case (single line scroll).
        // A batch drain+splice approach would be O(region_size) but adds complexity.
        for _ in 0..count {
            // Discard the bottom-most line in the scroll region
            screen.lines.remove(bottom - 1);
            // Insert a blank line at the cursor row (shifts existing lines down)
            screen
                .lines
                .insert(cursor_row, Line::new(screen.cols as usize));
        }

        // All rows from cursor to bottom of scroll region are now dirty
        screen.mark_dirty_range(cursor_row, bottom);
    }

    /// Delete `count` lines at the cursor row within the scroll region (DL — CSI Ps M)
    ///
    /// Lines below the deleted area scroll up within the scroll region. Blank lines
    /// fill the bottom of the scroll region. No-op when the cursor is outside the
    /// scroll region. Does NOT save lines to the scrollback buffer.
    #[inline]
    pub fn delete_lines(&mut self, count: usize) {
        let Some(screen) = self.active_screen_mut() else {
            return;
        };
        let cursor_row = screen.cursor.row;
        let top = screen.scroll_region.top;
        let bottom = screen.scroll_region.bottom;

        // Strict guard: no-op when cursor is outside [top, bottom)
        if cursor_row < top || cursor_row >= bottom {
            return;
        }

        // Clamp to lines available between cursor and scroll region bottom
        let count = count.min(bottom - cursor_row);

        // NOTE: O(n * region_size) for n > 1 due to per-iteration VecDeque::remove + insert.
        // Acceptable because n == 1 is the overwhelmingly common case (single line scroll).
        // A batch drain+splice approach would be O(region_size) but adds complexity.
        for _ in 0..count {
            // Remove the line at the cursor row (shifts lines below it up)
            screen.lines.remove(cursor_row);
            // Insert a blank line at the bottom of the scroll region
            screen
                .lines
                .insert(bottom - 1, Line::new(screen.cols as usize));
        }

        // All rows from cursor to bottom of scroll region are now dirty
        screen.mark_dirty_range(cursor_row, bottom);
    }

    /// Insert `count` blank characters at the cursor column in the current line (ICH — CSI Ps @)
    ///
    /// Characters to the right of the cursor shift right. Characters pushed past
    /// the right margin are discarded. Blank cells use the current SGR background color.
    #[inline]
    pub fn insert_chars(&mut self, count: usize, attrs: SgrAttributes) {
        let Some(screen) = self.active_screen_mut() else {
            return;
        };
        let cursor_row = screen.cursor.row;
        let cursor_col = screen.cursor.col;
        let cols = screen.cols as usize;

        // Clamp to columns available from cursor to right margin
        let count = count.min(cols.saturating_sub(cursor_col));
        if count == 0 {
            return;
        }

        if let Some(line) = screen.lines.get_mut(cursor_row) {
            let mut blank = Cell::default();
            blank.attrs.background = attrs.background;

            // Wide pair safety: if cursor is on a Wide placeholder, blank its Full partner.
            // Inserting blanks at this position destroys the pair relationship.
            if cursor_col > 0 && line.cells[cursor_col].width == CellWidth::Wide {
                line.cells[cursor_col - 1] = Cell::default();
            }

            // In-place rotation: shift existing cells right, discarding overflow
            let cols = line.cells.len();
            if cursor_col < cols {
                let count = count.min(cols - cursor_col);
                line.cells[cursor_col..].rotate_right(count);
                // Fill the inserted positions with blanks
                line.cells[cursor_col..cursor_col + count].fill(blank);
            }

            line.is_dirty = true;
            line.version = line.version.wrapping_add(1);
            screen.mark_dirty_range(cursor_row, cursor_row + 1);
        }
    }

    /// Delete `count` characters at the cursor column in the current line (DCH — CSI Ps P)
    ///
    /// Characters to the right of the deleted area shift left. Blank cells fill
    /// the right end of the line.
    #[inline]
    pub fn delete_chars(&mut self, count: usize) {
        let Some(screen) = self.active_screen_mut() else {
            return;
        };
        let cursor_row = screen.cursor.row;
        let cursor_col = screen.cursor.col;
        let cols = screen.cols as usize;

        // Clamp to columns available from cursor to right margin
        let count = count.min(cols.saturating_sub(cursor_col));
        if count == 0 {
            return;
        }

        if let Some(line) = screen.lines.get_mut(cursor_row) {
            // Wide pair safety (must be done before drain):
            // 1. If start of range is a Wide placeholder, blank its Full partner.
            if cursor_col > 0 && line.cells[cursor_col].width == CellWidth::Wide {
                line.cells[cursor_col - 1] = Cell::default();
            }
            // 2. If end of range ends on a Full cell, blank its Wide partner
            //    (the Wide placeholder would shift left and become orphaned).
            let drain_end = (cursor_col + count).min(cols);
            if drain_end < cols && line.cells[drain_end - 1].width == CellWidth::Full {
                line.cells[drain_end] = Cell::default();
            }

            line.cells.drain(cursor_col..drain_end);
            line.cells.resize(cols, Cell::default());
            line.is_dirty = true;
            line.version = line.version.wrapping_add(1);
            screen.mark_dirty_range(cursor_row, cursor_row + 1);
        }
    }

    /// Erase `count` characters at the cursor column in the current line (ECH — CSI Ps X)
    ///
    /// Cells are replaced with blanks using the current SGR background color (BCE).
    /// The cursor position does not change. Characters beyond the right margin are ignored.
    #[inline]
    pub fn erase_chars(&mut self, count: usize, attrs: SgrAttributes) {
        let Some(screen) = self.active_screen_mut() else {
            return;
        };
        let cursor_row = screen.cursor.row;
        let cursor_col = screen.cursor.col;
        let cols = screen.cols as usize;

        let end = (cursor_col + count).min(cols);
        if cursor_col >= end {
            return;
        }

        if let Some(line) = screen.lines.get_mut(cursor_row) {
            // Wide pair safety: extend erase range to include orphaned pair halves.
            // 1. If start of range is a Wide placeholder, also erase its Full partner.
            let erase_start = if cursor_col > 0 && line.cells[cursor_col].width == CellWidth::Wide {
                cursor_col - 1
            } else {
                cursor_col
            };
            // 2. If end of range ends on a Full cell, also erase its Wide partner.
            let erase_end = if end < cols && line.cells[end - 1].width == CellWidth::Full {
                end + 1
            } else {
                end
            };

            let mut blank = Cell::default();
            blank.attrs.background = attrs.background;
            line.cells[erase_start..erase_end].fill(blank);
            line.is_dirty = true;
            line.version = line.version.wrapping_add(1);
            screen.mark_dirty_range(cursor_row, cursor_row + 1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fill_rows(screen: &mut Screen) {
        let rows = screen.rows() as usize;
        for r in 0..rows {
            let ch = char::from(b'A' + (r % 26) as u8);
            if let Some(line) = screen.lines.get_mut(r) {
                line.update_cell_with(0, Cell::new(ch));
            }
        }
    }

    fn row_char(screen: &Screen, row: usize) -> char {
        screen.get_cell(row, 0).map_or(' ', Cell::char)
    }

    fn row_is_blank(screen: &Screen, row: usize) -> bool {
        screen
            .get_line(row)
            .is_some_and(|l| l.cells.iter().all(|c| c.char() == ' '))
    }

    macro_rules! assert_row_char {
        ($screen:expr, $row:expr, $ch:expr) => {
            assert_eq!(row_char($screen, $row), $ch, "row {} char mismatch", $row);
        };
    }

    macro_rules! assert_row_blank {
        ($screen:expr, $row:expr) => {
            assert!(row_is_blank($screen, $row), "row {} must be blank", $row);
        };
    }

    // ── erase_chars ───────────────────────────────────────────────────────────

    #[test]
    fn erase_chars_clears_n_cells_at_cursor() {
        let mut screen = Screen::new(5, 10);
        for c in 0..10 {
            if let Some(line) = screen.lines.get_mut(0) {
                line.update_cell_with(c, Cell::new('X'));
            }
        }
        screen.move_cursor(0, 3);
        screen.erase_chars(4, SgrAttributes::default());
        let line = screen.get_line(0).unwrap();
        for c in 0..3 {
            assert_eq!(line.cells[c].char(), 'X', "col {c} before cursor unchanged");
        }
        for c in 3..7 {
            assert_eq!(line.cells[c].char(), ' ', "col {c} must be blank after ECH");
        }
        for c in 7..10 {
            assert_eq!(
                line.cells[c].char(),
                'X',
                "col {c} after erased range unchanged"
            );
        }
        assert_eq!(screen.cursor().col, 3, "ECH must not move cursor");
    }

    #[test]
    fn erase_chars_count_exceeds_line_width_clamps() {
        let mut screen = Screen::new(3, 8);
        for c in 0..8 {
            if let Some(line) = screen.lines.get_mut(0) {
                line.update_cell_with(c, Cell::new('Y'));
            }
        }
        screen.move_cursor(0, 5);
        screen.erase_chars(999, SgrAttributes::default());
        let line = screen.get_line(0).unwrap();
        for c in 0..5 {
            assert_eq!(line.cells[c].char(), 'Y', "col {c} before cursor unchanged");
        }
        for c in 5..8 {
            assert_eq!(line.cells[c].char(), ' ', "col {c} erased");
        }
        assert_eq!(line.cells.len(), 8, "line width preserved");
    }

    #[test]
    fn erase_chars_zero_count_is_noop() {
        let mut screen = Screen::new(3, 8);
        for c in 0..8 {
            if let Some(line) = screen.lines.get_mut(0) {
                line.update_cell_with(c, Cell::new('Z'));
            }
        }
        screen.move_cursor(0, 3);
        screen.erase_chars(0, SgrAttributes::default());
        let line = screen.get_line(0).unwrap();
        for c in 0..8 {
            assert_eq!(line.cells[c].char(), 'Z', "col {c}: noop on count=0");
        }
    }

    // ── insert_chars ──────────────────────────────────────────────────────────

    #[test]
    fn insert_chars_shifts_existing_right() {
        let mut screen = Screen::new(3, 8);
        for c in 0..8 {
            if let Some(line) = screen.lines.get_mut(0) {
                line.update_cell_with(c, Cell::new(char::from(b'A' + c as u8)));
            }
        }
        screen.move_cursor(0, 2);
        screen.insert_chars(2, SgrAttributes::default());
        let line = screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].char(), 'A');
        assert_eq!(line.cells[1].char(), 'B');
        assert_eq!(line.cells[2].char(), ' ', "inserted blank at col 2");
        assert_eq!(line.cells[3].char(), ' ', "inserted blank at col 3");
        assert_eq!(line.cells[4].char(), 'C', "old col 2 shifted to col 4");
        assert_eq!(line.cells[5].char(), 'D');
    }

    #[test]
    fn insert_chars_at_col_zero_shifts_all() {
        let mut screen = Screen::new(3, 5);
        for c in 0..5 {
            if let Some(line) = screen.lines.get_mut(0) {
                line.update_cell_with(c, Cell::new(char::from(b'A' + c as u8)));
            }
        }
        screen.move_cursor(0, 0);
        screen.insert_chars(1, SgrAttributes::default());
        let line = screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].char(), ' ', "blank at col 0");
        assert_eq!(line.cells[1].char(), 'A', "old col 0 shifted to col 1");
        assert_eq!(line.cells[2].char(), 'B');
    }

    // ── delete_chars ──────────────────────────────────────────────────────────

    #[test]
    fn delete_chars_shifts_remaining_left() {
        let mut screen = Screen::new(3, 8);
        for c in 0..8 {
            if let Some(line) = screen.lines.get_mut(0) {
                line.update_cell_with(c, Cell::new(char::from(b'A' + c as u8)));
            }
        }
        screen.move_cursor(0, 2);
        screen.delete_chars(2);
        let line = screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].char(), 'A');
        assert_eq!(line.cells[1].char(), 'B');
        assert_eq!(line.cells[2].char(), 'E', "old col 4 shifted to col 2");
        assert_eq!(line.cells[3].char(), 'F');
        assert_eq!(line.cells[6].char(), ' ', "tail filled with blank");
        assert_eq!(line.cells[7].char(), ' ');
        assert_eq!(line.cells.len(), 8, "line width preserved");
    }

    #[test]
    fn delete_chars_count_exceeds_remaining_clamps() {
        let mut screen = Screen::new(3, 5);
        for c in 0..5 {
            if let Some(line) = screen.lines.get_mut(0) {
                line.update_cell_with(c, Cell::new(char::from(b'0' + c as u8)));
            }
        }
        screen.move_cursor(0, 3);
        screen.delete_chars(999);
        let line = screen.get_line(0).unwrap();
        assert_eq!(line.cells[0].char(), '0');
        assert_eq!(line.cells[1].char(), '1');
        assert_eq!(line.cells[2].char(), '2');
        assert_eq!(line.cells[3].char(), ' ', "erased by DCH");
        assert_eq!(line.cells[4].char(), ' ', "erased by DCH");
        assert_eq!(line.cells.len(), 5);
    }

    // ── insert_lines ──────────────────────────────────────────────────────────

    #[test]
    fn insert_lines_shifts_content_down() {
        let mut screen = Screen::new(5, 10);
        fill_rows(&mut screen);
        screen.cursor.row = 1;
        screen.insert_lines(1);
        assert_row_char!(&screen, 0, 'A');
        assert_row_blank!(&screen, 1);
        assert_row_char!(&screen, 2, 'B');
        assert_row_char!(&screen, 3, 'C');
        assert_row_char!(&screen, 4, 'D');
    }

    #[test]
    fn insert_lines_noop_outside_scroll_region() {
        let mut screen = Screen::new(6, 10);
        fill_rows(&mut screen);
        screen.set_scroll_region(1, 4);
        screen.cursor.row = 5;
        screen.insert_lines(1);
        for r in 0..6usize {
            assert_row_char!(&screen, r, char::from(b'A' + r as u8));
        }
    }

    // ── delete_lines ──────────────────────────────────────────────────────────

    #[test]
    fn delete_lines_shifts_content_up() {
        let mut screen = Screen::new(5, 10);
        fill_rows(&mut screen);
        screen.cursor.row = 1;
        screen.delete_lines(1);
        assert_row_char!(&screen, 0, 'A');
        assert_row_char!(&screen, 1, 'C');
        assert_row_char!(&screen, 2, 'D');
        assert_row_char!(&screen, 3, 'E');
        assert_row_blank!(&screen, 4);
    }

    #[test]
    fn delete_lines_noop_outside_scroll_region() {
        let mut screen = Screen::new(6, 10);
        fill_rows(&mut screen);
        screen.set_scroll_region(2, 5);
        screen.cursor.row = 0;
        screen.delete_lines(1);
        for r in 0..6usize {
            assert_row_char!(&screen, r, char::from(b'A' + r as u8));
        }
    }

    // ── scroll_up / scroll_down ───────────────────────────────────────────────

    #[test]
    fn scroll_up_moves_content_up_one_row() {
        let mut screen = Screen::new(5, 10);
        if let Some(line) = screen.lines.get_mut(1) {
            line.update_cell_with(0, Cell::new('A'));
        }
        screen.scroll_up(1, crate::types::Color::Default);
        assert_eq!(
            screen.get_cell(0, 0).map_or(' ', Cell::char),
            'A',
            "row 1 content should move to row 0 after scroll_up(1)"
        );
        assert!(row_is_blank(&screen, 4));
    }

    #[test]
    fn scroll_down_moves_content_down_one_row() {
        let mut screen = Screen::new(5, 10);
        if let Some(line) = screen.lines.get_mut(0) {
            line.update_cell_with(0, Cell::new('B'));
        }
        screen.scroll_down(1, crate::types::Color::Default);
        assert_eq!(
            screen.get_cell(1, 0).map_or(' ', Cell::char),
            'B',
            "row 0 content should move to row 1 after scroll_down(1)"
        );
        assert!(row_is_blank(&screen, 0));
    }
}
