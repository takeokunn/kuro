//! Tests for soft-wrap reflow (rewrap) on width change.

use super::super::Screen;
use crate::types::cell::{CellWidth, SgrAttributes};

/// Print a string at the current cursor with DECAWM auto-wrap enabled.
fn type_str(s: &mut Screen, text: &str) {
    let attrs = SgrAttributes::default();
    for c in text.chars() {
        s.print(c, attrs, true);
    }
}

/// Collect the visible (non-trailing-blank) text of every primary screen row,
/// concatenating soft-wrapped runs into logical lines.  Trailing all-blank
/// rows are dropped so width changes that add blank rows don't affect equality.
fn logical_text(s: &Screen) -> Vec<String> {
    // Walk scrollback then live lines, joining wrapped runs.
    let mut out: Vec<String> = Vec::new();
    let mut cur = String::new();
    let mut active = false;

    let push_row =
        |cur: &mut String, line: &super::super::Line, active: &mut bool, out: &mut Vec<String>| {
            for cell in &line.cells {
                cur.push_str(cell.grapheme());
            }
            if line.wrapped {
                *active = true;
            } else {
                // trim trailing spaces from the logical line
                let trimmed = cur.trim_end_matches(' ').to_string();
                out.push(trimmed);
                cur.clear();
                *active = false;
            }
        };

    for line in &s.scrollback_buffer {
        push_row(&mut cur, line, &mut active, &mut out);
    }
    for line in &s.lines {
        push_row(&mut cur, line, &mut active, &mut out);
    }
    if active {
        out.push(cur.trim_end_matches(' ').to_string());
    }
    out
}

