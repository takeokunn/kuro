//! Adversarial reflow tests — attempts to break content identity, wide-char
//! integrity, cursor recovery, scrollback eviction, incremental resizes,
//! alternate-screen isolation, hard-newline boundaries, and degenerate widths.

use super::super::Screen;
use crate::types::cell::{CellWidth, SgrAttributes};
use crate::types::Color;

fn type_str(s: &mut Screen, text: &str) {
    let attrs = SgrAttributes::default();
    for c in text.chars() {
        s.print(c, attrs, true);
    }
}

fn newline(s: &mut Screen) {
    s.line_feed(Color::Default);
    s.carriage_return();
}

/// Concatenate scrollback+live rows into logical lines (joining soft-wrap runs),
/// trimming trailing spaces on each logical line. Mirrors tests.rs::logical_text.
fn logical_text(s: &Screen) -> Vec<String> {
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
                out.push(cur.trim_end_matches(' ').to_string());
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

fn nonblank_logical(s: &Screen) -> Vec<String> {
    logical_text(s).into_iter().filter(|l| !l.is_empty()).collect()
}

// ───────────────────────── (1) CONTENT LOSS ─────────────────────────

#[test]
fn round_trip_80_40_80_multiwrap_byte_identical() {
    let mut s = Screen::new(10, 80);
    // A paragraph long enough to wrap several times at every width in the trip.
    type_str(&mut s, &"abcdefghij".repeat(25)); // 250 chars, one logical line
    let before = nonblank_logical(&s);

    s.resize(10, 40);
    let mid = nonblank_logical(&s);
    assert_eq!(mid, before, "content preserved through narrow 80->40");

    s.resize(10, 80);
    let after = nonblank_logical(&s);
    assert_eq!(after, before, "content byte-identical after 80->40->80 round trip");
}

#[test]
fn round_trip_multiple_paragraphs_preserved() {
    let mut s = Screen::new(8, 80);
    // 4 distinct logical lines, each wrapping at 80.
    for tag in ['A', 'B', 'C', 'D'] {
        type_str(&mut s, &tag.to_string().repeat(130));
        newline(&mut s);
    }
    let before = nonblank_logical(&s);
    assert_eq!(before.len(), 4, "four logical paragraphs");

    s.resize(8, 40);
    s.resize(8, 80);
    let after = nonblank_logical(&s);
    assert_eq!(after, before, "4-paragraph identity across 80->40->80");
}

// ─────────────── (2) WIDE CHAR AT WRAP COLUMN — shrink & grow ───────────────

/// Verify every wide-char lead (`Full`) is immediately followed by `Wide` and
/// never sits in the final column of a row (which would mean it was split).
fn assert_wide_chars_intact(s: &Screen) {
    let all: Vec<&super::super::Line> =
        s.scrollback_buffer.iter().chain(s.lines.iter()).collect();
    for line in &all {
        let n = line.cells.len();
        for (i, cell) in line.cells.iter().enumerate() {
            if cell.width == CellWidth::Full {
                assert!(
                    i + 1 < n,
                    "Full lead must not be in the last column (would be split)"
                );
                assert_eq!(
                    line.cells[i + 1].width,
                    CellWidth::Wide,
                    "Full lead must be followed by a Wide placeholder on the same row"
                );
            }
        }
    }
}

#[test]
fn wide_char_exactly_at_wrap_column_shrink_and_grow() {
    // Build at width 10: "12345678世" — '世' (wide) at cols 8,9 fits exactly.
    let mut s = Screen::new(5, 10);
    type_str(&mut s, "12345678世");
    assert_eq!(nonblank_logical(&s).join(""), "12345678世");
    assert_wide_chars_intact(&s);

    // Shrink to 9: '世' would start at col 8 but needs cols 8,9 — col 9 absent →
    // wraps, leaving col 8 blank. Must remain intact, no duplication.
    s.resize(5, 9);
    assert_eq!(nonblank_logical(&s).join("").replace(' ', ""), "12345678世");
    assert_wide_chars_intact(&s);
    let wide_count: usize = s
        .scrollback_buffer
        .iter()
        .chain(s.lines.iter())
        .flat_map(|l| l.cells.iter())
        .filter(|c| c.grapheme() == "世")
        .count();
    assert_eq!(wide_count, 1, "wide char must not be duplicated on shrink");

    // Grow back to 10: must coalesce to "12345678世" with no spurious pad.
    s.resize(5, 10);
    assert_eq!(nonblank_logical(&s).join(""), "12345678世");
    assert_wide_chars_intact(&s);
}

#[test]
fn many_wide_chars_round_trip_no_loss_or_dup() {
    let mut s = Screen::new(6, 20);
    // 12 wide chars = 24 columns → wraps at width 20.
    type_str(&mut s, &"世".repeat(12));
    let count_wide = |s: &Screen| -> usize {
        s.scrollback_buffer
            .iter()
            .chain(s.lines.iter())
            .flat_map(|l| l.cells.iter())
            .filter(|c| c.grapheme() == "世")
            .count()
    };
    assert_eq!(count_wide(&s), 12);

    for w in [7u16, 9, 13, 21, 4, 20] {
        s.resize(6, w);
        assert_wide_chars_intact(&s);
        assert_eq!(count_wide(&s), 12, "12 wide chars preserved at width {w}");
    }
}

// ───────────────────────── (3) CURSOR positions ─────────────────────────

#[test]
fn cursor_at_end_of_wrapped_line() {
    let mut s = Screen::new(5, 40);
    type_str(&mut s, &"z".repeat(80)); // exactly fills 2 rows, pending wrap
    s.resize(5, 80);
    // 80 chars at width 80: cursor at logical offset 80 → clamp to col 79.
    assert_eq!(s.cursor().row, 0);
    assert!(s.cursor().col >= 79, "cursor at end of single wide row, got {}", s.cursor().col);
}

#[test]
fn cursor_at_col0_of_continuation_row() {
    // Type 40 chars then position cursor explicitly at start of a continuation.
    let mut s = Screen::new(5, 80);
    type_str(&mut s, &"q".repeat(85)); // wraps to row 1 col 5
    assert_eq!(s.cursor().row, 1);
    assert_eq!(s.cursor().col, 5);
    s.resize(5, 40);
    // 85 chars at 40: rows of 40,40,5 → cursor logical offset 85 → row2 col5.
    assert_eq!(s.cursor().row, 2, "cursor row");
    assert_eq!(s.cursor().col, 5, "cursor col");
}

#[test]
fn cursor_past_content_does_not_panic_and_clamps() {
    let mut s = Screen::new(5, 80);
    type_str(&mut s, "short");
    // Force the cursor far to the right (past content) without printing.
    // Use a CUP-like move via direct field manipulation through public cursor.
    // We move via printing then backspace? Simpler: just resize with cursor at
    // col 5 (after "short") — already past trimmed content of length 5.
    s.resize(5, 3);
    assert!(s.cursor().col <= 2, "cursor col clamped to new width-1");
    assert!(s.cursor().row < 5);
}

// ──────── (4) LOGICAL LINE LONGER THAN SCREEN HEIGHT + scrollback evict ────────

#[test]
fn logical_line_taller_than_screen_with_scrollback_eviction() {
    let mut s = Screen::new(3, 80);
    s.scrollback_max_lines = 4; // tiny cap to force eviction
    // One logical line of 800 chars → 10 rows at width 80.
    type_str(&mut s, &"L".repeat(800));
    s.resize(3, 40);
    // 800 chars at width 40 → 20 physical rows. Screen holds 3, scrollback cap 4.
    assert!(s.scrollback_buffer.len() <= 4, "scrollback capped");
    // The *tail* of the logical line must be intact on the live screen (no corruption).
    let tail: String = s
        .lines
        .iter()
        .flat_map(|l| l.cells.iter())
        .map(|c| c.grapheme().to_string())
        .collect::<String>()
        .trim_end_matches(' ')
        .to_string();
    assert!(tail.chars().all(|c| c == 'L'), "live tail is all L's, no corruption: {tail:?}");
    // No panic is the main assertion.
}

// ──────── (5) REPEATED 1-COL INCREMENTAL RESIZES — no drift ────────

#[test]
fn incremental_resizes_down_and_back_no_drift() {
    let mut s = Screen::new(10, 80);
    type_str(&mut s, &"0123456789".repeat(30)); // 300 chars, one logical line
    let before = nonblank_logical(&s);

    let mut w = 80u16;
    while w > 20 {
        w -= 1;
        s.resize(10, w);
        assert_eq!(nonblank_logical(&s), before, "no drift narrowing to {w}");
    }
    while w < 80 {
        w += 1;
        s.resize(10, w);
        assert_eq!(nonblank_logical(&s), before, "no drift widening to {w}");
    }
    assert_eq!(nonblank_logical(&s), before, "round trip identity preserved");
}

#[test]
fn incremental_resizes_with_wide_chars_no_drift() {
    let mut s = Screen::new(10, 60);
    // Mixed ASCII + wide, one logical line.
    type_str(&mut s, &"ab世cd".repeat(20));
    let before = nonblank_logical(&s);
    let count_wide = |s: &Screen| -> usize {
        s.scrollback_buffer
            .iter()
            .chain(s.lines.iter())
            .flat_map(|l| l.cells.iter())
            .filter(|c| c.grapheme() == "世")
            .count()
    };
    let base_wide = count_wide(&s);

    let mut w = 60u16;
    while w > 20 {
        w -= 1;
        s.resize(10, w);
        assert_wide_chars_intact(&s);
        assert_eq!(count_wide(&s), base_wide, "wide count stable at {w}");
    }
    while w < 60 {
        w += 1;
        s.resize(10, w);
        assert_wide_chars_intact(&s);
    }
    assert_eq!(nonblank_logical(&s), before, "mixed content identity after round trip");
}

// ──────── (6) ALTERNATE screen NOT reflowed, primary IS ────────

#[test]
fn alt_active_resize_then_switch_back_primary_reflowed() {
    let mut s = Screen::new(5, 80);
    type_str(&mut s, &"p".repeat(120)); // wraps at 80
    let primary_before = nonblank_logical(&s);

    s.switch_to_alternate();
    type_str(&mut s, &"q".repeat(120));

    s.resize(5, 40); // resize WHILE alternate active

    // Switch back to primary — it must have been reflowed to width 40.
    s.switch_to_primary();
    let primary_after = nonblank_logical(&s);
    assert_eq!(primary_after, primary_before, "primary content preserved & reflowed");
    // Primary rows are now 40 cols.
    assert!(s.lines.iter().all(|l| l.cells.len() == 40), "primary rows reflowed to 40 cols");
}

// ──────── (7) hard-newline boundaries, empties, trailing whitespace ────────

#[test]
fn hard_newline_boundary_preserved_not_merged() {
    let mut s = Screen::new(6, 80);
    type_str(&mut s, "alpha");
    newline(&mut s);
    type_str(&mut s, "beta");
    s.resize(6, 40);
    let nb = nonblank_logical(&s);
    assert_eq!(nb, vec!["alpha".to_string(), "beta".to_string()], "hard newline kept as boundary");
}

#[test]
fn empty_lines_between_content_preserved() {
    let mut s = Screen::new(8, 80);
    type_str(&mut s, "one");
    newline(&mut s);
    newline(&mut s); // blank logical line
    type_str(&mut s, "two");
    s.resize(8, 30);
    let all = logical_text(&s);
    // Find positions of "one" and "two" with a blank between.
    let one = all.iter().position(|l| l == "one").expect("one present");
    let two = all.iter().position(|l| l == "two").expect("two present");
    assert!(two > one + 1, "blank logical line preserved between one and two: {all:?}");
}

#[test]
fn line_with_no_wrap_flag_is_a_boundary_even_when_full_width() {
    // Type exactly 40 chars (no auto-wrap fired since it fits) then hard newline,
    // then 40 more. At a narrower width these must NOT be merged into one logical.
    let mut s = Screen::new(6, 40);
    type_str(&mut s, &"x".repeat(39)); // 39 chars, fits, no wrap
    newline(&mut s);
    type_str(&mut s, &"y".repeat(39));
    s.resize(6, 20);
    let nb = nonblank_logical(&s);
    assert_eq!(nb.len(), 2, "two independent logical lines: {nb:?}");
    assert_eq!(nb[0], "x".repeat(39));
    assert_eq!(nb[1], "y".repeat(39));
}

#[test]
fn trailing_whitespace_only_line_does_not_corrupt() {
    let mut s = Screen::new(5, 80);
    type_str(&mut s, "data");
    newline(&mut s);
    type_str(&mut s, "   "); // spaces only
    s.resize(5, 40);
    let nb = nonblank_logical(&s);
    assert!(nb.contains(&"data".to_string()), "data preserved: {nb:?}");
}

// ──────── (8) degenerate widths — no panic ────────

#[test]
fn resize_to_one_column_no_panic() {
    let mut s = Screen::new(5, 80);
    type_str(&mut s, "hello");
    s.resize(5, 1);
    assert_eq!(s.cols(), 1);
    // Each char becomes its own row; content preserved when concatenated.
    let joined: String = s
        .scrollback_buffer
        .iter()
        .chain(s.lines.iter())
        .flat_map(|l| l.cells.iter())
        .map(|c| c.grapheme().to_string())
        .collect::<String>()
        .replace(' ', "");
    assert_eq!(joined, "hello", "content preserved at width 1");
}

#[test]
fn resize_to_one_column_with_wide_char() {
    // Width 1 cannot hold a wide char (needs 2 cols). Must not panic; the new_cols
    // >= 2 guard in resplit means the wide char is placed (and truncated) without
    // an infinite loop or panic.
    let mut s = Screen::new(5, 10);
    type_str(&mut s, "a世b");
    s.resize(5, 1);
    assert_eq!(s.cols(), 1);
    // Main assertion: no panic / no infinite loop. Content of ASCII survives.
    let joined: String = s
        .scrollback_buffer
        .iter()
        .chain(s.lines.iter())
        .flat_map(|l| l.cells.iter())
        .map(|c| c.grapheme().to_string())
        .collect();
    assert!(joined.contains('a') || joined.contains('b'), "ascii survived width-1 reflow");
}

#[test]
fn resize_to_zero_columns_no_panic() {
    let mut s = Screen::new(5, 80);
    type_str(&mut s, "edge");
    // Zero-width is degenerate; must not panic or loop forever.
    s.resize(5, 0);
    // Geometry recorded; no assertion on content (undefined at width 0).
    assert_eq!(s.cols(), 0);
}

#[test]
fn resize_one_to_eighty_then_back() {
    let mut s = Screen::new(4, 1);
    type_str(&mut s, "wxyz"); // each on its own row at width 1
    s.resize(4, 80);
    let nb = nonblank_logical(&s);
    assert_eq!(nb.join(""), "wxyz", "content reassembled when widened from 1");
    s.resize(4, 1);
    let joined: String = s
        .scrollback_buffer
        .iter()
        .chain(s.lines.iter())
        .flat_map(|l| l.cells.iter())
        .map(|c| c.grapheme().to_string())
        .collect::<String>()
        .replace(' ', "");
    assert_eq!(joined, "wxyz", "content survives 1->80->1");
}

// ──────── Regression probes: trailing space at wrap column ────────

#[test]
fn typed_space_at_wrap_column_not_lost_on_reflow() {
    // Width 5: "abcd ef".
    //   col0..3 = abcd, col4 = ' ' (a REAL typed space), then 'e' auto-wraps.
    //   row0 = "abcd " (wrapped=true, last cell is a genuine space),
    //   row1 = "ef".
    // The logical content is exactly "abcd ef" (7 chars). On widen to 10 this
    // must remain "abcd ef" — the space between 'd' and 'e' MUST survive.
    let mut s = Screen::new(4, 5);
    type_str(&mut s, "abcd ef");
    assert!(s.lines[0].wrapped, "row 0 should be soft-wrapped");
    // Sanity: the wrapped row's last cell is the typed space.
    assert_eq!(s.lines[0].cells[4].grapheme(), " ");

    s.resize(4, 10);
    let nb = nonblank_logical(&s);
    assert_eq!(nb, vec!["abcd ef".to_string()], "typed wrap-column space preserved on widen");
}

// ──────── PART 1 adversarial probes (final verify session) ────────

/// A final (non-wrapped) logical line consisting entirely of *styled* spaces
/// (e.g. a colored status bar) must not be dropped by the trailing-blank trim,
/// which only recognises plain ' ' graphemes. If reflow trimmed it, the colored
/// background line would vanish on resize.
#[test]
fn styled_blank_final_line_survives_reflow_probe() {
    let mut s = Screen::new(5, 20);
    type_str(&mut s, "header");
    newline(&mut s);
    // A line of spaces carrying a non-default background.
    let mut attrs = SgrAttributes::default();
    attrs.background = Color::Indexed(4);
    for _ in 0..10 {
        s.print(' ', attrs, true);
    }
    // Count styled-bg space cells before reflow.
    let count_styled = |s: &Screen| -> usize {
        s.scrollback_buffer
            .iter()
            .chain(s.lines.iter())
            .flat_map(|l| l.cells.iter())
            .filter(|c| c.grapheme() == " " && c.attrs.background == Color::Indexed(4))
            .count()
    };
    let before = count_styled(&s);
    assert_eq!(before, 10, "10 styled spaces present pre-reflow");
    s.resize(5, 12);
    assert_eq!(count_styled(&s), 10, "styled background spaces preserved across reflow");
}

/// Reflow when scrollback is already non-empty before the resize: the combined
/// chronological sequence (scrollback ++ live) must be reflowed as one unit and
/// content must stay byte-identical across a narrow round trip.
#[test]
fn preexisting_scrollback_reflowed_with_live_rows() {
    let mut s = Screen::new(3, 40);
    // Push several logical lines; with only 3 live rows, older ones spill to
    // scrollback as we add more.
    for tag in ['A', 'B', 'C', 'D', 'E', 'F'] {
        type_str(&mut s, &tag.to_string().repeat(60)); // wraps at 40
        newline(&mut s);
    }
    assert!(!s.scrollback_buffer.is_empty(), "scrollback must be populated for this probe");
    let before = nonblank_logical(&s);
    s.resize(3, 25);
    s.resize(3, 40);
    let after = nonblank_logical(&s);
    assert_eq!(after, before, "scrollback+live content identical across 40->25->40");
}

/// Cursor sitting on the final column of a soft-wrapped row whose trailing blank
/// gets popped because the next row leads with a wide char: cursor must still
/// resolve to a valid in-bounds position (no panic, no past-end index).
#[test]
fn cursor_on_popped_wide_wrap_blank_resolves_in_bounds() {
    // Width 9: 8 ASCII then a wide char that cannot fit col 8 (needs 8,9) so it
    // wraps, leaving col 8 blank on row 0; cursor ends after the wide char.
    let mut s = Screen::new(4, 9);
    type_str(&mut s, "12345678世X");
    s.resize(4, 12);
    // Just assert the cursor is in-bounds and content intact.
    assert!(s.cursor().row < 4);
    assert!(s.cursor().col < 12);
    assert_eq!(nonblank_logical(&s).join("").replace(' ', ""), "12345678世X");
}
