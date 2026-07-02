//! End-to-end tests for Kitty Unicode placeholders (`U+10EEEE`) driven through
//! `TerminalCore::advance`.
//!
//! Module under test: `parser/vte_handler.rs` (`finalize_placeholder_cell`) +
//! `grid/placeholder.rs`.

use crate::grid::placeholder::{PLACEHOLDER_CHAR, ROWCOLUMN_DIACRITICS};

/// UTF-8 bytes for the placeholder base character.
fn placeholder_bytes() -> Vec<u8> {
    let mut buf = [0u8; 4];
    PLACEHOLDER_CHAR.encode_utf8(&mut buf).as_bytes().to_vec()
}

/// Append the UTF-8 of a diacritic (by table index) to `out`.
fn push_diacritic(out: &mut Vec<u8>, idx: usize) {
    let mut buf = [0u8; 4];
    out.extend_from_slice(ROWCOLUMN_DIACRITICS[idx].encode_utf8(&mut buf).as_bytes());
}

/// Store a 1×1 image with id `n` (transmit-only, no placement yet).
fn store_image(core: &mut crate::TerminalCore, n: u32) {
    let seq = format!("\x1b_Ga=t,f=24,i={n},s=1,v=1;AAAA\x1b\\");
    core.advance(seq.as_bytes());
}

fn placement_count(core: &crate::TerminalCore) -> usize {
    core.screen.active_graphics().placement_count()
}

/// INTENT: a placeholder cell with an indexed foreground decodes the image id
/// from the fg color, stamps it on the cell, and emits a placement
/// notification when the image exists.
#[test]
fn placeholder_indexed_fg_decodes_id_and_associates_cell() {
    let mut core = crate::TerminalCore::new(24, 80);
    store_image(&mut core, 42);

    core.screen.move_cursor(0, 0);
    // SGR 38;5;42 → indexed fg = 42, then print the placeholder.
    let mut seq = b"\x1b[38;5;42m".to_vec();
    seq.extend_from_slice(&placeholder_bytes());
    core.advance(&seq);

    let cell = core.screen.get_cell(0, 0).expect("cell exists");
    assert_eq!(cell.image_id(), Some(42), "cell associated with image 42");
    assert_eq!(
        placement_count(&core),
        1,
        "one placeholder placement emitted"
    );
}

/// INTENT: a truecolor foreground encodes the 24-bit image id directly.
#[test]
fn placeholder_truecolor_fg_decodes_24bit_id() {
    let mut core = crate::TerminalCore::new(24, 80);
    // id = 0x010203 = 66051.
    store_image(&mut core, 0x0001_0203);

    core.screen.move_cursor(0, 0);
    let mut seq = b"\x1b[38;2;1;2;3m".to_vec();
    seq.extend_from_slice(&placeholder_bytes());
    core.advance(&seq);

    let cell = core.screen.get_cell(0, 0).expect("cell exists");
    assert_eq!(cell.image_id(), Some(0x0001_0203));
}

/// INTENT: row/column come from the 1st/2nd combining diacritics; the cell is
/// still associated with the image. (We verify association + that diacritics
/// were attached to the cell's grapheme.)
#[test]
fn placeholder_row_col_from_diacritics() {
    let mut core = crate::TerminalCore::new(24, 80);
    store_image(&mut core, 5);

    core.screen.move_cursor(0, 0);
    let mut seq = b"\x1b[38;5;5m".to_vec();
    seq.extend_from_slice(&placeholder_bytes());
    push_diacritic(&mut seq, 3); // row = 3
    push_diacritic(&mut seq, 9); // col = 9
    core.advance(&seq);

    let cell = core.screen.get_cell(0, 0).expect("cell exists");
    assert_eq!(cell.image_id(), Some(5));
    // Grapheme retains base + the two diacritics (decoder reads them for row/col).
    assert_eq!(cell.grapheme().chars().count(), 3);
}

