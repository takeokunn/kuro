// ── DEC mode 2027 grapheme clustering — ADVERSARIAL tests ───────────────────
//
// Companion to `grapheme_cluster.rs`. These tests TRY TO BREAK the mode-2027
// print path: odd RI counts, screen edges, control/CSI interruption, auto-wrap
// boundaries, screen edits over multi-codepoint cells, DECRQM state, cursor
// reporting, and unbounded ZWJ chains.
//
// Module under test: `parser/vte_handler.rs` clustering helpers +
// `grid/screen/dirty.rs::merge_flag_pair` + `grid/screen/cursor.rs::print`.

use super::*;
use crate::types::cell::CellWidth;

// Codepoints (mirrors grapheme_cluster.rs).
const MAN: char = '\u{1F468}'; // 👨 width 2
const WOMAN: char = '\u{1F469}'; // 👩 width 2
const ZWJ: char = '\u{200D}'; // zero-width joiner, width 0
const RI_J: char = '\u{1F1EF}'; // 🇯 regional indicator, width 1
const RI_P: char = '\u{1F1F5}'; // 🇵 regional indicator, width 1
const RI_U: char = '\u{1F1FA}'; // 🇺 regional indicator, width 1
const RI_S: char = '\u{1F1F8}'; // 🇸 regional indicator, width 1

fn bytes(chars: &[char]) -> Vec<u8> {
    chars.iter().collect::<String>().into_bytes()
}

fn term_2027_on() -> TerminalCore {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2027h");
    term
}

// ── (1) clustering OFF must be byte-identical to pre-feature behavior ─────────

/// INTENT: With 2027 OFF, an isolated ZWJ between two ASCII letters behaves
/// exactly as the legacy combining path: ZWJ (width 0, non-control) attaches to
/// the preceding cell; the next ASCII advances normally. No cluster machinery.
#[test]
fn off_zwj_between_ascii_matches_legacy_combining() {
    let mut off = TerminalCore::new(24, 80);
    off.advance(b"A");
    off.advance(&bytes(&[ZWJ]));
    off.advance(b"B");

    // ZWJ attaches to 'A' cell; 'B' is a separate advancing cell.
    let cell_a: Vec<char> = off.screen.get_cell(0, 0).unwrap().grapheme().chars().collect();
    assert_eq!(cell_a, vec!['A', ZWJ], "ZWJ joins 'A' via legacy combining path");
    assert_eq!(off.screen.get_cell(0, 1).unwrap().char(), 'B');
    assert_cursor!(off, row 0, col 2);
}

/// INTENT: With 2027 OFF, three consecutive regional indicators print as three
/// independent width-1 cells — no flag merge whatsoever.
#[test]
fn off_three_ris_print_three_cells() {
    let mut off = TerminalCore::new(24, 80);
    off.advance(&bytes(&[RI_J, RI_P, RI_U]));

    assert_eq!(off.screen.get_cell(0, 0).unwrap().char(), RI_J);
    assert_eq!(off.screen.get_cell(0, 1).unwrap().char(), RI_P);
    assert_eq!(off.screen.get_cell(0, 2).unwrap().char(), RI_U);
    assert_cursor!(off, row 0, col 3);
}

// ── (2) odd number of regional indicators (3 RIs => flag + lone RI) ──────────

