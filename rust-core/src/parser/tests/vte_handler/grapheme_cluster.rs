// ── DEC mode 2027 grapheme clustering tests ─────────────────────────────────
//
// Module under test: `parser/vte_handler.rs` (`handle_grapheme_clustering`,
// `append_to_previous_cluster`, `merge_regional_indicator`) plus the
// `merge_flag_pair` Screen helper. Mode 2027 wiring lives in
// `parser/dec_private.rs`.

use super::*;
use crate::types::cell::CellWidth;

// Codepoints used across these tests.
const MAN: char = '\u{1F468}'; // 👨 base emoji, width 2
const WOMAN: char = '\u{1F469}'; // 👩 width 2
const GIRL: char = '\u{1F467}'; // 👧 width 2
const ZWJ: char = '\u{200D}'; // zero-width joiner, width 0
const VS16: char = '\u{FE0F}'; // variation selector-16, width 0
const HEART: char = '\u{2764}'; // ❤ base, width 1
const RI_J: char = '\u{1F1EF}'; // 🇯 regional indicator J, width 1
const RI_P: char = '\u{1F1F5}'; // 🇵 regional indicator P, width 1

/// Build a UTF-8 byte vector from a slice of chars (test ergonomics).
fn bytes(chars: &[char]) -> Vec<u8> {
    chars.iter().collect::<String>().into_bytes()
}

fn term_2027_on() -> TerminalCore {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2027h");
    term
}

// ── STEP 1: mode wiring ─────────────────────────────────────────────────────

/// INTENT: `CSI ? 2027 h` enables grapheme clustering; `l` disables it.
#[test]
fn dec_2027_set_and_reset_toggles_flag() {
    let mut term = TerminalCore::new(24, 80);
    assert!(
        !term.dec_modes.grapheme_clustering,
        "mode 2027 must default OFF so existing behavior is unchanged"
    );
    term.advance(b"\x1b[?2027h");
    assert!(term.dec_modes.grapheme_clustering, "?2027h must set the flag");
    term.advance(b"\x1b[?2027l");
    assert!(
        !term.dec_modes.grapheme_clustering,
        "?2027l must clear the flag"
    );
}

/// INTENT: DECRQM (`CSI ? 2027 $ p`) reports reset (status 2) by default and
/// set (status 1) once enabled — mirroring mode 2026's reporting.
#[test]
fn dec_2027_decrqm_reports_state() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2027$p");
    assert_single_pending_response_bytes(&term, b"\x1b[?2027;2$y");

    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2027h");
    term.meta.pending_responses.clear();
    term.advance(b"\x1b[?2027$p");
    assert_single_pending_response_bytes(&term, b"\x1b[?2027;1$y");
}

// ── STEP 2a: ZWJ family emoji ───────────────────────────────────────────────

/// INTENT: With 2027 ON, a family ZWJ sequence
/// (👨‍👩‍👧 = MAN ZWJ WOMAN ZWJ GIRL) coalesces into ONE grapheme cluster
/// occupying 2 cells; the cursor advances by exactly 2.
#[test]
fn family_zwj_emoji_is_one_cluster_cursor_advances_two() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[MAN, ZWJ, WOMAN, ZWJ, GIRL]));

    let cell = term.screen.get_cell(0, 0).unwrap();
    let cluster: Vec<char> = cell.grapheme().chars().collect();
    assert_eq!(
        cluster,
        vec![MAN, ZWJ, WOMAN, ZWJ, GIRL],
        "all 5 scalars must live in one cell's grapheme cluster"
    );
    assert_cursor!(term, row 0, col 2);
    // The base emoji is width 2, so the cell stays Full and col 1 is a
    // continuation placeholder.
    assert_eq!(term.screen.get_cell(0, 0).unwrap().width, CellWidth::Full);
}

/// INTENT: emoji + VS16 (❤️ = HEART VS16) is a single cluster — VS16 attaches
/// as a zero-width combining selector without advancing the cursor.
#[test]
fn emoji_plus_vs16_is_one_cluster() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[HEART, VS16]));

    let cell = term.screen.get_cell(0, 0).unwrap();
    let cluster: Vec<char> = cell.grapheme().chars().collect();
    assert_eq!(cluster, vec![HEART, VS16], "VS16 must join the heart's cell");
    assert_cursor!(term, row 0, col 1);
}

// ── STEP 2c: regional-indicator flags ───────────────────────────────────────

/// INTENT: A JP flag (🇯🇵 = RI_J RI_P) is ONE cluster of width 2 with the
/// trailing continuation cell reserved; the cursor advances by 2.
#[test]
fn jp_flag_is_one_width2_cluster() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[RI_J, RI_P]));

    let cell = term.screen.get_cell(0, 0).unwrap();
    let cluster: Vec<char> = cell.grapheme().chars().collect();
    assert_eq!(cluster, vec![RI_J, RI_P], "both RIs must form one flag cell");
    assert_eq!(
        cell.width,
        CellWidth::Full,
        "a flag is a width-2 grapheme cluster"
    );
    assert_eq!(
        term.screen.get_cell(0, 1).unwrap().width,
        CellWidth::Wide,
        "the trailing cell must be a wide continuation placeholder"
    );
    assert_cursor!(term, row 0, col 2);
}

