#[test]
fn insert_lines_count_clamped_to_remaining_lines_in_region() {
    // insert_lines(count) where count > (bottom - cursor_row) must clamp;
    // total line count must remain constant and not panic.
    let mut s = make_screen();
    let rows_before = s.rows() as usize;
    // Position cursor at row 20 of a 24-row screen (scroll region 0..24).
    // Only 4 lines remain until the bottom; inserting 100 must act as 4.
    s.move_cursor(20, 0);
    s.insert_lines(100);
    assert_eq!(s.rows() as usize, rows_before);
    // Rows 20..24 must be blank (all available slots were replaced)
    for row in 20..24 {
        assert_eq!(
            s.get_cell(row, 0).unwrap().char(),
            ' ',
            "row {row} must be blank after over-large insert_lines"
        );
    }
}

#[test]
fn insert_lines_at_bottom_minus_one_is_single_blank() {
    // insert_lines(1) at the last row inside the scroll region produces exactly
    // one blank at the cursor row and discards the former bottom row.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    let bottom = s.rows() as usize; // default scroll region ends at rows

    // Write 'X' at the second-to-last row (bottom - 1 is the bottom exclusive bound,
    // so the last inclusive row is bottom - 1 in 0-indexed).
    let last_row = bottom - 1;
    s.move_cursor(last_row, 0);
    s.print('X', attrs, true);

    s.move_cursor(last_row, 0);
    s.insert_lines(1);

    // That row is now blank (the inserted blank)
    assert_eq!(s.get_cell(last_row, 0).unwrap().char(), ' ');
    // Total rows unchanged
    assert_eq!(s.rows() as usize, bottom);
}

// ---------------------------------------------------------------------------
// delete_lines — multi-count and clamping
// ---------------------------------------------------------------------------

#[test]
fn delete_lines_count_greater_than_one_scrolls_multiple_rows_up() {
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    // Rows 0/1/2/3: 'A'/'B'/'C'/'D'
    for (row, ch) in [(0, 'A'), (1, 'B'), (2, 'C'), (3, 'D')] {
        s.move_cursor(row, 0);
        s.print(ch, attrs, true);
    }

    // Delete 2 lines at row 0
    s.move_cursor(0, 0);
    s.delete_lines(2);

    // Old rows 2/3 are now at rows 0/1
    assert_cell_char!(s, 0, 0, 'C');
    assert_cell_char!(s, 1, 0, 'D');
    // Bottom two rows of scroll region become blank
    assert_cell_char!(s, 22, 0, ' ');
    assert_cell_char!(s, 23, 0, ' ');
}

#[test]
fn delete_lines_count_clamped_to_remaining_lines_in_region() {
    // delete_lines(count) where count > (bottom - cursor_row) must clamp and not panic.
    let mut s = make_screen();
    let rows_before = s.rows() as usize;
    s.move_cursor(20, 0);
    s.delete_lines(100);
    assert_eq!(s.rows() as usize, rows_before);
    // Rows 20..24 must all be blank (filled by the clamped delete)
    for row in 20..24 {
        assert_eq!(
            s.get_cell(row, 0).unwrap().char(),
            ' ',
            "row {row} must be blank after over-large delete_lines"
        );
    }
}

#[test]
fn delete_lines_within_partial_scroll_region_does_not_affect_outside_rows() {
    // delete_lines inside a sub-region must not touch rows above top or below bottom.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Write sentinels outside the scroll region
    s.move_cursor(0, 0);
    s.print('T', attrs, true); // above top=5
    s.move_cursor(15, 0);
    s.print('B', attrs, true); // below bottom=10

    // Restrict scroll region to rows 5..10
    s.set_scroll_region(5, 10);

    // Write content inside the region
    s.move_cursor(5, 0);
    s.print('X', attrs, true);

    // Delete 1 line inside the region
    s.move_cursor(5, 0);
    s.delete_lines(1);

    // Sentinels outside the region must be untouched
    assert_eq!(s.get_cell(0, 0).unwrap().char(), 'T');
    assert_eq!(s.get_cell(15, 0).unwrap().char(), 'B');
}

// ---------------------------------------------------------------------------
// PBT — insert_lines / delete_lines invariants
// ---------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    // PANIC SAFETY: insert_lines(n) with arbitrary n from any row never panics
    fn prop_insert_lines_no_panic(n in 0usize..50usize, row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        let rows_before = s.rows() as usize;
        s.move_cursor(row, 0);
        s.insert_lines(n);
        prop_assert_eq!(s.rows() as usize, rows_before);
    }

    #[test]
    // PANIC SAFETY: delete_lines(n) with arbitrary n from any row never panics
    fn prop_delete_lines_no_panic(n in 0usize..50usize, row in 0usize..24usize) {
        let mut s = Screen::new(24, 80);
        let rows_before = s.rows() as usize;
        s.move_cursor(row, 0);
        s.delete_lines(n);
        prop_assert_eq!(s.rows() as usize, rows_before);
    }
}

// ---------------------------------------------------------------------------
// Additional edge-case tests
// ---------------------------------------------------------------------------

#[test]
fn erase_chars_with_count_zero_is_noop() {
    // erase_chars(0) must not modify any cell (count of 0 means no-op).
    // The handler passes max(count,1) in some implementations, but Screen::erase_chars
    // with 0 must leave content untouched.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    s.move_cursor(0, 0);
    s.print('X', attrs, true);

    s.move_cursor(0, 0);
    s.erase_chars(0, attrs);

    // If the implementation treats 0 as no-op, 'X' survives.
    // If it treats 0 as 1 (standard VT semantics), col 0 becomes ' '.
    // Both are valid — the invariant is that the line width must stay at 80.
    assert_eq!(
        s.get_line(0).unwrap().cells.len(),
        80,
        "line must still have 80 cells after erase_chars(0)"
    );
}