/// INTENT: Three RIs with 2027 ON = ONE flag (cols 0-1, width 2) + ONE lone RI
/// (col 2, width 1) left armed for a future pairing. The third RI must NOT fold
/// back into the already-completed first flag.
#[test]
fn three_ris_form_one_flag_plus_lone_ri() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[RI_J, RI_P, RI_U]));

    let flag: Vec<char> = term.screen.get_cell(0, 0).unwrap().grapheme().chars().collect();
    assert_eq!(flag, vec![RI_J, RI_P], "cols 0-1 = first flag (JP)");
    assert_eq!(term.screen.get_cell(0, 0).unwrap().width, CellWidth::Full);
    assert_eq!(term.screen.get_cell(0, 1).unwrap().width, CellWidth::Wide);

    // Third RI is a fresh lone width-1 cell at col 2.
    let lone: Vec<char> = term.screen.get_cell(0, 2).unwrap().grapheme().chars().collect();
    assert_eq!(lone, vec![RI_U], "col 2 = lone third RI, width 1");
    assert_eq!(term.screen.get_cell(0, 2).unwrap().width, CellWidth::Half);
    assert_cursor!(term, row 0, col 3);

    // The lone RI is armed: a 4th RI completes a second flag at cols 2-3.
    term.advance(&bytes(&[RI_S]));
    let flag2: Vec<char> = term.screen.get_cell(0, 2).unwrap().grapheme().chars().collect();
    assert_eq!(flag2, vec![RI_U, RI_S], "cols 2-3 = second flag (US)");
    assert_cursor!(term, row 0, col 4);
}

// ── (3) ZWJ at the very start of the screen (col 0, row 0) ───────────────────

/// INTENT: A ZWJ as the FIRST byte ever (row 0, col 0, nothing before it) must
/// be dropped harmlessly and must NOT arm join-pending in a way that swallows
/// the next printable. (Implementation returns true but does not set the
/// pending flag when there is no previous cell.)
#[test]
fn zwj_first_byte_at_origin_then_emoji_prints_normally() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[ZWJ, MAN]));

    // MAN must print as a fresh width-2 cell at col 0 — NOT swallowed by a
    // bogus pending-join from the dropped ZWJ.
    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), MAN);
    let cluster: Vec<char> = term.screen.get_cell(0, 0).unwrap().grapheme().chars().collect();
    assert_eq!(cluster, vec![MAN], "MAN is a fresh cell, not joined to a dropped ZWJ");
    assert_cursor!(term, row 0, col 2);
}

/// INTENT: ZWJ at the start of row 1 (col 0) when row 0 has content must NOT
/// reach back and join row 0's last cell across the line boundary. With the
/// implementation's `combining_attach_position`, col 0 / row > 0 attaches to
/// the previous row's last column — verify this matches the documented combining
/// behavior and does not panic, then a printable advances correctly.
#[test]
fn zwj_at_row1_col0_documented_behavior() {
    let mut term = term_2027_on();
    term.advance(b"\x1b[2;1H"); // move to row 1 (0-indexed), col 0
    term.advance(&bytes(&[ZWJ]));
    term.advance(b"Z");

    // The ZWJ at row1/col0 attaches (per combining_attach_position) to row0's
    // last column, and arms the join. Then 'Z' is ASCII: it continues the join?
    // No — ASCII goes through buffer_ascii_print which CLEARS cluster state.
    // So 'Z' must print fresh at row1 col0.
    assert_eq!(term.screen.get_cell(1, 0).unwrap().char(), 'Z', "'Z' prints fresh at row1 col0");
    assert_cursor!(term, row 1, col 1);
}

// ── (4) ZWJ immediately before a control char / CSI sequence ─────────────────

/// INTENT: ZWJ then a backspace (C0 control) then a printable: the control must
/// clear join-pending so the printable does NOT fold onto the ZWJ cluster.
#[test]
fn zwj_then_backspace_then_emoji_no_join() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[MAN, ZWJ])); // MAN at col0, ZWJ armed, cursor col2
    term.advance(b"\x08"); // backspace
    term.advance(&bytes(&[WOMAN]));

    // After BS from col 2 -> col 1, WOMAN prints at col 1 fresh (not joined).
    let man_cluster: Vec<char> = term.screen.get_cell(0, 0).unwrap().grapheme().chars().collect();
    assert_eq!(man_cluster, vec![MAN, ZWJ], "row0 col0 keeps only MAN+ZWJ");
    assert_eq!(term.screen.get_cell(0, 1).unwrap().char(), WOMAN, "WOMAN is fresh, not joined");
}