/// INTENT: A lone trailing RI followed by a non-RI does NOT merge: the second
/// glyph prints independently and the RI-pending state resets.
#[test]
fn lone_ri_then_ascii_does_not_merge() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[RI_J]));
    term.advance(b"X");

    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), RI_J);
    assert_eq!(term.screen.get_cell(0, 1).unwrap().char(), 'X');
    assert_cursor!(term, row 0, col 2);
}

/// INTENT: Four RIs in a row form TWO flags, not one giant cluster — pairing
/// resets after each completed flag.
#[test]
fn four_regional_indicators_form_two_flags() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[RI_J, RI_P, RI_J, RI_P]));

    let first: Vec<char> = term.screen.get_cell(0, 0).unwrap().grapheme().chars().collect();
    let second: Vec<char> = term.screen.get_cell(0, 2).unwrap().grapheme().chars().collect();
    assert_eq!(first, vec![RI_J, RI_P], "cols 0-1 = first flag");
    assert_eq!(second, vec![RI_J, RI_P], "cols 2-3 = second flag");
    assert_cursor!(term, row 0, col 4);
}

// ── STEP 2: edge-case robustness ────────────────────────────────────────────

/// INTENT: A lone ZWJ at column 0 (no previous cell) must not panic or corrupt
/// state; the following printable prints normally as a fresh cell.
#[test]
fn lone_zwj_at_col0_no_corruption() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[ZWJ]));
    term.advance(b"A");

    assert_eq!(
        term.screen.get_cell(0, 0).unwrap().char(),
        'A',
        "stray ZWJ at origin is dropped; 'A' prints at col 0"
    );
    assert_cursor!(term, row 0, col 1);
}

/// INTENT: ZWJ then newline then a printable must NOT join across the line —
/// the join-pending state is cleared by the LF control.
#[test]
fn zwj_then_newline_then_char_no_cross_line_join() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[MAN, ZWJ]));
    term.advance(b"\r\n");
    // Use a NON-ASCII printable (woman emoji) so the control-char clearing path
    // is genuinely exercised — an ASCII char would clear via the fast path.
    term.advance(&bytes(&[WOMAN]));

    // The man emoji + ZWJ remain on row 0, unjoined by the next-line glyph.
    let row0: Vec<char> = term.screen.get_cell(0, 0).unwrap().grapheme().chars().collect();
    assert_eq!(row0, vec![MAN, ZWJ]);
    // WOMAN prints fresh on row 1, NOT appended to the row-0 cluster.
    assert_eq!(term.screen.get_cell(1, 0).unwrap().char(), WOMAN);
    assert_cursor!(term, row 1, col 2);
}

/// INTENT: A cursor move between a ZWJ and the next printable breaks the join,
/// so a stray ZWJ cannot corrupt an unrelated cell reached via positioning.
#[test]
fn zwj_then_cursor_move_breaks_join() {
    let mut term = term_2027_on();
    term.advance(&bytes(&[MAN, ZWJ]));
    term.advance(b"\x1b[5;5H"); // CUP to row 4, col 4
    term.advance(b"Q");

    assert_eq!(
        term.screen.get_cell(4, 4).unwrap().char(),
        'Q',
        "'Q' prints fresh at the moved cursor, not joined to the ZWJ cluster"
    );
}

// ── STEP 3: mode OFF parity ─────────────────────────────────────────────────

/// INTENT: With mode 2027 OFF (default), a family ZWJ emoji prints exactly as
/// today: the base emoji + ZWJ collapse onto the first cell via the existing
/// combining path, the following emoji advances as its own width-2 cell. This
/// asserts the OFF path is unchanged versus the current implementation.
#[test]
fn family_emoji_with_mode_off_matches_current_behavior() {
    // Reference run with no mode set — current production behavior.
    let mut reference = TerminalCore::new(24, 80);
    reference.advance(&bytes(&[MAN, ZWJ, WOMAN, ZWJ, GIRL]));

    // The OFF path: WOMAN and GIRL are width-2 advancing prints; ZWJ chars
    // attach as combining to whatever cell precedes the cursor.
    let ref_row = reference.screen.cursor().row;
    let ref_col = reference.screen.cursor().col;
    // MAN at col0 (Full), WOMAN at col2 (Full), GIRL at col4 (Full):
    // cursor lands at col 6.
    assert_cursor!(reference, row 0, col 6);
    assert_eq!(reference.screen.get_cell(0, 0).unwrap().char(), MAN);
    assert_eq!(reference.screen.get_cell(0, 2).unwrap().char(), WOMAN);
    assert_eq!(reference.screen.get_cell(0, 4).unwrap().char(), GIRL);

    // Confirm leaving the flag explicitly unset yields the same cursor.
    let mut off = TerminalCore::new(24, 80);
    assert!(!off.dec_modes.grapheme_clustering);
    off.advance(&bytes(&[MAN, ZWJ, WOMAN, ZWJ, GIRL]));
    assert_eq!(
        (off.screen.cursor().row, off.screen.cursor().col),
        (ref_row, ref_col),
        "explicit-OFF must match default behavior byte-for-byte"
    );
}

/// INTENT: With mode 2027 OFF, a regional-indicator pair prints as two
/// independent cells (no flag merge) — cursor advances by 2 across two cells.
#[test]
fn ri_pair_with_mode_off_prints_two_cells() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(&bytes(&[RI_J, RI_P]));

    assert_eq!(term.screen.get_cell(0, 0).unwrap().char(), RI_J);
    assert_eq!(term.screen.get_cell(0, 1).unwrap().char(), RI_P);
    assert_cursor!(term, row 0, col 2);
}