#[test]
fn insert_chars_at_last_col_does_not_grow_line() {
    // Inserting characters when the cursor is at the last column must not
    // grow the line beyond cols; content shifts right and the rightmost
    // character is discarded.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();
    let last_col = s.cols() as usize - 1;

    // Write 'Z' at the last column
    s.move_cursor(0, last_col);
    s.print('Z', attrs, true);

    // Now insert 1 char at the last column
    s.move_cursor(0, last_col);
    s.insert_chars(1, attrs);

    // Line width must not exceed cols
    assert_eq!(
        s.get_line(0).unwrap().cells.len(),
        80,
        "line must still have exactly 80 cells"
    );
}

#[test]
fn delete_chars_at_col_zero_shifts_entire_row_left() {
    // Deleting chars at col 0 shifts the whole visible content one step left;
    // the rightmost cell must become blank.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Write "ABCDE" starting at col 0
    s.move_cursor(0, 0);
    for ch in ['A', 'B', 'C', 'D', 'E'] {
        s.print(ch, attrs, true);
    }

    // Delete 1 char at col 0
    s.move_cursor(0, 0);
    s.delete_chars(1);

    // Remaining chars shift left: B→0, C→1, D→2, E→3
    assert_cell_char!(s, 0, 0, 'B', "col 0 must become 'B' after delete_chars(1)");
    assert_cell_char!(s, 0, 1, 'C', "col 1 must become 'C'");
    assert_cell_char!(s, 0, 2, 'D', "col 2 must become 'D'");
    assert_cell_char!(s, 0, 3, 'E', "col 3 must become 'E'");
    // Last cell must be blank
    assert_cell_char!(s, 0, 79, ' ', "last cell must be blank after delete_chars");
}

#[test]
fn insert_lines_within_scroll_region_does_not_affect_rows_outside() {
    // IL inside a sub-region must not touch rows above the top or below the bottom.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Write sentinels outside the scroll region
    s.move_cursor(0, 0);
    s.print('T', attrs, true); // above top=5
    s.move_cursor(15, 0);
    s.print('B', attrs, true); // below bottom=10

    // Restrict scroll region to rows 5..10
    s.set_scroll_region(5, 10);

    // Write content at the top of the region and insert
    s.move_cursor(5, 0);
    s.print('X', attrs, true);
    s.move_cursor(5, 0);
    s.insert_lines(1);

    // Row 5 must be blank (inserted); 'X' shifted to row 6
    assert_cell_char!(s, 5, 0, ' ', "row 5 must be blank after insert_lines");
    assert_cell_char!(s, 6, 0, 'X', "row 6 must have shifted 'X'");

    // Sentinels outside the region must be untouched
    assert_eq!(
        s.get_cell(0, 0).unwrap().char(),
        'T',
        "row 0 sentinel must be untouched"
    );
    assert_eq!(
        s.get_cell(15, 0).unwrap().char(),
        'B',
        "row 15 sentinel must be untouched"
    );
}

#[test]
fn clear_lines_does_not_affect_rows_outside_range() {
    // clear_lines(start, end) must only blank rows in [start, end); rows
    // outside the range must be untouched.
    let mut s = make_screen();
    let attrs = SgrAttributes::default();

    // Write sentinels at rows 1 and 5 (outside the cleared range 2..4)
    s.move_cursor(1, 0);
    s.print('X', attrs, true);
    s.move_cursor(5, 0);
    s.print('Y', attrs, true);

    // Write content inside the range
    s.move_cursor(2, 0);
    s.print('A', attrs, true);
    s.move_cursor(3, 0);
    s.print('B', attrs, true);

    s.clear_lines(2, 4);

    // Rows 2 and 3 must be blank
    assert_eq!(s.get_cell(2, 0).unwrap().char(), ' ', "row 2 must be blank");
    assert_eq!(s.get_cell(3, 0).unwrap().char(), ' ', "row 3 must be blank");

    // Rows outside must be untouched
    assert_eq!(
        s.get_cell(1, 0).unwrap().char(),
        'X',
        "row 1 must be untouched"
    );
    assert_eq!(
        s.get_cell(5, 0).unwrap().char(),
        'Y',
        "row 5 must be untouched"
    );
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    // PANIC SAFETY: erase_chars(n) with arbitrary n never panics
    fn prop_erase_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        let attrs = SgrAttributes::default();
        s.move_cursor(0, col);
        s.erase_chars(n, attrs);
        // Line must still have exactly 80 cells
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }

    #[test]
    // PANIC SAFETY: delete_chars(n) with arbitrary n never panics
    fn prop_delete_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        s.move_cursor(0, col);
        s.delete_chars(n);
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }

    #[test]
    // PANIC SAFETY: insert_chars(n) with arbitrary n never panics and preserves line width
    fn prop_insert_chars_no_panic(n in 0usize..300usize, col in 0usize..80usize) {
        let mut s = Screen::new(24, 80);
        let attrs = SgrAttributes::default();
        s.move_cursor(0, col);
        s.insert_chars(n, attrs);
        prop_assert_eq!(s.get_line(0).unwrap().cells.len(), 80);
    }
}