/// INTENT: a 3rd diacritic raises the image id by its high byte.
#[test]
fn placeholder_high_byte_extends_id() {
    let mut core = crate::TerminalCore::new(24, 80);
    // base fg id = 1; high byte = 2 → full id = (2<<24)|1.
    let full_id = (2u32 << 24) | 1;
    store_image(&mut core, full_id);

    core.screen.move_cursor(0, 0);
    let mut seq = b"\x1b[38;2;0;0;1m".to_vec();
    seq.extend_from_slice(&placeholder_bytes());
    push_diacritic(&mut seq, 0); // row = 0
    push_diacritic(&mut seq, 0); // col = 0
    push_diacritic(&mut seq, 2); // high byte = 2
    core.advance(&seq);

    let cell = core.screen.get_cell(0, 0).expect("cell exists");
    assert_eq!(cell.image_id(), Some(full_id));
}

/// INTENT: a multi-cell placeholder grid associates each cell with the image.
#[test]
fn placeholder_multi_cell_grid() {
    let mut core = crate::TerminalCore::new(24, 80);
    store_image(&mut core, 7);

    core.screen.move_cursor(0, 0);
    let mut seq = b"\x1b[38;5;7m".to_vec();
    // Two adjacent placeholder cells (row 0, cols 0 and 1).
    seq.extend_from_slice(&placeholder_bytes());
    seq.extend_from_slice(&placeholder_bytes());
    core.advance(&seq);

    assert_eq!(core.screen.get_cell(0, 0).unwrap().image_id(), Some(7));
    assert_eq!(core.screen.get_cell(0, 1).unwrap().image_id(), Some(7));
    assert_eq!(
        placement_count(&core),
        2,
        "one placement per placeholder cell"
    );
}

/// INTENT: a malformed placeholder (no fg id / default color) is ignored — no
/// cell association and no placement.
#[test]
fn placeholder_without_fg_id_is_ignored() {
    let mut core = crate::TerminalCore::new(24, 80);
    store_image(&mut core, 1);

    core.screen.move_cursor(0, 0);
    // No SGR fg set → default foreground → malformed placeholder.
    core.advance(&placeholder_bytes());

    let cell = core.screen.get_cell(0, 0).expect("cell exists");
    assert_eq!(
        cell.image_id(),
        None,
        "malformed placeholder not associated"
    );
    assert_eq!(placement_count(&core), 0, "no placement emitted");
}

/// INTENT: an orphan placeholder (valid id, but image not stored) associates
/// the cell but emits no notification (nothing to draw).
#[test]
fn placeholder_orphan_image_emits_no_notification() {
    let mut core = crate::TerminalCore::new(24, 80);
    // Do NOT store image 99.
    core.screen.move_cursor(0, 0);
    let mut seq = b"\x1b[38;5;99m".to_vec();
    seq.extend_from_slice(&placeholder_bytes());
    core.advance(&seq);

    let cell = core.screen.get_cell(0, 0).expect("cell exists");
    assert_eq!(cell.image_id(), Some(99), "cell still records the id");
    assert_eq!(
        placement_count(&core),
        0,
        "orphan placeholder draws nothing"
    );
}

/// INTENT: the placement id is decoded from the cell's underline color.
#[test]
fn placeholder_placement_id_from_underline_color() {
    let mut core = crate::TerminalCore::new(24, 80);
    store_image(&mut core, 3);

    core.screen.move_cursor(0, 0);
    // fg indexed = 3 (image id), underline color indexed = 4 (placement id).
    let mut seq = b"\x1b[38;5;3m\x1b[58;5;4m".to_vec();
    seq.extend_from_slice(&placeholder_bytes());
    core.advance(&seq);

    // The placement we created must carry placement_id = 4: delete it via a=d,p.
    core.advance(b"\x1b_Ga=d,i=3,p=4,d=p\x1b\\");
    assert_eq!(
        placement_count(&core),
        0,
        "placement was targetable by its underline-derived placement id"
    );
}