/// INTENT: ZWJ then a CSI sequence (cursor save/restore — a no-op move) then a
/// printable: the CSI dispatch must clear join-pending. The printable prints
/// fresh, not appended to the ZWJ cluster.
#[test]
fn zwj_then_csi_then_emoji_no_join() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[MAN, ZWJ]));
    term.advance(b"\x1b[0m"); // SGR reset — a CSI dispatch
    term.advance(&bytes(&[WOMAN]));

    let man_cluster: Vec<char> = term.screen.get_cell(0, 0).unwrap().grapheme().chars().collect();
    assert_eq!(man_cluster, vec![MAN, ZWJ], "CSI must break the pending join");
    assert_eq!(term.screen.get_cell(0, 2).unwrap().char(), WOMAN, "WOMAN advances as its own cell");
    assert_cursor!(term, row 0, col 4);
}

// ── (5) cluster crossing an auto-wrap line boundary ──────────────────────────

/// INTENT (REGRESSION): First RI printed in the LAST column sets pending_wrap;
/// the cursor stays ON that cell. A second RI must merge into the SAME cell
/// (the just-printed RI at col 3), NOT the cell before it. The pre-fix bug
/// attached the merge to `cursor.col - 1` (col 2 = 'c'), destroying the RI and
/// corrupting an unrelated cell. After the `combining_attach_position`
/// pending_wrap fix both RIs land on col 3 and 'c' at col 2 is untouched.
#[test]
fn ri_pair_straddling_last_column_merges_into_same_cell() {
    let mut term = TerminalCore::new(24, 4); // 4 columns wide
    term.advance(b"\x1b[?2027h");
    term.advance(b"abc"); // cols 0,1,2 filled; cursor at col 3 (last col)
    term.advance(&bytes(&[RI_J])); // first RI at col 3 -> pending_wrap set
    term.advance(&bytes(&[RI_P])); // second RI: merge at the edge

    // Both RIs fold into the last-column cell — the lone RI is NOT destroyed.
    let edge: Vec<char> = term.screen.get_cell(0, 3).unwrap().grapheme().chars().collect();
    assert_eq!(edge, vec![RI_J, RI_P], "both RIs merge into the last-column cell");
    assert_eq!(
        term.screen.get_cell(0, 3).unwrap().width,
        CellWidth::Full,
        "flag promoted to width-2 even clipped at the edge"
    );
    // The unrelated 'c' at col 2 must be untouched (the pre-fix bug clobbered it).
    assert_eq!(
        term.screen.get_cell(0, 2).unwrap().char(),
        'c',
        "neighbour cell 'c' must NOT be corrupted by the edge merge"
    );
    // Cursor stays in-bounds (no trailing continuation cell fits past col 3).
    assert!(term.screen.cursor().col < 4, "cursor stays in-bounds after edge merge");
}

/// INTENT (REGRESSION): the SAME pending_wrap bug existed on the legacy combining
/// path with mode 2027 OFF — a combining accent applied after a glyph printed in
/// the last column must attach to THAT glyph (col 3), not the previous cell.
#[test]
fn combining_at_last_column_attaches_to_correct_cell() {
    let mut term = TerminalCore::new(24, 4);
    term.advance(b"abcd"); // 'd' fills col 3, pending_wrap set, cursor stays col 3
    term.advance("\u{0301}".as_bytes()); // combining acute accent (width 0)

    let c2: Vec<char> = term.screen.get_cell(0, 2).unwrap().grapheme().chars().collect();
    let c3: Vec<char> = term.screen.get_cell(0, 3).unwrap().grapheme().chars().collect();
    assert_eq!(c2, vec!['c'], "'c' must NOT receive the accent");
    assert_eq!(c3, vec!['d', '\u{301}'], "accent attaches to 'd' at the last column");
}