/// Join all non-blank logical lines into a single string (content identity check).
fn all_content(s: &Screen) -> String {
    logical_text(s)
        .into_iter()
        .filter(|l| !l.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn narrow_splits_logical_line_into_more_rows() {
    // A logical line of 100 'a's wrapped across 2 physical rows at width 80.
    let mut s = Screen::new(5, 80);
    type_str(&mut s, &"a".repeat(100));
    // Pre-condition: row 0 is soft-wrapped into row 1.
    assert!(
        s.lines[0].wrapped,
        "row 0 should be soft-wrapped at width 80"
    );

    s.resize(5, 40);

    // 100 chars at width 40 → 3 physical rows (40 + 40 + 20).
    // Count rows that carry content (scrollback + live).
    let content = all_content(&s);
    assert_eq!(
        content,
        "a".repeat(100),
        "content identical when concatenated"
    );

    // The first content rows must be soft-wrapped.
    // Find rows belonging to the logical line and assert >= 3.
    let total_content_rows: usize = s
        .lines
        .iter()
        .chain(s.scrollback_buffer.iter())
        .filter(|l| l.cells.iter().any(|c| c.grapheme() != " "))
        .count();
    assert!(
        total_content_rows >= 3,
        "100 chars at width 40 should occupy at least 3 physical rows, got {total_content_rows}"
    );
}

#[test]
fn widen_coalesces_into_fewer_rows() {
    // 100 'b's wrapped at width 40 → resize to 100 → fits on one row.
    let mut s = Screen::new(5, 40);
    type_str(&mut s, &"b".repeat(100));
    s.resize(5, 100);

    assert_eq!(
        all_content(&s),
        "b".repeat(100),
        "content preserved on widen"
    );

    // Exactly one physical row should carry the content now.
    let content_rows: usize = s
        .lines
        .iter()
        .chain(s.scrollback_buffer.iter())
        .filter(|l| l.cells.iter().any(|c| c.grapheme() != " "))
        .count();
    assert_eq!(
        content_rows, 1,
        "100 chars at width 100 fit on a single row"
    );
    // That row is not soft-wrapped (it is the logical end).
    let row = s
        .lines
        .iter()
        .find(|l| l.cells.iter().any(|c| c.grapheme() != " "))
        .unwrap();
    assert!(
        !row.wrapped,
        "the single full row is the logical end, not wrapped"
    );
}

#[test]
fn wide_char_not_split_at_wrap_boundary() {
    // Width 5: print 4 ASCII then a CJK wide char (width 2).  At width 5 the
    // wide char would occupy cols 4-5, but col 5 doesn't exist, so it wraps to
    // the next row, leaving col 4 blank.  After resizing to width 5 (no-op) is
    // pointless — instead build content at width 6 then narrow to 5.
    let mut s = Screen::new(4, 6);
    // "abcd" + '世' (wide).  At width 6: a b c d 世(4,5) fits exactly.
    type_str(&mut s, "abcd世");
    assert_eq!(all_content(&s), "abcd世");

    s.resize(4, 5);

    // At width 5 (cols 0..=4) 'abcd' fills cols 0..3; '世' (width 2) cannot
    // start at col 4 (would need cols 4,5 but col 5 doesn't exist) so it wraps
    // to the next physical row, leaving col 4 of the first row BLANK — exactly
    // as the printer does.  The reflowed text therefore reads "abcd 世" (note
    // the padding space): the wide char is pushed intact, never split.
    let joined = all_content(&s).replace(' ', "");
    assert_eq!(
        joined, "abcd世",
        "wide char preserved intact across wrap (padding aside)"
    );

    // The wide char must be intact: find the Full lead cell, its next cell is Wide.
    let mut found = false;
    for line in &s.lines {
        for (i, cell) in line.cells.iter().enumerate() {
            if cell.grapheme() == "世" {
                assert_eq!(cell.width, CellWidth::Full, "wide lead must be Full");
                assert_eq!(
                    line.cells[i + 1].width,
                    CellWidth::Wide,
                    "wide trailing placeholder must follow on same row"
                );
                found = true;
            }
        }
    }
    assert!(found, "wide char must be present after reflow");
}

#[test]
fn wide_char_wrap_padding_dropped_on_widen() {
    // Build content where a wide char wraps at width 5 (leaving a blank pad on
    // the soft-wrapped row), then widen to 10.  The reflowed single row must
    // read "abcd世" with NO spurious space introduced by the old pad cell.
    let mut s = Screen::new(4, 5);
    type_str(&mut s, "abcd世");
    // At width 5: row0 = "abcd " (col 4 blank, wrapped), row1 = "世".
    assert!(s.lines[0].wrapped, "wide char wrapped, row 0 soft-wrapped");

    s.resize(4, 10);
    // Now everything fits on one row with no embedded pad space.
    assert_eq!(
        all_content(&s),
        "abcd世",
        "wide-char wrap padding dropped on widen"
    );
}

#[test]
fn trailing_blanks_trimmed_on_logical_end() {
    // A short line "hi" on an 80-col screen has 78 trailing blanks.  After
    // narrowing to 40, it must still be a single 40-col row reading "hi", not
    // padded out to multiple rows of spaces.
    let mut s = Screen::new(5, 80);
    type_str(&mut s, "hi");
    s.resize(5, 40);
    assert_eq!(all_content(&s), "hi");
    // Exactly one content row.
    let content_rows: usize = s
        .lines
        .iter()
        .filter(|l| l.cells.iter().any(|c| c.grapheme() != " "))
        .count();
    assert_eq!(content_rows, 1, "short line must not be padded across rows");
}

#[test]
fn cursor_stays_on_same_logical_char_after_narrow() {
    // Type 50 chars at width 80 (one logical line, not wrapped: 50 < 80).
    // Cursor ends at col 50, row 0.  Narrow to 40: char index 50 lands on the
    // 2nd physical row at col 10.
    let mut s = Screen::new(5, 80);
    type_str(&mut s, &"x".repeat(50));
    assert_eq!(s.cursor().row, 0);
    assert_eq!(s.cursor().col, 50);

    s.resize(5, 40);
    // 50 chars at width 40 → row 0 = cols 0..39, row 1 = cols 0..9, cursor at
    // logical offset 50 → row 1, col 10.
    assert_eq!(s.cursor().row, 1, "cursor row after narrow");
    assert_eq!(s.cursor().col, 10, "cursor col after narrow");
}

#[test]
fn cursor_stays_on_same_logical_char_after_widen() {
    // 100 chars at width 40 → wrapped across 3 rows, cursor at offset 100.
    let mut s = Screen::new(5, 40);
    type_str(&mut s, &"y".repeat(100));
    s.resize(5, 100);
    // 100 chars at width 100 → all on row 0, cursor at offset 100 → clamped to
    // col 99 (last column) since pending wrap.
    assert_eq!(s.cursor().row, 0, "cursor row after widen");
    assert!(s.cursor().col >= 99, "cursor near end of single wide row");
}

#[test]
fn alternate_screen_not_reflowed() {
    // Fill primary with a wrapped logical line, switch to alternate, write
    // alt content, resize.  The alternate buffer must NOT reflow (apps redraw).
    let mut s = Screen::new(5, 80);
    type_str(&mut s, &"p".repeat(100));
    s.switch_to_alternate();
    // Write a marker that would wrap if reflowed.
    type_str(&mut s, &"q".repeat(100));
    // The alternate row 0 is soft-wrapped at width 80.
    assert!(
        s.alternate_screen.as_ref().unwrap().lines[0].wrapped,
        "alt row 0 wrapped at width 80"
    );

    s.resize(5, 40);

    // Alternate screen: each row simply truncated/padded to 40, NOT rewrapped.
    // The alt buffer keeps exactly 5 rows of 40 cols; row 0 still holds the
    // first 40 'q's and is no longer marked wrapped (resize clears it).
    let alt = s.alternate_screen.as_ref().unwrap();
    assert_eq!(alt.lines.len(), 5, "alt keeps row count");
    assert_eq!(alt.lines[0].cells.len(), 40, "alt row truncated to 40 cols");
    // Distinguishing check: typing 100 q's at width 80 auto-wrapped into
    //   alt row 0 = 80 q's (wrapped), alt row 1 = 20 q's.
    // A *reflow* to width 40 would redistribute into 40 + 40 + 20.  A plain
    // per-row resize (correct for the alternate screen) just truncates each row
    // independently → row 0 keeps its first 40 q's, row 1 keeps exactly its
    // original 20 q's (NOT 40).  Counting row 1's q's proves no reflow ran.
    let row0_qs = alt.lines[0]
        .cells
        .iter()
        .filter(|c| c.grapheme() == "q")
        .count();
    let row1_qs = alt.lines[1]
        .cells
        .iter()
        .filter(|c| c.grapheme() == "q")
        .count();
    assert_eq!(row0_qs, 40, "alt row 0 truncated, not rewrapped");
    assert_eq!(
        row1_qs, 20,
        "alt row 1 keeps its original 20 q's — reflow would have refilled it to 40"
    );
    // And alt row 0 is no longer flagged wrapped (per-row resize clears it).
    assert!(
        !alt.lines[0].wrapped,
        "per-row resize clears the soft-wrap flag"
    );
}

#[test]
fn scrollback_is_reflowed() {
    // Produce scrollback by scrolling: small screen, type many wrapped lines.
    let mut s = Screen::new(3, 80);
    // Three logical lines each 100 chars → each wraps to 2 rows = 6 rows; with
    // a 3-row screen, older rows spill into scrollback.
    type_str(&mut s, &"A".repeat(100));
    s.line_feed(crate::types::Color::Default);
    s.carriage_return();
    type_str(&mut s, &"B".repeat(100));
    s.line_feed(crate::types::Color::Default);
    s.carriage_return();
    type_str(&mut s, &"C".repeat(100));

    let before = all_content(&s);
    assert!(
        !s.scrollback_buffer.is_empty(),
        "should have scrollback content"
    );

    s.resize(3, 40);

    // Content across scrollback + screen must be preserved & still correct.
    let after = all_content(&s);
    assert_eq!(before, after, "scrollback content preserved through reflow");
    assert!(after.contains(&"A".repeat(100)));
    assert!(after.contains(&"C".repeat(100)));
}

#[test]
fn width_unchanged_height_change_no_reflow_change() {
    // Height-only change must behave exactly like the old per-line path.
    let mut s = Screen::new(24, 80);
    type_str(&mut s, "hello world");
    let before = all_content(&s);
    s.resize(30, 80); // same width, taller
    assert_eq!(
        all_content(&s),
        before,
        "height-only change preserves content"
    );
    assert_eq!(s.cols(), 80);
    assert_eq!(s.rows(), 30);
}

#[test]
fn multiple_logical_lines_preserved_independently() {
    // Two separate (non-wrapped) logical lines must stay separate after reflow.
    let mut s = Screen::new(5, 80);
    type_str(&mut s, "first line");
    s.line_feed(crate::types::Color::Default);
    s.carriage_return();
    type_str(&mut s, "second line");
    s.resize(5, 40);
    let lines = logical_text(&s);
    let non_empty: Vec<&String> = lines.iter().filter(|l| !l.is_empty()).collect();
    assert_eq!(non_empty.len(), 2, "two distinct logical lines preserved");
    assert_eq!(non_empty[0], "first line");
    assert_eq!(non_empty[1], "second line");
}
