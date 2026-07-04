// Tests for DECIC (Insert Column, CSI Ps ' }) and DECDC (Delete Column, CSI Ps ' ~).
//
// Both sequences use a single-quote intermediate byte (0x27) to distinguish
// them from other VT sequences.  They operate on every row within the current
// scroll region.

fn write_row_id(term: &mut crate::TerminalCore, row: usize, text: &str) {
    term.screen.move_cursor(row, 0);
    term.advance(text.as_bytes());
}

fn col_chars(term: &crate::TerminalCore, row: usize, n: usize) -> String {
    (0..n)
        .map(|c| term.screen.get_line(row).unwrap().cells[c].char())
        .collect()
}

// ── DECIC (Insert Column) ─────────────────────────────────────────────────────

#[test]
fn test_decic_inserts_blank_column_at_cursor() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row_id(&mut term, 0, "ABCDEFGHIJ");
    term.screen.move_cursor(0, 3); // cursor at col 3
    term.advance(b"\x1b[1'}"); // DECIC 1 — insert 1 column at col 3
    let got = col_chars(&term, 0, 10);
    // col 3 becomes blank; content shifts right; last char is lost
    assert_eq!(&got[..3], "ABC", "DECIC: cols left of cursor unchanged");
    assert_eq!(&got[3..4], " ", "DECIC: inserted blank column");
    assert_eq!(&got[4..], "DEFGHI", "DECIC: content shifts right");
}

#[test]
fn test_decic_default_inserts_one_column() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row_id(&mut term, 0, "ABCDEFGHIJ");
    term.screen.move_cursor(0, 0);
    term.advance(b"\x1b['}"); // DECIC default (1)
    let got = col_chars(&term, 0, 10);
    assert_eq!(&got[..1], " ", "DECIC default: first col is blank");
    assert_eq!(&got[1..], "ABCDEFGHI");
}

#[test]
fn test_decic_applies_to_all_rows_in_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        write_row_id(&mut term, r, "ABCDEFGHIJ");
    }
    // Set scroll region rows 2-5 (1-indexed CSI 3;6 r → 0-indexed top=2, bottom=6)
    term.advance(b"\x1b[3;6r");
    term.screen.move_cursor(2, 2); // cursor at col 2 in scroll region
    term.advance(b"\x1b[1'}"); // DECIC 1
                               // Rows outside scroll region must be unchanged
    assert_eq!(col_chars(&term, 0, 10), "ABCDEFGHIJ");
    assert_eq!(col_chars(&term, 6, 10), "ABCDEFGHIJ");
    // Rows inside scroll region: blank inserted at col 2
    let in_region = col_chars(&term, 2, 10);
    assert_eq!(&in_region[..2], "AB");
    assert_eq!(&in_region[2..3], " ");
    assert_eq!(&in_region[3..], "CDEFGHI");
}

#[test]
fn test_decic_large_n_clears_right_of_cursor() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row_id(&mut term, 0, "ABCDEFGHIJ");
    term.screen.move_cursor(0, 3);
    term.advance(b"\x1b[99'}"); // DECIC 99 — way more than cols available
    let got = col_chars(&term, 0, 10);
    assert_eq!(&got[..3], "ABC", "DECIC large: left of cursor unchanged");
    assert_eq!(&got[3..], "       ", "DECIC large: right of cursor blanked");
}

// ── DECDC (Delete Column) ─────────────────────────────────────────────────────

#[test]
fn test_decdc_deletes_column_at_cursor() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row_id(&mut term, 0, "ABCDEFGHIJ");
    term.screen.move_cursor(0, 3); // cursor at col 3
    term.advance(b"\x1b[1'~"); // DECDC 1 — delete column at col 3
    let got = col_chars(&term, 0, 10);
    assert_eq!(&got[..3], "ABC", "DECDC: cols left of cursor unchanged");
    assert_eq!(&got[3..9], "EFGHIJ", "DECDC: content shifts left");
    assert_eq!(&got[9..], " ", "DECDC: blank fills right end");
}

#[test]
fn test_decdc_default_deletes_one_column() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row_id(&mut term, 0, "ABCDEFGHIJ");
    term.screen.move_cursor(0, 0);
    term.advance(b"\x1b['~"); // DECDC default (1)
    let got = col_chars(&term, 0, 10);
    assert_eq!(&got[..9], "BCDEFGHIJ");
    assert_eq!(&got[9..], " ");
}

#[test]
fn test_decdc_applies_to_all_rows_in_scroll_region() {
    let mut term = crate::TerminalCore::new(10, 10);
    for r in 0..10 {
        write_row_id(&mut term, r, "ABCDEFGHIJ");
    }
    term.advance(b"\x1b[3;6r");
    term.screen.move_cursor(2, 2);
    term.advance(b"\x1b[1'~"); // DECDC 1
    assert_eq!(col_chars(&term, 0, 10), "ABCDEFGHIJ");
    assert_eq!(col_chars(&term, 6, 10), "ABCDEFGHIJ");
    let in_region = col_chars(&term, 3, 10);
    assert_eq!(&in_region[..2], "AB");
    assert_eq!(&in_region[2..9], "DEFGHIJ");
}

#[test]
fn test_decdc_large_n_clears_right_of_cursor() {
    let mut term = crate::TerminalCore::new(5, 10);
    write_row_id(&mut term, 0, "ABCDEFGHIJ");
    term.screen.move_cursor(0, 3);
    term.advance(b"\x1b[99'~"); // DECDC 99
    let got = col_chars(&term, 0, 10);
    assert_eq!(&got[..3], "ABC", "DECDC large: left of cursor unchanged");
    assert_eq!(&got[3..], "       ", "DECDC large: right blanked");
}