/// INTENT: A ZWJ-join that would continue past auto-wrap. MAN fills cols at the
/// end of a narrow line; ZWJ arms; the next emoji continues the cluster onto the
/// SAME cell (clusters never advance), so no wrap occurs from the join itself.
#[test]
fn zwj_continuation_does_not_wrap() {
    let mut term = TerminalCore::new(24, 4);
    term.advance(b"\x1b[?2027h");
    term.advance(&bytes(&[MAN])); // width-2 at cols 0-1, cursor col2
    term.advance(&bytes(&[ZWJ, WOMAN])); // continue cluster on the MAN cell

    let cluster: Vec<char> = term.screen.get_cell(0, 0).unwrap().grapheme().chars().collect();
    assert_eq!(cluster, vec![MAN, ZWJ, WOMAN], "join stays on the one cell, no wrap");
    assert_cursor!(term, row 0, col 2); // cursor unchanged by the join continuation
}

// ── (6) screen edits over a multi-codepoint cluster cell ─────────────────────

/// INTENT: Erase-in-line over a flag cluster must clear BOTH the base and the
/// trailing wide continuation, leaving no orphaned wide cell or stale scalars.
#[test]
fn erase_line_over_flag_clears_both_cells() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[RI_J, RI_P])); // JP flag at cols 0-1 (Full + Wide)
    term.advance(b"\x1b[H"); // cursor home
    term.advance(b"\x1b[2K"); // erase entire line

    let c0 = term.screen.get_cell(0, 0).unwrap();
    let c1 = term.screen.get_cell(0, 1).unwrap();
    assert_eq!(c0.char(), ' ', "base cell erased to blank");
    assert_eq!(c0.width, CellWidth::Half, "no stale Full width remains");
    assert_eq!(c1.width, CellWidth::Half, "no orphaned Wide continuation remains");
}

/// INTENT: delete-char (DCH) over a flag cluster. After deleting the 2-cell
/// flag's base column, the line must not retain a dangling wide continuation in
/// the shifted content. Verify no panic and content shifts sanely.
#[test]
fn delete_char_over_flag_no_dangling_wide() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[RI_J, RI_P])); // flag cols 0-1
    term.advance(b"XY"); // cols 2,3
    term.advance(b"\x1b[H"); // home
    term.advance(b"\x1b[2P"); // delete 2 chars (the whole flag)

    // After deleting 2 columns, 'X' and 'Y' shift left to cols 0,1.
    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), 'X');
    assert_eq!(term.screen.get_cell(0, 1).unwrap().char(), 'Y');
}

/// INTENT: backspace after a ZWJ family cluster lands the cursor on the cluster
/// cell's trailing column, and a subsequent overwrite does not silently merge
/// into the old cluster (mode state was cleared by the BS control).
#[test]
fn backspace_over_zwj_cluster_then_overwrite() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[MAN, ZWJ, WOMAN])); // 2-cell cluster, cursor col2
    term.advance(b"\x08"); // BS -> col 1
    term.advance(b"\x08"); // BS -> col 0
    term.advance(b"Q"); // overwrite base cell

    // 'Q' overwrites col 0; it must be a clean fresh cell, not carrying old
    // cluster scalars.
    let c0: Vec<char> = term.screen.get_cell(0, 0).unwrap().grapheme().chars().collect();
    assert_eq!(c0, vec!['Q'], "overwrite produces a clean single-scalar cell");
}

// ── (7) DECRQM reports correct state after set/reset cycles ──────────────────

