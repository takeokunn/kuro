
// Tests for SL (Scroll Left, CSI Ps SP @) and SR (Scroll Right, CSI Ps SP A).
//
// Both sequences use a SPACE intermediate byte (0x20) to distinguish them from
// ICH (CSI @) and CUU (CSI A).  They shift each row in the scroll region left
// or right, filling the vacated columns with blank cells.

fn write_row(term: &mut crate::TerminalCore, row: usize, text: &str) {
    term.screen.move_cursor(row, 0);
    term.advance(text.as_bytes());
}

fn row_str(term: &crate::TerminalCore, row: usize, cols: usize) -> String {
    (0..cols)
        .map(|c| term.screen.get_line(row).unwrap().cells[c].char())
        .collect()
}

// ── SL (Scroll Left) ─────────────────────────────────────────────────────────

#[test]
fn test_sl_shifts_row_left_by_n() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row(&mut term, 0, "ABCDEFGHIJ");
    term.advance(b"\x1b[3 @"); // SL 3 — shift left by 3
    let got = row_str(&term, 0, 10);
    // first 7 chars shift left; last 3 become blanks
    assert_eq!(&got[..7], "DEFGHIJ", "SL 3 must shift content left");
    assert_eq!(&got[7..], "   ", "SL 3 must fill 3 blank cols on right");
}

#[test]
fn test_sl_default_shifts_by_1() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row(&mut term, 0, "ABCDEFGHIJ");
    term.advance(b"\x1b[ @"); // SL default (1)
    let got = row_str(&term, 0, 10);
    assert_eq!(&got[..9], "BCDEFGHIJ");
    assert_eq!(&got[9..], " ");
}

#[test]
fn test_sl_large_n_clears_entire_row() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row(&mut term, 0, "ABCDEFGHIJ");
    term.advance(b"\x1b[99 @"); // SL 99 — exceeds column count
    let got = row_str(&term, 0, 10);
    assert_eq!(got, "          ", "SL >= cols must blank the entire row");
}

#[test]
fn test_sl_applies_only_to_scroll_region_rows() {
    let mut term = crate::TerminalCore::new(10, 10);
    // Fill rows 0-4 with 'A', rows 5-9 with 'B'
    for r in 0..5 {
        write_row(&mut term, r, "AAAAAAAAAA");
    }
    for r in 5..10 {
        write_row(&mut term, r, "BBBBBBBBBB");
    }
    // Restrict scroll region to rows 2-4 (1-indexed CSI 3;5 r)
    term.advance(b"\x1b[3;5r");
    term.advance(b"\x1b[2 @"); // SL 2 within region
    // Rows outside the region must be unchanged
    assert_eq!(&row_str(&term, 0, 10), "AAAAAAAAAA");
    assert_eq!(&row_str(&term, 5, 10), "BBBBBBBBBB");
    // Rows inside the region must be shifted
    let in_region = row_str(&term, 2, 10);
    assert_eq!(&in_region[..8], "AAAAAAAA");
    assert_eq!(&in_region[8..], "  ");
}

// ── SR (Scroll Right) ────────────────────────────────────────────────────────

#[test]
fn test_sr_shifts_row_right_by_n() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row(&mut term, 0, "ABCDEFGHIJ");
    term.advance(b"\x1b[3 A"); // SR 3 — shift right by 3
    let got = row_str(&term, 0, 10);
    assert_eq!(&got[..3], "   ", "SR 3 must fill 3 blank cols on left");
    assert_eq!(&got[3..], "ABCDEFG", "SR 3 must shift content right");
}

#[test]
fn test_sr_default_shifts_by_1() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row(&mut term, 0, "ABCDEFGHIJ");
    term.advance(b"\x1b[ A"); // SR default (1)
    let got = row_str(&term, 0, 10);
    assert_eq!(&got[..1], " ");
    assert_eq!(&got[1..], "ABCDEFGHI");
}

#[test]
fn test_sr_large_n_clears_entire_row() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row(&mut term, 0, "ABCDEFGHIJ");
    term.advance(b"\x1b[99 A"); // SR 99 — exceeds column count
    let got = row_str(&term, 0, 10);
    assert_eq!(got, "          ", "SR >= cols must blank the entire row");
}

#[test]
fn test_sr_applies_only_to_scroll_region_rows() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..5 {
        write_row(&mut term, r, "AAAAAAAAAA");
    }
    for r in 5..10 {
        write_row(&mut term, r, "BBBBBBBBBB");
    }
    term.advance(b"\x1b[3;5r");
    term.advance(b"\x1b[2 A"); // SR 2 within region
    assert_eq!(&row_str(&term, 0, 10), "AAAAAAAAAA");
    assert_eq!(&row_str(&term, 5, 10), "BBBBBBBBBB");
    let in_region = row_str(&term, 2, 10);
    assert_eq!(&in_region[..2], "  ");
    assert_eq!(&in_region[2..], "AAAAAAAA");
}