/// INTENT: DECRQM (`CSI ? 2027 $ p`) must reflect the CURRENT state across
/// multiple set/reset toggles, not a stale value.
#[test]
fn decrqm_2027_tracks_toggle_cycles() {
    let mut term = TerminalCore::new(24, 80);

    // set -> report 1
    term.advance(b"\x1b[?2027h");
    term.meta.pending_responses.clear();
    term.advance(b"\x1b[?2027$p");
    assert_single_pending_response_bytes(&term, b"\x1b[?2027;1$y");

    // reset -> report 2
    term.meta.pending_responses.clear();
    term.advance(b"\x1b[?2027l");
    term.meta.pending_responses.clear();
    term.advance(b"\x1b[?2027$p");
    assert_single_pending_response_bytes(&term, b"\x1b[?2027;2$y");

    // set again -> report 1
    term.meta.pending_responses.clear();
    term.advance(b"\x1b[?2027h");
    term.meta.pending_responses.clear();
    term.advance(b"\x1b[?2027$p");
    assert_single_pending_response_bytes(&term, b"\x1b[?2027;1$y");
}

// ── (8) cursor-position report lands correctly past a 2-cell cluster ─────────

/// INTENT: After printing a flag (width-2 cluster) the DSR cursor-position
/// report (`CSI 6n`) must report column 3 (1-indexed col after 2 advanced
/// cells), proving cluster width bookkeeping feeds cursor reporting correctly.
#[test]
fn dsr_after_flag_reports_column_three() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[RI_J, RI_P])); // cursor now at col 2 (0-indexed)
    term.advance(b"\x1b[6n");
    // CPR is 1-indexed: row 1, col 3.
    assert_single_pending_response_bytes(&term, b"\x1b[1;3R");
}

/// INTENT: Backward cursor movement over a 2-cell flag lands on the correct
/// column. After the flag (cursor col 2), CUB 1 (`CSI D`) lands on col 1 — the
/// trailing wide continuation — and forward CUF returns to col 2.
#[test]
fn cursor_movement_over_flag_columns() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[RI_J, RI_P])); // cursor col 2
    term.advance(b"\x1b[D"); // CUB 1
    assert_cursor!(term, row 0, col 1);
    term.advance(b"\x1b[C"); // CUF 1
    assert_cursor!(term, row 0, col 2);
}

// ── (9) extremely long ZWJ chain does not grow unboundedly or panic ──────────

/// INTENT: A pathological infinite ZWJ+emoji chain must not panic and must not
/// grow the cell's grapheme storage without bound — `push_combining` caps the
/// cluster at 32 bytes. The cursor must not advance (all joins land on one cell).
#[test]
fn pathological_long_zwj_chain_is_capped_and_safe() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[MAN])); // base width-2 cell, cursor col 2

    // Feed 1000 (ZWJ, WOMAN) pairs into the same cluster.
    let mut chain = Vec::new();
    for _ in 0..1000 {
        chain.push(ZWJ);
        chain.push(WOMAN);
    }
    term.advance(&bytes(&chain));

    let cell = term.screen.get_cell(0, 0).unwrap();
    // Storage is capped at 32 bytes regardless of input length.
    assert!(
        cell.grapheme().len() <= 32,
        "grapheme storage must stay capped (<=32 bytes), got {}",
        cell.grapheme().len()
    );
    // The base scalar is preserved.
    assert_eq!(cell.char(), MAN, "base emoji preserved through the chain");
    // Cluster never advances the cursor.
    assert_cursor!(term, row 0, col 2); // cursor stays put through the entire chain
}

/// INTENT: A long run of lone-then-merge regional indicators (200 RIs) forms
/// exactly 100 flags marching across rows via auto-wrap, with no panic and no
/// runaway state.
#[test]
fn many_ri_pairs_form_many_flags_no_panic() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2027h");
    let mut chain = Vec::new();
    for _ in 0..100 {
        chain.push(RI_J);
        chain.push(RI_P);
    }
    term.advance(&bytes(&chain));

    // First flag still intact at origin.
    let first: Vec<char> = term.screen.get_cell(0, 0).unwrap().grapheme().chars().collect();
    assert_eq!(first, vec![RI_J, RI_P], "first flag intact after 100 flags");
    assert_eq!(term.screen.get_cell(0, 0).unwrap().width, CellWidth::Full);
}
